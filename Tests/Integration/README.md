# 🔧 Интеграционные тесты для Audit Server

## 📋 Описание

Интеграционные тесты проверяют **взаимодействие между компонентами системы** в условиях, максимально приближенных к продакшену:
- Android-клиент ↔ DataSnap-сервер ↔ PostgreSQL
- Реальные HTTP-запросы
- Реальные транзакции в БД
- Реальные файлы на диске

## 📊 Статистика покрытия

### ✅ Реализованные тесты (15 тестов)

| Тестовый набор | Тестов | Назначение |
|----------------|:------:|------------|
| `TTestLoginIntegration` | 5 | Авторизация, валидные/невалидные токены, истечение сессий |
| `TTestUploadIntegration` | 4 | Загрузка фото, валидация формата, размера, откат транзакций |
| `TTestSyncIntegration` | 4 | Batch-синхронизация, валидация координат, дубликаты |
| **ИТОГО** | **13** | **Полное покрытие критических сценариев** |

### 📝 Список тестов

#### TTestLoginIntegration (5 тестов)
1. **TestLogin_ValidCredentials_ReturnsToken** (INT-001) — полный цикл авторизации
2. **TestLogin_InvalidPassword_Returns401** (INT-002) — неверный пароль
3. **TestValidToken_AccessProtectedEndpoint_Returns200** (INT-003) — валидный токен
4. **TestInvalidToken_AccessProtectedEndpoint_Returns401** (INT-004) — невалидный токен
5. **TestExpiredToken_AccessProtectedEndpoint_Returns401** (INT-008) — просроченный токен

#### TTestUploadIntegration (4 теста)
1. **TestUpload_ValidJpeg_CreatesFileAndRecords** (INT-005) — загрузка JPEG
2. **TestUpload_NonJpegFile_Returns400** (INT-006) — не-JPEG файл
3. **TestUpload_TooLargeFile_Returns413** (INT-007) — слишком большой файл
4. **TestUpload_InvalidBase64_NoRecordsCreated** (INT-009) — откат транзакции

#### TTestSyncIntegration (4 теста)
1. **TestBatchSync_MultipleRecords_AllCreated** (INT-010) — batch-синхронизация
2. **TestSync_InvalidCoordinates_Returns400** (INT-013) — валидация координат
3. **TestSync_EmptyArray_Returns200NoRecords** (INT-014) — пустой массив
4. **TestUpload_SameFileTwice_CreatesTwoRecords** (INT-015) — дубликаты

---

## 🚀 Быстрый старт

### Шаг 1: Установка Docker Desktop

Скачайте и установите Docker Desktop:
- **Windows:** https://www.docker.com/products/docker-desktop

Проверьте установку:
```bash
docker --version
docker compose version
```

### Шаг 2: Запуск тестовой БД

Перейдите в папку с интеграционными тестами:
```bash
cd DataSnapServer\Tests\Integration
```

Запустите тестовую БД:
```bash
docker compose -f docker-compose.test.yml up -d
```

Проверьте статус:
```bash
docker compose -f docker-compose.test.yml ps
```

Ожидаемый вывод:
```
NAME            IMAGE              STATUS         PORTS                    NAMES
audit-test-db   postgres:14-alpine Up (healthy)   0.0.0.0:5433->5432/tcp   audit-test-db
```

### Шаг 3: Первоначальная настройка сервера для тестов

**⚠️ ВАЖНО:** Сервер DataSnap должен быть настроен на работу с тестовой БД. Для этого используется параметр командной строки `/test`.

**Первый запуск (настройка):**
```bash
setup-test-env.bat
```

Этот скрипт:
1. Запустит сервер с параметром `/test`
2. Откроет диалог настройки подключения к БД
3. Вам нужно будет указать параметры тестовой БД:
   - Хост: `localhost`
   - Порт: `5433`
   - БД: `audit_test`
   - Пользователь: `test_user`
   - Пароль: `test_password`
4. Сервер сохранит настройки в файл `db_settings_test.xml`

**Последующие запуски:**
После первоначальной настройки сервер можно запускать с параметром `/test` напрямую:
```bash
start "" "..\Win32\Debug\AuditServer.exe" /test
```

### Шаг 4: Запуск интеграционных тестов

**Автоматический запуск (рекомендуется):**
```bash
run-integration-tests.bat
```

Этот скрипт:
1. Проверит, что Docker-контейнер запущен
2. Проверит, что сервер запущен с параметром `/test`
3. Запустит интеграционные тесты
4. Покажет результаты

**Ручной запуск:**
1. Откройте `IntegrationTests.dpr` в Delphi
2. Нажмите **Ctrl+F9** (Compile)
3. Нажмите **F9** (Run)

Или из командной строки:
```bash
cd Win32\Debug
.\IntegrationTests.exe
```

---

## 📁 Структура проекта

