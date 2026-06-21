# 🧪 DataSnapServer Tests

Автоматические модульные тесты для сервера **DataSnap REST Server: FieldAudit Sync Service**, реализованные на фреймворке **DUnitX**.

Проект покрывает критически важные модули: шифрование DPAPI, работу с настройками и парсинг JSON.

## 📊 Статистика покрытия

### ✅ Выполняемые тесты (42 теста)

| Тестовый набор | Тестов | Назначение |
|----------------|:------:|------------|
| `TTestWinDPAPIUtils` | 5 | Шифрование/дешифрование через Windows DPAPI |
| `TTestServerSettings` | 7 | Сохранение/загрузка настроек, генерация API-ключей |
| `TTestJsonParsing` | 6 | Парсинг входящего JSON во всех поддерживаемых форматах |
| `TTestUploadUtils` | 18 | Проверка JPEG-заголовка, SHA-256, генерация UUID, атомарное сохранение, валидация Base64 |
| `TTestUploadPayloadParser` | 6 | Парсинг payload для endpoint `/upload`: Base64, координаты, метаданные |
| **ИТОГО** | **42** | **100% успешное прохождение** ✅ |

## 🧪 Список тестов

### TTestWinDPAPIUtils (5 тестов)
Проверяет корректность работы модуля `WinDPAPIUtils.pas`, который отвечает за криптографическое хранение секретов.

| Имя теста | Что проверяет |
|-----------|---------------|
| `TestEncryptDecryptRoundTrip` | Шифрование и последующее дешифрование даёт исходную строку |
| `TestEncryptEmptyString` | Корректная обработка пустых строк |
| `TestEncryptSpecialCharacters` | Работа с кириллицей и спецсимволами (`!@#$%^&*()`) |
| `TestEncryptLongString` | Шифрование длинных строк (1000 символов) |
| `TestDecryptInvalidData` | При передаче невалидных данных функция возвращает пустую строку (без исключений) |

### TTestServerSettings (7 тестов)
Проверяет модуль `ServerSettings.pas`, отвечающий за конфигурацию сервера.

| Имя теста | Что проверяет |
|-----------|---------------|
| `TestDefaultValues` | Корректность значений по умолчанию (`Host='localhost'`, `Port=5432`) |
| `TestApiKeyGeneration` | Генерация API-ключа длиной ровно 32 символа |
| `TestApiKeyGenerationUniqueness` | Два последовательных ключа всегда различаются |
| `TestSetAndGetProperties` | Работа свойств `Host`, `Port`, `Database`, `Username`, `Password`, `ApiKey` |
| `TestPasswordEncryptionRoundTrip` | Пароль шифруется через DPAPI при сохранении и дешифруется при загрузке |
| `TestSaveAndLoadRoundTrip` | Полный цикл сохранения и загрузки XML-конфига |
| `TestLoadFromFileReturnsFalseWhenNoFile` | Метод возвращает `False`, если файл настроек отсутствует |

### TTestJsonParsing (6 тестов)
Проверяет корректность парсинга входящего JSON в методе `updateSyncUpload`.

| Имя теста | Что проверяет |
|-----------|---------------|
| `TestParseValidJsonArray` | Прямой массив: `[{...}]` |
| `TestParseJsonWithWrapper` | Обёртка с массивом: `{"AJsonData": [{...}]}` |
| `TestParseJsonStringWrapper` | Обёртка со строкой: `{"AJsonData": "[{...}]"}` |
| `TestParseInvalidJson` | Некорректный JSON возвращает `nil` |
| `TestParseEmptyArray` | Пустой массив `[]` обрабатывается корректно |
| `TestParseJsonWithMissingFields` | Отсутствие опциональных полей не вызывает ошибок |

### TTestUploadUtils (18 тестов)
Проверяет модуль `UploadUtils.pas`, отвечающий за обработку загруженных фотографий.

