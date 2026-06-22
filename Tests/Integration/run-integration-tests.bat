@echo off
REM ============================================================
REM Запуск интеграционных тестов
REM ============================================================

echo ============================================================
echo  Запуск интеграционных тестов
echo ============================================================
echo.

REM Проверяем, запущен ли Docker-контейнер
echo [1/3] Проверка Docker-контейнера...
docker ps | findstr "audit-test-db" >nul
if errorlevel 1 (
    echo ❌ Docker-контейнер audit-test-db не запущен!
    echo Запустите: docker compose -f docker-compose.test.yml up -d
    pause
    exit /b 1
)
echo ✅ Docker-контейнер запущен
echo.

REM Проверяем, существует ли db_settings_test.xml
echo [2/3] Проверка настроек тестовой БД...
if not exist "..\..\Source\Win32\Debug\db_settings_test.xml" (
    echo ❌ Файл db_settings_test.xml не найден!
    echo Запустите setup-test-env.bat для первоначальной настройки.
    pause
    exit /b 1
)
echo ✅ Настройки тестовой БД найдены
echo.

REM Проверяем, запущен ли сервер
echo [3/3] Проверка сервера DataSnap...
powershell -Command "try { $r = Invoke-WebRequest -Uri 'http://localhost:8082/' -UseBasicParsing -TimeoutSec 3; exit 0 } catch { exit 1 }" >nul
if errorlevel 1 (
    echo ❌ Сервер DataSnap не запущен на порту 8082!
    echo.
    echo Запустите сервер в тестовом режиме:
    echo   start "" "..\..\Source\Win32\Debug\AuditServer.exe" /test
    echo.
    echo Или используйте setup-test-env.bat для первоначальной настройки.
    pause
    exit /b 1
)
echo ✅ Сервер DataSnap запущен
echo.

echo ============================================================
echo  Запуск тестов...
echo ============================================================
echo.

REM Запускаем интеграционные тесты
Win32\Debug\IntegrationTests.exe

echo.
echo ============================================================
echo  Тесты завершены
echo ============================================================
echo.
echo Результаты сохранены в: Win32\Debug\dunitx-results.xml
echo.
pause