```
Integration/
├── IntegrationTests.dpr              ← Главный файл проекта
├── TestBase.pas                       ← Базовый класс для тестов
├── TestLoginIntegration.pas           ← Тесты авторизации (INT-001..004, 008)
├── TestUploadIntegration.pas          ← Тесты загрузки файлов (INT-005..007, 009)
├── TestSyncIntegration.pas            ← Тесты синхронизации (INT-010, 013..015)
├── docker-compose.test.yml            ← Docker Compose для тестовой БД
├── init-test-db.sql                   ← SQL-скрипт инициализации БД
├── setup-test-env.bat                 ← Скрипт первоначальной настройки
├── run-integration-tests.bat          ← Скрипт запуска тестов
├── README.md                          ← Документация (этот файл)
└── TestData/                          ← Тестовые данные (опционально)
    └── README.md                      ← Описание тестовых данных
```

---

## 🗄️ Тестовая база данных

### Параметры подключения

| Параметр | Значение |
|----------|----------|
| **Хост** | `localhost` |
| **Порт** | `5433` (отдельный от продакшена) |
| **База данных** | `audit_test` |
| **Пользователь** | `test_user` |
| **Пароль** | `test_password` |

### Таблицы

- `users_test` — тестовые пользователи
- `user_sessions_test` — тестовые сессии
- `audit_logs_test` — тестовые журналы аудита
- `audit_files_test` — тестовые файлы

### Вспомогательные функции

- `cleanup_test_data()` — очистка всех тестовых данных
- `create_test_session(user_id, expires_in)` — создание валидной сессии
- `create_expired_test_session(user_id, expired_ago)` — создание просроченной сессии

### Представления

- `v_test_stats` — статистика тестовых данных

---

## 🔧 Управление тестовой БД

### Запуск
```bash
docker-compose -f docker-compose.test.yml up -d
```

### Остановка
```bash
docker-compose -f docker-compose.test.yml down
```

### Перезапуск
```bash
docker-compose -f docker-compose.test.yml restart
```

### Полное удаление (с данными)
```bash
docker-compose -f docker-compose.test.yml down -v
```

### Просмотр логов
```bash
docker-compose -f docker-compose.test.yml logs -f
```

### Подключение к БД через psql
```bash
docker exec -it audit-test-db psql -U test_user -d audit_test
```

### Ручная очистка данных
```sql
SELECT cleanup_test_data();
```

---

## 📊 Результаты тестов

После запуска тестов создаётся файл `integration-test-results.xml` в формате NUnit XML.

### Пример вывода
```
========================================
  Integration Tests for Audit Server
========================================

Требования:
1. Docker Desktop запущен
2. Тестовая БД запущена: docker-compose -f docker-compose.test.yml up -d
3. DataSnap Server запущен на http://localhost:8082

Запуск тестов...

[TTestLoginIntegration]
  [PASS] TestLogin_ValidCredentials_ReturnsToken
  [PASS] TestLogin_InvalidPassword_Returns401
  [PASS] TestValidToken_AccessProtectedEndpoint_Returns200
  [PASS] TestInvalidToken_AccessProtectedEndpoint_Returns401
  [PASS] TestExpiredToken_AccessProtectedEndpoint_Returns401

[TTestUploadIntegration]
  [PASS] TestUpload_ValidJpeg_CreatesFileAndRecords
  [PASS] TestUpload_NonJpegFile_Returns400
  [PASS] TestUpload_TooLargeFile_Returns413
  [PASS] TestUpload_InvalidBase64_NoRecordsCreated

[TTestSyncIntegration]
  [PASS] TestBatchSync_MultipleRecords_AllCreated
  [PASS] TestSync_InvalidCoordinates_Returns400
  [PASS] TestSync_EmptyArray_Returns200NoRecords
  [PASS] TestUpload_SameFileTwice_CreatesTwoRecords

Total tests: 13
Passed:      13 ✅
Failed:      0
Time:        ~5.0s
```

---

## ⚠️ Важные замечания

### 1. Изоляция тестов
- Каждый тест выполняется в изолированной среде
- Перед каждым тестом вызывается `cleanup_test_data()`
- После каждого теста данные очищаются
- Тесты не влияют друг на друга

### 2. Требования к серверу
- DataSnap Server должен быть запущен **с параметром `/test`**
- Сервер должен использовать файл `db_settings_test.xml` с настройками тестовой БД
- Endpoint `/upload` должен быть доступен
- Endpoint `/datasnap/rest/TServerMethods1/updateSyncUpload` должен быть доступен

**Запуск сервера в тестовом режиме:**
```bash
# Первоначальная настройка (один раз)
setup-test-env.bat

# Последующие запуски
start "" "..\Win32\Debug\AuditServer.exe" /test

# Или используйте автоматический запуск тестов
run-integration-tests.bat
```