| Имя теста | Что проверяет |
|-----------|---------------|
| `TestIsValidJpegMagic_Valid` | Корректное распознавание JPEG-заголовка (FF D8 FF) |
| `TestIsValidJpegMagic_Invalid` | Отклонение не-JPEG файлов (PNG, и т.д.) |
| `TestIsValidJpegMagic_Empty` | Обработка пустого потока |
| `TestComputeSHA256_Deterministic` | Один и тот же контент даёт одинаковый хеш |
| `TestComputeSHA256_Length` | SHA-256 возвращает ровно 64 hex-символа |
| `TestGenerateFileUUID_Unique` | 100 последовательных UUID всегда различаются |
| `TestGenerateFileUUID_Format` | Формат UUID: 36 символов без фигурных скобок |
| `TestEnsureAuditDir_CreatesHierarchy` | Создаётся иерархия папок YYYY/MM/DD |
| `TestEnsureAuditDir_YearMonthDay` | Путь содержит правильные год, месяц, день |
| `TestSaveUploadedFile_Atomic` | Файл сохраняется атомарно (через .tmp → rename), .tmp не остаётся |
| `TestSaveUploadedFile_Content` | Содержимое сохранённого файла совпадает с исходным |
| `TestIsValidBase64Chars_Valid` | Корректная валидация валидных Base64-символов |
| `TestIsValidBase64Chars_InvalidChars` | Отклонение Base64 с некорректными символами |
| `TestIsValidBase64Chars_WrongLength` | Отклонение Base64 неправильной длины |
| `TestIsValidBase64Chars_Empty` | Обработка пустой строки |
| `TestTryDecodeBase64_Valid` | Успешное декодирование валидного Base64 |
| `TestTryDecodeBase64_Invalid` | Возврат `False` для невалидного Base64 |
| `TestTryDecodeBase64_Empty` | Обработка пустой строки |

### TTestUploadPayloadParser (6 тестов)
Проверяет парсинг JSON-payload для endpoint `/upload`.

| Имя теста | Что проверяет |
|-----------|---------------|
| `TestValidPayload_AllFields` | Полный payload: Base64, координаты, метаданные |
| `TestMissingPhotoBase64` | Отсутствие поля `photo_base64` корректно определяется |
| `TestInvalidBase64` | Невалидный Base64 даёт пустой или некорректный результат |
| `TestLargePhotoBase64` | Обработка больших файлов (5 MB → ~6.6 MB Base64) |
| `TestGeoCoordinatesPrecision` | Точность координат до 7 знаков после запятой |
| `TestMetadataExtraction` | Извлечение `device_id`, `batch_id`, `title`, `occurred_at` |

## 📈 Результаты тестирования

Последний прогон (2026-06-21):

```
Total tests: 42
Passed:      42 ✅
Failed:      0
Ignored:     0
Time:        3.200s
```

### История исправлений

| Дата | Описание |
|------|----------|
| 2026-06-21 | Подключены и успешно запущены `TestUploadUtils.pas` (18 тестов) и `TestUploadPayloadParser.pas` (6 тестов). Итого 42 теста, 100% прохождение |
| 2026-06-19 | Подключены `TestUploadUtils.pas` и `TestUploadPayloadParser.pas` к `TestRunner.dpr` |
| 2026-06-18 | `TestDecryptInvalidData` — изменено ожидание: функция возвращает пустую строку вместо выброса исключения (более безопасное поведение) |

## 🚀 Как запустить тесты

### Требования
- Embarcadero Delphi 11/12
- DUnitX (входит в стандартную поставку Delphi)
- Доступ к папке `DataSnapServer/Source/` (тесты ссылаются на модули сервера)

### Пошаговая инструкция

1. **Откройте проект тестов:**
   - В Delphi: **File → Open**
   - Выберите файл `DataSnapServer/Tests/TestRunner.dpr`
   - *Примечание: отдельный `.dproj` создавать не нужно — Delphi использует `TestRunner.dpr` как главный файл проекта*

