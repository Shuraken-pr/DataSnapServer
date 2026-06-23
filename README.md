# 🌐 DataSnap REST Server: FieldAudit Sync Service

Высоконагруженный, безопасный бэкенд-сервис на базе **Embarcadero Delphi 12 (VCL) + DataSnap REST**, разработанный для приема, валидации и сохранения данных от мобильного приложения **FieldAudit** (Android) в центральную базу данных **PostgreSQL**.

Проект реализует паттерн **Offline-First** и прошел полный цикл рефакторинга для соответствия стандартам промышленной эксплуатации (Production-Ready).

## ✨ Ключевые особенности и архитектурные решения

### 🔒 Безопасность (Security)
* **Windows DPAPI:** Пароли от БД и API-ключи хранятся в `db_settings.xml` в зашифрованном виде. Используется флаг `CRYPTPROTECT_LOCAL_MACHINE` — расшифровка возможна только на том же компьютере, где было произведено шифрование (любым пользователем на этой машине).
* **Сессионная аутентификация с bcrypt:** Вместо статических ключей используется механизм временных токенов (GUID) с ограниченным временем жизни (TTL). Пароли хранятся в таблице `users` в виде bcrypt-хешей (12 раундов, расширение `pgcrypto` PostgreSQL). Проверка пароля выполняется через `crypt(password, hash) = hash` на уровне БД. Fallback на plain text для обратной совместимости.
* **Защита от brute force:** После 5 неудачных попыток входа аккаунт блокируется на 30 минут. Реализовано через `BruteForceProtector` (модуль `BruteForceProtector.pas`).
* **Rate limiting:** Защита от DDoS через ограничение количества запросов с одного IP (20 запросов/час на Login, 100 запросов/час на Upload). Реализовано через `RateLimiter` (модуль `RateLimiter.pas`).
* **Security audit logging:** Все события безопасности (успешный/неудачный вход, блокировка аккаунта, rate limit) записываются в таблицу `security_events`. Реализовано через `SecurityAuditor` (модуль `SecurityAuditor.pas`).
* **Защита от подмены данных (Privilege Escalation):** Сервер **полностью игнорирует** поле `user_id`, передаваемое клиентом в JSON-теле запроса. Реальный `user_id` извлекается исключительно из валидной сессии и принудительно подставляется в SQL-запрос.
* **Ограничения размера запроса:** Входящий JSON-пакет ограничен 1 МБ (`MAX_JSON_LENGTH = 1048576`). Массив событий — не более 1000 элементов (`MAX_ARRAY_ITEMS = 1000`). Превышение любого лимита немедленно отклоняется.
* **Сокрытие внутренних ошибок:** При сбоях БД клиент получает только generic-сообщение (`"Database operation failed"`). Детали ошибки (`E.Message`) записываются только в серверный лог и никогда не передаются наружу.
* **API-ключ:** Автоматически генерируемый 32-символьный ключ (`RtlGenRandom` из Advapi32.dll) для машинной аутентификации. Хранится в `db_settings.xml` в зашифрованном (DPAPI) виде. Доступен для генерации через UI формы настроек.

### ⚡ Производительность и Надежность
* **Потокобезопасность FireDAC:** Для класса `TDSServerClass` установлен жизненный цикл **`LifeCycle = Invocation`**. Это гарантирует создание нового, изолированного экземпляра `TServerMethods1` (со своими компонентами `TFDConnection` и `TFDQuery`) для *каждого* HTTP-запроса, исключая гонки данных (Race Conditions). Соединения берутся из пула (`Pooled = True`, `PoolMaximumItems = 10`, имя пула — `PgServerConn`).
* **Асинхронное логирование:** Интегрирована библиотека **LoggerPro** (минимальный уровень `Info`). Запись логов происходит в фоновом потоке с автоматической ротацией файлов (макс. 15 файлов по 10 МБ), что не блокирует обработку клиентских запросов.
* **Оптимизированный парсинг JSON:** Метод `updateSyncUpload` корректно обрабатывает три возможных формата входящего JSON (строка в обертке, массив в обертке, прямой массив) с гарантированным предотвращением утечек памяти (Memory Leaks).
* **Автоочистка сессий:** При старте сервер автоматически выполняет удаление просроченных записей из таблицы `user_sessions` (см. SQL ниже).

