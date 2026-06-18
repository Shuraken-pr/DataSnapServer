# 🌐 DataSnap REST Server: FieldAudit Sync Service

Высоконагруженный, безопасный бэкенд-сервис на базе **Embarcadero Delphi 12 (VCL) + DataSnap REST**, разработанный для приема, валидации и сохранения данных от мобильного приложения **FieldAudit** (Android) в центральную базу данных **PostgreSQL**.

Проект реализует паттерн **Offline-First** и прошел полный цикл рефакторинга для соответствия стандартам промышленной эксплуатации (Production-Ready).

## ✨ Ключевые особенности и архитектурные решения

### 🔒 Безопасность (Security)
* **Windows DPAPI:** Пароли от БД и API-ключи хранятся в `db_settings.xml` в зашифрованном виде. Используется флаг `CRYPTPROTECT_LOCAL_MACHINE` — расшифровка возможна только на том же компьютере, где было произведено шифрование (любым пользователем на этой машине).
* **Сессионная аутентификация:** Вместо статических ключей используется механизм временных токенов (GUID) с ограниченным временем жизни (TTL), хранящихся в таблице `user_sessions`.
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
└── Source/
    ├── FormUnitMain.pas          # Главная форма: инициализация FDManager, автоочистка сессий при старте
    ├── ServerMethodsUnitMain.pas # Бизнес-логика: Login, парсинг JSON, транзакции, SQL-инсерты
    ├── WebModuleUnitMain.pas     # HTTP-перехватчик: проверка токенов, извлечение user_id в threadvar
    ├── ServerSessionContext.pas  # Объявление threadvar CurrentUserID для безопасной межмодульной передачи
    ├── ServerSettings.pas        # Конфигурация: чтение/запись XML, генерация API-ключа (RtlGenRandom), вызов WinDPAPIUtils
    ├── ServerLogger.pas          # Инициализация глобального экземпляра LoggerPro (мин. уровень Info, ротация 15×10 МБ)
    ├── WinDPAPIUtils.pas         # Обертка над Crypt32.dll (CryptProtectData / CryptUnprotectData, флаг CRYPTPROTECT_LOCAL_MACHINE)
    └── frServerSettings.pas      # UI формы настроек: тест соединения, генерация API-ключа, сброс флага теста при изменении полей
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

Перед запуском сервера выполните следующий SQL-скрипт в вашей базе данных для создания необходимых таблиц и индексов:

```sql
-- 1. Аутентификация использует встроенные учётные записи PostgreSQL (pg_user).
--    Отдельная таблица users НЕ требуется: Login подключается к БД от имени
--    указанного пользователя и извлекает usesysid из системного каталога.
--    В дальнейшем рекомендуется создать собственную таблицу с хэшированием паролей (bcrypt/Argon2).

-- 2. Таблица активных сессий
CREATE TABLE user_sessions (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL,  -- ID из pg_user.usesysid
    session_token VARCHAR(64) UNIQUE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP NOT NULL
);

-- Критически важный индекс для молниеносной проверки токена при каждом запросе
CREATE INDEX idx_user_sessions_token ON user_sessions(session_token);

-- 3. Целевая таблица событий (пример)
CREATE TABLE events (
    id SERIAL PRIMARY KEY,
    user_id INT NOT NULL,
    event_type VARCHAR(50) NOT NULL,
    occurred_at TIMESTAMP NOT NULL,
    metadata JSONB
);

-- 4. Очистка просроченных сессий (выполняется при старте сервера)
DELETE FROM user_sessions WHERE expires_at < CURRENT_TIMESTAMP;
```

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
  "token": "{86AB48DA-D896-4480-8BA8-99E620F05C5E}"
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

**Response (401 Unauthorized):**
```json
{
  "error": "Unauthorized: session expired or invalid"
}
```

---

## 🔒 Примечания по безопасности для администраторов

1. **Логирование:** Токены сессии и пароли **никогда** не записываются в лог-файлы (`logs/DataSnapServer_*.log`) в открытом виде.
2. **Изоляция запросов:** Благодаря настройке `LifeCycle = Invocation` в `DSServerClass1`, компоненты FireDAC не разделяются между потоками, что делает сервер устойчивым к конкурентным запросам.
3. **Контекст пользователя:** Передача `user_id` осуществляется через `threadvar CurrentUserID` (модуль `ServerSessionContext.pas`). Это самый надежный и быстрый способ передачи контекста в архитектуре Indy + DataSnap, исключающий ошибки `Access Violation`, свойственные `TDSSessionManager`.
4. **Сетевая изоляция:** Сервер слушает только `127.0.0.1`, что делает его недоступным напрямую из внешней сети. Только Nginx (работающий на той же машине) имеет доступ к внутреннему HTTP-порту.

---

## 🧪 Автоматическое тестирование

Проект покрыт **18 автоматическими модульными тестами** на фреймворке **DUnitX** со **100% успешным прохождением**.

### Покрытие тестами

| Модуль | Тестов | Что проверяется |
|--------|:------:|------------------|
| `WinDPAPIUtils.pas` | 5 | Шифрование/дешифрование через Windows DPAPI |
| `ServerSettings.pas` | 7 | Сохранение/загрузка настроек, генерация API-ключей |
| Парсинг JSON | 6 | Обработка всех поддерживаемых форматов входящего JSON |
| **ИТОГО** | **18** | **100% прохождение** ✅ |

### Запуск тестов

```bash
cd DataSnapServer\Tests\Win32\Debug
TestRunner.exe
```

Подробная документация по тестированию доступна в [Tests/README.md](Tests/README.md).

---

## 🔮 Roadmap (Планы развития)

- [ ] Создание собственной таблицы `users` с криптографическим хешированием паролей (bcrypt или Argon2) взамен аутентификации через `pg_user`.
- [ ] Настройка фоновой задачи `pg_cron` в PostgreSQL для регулярной очистки просроченных сессий (в дополнение к очистке при старте сервера).
- [ ] Расширенный алертинг: отправка уведомлений о критических ошибках (Fatal) в Telegram или по электронной почте через дополнительные аппендеры LoggerPro.
- [ ] Мониторинг производительности: интеграция с Prometheus/Grafana для отслеживания метрик (количество запросов, время отклика, размер пула соединений).
- [ ] Rate limiting: защита от DDoS-атак через ограничение количества запросов с одного IP (через Nginx или встроенный механизм).
- [ ] Интеграционные тесты с реальной БД PostgreSQL (через Docker-контейнер).
- [ ] Загрузка файлов (фотографий) через Multipart/Form-Data.

---

## 📄 Лицензия
MIT License. Свободно используйте, модифицируйте и распространяйте.
