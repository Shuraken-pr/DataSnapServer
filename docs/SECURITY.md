# 🔐 Безопасность DataSnap Server

## 📋 Обзор

Сервер реализует многоуровневую систему безопасности:

1. **Аутентификация** — bcrypt через pgcrypto
2. **Защита от brute-force** — блокировка аккаунтов после 5 неудачных попыток
3. **Rate limiting** — ограничение запросов по IP/endpoint
4. **Аудит безопасности** — запись всех событий входа/блокировок

---

## 🔑 Аутентификация

### Алгоритм

- Пароли хешируются через **bcrypt** (расширение `pgcrypto`)
- Стоимость хеширования: **12** (2^12 = 4096 итераций)
- Формат хеша: `$2a$12$...` (60 символов)

### Проверка пароля

```pascal
// В ServerMethodsUnitMain.pas
Qry.SQL.Text := 
  'SELECT id FROM users WHERE username = :username ' +
  'AND password_hash = crypt(:password, password_hash) ' +
  'AND is_active = TRUE';
```

### Модуль `PasswordHasher.pas`

Обёртка над pgcrypto для работы с bcrypt:

```pascal
var
  Hasher: TPasswordHasher;
  Hash: string;
begin
  Hasher := TPasswordHasher.Create(Connection, 12);
  try
    Hash := Hasher.HashPassword('my_password');
    if Hasher.VerifyPassword('my_password', Hash) then
      WriteLn('Password is correct');
  finally
    Hasher.Free;
  end;
end;
```

---

## 🛡️ Защита от brute-force

### Параметры

| Параметр | Значение | Обоснование |
|----------|:--------:|-------------|
| `MAX_FAILED_ATTEMPTS` | 5 | Баланс удобства и безопасности |
| `LOCK_DURATION_MINUTES` | 15 | Достаточно для предотвращения brute-force |

### Алгоритм

1. При каждом неудачном входе увеличивается `failed_login_attempts`
2. После 5 неудачных попыток аккаунт блокируется на 15 минут
3. Успешный вход сбрасывает счётчик
4. Автоматическая разблокировка через функцию `unlock_expired_accounts()`

### Модуль `BruteForceProtector.pas`

```pascal
var
  Protector: TBruteForceProtector;
begin
  Protector := TBruteForceProtector.Create(Connection, 5, 15);
  try
    if Protector.IsAccountLocked('user') then
      raise Exception.Create('Account locked');
    
    if not VerifyPassword('user', 'password') then
    begin
      Protector.RecordFailedAttempt('user', '127.0.0.1');
      raise Exception.Create('Invalid password');
    end;
    
    Protector.ResetFailedAttempts('user');
  finally
    Protector.Free;
  end;
end;
```

---

## 🚦 Rate Limiting

### Лимиты

| Endpoint | Лимит (запросов/час) | Обоснование |
|----------|:-------------------:|-------------|
| `/Login` | 20 | Защита от brute-force |
| `/upload` | 100 | Ограничение загрузки файлов |
| `/SyncUpload` | 200 | Синхронизация данных |
| Прочие | 500 | Общий лимит |

### Алгоритм

- Используется **Fixed Window** алгоритм
- Счётчики хранятся в таблице `rate_limits`
- Проверка выполняется в `WebModuleBeforeDispatch`
- При превышении лимита возвращается HTTP 429

### Модуль `RateLimiter.pas`

```pascal
var
  Limiter: TRateLimiter;
begin
  Limiter := TRateLimiter.Create(Connection, 60);
  try
    if Limiter.CheckLimit('192.168.1.1', '/Login') = rlExceeded then
    begin
      Response.StatusCode := 429;
      Response.Content := '{"error":"Too Many Requests"}';
      Exit;
    end;
    
    Limiter.RecordRequest('192.168.1.1', '/Login');
  finally
    Limiter.Free;
  end;
end;
```

---

## 📝 Аудит безопасности

### Таблица `security_events`

| Поле | Тип | Описание |
|------|-----|----------|
| `event_id` | BIGINT | Первичный ключ |
| `event_type` | TEXT | Тип события (login_success, login_failed, etc.) |
| `username` | TEXT | Имя пользователя |
| `ip_address` | TEXT | IP-адрес клиента |
| `user_agent` | TEXT | User-Agent клиента |
| `details` | JSONB | Дополнительная информация |
| `severity` | TEXT | Уровень серьёзности (info, warning, critical) |
| `created_at` | TIMESTAMPTZ | Время события |