### 🌐 Архитектура с Nginx Reverse Proxy
* **HTTPS через Nginx:** Сервер работает в режиме HTTP на локальном порту (обычно 8082), а весь HTTPS-трафик обрабатывается Nginx как Reverse Proxy.
* **Изоляция от интернета:** Сервер слушает только `127.0.0.1`, что делает его недоступным напрямую из внешней сети. Только Nginx имеет доступ к внутреннему порту.
* **Упрощение кода:** Delphi-сервер не содержит кода для работы с SSL-сертификатами — вся криптография делегирована Nginx.
* **Гибкость:** Легко заменить самоподписанный сертификат на настоящий (Let's Encrypt) без изменения кода сервера.

---

## 🏗️ Структура проекта

```text
DataSnapServer/
├── Source/
│   ├── FormUnitMain.pas          # Главная форма: инициализация FDManager, автоочистка сессий при старте
│   ├── ServerMethodsUnitMain.pas # Бизнес-логика: Login, парсинг JSON, транзакции, SQL-инсерты
│   ├── WebModuleUnitMain.pas     # HTTP-перехватчик: проверка токенов, endpoint /upload, извлечение user_id в threadvar
│   ├── ServerSessionContext.pas  # Объявление threadvar CurrentUserID для безопасной межмодульной передачи
│   ├── ServerSettings.pas        # Конфигурация: чтение/запись XML, генерация API-ключа (RtlGenRandom), вызов WinDPAPIUtils
│   ├── ServerLogger.pas          # Инициализация глобального экземпляра LoggerPro (мин. уровень Info, ротация 15×10 МБ)
│   ├── WinDPAPIUtils.pas         # Обертка над Crypt32.dll (CryptProtectData / CryptUnprotectData, флаг CRYPTPROTECT_LOCAL_MACHINE)
│   ├── UploadUtils.pas           # Утилиты для загрузки фото: проверка JPEG, SHA-256, генерация UUID, атомарное сохранение
│   ├── BruteForceProtector.pas   # Защита от brute force: блокировка после 5 неудачных попыток, сброс при успешном входе
│   ├── RateLimiter.pas           # Rate limiting: ограничение запросов с одного IP (20/час Login, 100/час Upload)
│   ├── SecurityAuditor.pas       # Логирование событий безопасности в таблицу security_events
│   └── frServerSettings.pas      # UI формы настроек: тест соединения, генерация API-ключа, сброс флага теста при изменении полей
├── migrations/
│   ├── 001_security_users.sql    # Миграция БД: расширение таблицы users, создание таблиц безопасности
│   └── README.md                 # Документация по миграциям
└── SQL/
    ├── table_events.sql          # Создание таблицы events
    ├── table_user_sessions.sql   # Создание таблицы user_sessions
    ├── table_audit_logs.sql      # Создание таблицы audit_logs
    └── table_audit_files.sql     # Создание таблицы audit_files
```

---

## 🛠️ Требования и зависимости

1. **Embarcadero Delphi 11/12** (с поддержкой 64-bit Windows).
2. **PostgreSQL 13+** (с установленным расширением `pg_cron` для периодической очистки, опционально).
3. **Библиотека LoggerPro:** Должна быть установлена через *Tools → GetIt Package Manager* или добавлена в *Library Path* (Необходимо скачать с https://github.com/danieleteti/loggerpro).
4. **FireDAC:** Драйвер `libpq.dll` должен быть доступен в PATH системы или в папке с исполняемым файлом.
5. **Nginx** (опционально, но рекомендуется): Для обработки HTTPS-трафика и работы в качестве Reverse Proxy.

---

## 🗄️ Настройка базы данных (PostgreSQL)

### Миграция существующей базы данных

Если у вас уже есть база данных с таблицей `users` (например, из проекта Postgre_Delphi), используйте файл миграции:

```bash
# Применить миграцию к существующей БД
psql -U postgres -d your_database -f migrations/001_security_users.sql
```

Миграция `001_security_users.sql`:
- ✅ Создаёт таблицу `users`, если её нет (с полями из Postgre_Delphi)
- ✅ Расширяет существующую таблицу `users` полями безопасности (`password_hash`, `is_active`, `role`, etc.)
- ✅ Создаёт вспомогательные таблицы (`user_sessions`, `security_events`, `rate_limits`)
- ✅ Идемпотентна — можно запускать многократно без ошибок

### Новая установка

Перед запуском сервера выполните следующий SQL-скрипт в вашей базе данных для создания необходимых таблиц и индексов:

```sql
-- 1. 🔑 Расширение pgcrypto для bcrypt
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- 2. Таблица пользователей (аутентификация через bcrypt, не pg_user)
CREATE TABLE IF NOT EXISTS users (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    username    TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    is_active   BOOLEAN DEFAULT TRUE,
    created_at  TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at  TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
CREATE INDEX IF NOT EXISTS idx_users_active ON users(is_active) WHERE is_active = TRUE;

-- 3. Таблица активных сессий
CREATE TABLE IF NOT EXISTS user_sessions (
    session_id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id),
    session_token VARCHAR(255) UNIQUE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP NOT NULL
);

-- Критически важный индекс для молниеносной проверки токена при каждом запросе
CREATE INDEX IF NOT EXISTS idx_sessions_token ON user_sessions(session_token);
CREATE INDEX IF NOT EXISTS idx_sessions_expires ON user_sessions(expires_at);
CREATE INDEX IF NOT EXISTS idx_sessions_user ON user_sessions(user_id);

-- 3. Таблица событий (для batch-синхронизации через SyncUpload)
CREATE TABLE IF NOT EXISTS events (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id),
    event_type VARCHAR(50) NOT NULL,
    occurred_at TIMESTAMP NOT NULL,
    metadata JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_events_user ON events(user_id);
CREATE INDEX IF NOT EXISTS idx_events_occurred ON events(occurred_at);

-- 4. Таблица журналов аудита (для endpoint /upload)
CREATE TABLE IF NOT EXISTS audit_logs (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id),
    event_type VARCHAR(50) NOT NULL,
    occurred_at TIMESTAMP NOT NULL,
    location point,  -- PostgreSQL native point type: (lon, lat)
    details JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_audit_logs_user ON audit_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_occurred ON audit_logs(occurred_at);

-- 5. Таблица файлов аудита (связь с audit_logs)
CREATE TABLE IF NOT EXISTS audit_files (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    log_id BIGINT REFERENCES audit_logs(id) ON DELETE CASCADE,
    file_uuid UUID NOT NULL,
    storage_path VARCHAR(500) NOT NULL,
    original_filename VARCHAR(255),
    file_size BIGINT NOT NULL,
    checksum_sha256 VARCHAR(64) NOT NULL,
    mime_type VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_audit_files_log ON audit_files(log_id);
CREATE INDEX IF NOT EXISTS idx_audit_files_uuid ON audit_files(file_uuid);

-- 6. Таблица событий безопасности (аудит)
CREATE TABLE IF NOT EXISTS security_events (
    id BIGSERIAL PRIMARY KEY,
    event_type VARCHAR(50) NOT NULL,
    username TEXT,
    user_id BIGINT REFERENCES users(id),
    ip_address INET,
    details TEXT,
    severity VARCHAR(20) DEFAULT 'info',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_security_events_type ON security_events(event_type);
CREATE INDEX IF NOT EXISTS idx_security_events_user ON security_events(user_id);
CREATE INDEX IF NOT EXISTS idx_security_events_created ON security_events(created_at);

-- 7. Таблица rate limiting (защита от DDoS)
CREATE TABLE IF NOT EXISTS rate_limits (
    id BIGSERIAL PRIMARY KEY,
    ip_address INET NOT NULL,
    endpoint VARCHAR(100) NOT NULL,
    request_count INTEGER DEFAULT 1,
    window_start TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(ip_address, endpoint)
);

CREATE INDEX IF NOT EXISTS idx_rate_limits_ip ON rate_limits(ip_address);
CREATE INDEX IF NOT EXISTS idx_rate_limits_endpoint ON rate_limits(endpoint);

-- 8. Колонки блокировки аккаунта в users
ALTER TABLE users ADD COLUMN IF NOT EXISTS failed_login_attempts INTEGER DEFAULT 0;
ALTER TABLE users ADD COLUMN IF NOT EXISTS locked_until TIMESTAMP;
ALTER TABLE users ADD COLUMN IF NOT EXISTS last_login_at TIMESTAMP;

-- 9. Очистка просроченных сессий (выполняется при старте сервера)
DELETE FROM user_sessions WHERE expires_at < CURRENT_TIMESTAMP;
```

### Миграция пользователей с plain-text паролями

Если у вас есть пользователи с паролями в открытом виде (например, из старой системы), выполните миграцию:

```sql
-- Обновить пароли на bcrypt-хеши
UPDATE users 
SET password_hash = crypt(password, gen_salt('bf', 12))
WHERE password_hash IS NULL OR password_hash = '';

-- Удалить колонку с открытыми паролями (опционально)
-- ALTER TABLE users DROP COLUMN password;
```

**Fallback на plain text:** Если `password_hash` пустой, сервер временно принимает пароль в открытом виде (для обратной совместимости). Рекомендуется заполнить `password_hash` для всех пользователей.

---

## 🚀 Запуск и конфигурация

### 1. Настройка Delphi-сервера

1. Скомпилируйте проект в Delphi.
2. При **первом запуске** сервер автоматически откроет окно **"Настройка подключения"**.
3. Введите параметры подключения к PostgreSQL (Host, Database, Username, Password).
4. Нажмите **"Тест соединения"**. Если успешно, нажмите **OK**.
5. Сервер сохранит настройки в файл `db_settings.xml` (пароль будет зашифрован через DPAPI) и запустит HTTP-слушатель на указанном порту (по умолчанию 8082).

> **Важно:** Если вы переносите исполняемый файл и `db_settings.xml` на другой компьютер, сервер не сможет расшифровать пароль и потребует настройки заново. Это ожидаемое поведение системы безопасности DPAPI.

### 2. Настройка Nginx (Reverse Proxy)

Для работы с HTTPS необходимо настроить Nginx как Reverse Proxy.

#### 2.1. Генерация самоподписанного сертификата

```bash
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
  -keyout /etc/nginx/key.pem \
  -out /etc/nginx/cert.pem \
  -subj "/CN=192.168.1.113" \
  -addext "subjectAltName=IP:192.168.1.113"
```

*(Замените `192.168.1.113` на ваш реальный IP или домен)*

#### 2.2. Конфигурация Nginx

Создайте файл `/etc/nginx/sites-available/fieldaudit` (или `C:\nginx\conf\nginx.conf` на Windows):

```nginx
server {
    listen 443 ssl;
    server_name 192.168.1.113;  # Замените на ваш IP или домен

    # Пути к сертификатам
    ssl_certificate     /etc/nginx/cert.pem;
    ssl_certificate_key /etc/nginx/key.pem;
    
    # Настройки SSL
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    # Проксирование на Delphi-сервер
    location / {
        proxy_pass http://127.0.0.1:8082;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

# Редирект с HTTP на HTTPS
server {
    listen 80;
    server_name 192.168.1.113;
    return 301 https://$host$request_uri;
}
```

Активируйте сайт и перезапустите Nginx:
```bash
sudo ln -s /etc/nginx/sites-available/fieldaudit /etc/nginx/sites-enabled/
sudo nginx -t          # Проверка конфигурации
sudo systemctl reload nginx
```

#### 2.3. Альтернатива: Let's Encrypt (для продакшена)

Если у вас есть публичный домен, используйте Certbot для получения настоящего сертификата:
```bash
sudo certbot --nginx -d your-domain.ru
```

---

## 📡 API Documentation

### 1. Аутентификация (Получение токена)
Позволяет получить временный сессионный токен для последующих запросов.

**Endpoint:**
```http
GET /datasnap/rest/TServerMethods1/Login/{username}/{password}
```

**Response (200 OK):**
*Обратите внимание: метод возвращает `TJSONObject`, поэтому DataSnap не добавляет лишнюю обертку `{"result": [...]}`.*
```json
{
  "status": "success",
  "token": "{86AB48DA-D896-4480-8BA8-99E620F05C5E}",
  "user_id": 1
}
```

**Response (401 Unauthorized / Ошибка):**
```json
{
  "status": "error",
  "message": "Invalid username or password"
}
```

---

### 2. Синхронизация данных (Upload)
Принимает пакет данных от мобильного клиента. Требует валидного токена.

**Endpoint:**
```http
POST /datasnap/rest/TServerMethods1/updateSyncUpload
```

**Headers:**
| Key | Value | Description |
| :--- | :--- | :--- |
| `Content-Type` | `application/json` | Обязательно |
| `X-Session-Token` | `{ваш_токен}` | Токен, полученный из метода `Login` |

**Request Body (JSON):**
*Примечание: Поле `user_id` внутри массива **игнорируется** сервером в целях безопасности. ID берется из сессии.*
```json
{
  "AJsonData": [
    {
      "event_type": "mobile_audit",
      "occurred_at": "2026-06-16T10:00:00",
      "details": {
        "photo_path": "/data/user/0/.../photo.jpg",
        "lat": 55.7558,
        "lon": 37.6173
      }
    }
  ]
}
```
*Сервер также поддерживает формат, где `AJsonData` является строкой с экранированным JSON, или прямой массив без обертки.*

**Response (200 OK):**
```json
{
  "result": "ok",
  "count": 1
}
```

**Response (внутренняя ошибка в JSON, HTTP 200):**
*DataSnap REST оборачивает возвращаемый string в `{"result": [...]}`. При ошибке внутри метода (например, невалидные координаты) HTTP-статус остаётся 200, но JSON содержит:*
```json
{
  "result": ["{\"result\":\"error\",\"message\":\"Invalid latitude in item 0: must be between -90 and 90\"}"]
}
```

**Response (401 Unauthorized):**
```json
{
  "error": "Unauthorized: session expired or invalid"
}
```

**Валидация:**
- `lat` внутри `details` должно быть в диапазоне **-90..90**
- `lon` внутри `details` должно быть в диапазоне **-180..180**
- При невалидных координатах вся транзакция откатывается, записи не создаются

---

### 3. Загрузка фотографий (Upload)
Принимает фотографию в формате JPEG, сохраняет на диск и регистрирует в БД.

**Endpoint:**
```http
POST /upload
```

**Headers:**
| Key | Value | Description |
| :--- | :--- | :--- |
| `Content-Type` | `application/json` | Обязательно |
| `X-Session-Token` | `{ваш_токен}` | Токен из метода `Login` |

**Request Body (JSON):**
```json
{
  "event_type": "mobile_audit",
  "lat": 55.7558,
  "lon": 37.6173,
  "photo_base64": "/9j/4AAQSkZJRgABAQ...",
  "photo_filename": "photo_20260619_143025.jpg",
  "title": "Inspection Site A",
  "device_id": "android",
  "batch_id": "{86AB48DA-D896-4480-8BA8-99E620F05C5E}",
  "occurred_at": "2026-06-19T14:30:00Z"
}
```

**Response (200 OK):**
```json
{
  "result": "ok",
  "file_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "checksum": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  "url": "https://192.168.1.113/audit-files/2026/6/19/a1b2c3d4-e5f6-7890-abcd-ef1234567890.jpg"
}
```

**Валидация:**
- `lat` должно быть в диапазоне **-90..90**
- `lon` должно быть в диапазоне **-180..180**
- При невалидных координатах возвращается **HTTP 400**, записи не создаются

**Особенности реализации:**
- Фото передаётся в Base64 внутри JSON (избегает проблем с multipart/кодировками)
- Проверяется JPEG-заголовок (магические байты `FF D8 FF`)
- Вычисляется SHA-256 хеш для контроля целостности
- Файл сохраняется атомарно (через `.tmp` → `rename`)
- Иерархия папок: `C:\AuditFiles\YYYY\MM\DD\{UUID}.jpg`
- Запись в `audit_logs` (метаданные) и `audit_files` (информация о файле)

---

## 🔒 Примечания по безопасности для администраторов

1. **Логирование:** Токены сессии и пароли **никогда** не записываются в лог-файлы (`logs/DataSnapServer_*.log`) в открытом виде.
2. **Изоляция запросов:** Благодаря настройке `LifeCycle = Invocation` в `DSServerClass1`, компоненты FireDAC не разделяются между потоками, что делает сервер устойчивым к конкурентным запросам.
3. **Контекст пользователя:** Передача `user_id` осуществляется через `threadvar CurrentUserID` (модуль `ServerSessionContext.pas`). Это самый надежный и быстрый способ передачи контекста в архитектуре Indy + DataSnap, исключающий ошибки `Access Violation`, свойственные `TDSSessionManager`.
4. **Сетевая изоляция:** Сервер слушает только `127.0.0.1`, что делает его недоступным напрямую из внешней сети. Только Nginx (работающий на той же машине) имеет доступ к внутреннему HTTP-порту.

---

## 🧪 Автоматическое тестирование

Проект покрыт **68 автоматическими тестами** (42 модульных + 26 интеграционных) на фреймворке **DUnitX** со **100% успешным прохождением**.

### Модульные тесты (42 теста)

| Модуль | Тестов | Что проверяется |
|--------|:------:|------------------|
| `WinDPAPIUtils.pas` | 5 | Шифрование/дешифрование через Windows DPAPI |
| `ServerSettings.pas` | 7 | Сохранение/загрузка настроек, генерация API-ключей |
| Парсинг JSON | 6 | Обработка всех поддерживаемых форматов входящего JSON |
| `UploadUtils.pas` | 18 | Проверка JPEG-заголовка, SHA-256, генерация UUID, атомарное сохранение, валидация Base64 |
| Парсинг Upload Payload | 6 | Base64-кодирование, координаты, метаданные, обработка больших файлов |
| **ИТОГО** | **42** | **100% прохождение** ✅ |

### Интеграционные тесты (17 тестов)

| Модуль | Тестов | Что проверяется |
|--------|:------:|------------------|
| Авторизация (Login) | 7 | Полный цикл авторизации, валидные/невалидные токены, истечение сессий, множественные сессии, очистка |
| Загрузка файлов | 6 | Загрузка JPEG, валидация формата/размера/координат, откат транзакций, user_id из токена |
| Синхронизация | 4 | Batch-синхронизация, валидация координат, дубликаты, пустой массив |
| Безопасность (Security) | 9 | Brute force (5 попыток → блокировка), rate limiting (20/100 в час), security audit logging, разблокировка, разные IP |
| **ИТОГО** | **26** | **100% прохождение** ✅ |

### Запуск модульных тестов

```bash
cd DataSnapServer\Tests\Win32\Debug
TestRunner.exe
```

### Запуск интеграционных тестов

**Требования:**
1. Docker Desktop запущен
2. Тестовая БД запущена: `docker compose -f docker-compose.test.yml up -d`
3. DataSnap Server запущен **с параметром `/test`** на `http://localhost:8082`

**Первоначальная настройка (один раз):**
```bash
cd DataSnapServer\Tests\Integration
setup-test-env.bat
```
Этот скрипт запустит сервер с параметром `/test` и позволит настроить подключение к тестовой БД через UI.

**Последующие запуски:**
```bash
# Вариант 1: Автоматический запуск (рекомендуется)
cd DataSnapServer\Tests\Integration
run-integration-tests.bat

# Вариант 2: Ручной запуск
start "" "DataSnapServer\Win32\Debug\AuditServer.exe" /test
cd DataSnapServer\Tests\Integration\Win32\Debug
IntegrationTests.exe
```

**Как работает параметр `/test`:**

Параметр `/test` заставляет сервер читать настройки из файла `db_settings_test.xml` вместо `db_settings.xml`. Это позволяет серверу работать с тестовой БД (порт 5433) независимо от продакшен-настроек.

**Реализация в коде:**
```pascal
// ServerSettings.pas
if FindCmdLineSwitch('test', ['-', '/'], True) then
  SettingsFile := TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'db_settings_test.xml')
else
  SettingsFile := TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'db_settings.xml');
```

**Тестовые пользователи:**

В тестовой БД автоматически создаются два пользователя (через `init-test-db.sql`):

| Username | Password | Роль | ID |
|----------|----------|------|:--:|
| `test_user` | `test_password` | user | 1 |
| `test_user_2` | `test_password` | user | 2 |

Пароли хранятся в виде bcrypt-хешей (12 раундов через `pgcrypto`). Тест `TestUpload_DifferentUserID_MatchesToken` использует `test_user_2` для проверки, что `user_id` извлекается из токена, а не хардкодится.

**Проверка тестовых пользователей:**
```bash
docker exec -it audit-test-db psql -U test_user -d audit_test -c "SELECT id, username, role, is_active FROM users;"
```

Подробная документация по тестированию доступна в:
- [Tests/README.md](Tests/README.md) — модульные тесты
- [Tests/Integration/README.md](Tests/Integration/README.md) — интеграционные тесты

---

## 🔮 Roadmap (Планы развития)

- [x] ~~Создание собственной таблицы `users` с криптографическим хешированием паролей (bcrypt) взамен аутентификации через `pg_user`~~ ✅ **Реализовано** (pgcrypto, 12 раундов, fallback на plain text)
- [ ] Настройка фоновой задачи `pg_cron` в PostgreSQL для регулярной очистки просроченных сессий (в дополнение к очистке при старте сервера).
- [ ] Расширенный алертинг: отправка уведомлений о критических ошибках (Fatal) в Telegram или по электронной почте через дополнительные аппендеры LoggerPro.
- [ ] Мониторинг производительности: интеграция с Prometheus/Grafana для отслеживания метрик (количество запросов, время отклика, размер пула соединений).
- [x] ~~Rate limiting: защита от DDoS-атак через ограничение количества запросов с одного IP~~ ✅ **Реализовано** (20/час Login, 100/час Upload, через PostgreSQL)
- [x] ~~Интеграционные тесты с реальной БД PostgreSQL (через Docker-контейнер)~~ ✅ **Реализовано** (26 тестов, Docker Compose, 100% прохождение)
- [x] ~~Загрузка файлов (фотографий) через Base64 в JSON~~ ✅ **Реализовано** (endpoint `/upload`)
- [x] ~~Подключение тестов `TestUploadUtils.pas` и `TestUploadPayloadParser.pas` к `TestRunner.dpr`~~ ✅ **Выполнено** (42 теста, 100% прохождение)

---

## 📄 Лицензия
MIT License. Свободно используйте, модифицируйте и распространяйте.
