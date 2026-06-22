@echo off
REM ============================================================
REM Настройка окружения для интеграционных тестов
REM Этот скрипт запускает сервер в тестовом режиме и позволяет
REM настроить подключение к тестовой БД через UI
REM ============================================================

echo ============================================================
echo  Настройка окружения для интеграционных тестов
echo ============================================================
echo.
echo Этот скрипт запустит сервер DataSnap в тестовом режиме.
echo Вам нужно будет настроить подключение к тестовой БД через UI.
echo.
echo Параметры тестовой БД:
echo   Хост: localhost
echo   Порт: 5433
echo   БД: audit_test
echo   Пользователь: test_user
echo   Пароль: test_password
echo.
echo Убедитесь, что Docker-контейнер с тестовой БД запущен:
echo   docker compose -f docker-compose.test.yml up -d
echo.
pause

REM Проверяем, запущен ли Docker-контейнер
docker ps | findstr "audit-test-db" >nul
if errorlevel 1 (
    echo.
    echo ❌ Docker-контейнер audit-test-db не запущен!
    echo Запустите: docker compose -f docker-compose.test.yml up -d
    pause
    exit /b 1
)

echo.
echo ✅ Docker-контейнер запущен
echo.
echo Запускаем сервер в тестовом режиме...
echo После настройки подключения к БД, закройте сервер.
echo.

REM Запускаем сервер с параметром /test
REM Сервер прочитает/создаст db_settings_test.xml
start "" "..\..\Source\Win32\Debug\AuditServer.exe" /test

echo.
echo Сервер запущен. Настройте подключение к тестовой БД через UI:
echo   Хост: localhost
echo   Порт: 5433
echo   БД: audit_test
echo   Пользователь: test_user
echo   Пароль: test_password
echo.
echo После настройки закройте сервер.
echo Файл db_settings_test.xml будет создан автоматически.
echo.
pause
