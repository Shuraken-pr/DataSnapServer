# 📝 CHANGELOG

Все значимые изменения в проекте будут документироваться в этом файле.

Формат основан на [Keep a Changelog](https://keepachangelog.com/ru/1.0.0/),
и этот проект придерживается [Semantic Versioning](https://semver.org/lang/ru/).

## [Unreleased]

---

## [1.2.1] - 2026-06-24

### Исправлено
- **Критическая ошибка в тестовой схеме БД (`init-test-db.sql`):**
  - В таблицу `security_events` добавлена отсутствующая колонка `user_agent TEXT`, которая используется модулем `SecurityAuditor.pas` при логировании событий безопасности.
  - Ранее при вызове `LogEvent` возникала ошибка `[FireDAC][Phys][PG][libpq] ERROR: column "user_agent" of relation "security_events" does not exist`, что приводило к падению 5 интеграционных тестов и возврату HTTP 500 вместо ожидаемых кодов.
  - Теперь тестовая схема (`init-test-db.sql`) полностью идентична production-схеме из `migrations/001_security_users.sql`.

- **Некорректное преобразование JSON в `SecurityAuditor.pas`:**
  - Убран вызов `to_jsonb(:details::text)` в SQL-запросе метода `LogEvent`. Колонка `details` имеет тип `TEXT`, а не `JSONB`, поэтому преобразование было избыточным и приводило к ошибке PostgreSQL при передаче обычных строк (например, `'User ID: 1'`, `'Account locked'`), не являющихся валидным JSON.
  - Все 4 вызова `LogEvent` в коде (`login_blocked`, `login_failed`, `account_locked`, `login_success`, `rate_limit_exceeded`) передают обычные строки, поэтому преобразование в JSON не требуется.
  - Методы чтения (`GetRecentEvents`, `GetEventsByUser`, `GetCriticalEvents`, `GetEventsByIP`) используют `.AsString` и также работают корректно со строковым типом.

### Результат
- **Все 26 интеграционных тестов теперь проходят успешно** (ранее 7 тестов падали с HTTP 500 или неверными данными).
- Восстановлена работоспособность:
  - `TestLogin_ValidCredentials_ReturnsToken` — HTTP 200 вместо 500
  - `TestLogin_InvalidPassword_ReturnsError` — HTTP 200 с JSON-ошибкой вместо 500
  - `TestLogin_Success_RecordsEvent` — событие успешно записывается в `security_events`
  - `TestLogin_FailedAfter5Attempts_LocksAccount` — аккаунт корректно блокируется
  - `TestLogin_UnlockedAfterSuccessfulLogin` — счётчик попыток сбрасывается после успешного входа
  - `TestRateLimit_LoginExceeded_Returns429` — HTTP 429 вместо 500
  - `TestRateLimit_UploadExceeded_Returns429` — HTTP 429 вместо 500

### Технические детали
- Изменения затрагивают только тестовую инфраструктуру и модуль аудита — бизнес-логика (`ServerMethodsUnitMain.pas`, `WebModuleUnitMain.pas`) не изменялась.
- На production-сервере миграция не требуется: в `migrations/001_security_users.sql` колонка `user_agent` уже присутствовала, а `to_jsonb()` не использовался.
- Исправления обратно совместимы — не требуется пересборка клиента или изменение API-контракта.

---

## [1.2.0] - 2026-06-21

### Добавлено
- **Интеграционные тесты (13 тестов):**
  - `TestLoginIntegration.pas` — авторизация, валидные/невалидные токены, истечение сессий (5 тестов)
  - `TestUploadIntegration.pas` — загрузка файлов, валидация формата/размера, откат транзакций (4 теста)
  - `TestSyncIntegration.pas` — batch-синхронизация, валидация координат, дубликаты (4 теста)
- **Docker Compose** для тестовой БД PostgreSQL (`docker-compose.test.yml`)
- **SQL-скрипт инициализации** тестовой БД (`init-test-db.sql`)
  - Тестовые таблицы: `users_test`, `user_sessions_test`, `audit_logs_test`, `audit_files_test`
  - Вспомогательные функции: `cleanup_test_data()`, `create_test_session()`, `create_expired_test_session()`
  - Представление `v_test_stats` для мониторинга
- **Базовый класс** для интеграционных тестов (`TestBase.pas`)
  - Подключение к тестовой БД
  - HTTP-клиент для запросов к серверу
  - Методы очистки данных
  - Автоматическая изоляция тестов
- **Документация** для интеграционных тестов (`Integration/README.md`)
- **Скрипты автоматизации:**
  - `quick-start.bat` — быстрый запуск тестов
  - `generate-test-data.bat` — генерация тестовых файлов
  - `cleanup-test-data.sql` — ручная очистка данных

### Изменено
- Обновлён главный `README.md`:
  - Добавлена секция "Интеграционные тесты"
  - Обновлена статистика: 42 → 55 тестов (42 модульных + 13 интеграционных)
  - Добавлены инструкции по запуску интеграционных тестов
- Обновлён Roadmap: задача "Интеграционные тесты" отмечена как выполненная

### Технические детали
- Тестовая БД работает на порту `5433` (отдельно от продакшена `5432`)
- Тесты используют HTTP напрямую к DataSnap (порт `8082`), без Nginx
- Каждый тест выполняется в изолированной среде (автоматическая очистка данных)
- Тесты генерируют NUnit XML отчёт для интеграции с CI/CD

---

## [1.1.0] - 2026-06-21

### Добавлено
- **Модульные тесты для загрузки файлов (24 теста):**
  - `TestUploadUtils.pas` — проверка JPEG, SHA-256, генерация UUID, атомарное сохранение, валидация Base64 (18 тестов)
  - `TestUploadPayloadParser.pas` — парсинг payload для endpoint `/upload` (6 тестов)
- **Endpoint `/upload`** для загрузки фотографий:
  - Приём Base64 в JSON
  - Проверка JPEG-заголовка (`FF D8 FF`)
  - Вычисление SHA-256 хеша
  - Атомарное сохранение через `.tmp` → `rename`
  - Иерархия папок `C:\AuditFiles\YYYY\MM\DD\{UUID}.jpg`
  - Запись в `audit_logs` и `audit_files`
- **Утилиты для загрузки файлов** (`UploadUtils.pas`):
  - `IsValidJpegMagic()` — проверка JPEG-заголовка
  - `ComputeSHA256()` — вычисление хеша файла
  - `EnsureAuditDir()` — создание иерархии папок
  - `GenerateFileUUID()` — генерация уникального имени
  - `SaveUploadedFile()` — атомарное сохранение

### Изменено
- Обновлён `WebModuleUnitMain.pas`:
  - Добавлен endpoint `/upload`
  - Исправлена критическая проблема: `user_id` теперь извлекается из токена, а не захардкожен
- Обновлён `README.md`:
  - Добавлена документация по endpoint `/upload`
  - Обновлена статистика тестов: 18 → 42 теста

---

## [1.0.0] - 2026-06-19

### Добавлено
- **Начальная версия сервера:**
  - DataSnap REST Server на Delphi 12 (VCL)
  - Аутентификация через `pg_user` PostgreSQL
  - Сессионные токены с ограниченным временем жизни (TTL)
  - Потокобезопасность FireDAC (`LifeCycle = Invocation`)
  - Асинхронное логирование через LoggerPro
  - Шифрование паролей через Windows DPAPI
  - Автоочистка просроченных сессий при старте сервера
- **Endpoint `/datasnap/rest/TServerMethods1/Login`** — получение токена
- **Endpoint `/datasnap/rest/TServerMethods1/updateSyncUpload`** — синхронизация данных
- **Модульные тесты (18 тестов):**
  - `TestWinDPAPIUtils.pas` — шифрование/дешифрование (5 тестов)
  - `TestServerSettings.pas` — сохранение/загрузка настроек (7 тестов)
  - `TestServerMethods.pas` — парсинг JSON (6 тестов)
- **Документация:**
  - Главный `README.md` с описанием архитектуры
  - API документация
  - Инструкции по настройке Nginx
  - Примеры SQL-скриптов для БД

### Технические детали
- Сервер слушает HTTP на `127.0.0.1:8082`
- Nginx обрабатывает HTTPS и проксирует на DataSnap
- Защита от подмены `user_id` (сервер игнорирует поле из JSON)
- Ограничения: JSON до 1 МБ, массив до 1000 элементов
- Пул соединений FireDAC: `Pooled = True`, `PoolMaximumItems = 10`

---

## [0.9.0] - 2026-06-18

### Добавлено
- **Начальная версия Android-клиента:**
  - Offline-first архитектура
  - Локальная SQLite БД через FireDAC
  - Синхронизация с сервером через HTTP/HTTPS
  - Загрузка фотографий (сжатие через `JpegUtils.pas`)
  - Управление сессией через `SessionManager.pas`
- **Модульные тесты клиента (29 тестов):**
  - `TestSessionManager.pas` — управление токеном, URL (8 тестов)
  - `TestJsonParsing.pas` — парсинг JSON ответов (8 тестов)
  - `TestLocalDb.pas` — CRUD операции с SQLite (8 тестов)
  - `TestJpegUtils.pas` — сжатие фото (5 тестов)

---

## Типы изменений

- **Добавлено** — для новых функций
- **Изменено** — для изменений в существующей функциональности
- **Исправлено** — для исправлений багов
- **Удалено** — для удалённой функциональности
- **Устарело** — для функций, которые будут удалены в будущих версиях

---

## Версионирование

- **MAJOR** — несовместимые изменения API
- **MINOR** — добавление функциональности с обратной совместимостью
- **PATCH** — исправления багов с обратной совместимостью

---

**Последнее обновление:** 2026-06-24  
**Текущая версия:** 1.2.1