### Типы событий

| Событие | Severity | Описание |
|---------|:--------:|----------|
| `login_success` | info | Успешный вход |
| `login_failed` | warning | Неверный пароль |
| `login_blocked` | warning | Попытка входа в заблокированный аккаунт |
| `account_locked` | critical | Аккаунт заблокирован |
| `rate_limit_exceeded` | warning | Превышен лимит запросов |

### Модуль `SecurityAuditor.pas`

```pascal
var
  Auditor: TSecurityAuditor;
begin
  Auditor := TSecurityAuditor.Create(Connection);
  try
    Auditor.LogEvent('login_success', 'user', '127.0.0.1', 
      'OK', ssInfo, 'Mozilla/5.0');
    
    // Получение событий
    Events := Auditor.GetCriticalEvents(24);
    for Event in Events do
      WriteLn(Event.EventType, ': ', Event.Details);
  finally
    Auditor.Free;
  end;
end;
```

---

## 🧪 Тестирование

### Модульные тесты (25 тестов)

| Модуль | Тестов | Описание |
|--------|:------:|----------|
| `TestPasswordHasher` | 4 | Хеширование и проверка паролей |
| `TestBruteForceProtector` | 8 | Блокировка аккаунтов |
| `TestRateLimiter` | 7 | Ограничение запросов |
| `TestSecurityAuditor` | 6 | Запись и чтение событий |

### Интеграционные тесты (9 тестов)

| ID | Тест | Описание |
|----|----|----------|
| SEC-001 | `TestLogin_Success_RecordsEvent` | Успешный вход записывается в аудит |
| SEC-002 | `TestLogin_FailedAfter5Attempts_LocksAccount` | Блокировка после 5 попыток |
| SEC-003 | `TestLogin_LockedAccount_Rejected` | Заблокированный аккаунт отклоняется |
| SEC-004 | `TestLogin_UnlockedAfterSuccessfulLogin` | Разблокировка после успешного входа |
| SEC-005 | `TestRateLimit_LoginExceeded_Returns429` | Rate limit для Login |
| SEC-006 | `TestRateLimit_UploadExceeded_Returns429` | Rate limit для Upload |
| SEC-007 | `TestRateLimit_DifferentIPs_SeparateLimits` | Разные лимиты для разных IP |
| SEC-008 | `TestSecurityEvents_RetainedAfterRestart` | События сохраняются |
| SEC-009 | `TestSecurityEvents_CriticalEventsFilter` | Фильтр критических событий |

---

## 🔧 Обслуживание

### Очистка старых событий

```sql
-- Удалить события старше 90 дней
DELETE FROM security_events 
WHERE created_at < CURRENT_TIMESTAMP - INTERVAL '90 days';
```

### Разблокировка пользователей

```sql
-- Разблокировать конкретного пользователя
UPDATE users SET locked_until = NULL, failed_login_attempts = 0
WHERE username = 'blocked_user';

-- Разблокировать всех просроченных пользователей
SELECT unlock_expired_accounts();
```

### Просмотр событий безопасности

```sql
-- Критические события за последние 24 часа
SELECT * FROM security_events 
WHERE severity = 'critical' 
AND created_at > CURRENT_TIMESTAMP - INTERVAL '24 hours'
ORDER BY created_at DESC;

-- События по пользователю
SELECT * FROM security_events 
WHERE username = 'test_user'
ORDER BY created_at DESC;

-- События по IP
SELECT * FROM security_events 
WHERE ip_address = '192.168.1.100'
ORDER BY created_at DESC;
```

---

## 📊 Метрики

| Метрика | Значение |
|---------|----------|
| **Время хеширования bcrypt** | ~200 мс (cost=12) |
| **Время проверки пароля** | ~200 мс |
| **Накладные расходы rate limit** | < 5 мс на запрос |
| **Размер security_events** | ~200 байт на запись |

---

## 📚 Ссылки

- [bcrypt](https://en.wikipedia.org/wiki/Bcrypt)
- [pgcrypto](https://www.postgresql.org/docs/current/pgcrypto.html)
- [Rate limiting algorithms](https://en.wikipedia.org/wiki/Rate_limiting)