2. **Проверьте пути поиска модулей:**
   - **Project → Options → Delphi Compiler → Search path**
   - Должен содержать: `..\Source\`

3. **Скомпилируйте проект:**
   - Нажмите **Ctrl+F9** (Build)
   - Исполняемый файл появится в `Tests/Win32/Debug/TestRunner.exe`

4. **Запустите тесты:**
   - **Из Delphi:** нажмите **Ctrl+Shift+F10** (Run)
   - **Из командной строки:**
     ```cmd
     cd DataSnapServer\Tests\Win32\Debug
     .\TestRunner.exe
     ```

5. **Посмотрите результаты:**
   - В консоли появится отчёт о прохождении тестов
   - XML-отчёт в формате NUnit сохранится в файл `dunitx-results.xml`

## 🔗 Интеграция с CI/CD

DUnitX генерирует отчёт в формате **NUnit XML** (`dunitx-results.xml`), который можно импортировать в популярные CI-системы:

### Jenkins
```groovy
pipeline {
    agent any
    stages {
        stage('Build & Test') {
            steps {
                bat '"C:\\Program Files (x86)\\Embarcadero\\Studio\\22.0\\bin\\rsvars.bat" && ' +
                    'msbuild DataSnapServer\\Tests\\TestRunner.dproj /t:Build'
                bat 'DataSnapServer\\Tests\\Win32\\Debug\\TestRunner.exe'
            }
            post {
                always {
                    nunit testResultsPattern: 'DataSnapServer/Tests/**/dunitx-results.xml'
                }
            }
        }
    }
}
```

### GitLab CI
```yaml
test:
  stage: test
  script:
    - msbuild DataSnapServer\Tests\TestRunner.dproj /t:Build
    - DataSnapServer\Tests\Win32\Debug\TestRunner.exe
  artifacts:
    reports:
      junit: DataSnapServer/Tests/**/dunitx-results.xml
```

### GitHub Actions
```yaml
name: Run DUnitX Tests
on: [push, pull_request]
jobs:
  test:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
      - name: Build tests
        run: msbuild DataSnapServer\Tests\TestRunner.dproj /t:Build
      - name: Run tests
        run: DataSnapServer\Tests\Win32\Debug\TestRunner.exe
      - name: Publish results
        uses: dorny/test-reporter@v1
        with:
          name: DUnitX Tests
          path: DataSnapServer/Tests/**/dunitx-results.xml
          reporter: java-junit
```

## 📁 Структура файлов

```
DataSnapServer/Tests/
├── TestRunner.dpr              # Главный файл проекта (открывать в Delphi)
├── TestRunner.dproj            # Настройки проекта (создаётся Delphi автоматически)
├── TestWinDPAPIUtils.pas       # Тесты шифрования DPAPI (✅ подключён)
├── TestServerSettings.pas      # Тесты настроек сервера (✅ подключён)
├── TestServerMethods.pas       # Тесты парсинга JSON (✅ подключён)
├── TestUploadUtils.pas         # Тесты UploadUtils.pas (✅ подключён)
├── TestUploadPayloadParser.pas # Тесты парсинга payload для /upload (✅ подключён)
├── dunitx-results.xml          # Отчёт о последнем прогоне (NUnit XML)
└── README.md                   # Этот файл
```

## 🎯 Что НЕ тестируется (и почему)

| Модуль | Причина отсутствия тестов |
|--------|---------------------------|
| `ServerMethodsUnitMain.Login` | Требует реальной БД PostgreSQL — это интеграционный тест, а не модульный |
| `ServerMethodsUnitMain.updateSyncUpload` | Требует реальной БД и настроенного соединения |
| `WebModuleUnitMain` (endpoint `/upload`) | Требует запущенного HTTP-сервера — тестируется через Postman/curl |
| `ServerLogger` | Асинхронное логирование сложно тестировать модульно |

Для полноценного покрытия рекомендуется добавить **интеграционные тесты** с использованием тестовой БД PostgreSQL (Docker-контейнер с `postgres:15`).

## 💡 Советы по расширению

1. **Добавьте mock-объекты** для `TFDConnection`, чтобы тестировать бизнес-логику без реальной БД
2. **Используйте `TestContainers`** для запуска PostgreSQL в Docker во время тестов
3. **Добавьте нагрузочные тесты** через JMeter или k6 для проверки производительности REST API
4. **Настройте pre-commit hook** для автоматического запуска тестов перед каждым коммитом

## 📄 Лицензия

MIT License. Свободно используйте, модифицируйте и распространяйте.
