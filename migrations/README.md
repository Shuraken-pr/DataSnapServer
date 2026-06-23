# 🗄️ Миграции базы данных

Этот каталог содержит SQL-скрипты для управления схемой базы данных.

## 📋 Список миграций

| Файл | Описание | Дата |
|------|----------|:----:|
| `001_security_users.sql` | Расширение таблицы `users` полями безопасности, создание таблиц `security_events` и `rate_limits` | 2026-06-22 |

## 🚀 Применение миграций

### Шаг 1: Резервная копия

**Перед применением миграции обязательно создайте резервную копию БД!**

```bash
pg_dump -U postgres -h localhost -p 5432 postgres > backup_before_migration_001.sql
```

### Шаг 2: Применение миграции

```bash
psql -U postgres -h localhost -p 5432 -d postgres -f migrations/001_security_users.sql
```

### Шаг 3: Проверка результата

После выполнения скрипта в консоли появится отчёт:

```
NOTICE: ============================================================
NOTICE:   Миграция 001 успешно выполнена
NOTICE: ============================================================
NOTICE: Пользователей в таблице users: 2
NOTICE: Поле password_hash:      OK
NOTICE: Поле is_active:          OK
NOTICE: Поле failed_login_attempts: OK
NOTICE: Поле locked_until:       OK
NOTICE: Таблица security_events: OK
NOTICE: Таблица rate_limits:     OK
NOTICE: ============================================================
```

## 📝 Особенности миграций

### Идемпотентность

Все миграции **идемпотентны** — их можно запускать многократно без ошибок. Это обеспечивается через:

- `CREATE TABLE IF NOT EXISTS` — не создаёт таблицу, если она уже есть
- `ADD COLUMN IF NOT EXISTS` — не добавляет колонку, если она уже есть
- `CREATE INDEX IF NOT EXISTS` — не создаёт индекс, если он уже есть
- Проверки `IF NOT EXISTS` для ограничений и триггеров

### Совместимость с Postgre_Delphi

Миграция `001_security_users.sql` совместима с проектом Postgre_Delphi:
- Таблица `users` создаётся с полями `id BIGINT GENERATED ALWAYS AS IDENTITY`, `username TEXT`, `created_at TIMESTAMPTZ` (как в Postgre_Delphi)
- Если таблица уже существует (создана Postgre_Delphi), миграция только **расширяет** её новыми полями

### Совместимость с SQL/ папкой

Миграция также совместима с SQL-скриптами в папке `SQL/`:
- `table_events.sql`
- `table_user_sessions.sql`
- `table_audit_logs.sql`
- `table_audit_files.sql`

Если эти таблицы уже созданы через эти скрипты, миграция не будет их пересоздавать.

## 📊 Что создаёт миграция 001

### Расширение таблицы `users`

| Поле | Тип | Назначение |
|------|-----|------------|
| `password_hash` | TEXT | bcrypt-хеш пароля (через pgcrypto) или plain text (fallback) |
| `role` | VARCHAR(20) | Роль: `user`, `admin`, `auditor` |
| `is_active` | BOOLEAN | Активен ли аккаунт |
| `last_login_at` | TIMESTAMPTZ | Время последнего успешного входа |
| `failed_login_attempts` | INTEGER | Счётчик неудачных попыток входа |
| `locked_until` | TIMESTAMPTZ | Время, до которого аккаунт заблокирован |
| `updated_at` | TIMESTAMPTZ | Время последнего обновления записи |

### Новые таблицы

| Таблица | Назначение |
|---------|------------|
| `security_events` | Аудит событий безопасности (входы, блокировки, подозрительная активность) |
| `rate_limits` | Счётчики запросов для защиты от DDoS и brute-force |

### Новые функции

| Функция | Назначение |
|---------|------------|
| `cleanup_rate_limits()` | Очистка записей rate_limits старше 1 часа |
| `unlock_expired_accounts()` | Автоматическая разблокировка пользователей |
| `cleanup_expired_sessions()` | Очистка просроченных сессий |
| `cleanup_old_security_events(days)` | Очистка событий безопасности старше N дней |

### Триггеры

| Триггер | Назначение |
|---------|------------|
| `trg_users_updated_at` | Автоматическое обновление `updated_at` при изменении записи в `users` |

## 🔐 Миграция паролей

После применения миграции нужно установить пароли для существующих пользователей.

### Вариант 1: Установка bcrypt-хешей (рекомендуется)

Если в PostgreSQL установлено расширение `pgcrypto`:

```sql
-- Установить пароль 'NewPassword123!' для пользователя 'admin'
UPDATE users
SET password_hash = crypt('NewPassword123!', gen_salt('bf', 12))
WHERE username = 'admin';
```

### Вариант 2: Установка plain-text паролей (для тестов)

```sql
-- Временно установить plain-text пароль (сервер поддерживает fallback)
UPDATE users
SET password_hash = 'TempPassword123'
WHERE username = 'admin';
```

⚠️ **Важно:** Plain-text пароли небезопасны! Используйте только для тестов и как можно скорее замените на bcrypt.

### Проверка pgcrypto

```sql
-- Проверить, установлено ли расширение pgcrypto
SELECT * FROM pg_extension WHERE extname = 'pgcrypto';

-- Если пусто, установить:
CREATE EXTENSION IF NOT EXISTS pgcrypto;
```

## 🔄 Откат миграции

Если нужно откатить миграцию:

```sql
-- Удалить новые таблицы
DROP TABLE IF EXISTS security_events;
DROP TABLE IF EXISTS rate_limits;

-- Удалить триггер
DROP TRIGGER IF EXISTS trg_users_updated_at ON users;
DROP FUNCTION IF EXISTS trg_users_updated_at();

-- Удалить функции
DROP FUNCTION IF EXISTS cleanup_rate_limits();
DROP FUNCTION IF EXISTS unlock_expired_accounts();
DROP FUNCTION IF EXISTS cleanup_expired_sessions();
DROP FUNCTION IF EXISTS cleanup_old_security_events(integer);

-- Удалить ограничения
ALTER TABLE users DROP CONSTRAINT IF EXISTS chk_users_role;
ALTER TABLE users DROP CONSTRAINT IF EXISTS chk_users_failed_attempts;

-- Удалить индексы
DROP INDEX IF EXISTS idx_users_active;
DROP INDEX IF EXISTS idx_users_locked;
DROP INDEX IF EXISTS idx_users_last_login;
DROP INDEX IF EXISTS idx_users_role;

-- Удалить колонки (ОСТОРОЖНО: потеря данных!)
ALTER TABLE users DROP COLUMN IF EXISTS password_hash;
ALTER TABLE users DROP COLUMN IF EXISTS role;
ALTER TABLE users DROP COLUMN IF EXISTS is_active;
ALTER TABLE users DROP COLUMN IF EXISTS last_login_at;
ALTER TABLE users DROP COLUMN IF EXISTS failed_login_attempts;
ALTER TABLE users DROP COLUMN IF EXISTS locked_until;
ALTER TABLE users DROP COLUMN IF EXISTS updated_at;
```

⚠️ **Откат миграции приведёт к потере данных безопасности!** Выполняйте только в экстренных случаях.

## 📚 Связанные документы

- [README.md](../README.md) — основная документация проекта
- [SQL/](../SQL/) — SQL-скрипты для создания таблиц
- [Tests/Integration/README.md](../Tests/Integration/README.md) — интеграционные тесты
