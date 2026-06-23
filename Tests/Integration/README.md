# Интеграционные тесты DataSnap Server

## Обзор

Этот проект содержит интеграционные тесты для DataSnap REST-сервера. Тесты выполняются через реальное HTTP-соединение с сервером и проверяют работу endpoints вместе с базой данных PostgreSQL.

## Требования

- **Delphi 12** (или выше)
- **DUnitX** (встроен в Delphi 12)
- **PostgreSQL** (запущен через Docker Compose)
- **DataSnap Server** (скомпилирован и запущен с параметром `/test`)
- **Docker Desktop** (для Windows) или **Docker Engine** (для Linux)

## Структура проекта

| Файл | Назначение |
|------|------------|
| `IntegrationTests.dpr` | Главный файл проекта тестов |
| `TestBase.pas` | Базовый класс с подключением к БД и HTTP-клиентом |
| `TestLoginIntegration.pas` | Тесты авторизации (Login + токены) |
| `TestSyncIntegration.pas` | Тесты синхронизации данных (SyncUpload) |
| `TestUploadIntegration.pas` | Тесты загрузки файлов (POST /upload) |
| `docker-compose.test.yml` | Docker Compose для тестовой БД |
| `init-test-db.sql` | Скрипт инициализации тестовой БД |

## Быстрый старт (одной командой)

```bash
cd DataSnapServer\Tests\Integration
quick-start.bat
```

Скрипт `quick-start.bat` выполняет полный цикл: запуск Docker → запуск сервера → выполнение тестов.

## Ручной запуск (пошагово)

### 1. Запуск тестовой базы данных (PostgreSQL)

```bash
docker compose -f docker-compose.test.yml up -d
```

Контейнер `audit-test-db` запустится на порту **5433** (изолирован от production базы на 5432).

### 2. Настройка сервера для тестов

Сервер должен быть запущен с параметром `/test` для использования тестовых настроек:

```bash
cd DataSnapServer\Source\Win32\Debug
AuditServer.exe /test
```

Или настройте ярлык для запуска с параметром `/test`.

### 3. Компиляция и запуск тестов

```bash
cd DataSnapServer\Tests\Integration
# Компиляция (Delphi IDE)
# Откройте IntegrationTests.dpr в Delphi и нажмите Ctrl+F9

# Запуск тестов
Win32\Debug\IntegrationTests.exe
```

## Результаты тестов

Тесты сохраняют результаты в файл `dunitx-results.xml` в формате XML для интеграции с CI/CD.

Пример вывода:
```xml
<testsuites>
  <testsuite name="TTestLoginIntegration" tests="7" failures="0" time="3.0">
    <testcase name="TestLogin_ValidCredentials_ReturnsToken" time="0.5"/>
    <testcase name="TestLogin_InvalidPassword_Returns401" time="0.5"/>
    <testcase name="TestValidToken_AccessProtectedEndpoint_Returns200" time="0.5"/>
    <testcase name="TestInvalidToken_AccessProtectedEndpoint_Returns401" time="0.5"/>
    <testcase name="TestExpiredToken_AccessProtectedEndpoint_Returns401" time="0.5"/>
    <testcase name="TestSession_MultipleTokens_SameUser" time="0.5"/>
    <testcase name="TestSession_CleanupTestData_RemovesSessions" time="0.5"/>
  </testsuite>
  <testsuite name="TTestUploadIntegration" tests="6" failures="0" time="2.8">
    <testcase name="TestUpload_ValidJpeg_CreatesFileAndRecords" time="0.7"/>
    <testcase name="TestUpload_NonJpegFile_Returns400" time="0.5"/>
    <testcase name="TestUpload_TooLargeFile_Returns413" time="0.5"/>
    <testcase name="TestUpload_InvalidBase64_NoRecordsCreated" time="0.5"/>
    <testcase name="TestUpload_DifferentUserID_MatchesToken" time="0.8"/>
    <testcase name="TestUpload_InvalidCoordinates_Returns400" time="0.8"/>
  </testsuite>
  <testsuite name="TTestSyncIntegration" tests="4" failures="0" time="2.0">
    <testcase name="TestBatchSync_MultipleRecords_AllCreated" time="0.8"/>
    <testcase name="TestSync_InvalidCoordinates_Returns400" time="0.5"/>
    <testcase name="TestSync_EmptyArray_Returns200NoRecords" time="0.4"/>
    <testcase name="TestUpload_SameFileTwice_CreatesTwoRecords" time="0.3"/>
  </testsuite>
</testsuites>
```

## ✅ Реализованные тесты (17 тестов)

| Тестовый набор | Тестов | Назначение |
|----------------|:------:|------------|
| `TTestLoginIntegration` | 7 | Авторизация, валидные/невалидные токены, истечение сессий, множественные сессии, очистка |
| `TTestUploadIntegration` | 6 | Загрузка фото, валидация формата/размера/координат, откат транзакций, user_id из токена |
| `TTestSyncIntegration` | 4 | Batch-синхронизация, валидация координат, дубликаты, пустой массив |
| **ИТОГО** | **17** | **Полное покрытие критических сценариев** |

### Подробное описание тестов