### 3. Файловая система
- Тесты создают файлы в `C:\AuditFiles\YYYY\MM\DD\`
- После тестов файлы удаляются автоматически
- Если тест упал, файлы могут остаться — удалите их вручную

### 4. Сетевые требования
- Тесты используют HTTP (не HTTPS) для простоты
- Порт `8082` должен быть доступен
- Порт `5433` должен быть доступен для Docker

---

## 🐛 Отладка

### Ошибка: "Не удалось подключиться к тестовой БД"

**Причины:**
1. Docker Desktop не запущен
2. Тестовая БД не запущена
3. Порт `5433` занят другим приложением

**Решение:**
```bash
# Проверьте Docker
docker ps

# Запустите тестовую БД
docker-compose -f docker-compose.test.yml up -d

# Проверьте статус
docker-compose -f docker-compose.test.yml ps

# Проверьте порт
netstat -ano | findstr :5433
```

### Ошибка: "Expected [200] but got [401]"

**Причина:** Сервер не настроен на работу с тестовой БД

**Решение:**
```bash
# Запустите первоначальную настройку
setup-test-env.bat

# Или запустите сервер с параметром /test
start "" "..\Win32\Debug\AuditServer.exe" /test

# Настройте подключение к тестовой БД через UI:
#   Хост: localhost
#   Порт: 5433
#   БД: audit_test
#   Пользователь: test_user
#   Пароль: test_password
```

### Ошибка: "Login endpoint not configured for test database"

**Причина:** Сервер использует `pg_user` вместо `users_test`

**Решение:**
- Убедитесь, что сервер запущен с параметром `/test`
- Проверьте, что файл `db_settings_test.xml` существует в папке `Win32\Debug\`

### Ошибка: "File should be created on disk"

**Причина:** Сервер и тесты на разных машинах

**Решение:**
- Убедитесь, что сервер и тесты на одной машине
- Или измените путь к файлам в `TestBase.pas`

---

## 📈 Интеграция с CI/CD

### GitHub Actions

```yaml
name: Integration Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: windows-latest
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Start Docker Compose
      run: |
        cd DataSnapServer/Tests/Integration
        docker-compose -f docker-compose.test.yml up -d
        sleep 10
    
    - name: Build Server
      run: msbuild DataSnapServer.dproj
    
    - name: Start Server
      run: Start-Process -FilePath "Win32\Debug\AuditServer.exe"
    
    - name: Build Tests
      run: msbuild IntegrationTests.dproj
    
    - name: Run Tests
      run: |
        cd DataSnapServer/Tests/Integration/Win32/Debug
        .\IntegrationTests.exe
    
    - name: Upload Results
      uses: actions/upload-artifact@v3
      with:
        name: test-results
        path: DataSnapServer/Tests/Integration/Win32/Debug/integration-test-results.xml
```

### Jenkins

```groovy
pipeline {
    agent any
    
    stages {
        stage('Start Test DB') {
            steps {
                bat 'cd DataSnapServer\\Tests\\Integration && docker-compose -f docker-compose.test.yml up -d'
                bat 'timeout /t 10'
            }
        }
        
        stage('Build Server') {
            steps {
                bat 'msbuild DataSnapServer.dproj'
            }
        }
        
        stage('Start Server') {
            steps {
                bat 'start Win32\\Debug\\AuditServer.exe'
                bat 'timeout /t 5'
            }
        }
        
        stage('Run Tests') {
            steps {
                bat 'cd DataSnapServer\\Tests\\Integration\\Win32\\Debug && IntegrationTests.exe'
            }
            post {
                always {
                    nunit testResultsPattern: 'DataSnapServer/Tests/Integration/Win32/Debug/integration-test-results.xml'
                }
            }
        }
    }
    
    post {
        always {
            bat 'cd DataSnapServer\\Tests\\Integration && docker-compose -f docker-compose.test.yml down'
        }
    }
}
```

---

## 📝 История изменений

| Дата | Версия | Описание |
|------|--------|----------|
| 2026-06-22 | 1.1 | Добавлена поддержка параметра `/test` для сервера, скрипты автоматизации |
| 2026-06-21 | 1.0 | Начальная версия: 13 интеграционных тестов |

---

## 🔮 Планы развития

- [ ] Добавить тесты для параллельных запросов (INT-011)
- [ ] Добавить тесты для очистки сессий (INT-012)
- [ ] Интеграция с CI/CD (GitHub Actions, Jenkins)
- [ ] Нагрузочное тестирование через JMeter/k6
- [ ] Тесты для HTTPS (через Nginx)
- [ ] Тесты для реальных пользователей PostgreSQL

---

## 📚 Дополнительные ресурсы

- [DUnitX Documentation](https://github.com/VSoftTechnologies/DUnitX)
- [Docker Compose Documentation](https://docs.docker.com/compose/)
- [PostgreSQL Docker Hub](https://hub.docker.com/_/postgres)
- [NUnit XML Format](https://docs.nunit.org/articles/nunit/overview.html)

---

**Версия:** 1.1  
**Дата:** 2026-06-22  
**Статус:** ✅ Готово к использованию
