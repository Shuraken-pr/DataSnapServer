# 🌐 DataSnap REST Server: FieldAudit Sync Service

Высоконагруженный, безопасный бэкенд-сервис на базе **Embarcadero Delphi 12 (VCL) + DataSnap REST**, разработанный для приема, валидации и сохранения данных от мобильного приложения **FieldAudit** (Android) в центральную базу данных **PostgreSQL**.

Проект реализует паттерн **Offline-First** и прошел полный цикл рефакторинга для соответствия стандартам промышленной эксплуатации (Production-Ready).

## ✨ Ключевые особенности и архитектурные решения

### 🔒 Безопасность (Security)
* **Windows DPAPI:** Пароли от БД и служебные ключи хранятся в `db_settings.xml` в зашифрованном виде. Расшифровка возможна только на той же машине/под той же учетной записью Windows, где было произведено шифрование.
* **Сессионная аутентификация:** Вместо статических ключей используется механизм временных токенов (GUID) с ограниченным временем жизни (TTL), хранящихся в таблице `user_sessions`.
* **Защита от подмены данных (Privilege Escalation):** Сервер **полностью игнорирует** поле `user_id`, передаваемое клиентом в JSON-теле запроса. Реальный `user_id` извлекается исключительно из валидной сессии и принудительно подставляется в SQL-запрос.
* **Timing-Safe сравнение:** Реализовано побитовое XOR-сравнение строк для защиты от атак по времени отклика (Timing Attacks).

### ⚡ Производительность и Надежность
* **Потокобезопасность FireDAC:** Для класса `TDSServerClass` установлен жизненный цикл **`LifeCycle = Invocation`**. Это гарантирует создание нового, изолированного экземпляра `TServerMethods1` (со своими компонентами `TFDConnection` и `TFDQuery`) для *каждого* HTTP-запроса, исключая гонки данных (Race Conditions).
* **Асинхронное логирование:** Интегрирована библиотека **LoggerPro**. Запись логов происходит в фоновом потоке с автоматической ротацией файлов (макс. 15 файлов по 10 МБ), что не блокирует обработку клиентских запросов.
* **Оптимизированный парсинг JSON:** Метод `updateSyncUpload` корректно обрабатывает три возможных формата входящего JSON (строка в обертке, массив в обертке, прямой массив) с гарантированным предотвращением утечек памяти (Memory Leaks).
* **Автоочистка сессий:** При старте сервер автоматически выполняет удаление просроченных записей из таблицы `user_sessions`.

---

## 🏗️ Структура проекта

```text
DataSnapServer/
└── Source/
    ├── FormUnitMain.pas          # Главная форма: инициализация FDManager, автоочистка сессий при старте
    ├── ServerMethodsUnitMain.pas # Бизнес-логика: Login, парсинг JSON, транзакции, SQL-инсерты
    ├── WebModuleUnitMain.pas     # HTTP-перехватчик: проверка токенов, извлечение user_id в threadvar
    ├── ServerSessionContext.pas  # Объявление threadvar CurrentUserID для безопасной межмодульной передачи
    ├── ServerSettings.pas        # Конфигурация: чтение/запись XML, вызов WinDPAPIUtils
    ├── ServerLogger.pas          # Инициализация глобального экземпляра LoggerPro
    ├── WinDPAPIUtils.pas         # Обертка над Crypt32.dll (CryptProtectData / CryptUnprotectData)
    └── frmServerSettings.pas     # UI формы настроек с кнопкой "Тест соединения"
```

---

## 🛠️ Требования и зависимости

1. **Embarcadero Delphi 11/12** (с поддержкой 64-bit Windows).
2. **PostgreSQL 13+** (с установленным расширением `pg_cron` для периодической очистки, опционально).
3. **Библиотека LoggerPro:** Должна быть установлена через *Tools → GetIt Package Manager* или добавлена в *Library Path* (папка `src` из репозитория).
4. **FireDAC:** Драйвер `libpq.dll` должен быть доступен в PATH системы или в папке с исполняемым файлом.

---

## 🗄️ Настройка базы данных (PostgreSQL)

Перед запуском сервера выполните следующий SQL-скрипт в вашей базе данных для создания необходимых таблиц и индексов:

```sql
-- 1. Таблица пользователей (для первичной аутентификации)
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    password VARCHAR(255) NOT NULL -- В продакшене рекомендуется хранить хэш (bcrypt/SHA-256)
);

-- 2. Таблица активных сессий
CREATE TABLE user_sessions (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
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
```

---

## 🚀 Запуск и конфигурация

1. Скомпилируйте проект в Delphi.
2. При **первом запуске** сервер автоматически откроет окно **"Настройка подключения"**.
3. Введите параметры подключения к PostgreSQL (Host, Database, Username, Password).
4. Нажмите **"Тест соединения"**. Если успешно, нажмите **OK**.
5. Сервер сохранит настройки в файл `db_settings.xml` (пароль будет зашифрован через DPAPI) и запустит HTTP-слушатель.

> **Важно:** Если вы переносите исполняемый файл и `db_settings.xml` на другой компьютер, сервер не сможет расшифровать пароль и потребует настройки заново. Это ожидаемое поведение системы безопасности DPAPI.

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
  "error": "Unauthorized: invalid or expired session token"
}
```

---

## 🔒 Примечания по безопасности для администраторов

1. **Логирование:** Токены сессии и пароли **никогда** не записываются в лог-файлы (`logs/DataSnapServer_*.log`) в открытом виде.
2. **Изоляция запросов:** Благодаря настройке `LifeCycle = Invocation` в `DSServerClass1`, компоненты FireDAC не разделяются между потоками, что делает сервер устойчивым к конкурентным запросам.
3. **Контекст пользователя:** Передача `user_id` осуществляется через `threadvar CurrentUserID` (модуль `ServerSessionContext.pas`). Это самый надежный и быстрый способ передачи контекста в архитектуре Indy + DataSnap, исключающий ошибки `Access Violation`, свойственные `TDSSessionManager`.

---

## 🔮 Roadmap (Планы развития)

- [ ] Переход на криптографическое хеширование паролей (bcrypt или Argon2) в таблице `users` вместо хранения в открытом виде.
- [ ] Настройка фоновой задачи `pg_cron` в PostgreSQL для регулярной очистки просроченных сессий (в дополнение к очистке при старте сервера).
- [ ] Внедрение HTTPS/TLS: настройка `TIdServerIOHandlerSSLOpenSSL` или использование Reverse Proxy (Nginx/Apache) для шифрования всего входящего трафика.
- [ ] Расширенный алертинг: отправка уведомлений о критических ошибках (Fatal) в Telegram или по электронной почте через дополнительные аппендеры LoggerPro.

---

## 📄 Лицензия
MIT License. Свободно используйте, модифицируйте и распространяйте.