#### TTestLoginIntegration (7 тестов)
1. **TestLogin_ValidCredentials_ReturnsToken** (INT-001) — полный цикл авторизации через таблицу users с bcrypt
2. **TestLogin_InvalidPassword_Returns401** (INT-002) — неверный пароль (bcrypt отклоняет)
3. **TestValidToken_AccessProtectedEndpoint_Returns200** (INT-003) — валидный токен
4. **TestInvalidToken_AccessProtectedEndpoint_Returns401** (INT-004) — невалидный токен
5. **TestExpiredToken_AccessProtectedEndpoint_Returns401** (INT-008) — просроченный токен
6. **TestSession_MultipleTokens_SameUser** (INT-011) — несколько валидных токенов для одного пользователя
7. **TestSession_CleanupTestData_RemovesSessions** (INT-012) — очистка тестовых данных удаляет сессии

#### TTestUploadIntegration (6 тестов)
1. **TestUpload_ValidJpeg_CreatesFileAndRecords** (INT-005) — загрузка JPEG, проверка user_id из токена
2. **TestUpload_NonJpegFile_Returns400** (INT-006) — не-JPEG файл
3. **TestUpload_TooLargeFile_Returns413** (INT-007) — слишком большой файл
4. **TestUpload_InvalidBase64_NoRecordsCreated** (INT-009) — откат транзакции
5. **TestUpload_DifferentUserID_MatchesToken** (INT-005b) — user_id из токена, не хардкод (user_id=2)
6. **TestUpload_InvalidCoordinates_Returns400** (INT-005c) — валидация координат в /upload

#### TTestSyncIntegration (4 теста)
1. **TestBatchSync_MultipleRecords_AllCreated** (INT-010) — batch из 10 записей
2. **TestSync_InvalidCoordinates_Returns400** (INT-013) — невалидные координаты (lat=100) — валидация на сервере
3. **TestSync_EmptyArray_Returns200NoRecords** (INT-014) — пустой массив
4. **TestUpload_SameFileTwice_CreatesTwoRecords** (INT-015) — дублирование файла (разные UUID, одинаковый checksum)

## 🔑 Особенности тестовой инфраструктуры

### Миграция тестовой БД

Тестовая БД инициализируется через `init-test-db.sql`, который:
- ✅ Создаёт таблицу `users` с полями из Postgre_Delphi (`id BIGINT GENERATED ALWAYS AS IDENTITY`)
- ✅ Расширяет таблицу полями безопасности (`password_hash`, `is_active`, `role`, `last_login_at`, `failed_login_attempts`, `locked_until`)
- ✅ Устанавливает расширение `pgcrypto` для bcrypt
- ✅ Создаёт вспомогательные таблицы (`events`, `audit_logs`, `audit_files`, `user_sessions`)
- ✅ Идемпотентен — можно запускать многократно

**Проверка структуры:**
```bash
docker exec -it audit-test-db psql -U test_user -d audit_test -c "\d users"
```

### Аутентификация через bcrypt (pgcrypto)

Сервер теперь использует собственную таблицу `users` с хешированием паролей через `bcrypt` (расширение `pgcrypto` PostgreSQL). Тестовый пользователь создаётся в `init-test-db.sql`:

```sql
INSERT INTO users (username, password_hash, is_active)
VALUES (
    'test_user',
    crypt('test_password', gen_salt('bf', 12)),
    TRUE
);
```

### Тестовые данные (test_user / test_password)

- **Username:** `test_user`
- **Password:** `test_password`
- **ID:** Определяется автоматически (`GENERATED ALWAYS AS IDENTITY`), получается через `GetTestUserID()`

### Изоляция тестов

- Каждый тест выполняет `CleanupTestData` в `TearDown`
- Docker-контейнер использует отдельную БД `audit_test` на порту **5433**
- Сервер запускается с `/test` для изоляции настроек

### Поддержка DataSnap REST

Тесты учитывают особенность DataSnap REST: методы возвращают `string`, который оборачивается в `{"result": [...]}`. Парсинг ответа учитывает двойную обёртку JSON.

### Параметризация через переменные окружения

Копируйте `.env.example` в `.env` и настройте параметры подключения:

```bash
cp .env.example .env
# Отредактируйте .env в текстовом редакторе
```

## 🔧 Диагностика

### Тесты не проходят: "Connection refused"
- Убедитесь, что сервер запущен с параметром `/test`
- Проверьте, что сервер слушает порт 8082: `netstat -an | findstr 8082`

### Тесты не проходят: "Docker not running"
- Запустите Docker Desktop
- Проверьте: `docker ps`

### Тесты не проходят: " relation \"events\" does not exist"
- Выполните `init-test-db.sql` в тестовой БД:
  ```bash
  docker compose -f docker-compose.test.yml exec -T db psql -U postgres -d audit_test < init-test-db.sql
  ```

### Тесты не проходят: "test_user not found"
- Выполните `init-test-db.sql` для создания тестовых пользователей
- Проверьте, что расширение `pgcrypto` установлено:
  ```sql
  CREATE EXTENSION IF NOT EXISTS pgcrypto;
  ```

## 📝 Changelog

| Дата | Версия | Изменения |
|------|--------|-----------|
| 2026-06-22 | 1.2 | Миграция на bcrypt (pgcrypto), собственная таблица users, 17 тестов, валидация координат |
| 2026-06-22 | 1.1 | Добавлена поддержка параметра `/test` для сервера, скрипты автоматизации |
| 2026-06-21 | 1.0 | Начальная версия: 13 интеграционных тестов |

---

**Версия:** 1.2
**Дата:** 2026-06-22
**Статус:** ✅ Готово к использованию
