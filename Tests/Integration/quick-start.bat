@echo off
REM =============================================================================
REM Скрипт быстрого запуска интеграционных тестов
REM =============================================================================
REM Автоматически:
REM 1. Запускает тестовую БД (Docker)
REM 2. Проверяет, что DataSnap Server запущен
REM 3. Компилирует и запускает тесты
REM =============================================================================

echo ========================================
echo   Integration Tests Quick Start
echo ========================================
echo.

REM Шаг 1: Проверка Docker
echo [1/5] Проверка Docker...
docker --version >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo ОШИБКА: Docker не установлен или не запущен
    echo Установите Docker Desktop: https://www.docker.com/products/docker-desktop
    pause
    exit /b 1
)
echo      OK: Docker установлен
echo.

REM Шаг 2: Запуск тестовой БД
echo [2/5] Запуск тестовой БД...
docker-compose -f docker-compose.test.yml ps | findstr "Up" >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo      Запуск тестовой БД...
    docker-compose -f docker-compose.test.yml up -d
    if %ERRORLEVEL% NEQ 0 (
        echo ОШИБКА: Не удалось запустить тестовую БД
        pause
        exit /b 1
    )
    echo      Ожидание готовности БД...
    timeout /t 10 /nobreak >nul
) else (
    echo      OK: Тестовая БД уже запущена
)
echo.

REM Шаг 3: Проверка DataSnap Server
echo [3/5] Проверка DataSnap Server...
curl -s http://localhost:8082/datasnap/rest >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo ВНИМАНИЕ: DataSnap Server не запущен на http://localhost:8082
    echo Запустите сервер вручную перед запуском тестов
    echo.
    choice /C YN /M "Продолжить anyway?"
    if errorlevel 2 exit /b 0
) else (
    echo      OK: DataSnap Server запущен
)
echo.

REM Шаг 4: Компиляция тестов
echo [4/5] Компиляция тестов...
if not exist "Win32\Debug\IntegrationTests.exe" (
    echo      Компиляция IntegrationTests.dpr...
    echo      Откройте проект в Delphi и нажмите Ctrl+F9
    echo.
    pause
    exit /b 0
) else (
    echo      OK: IntegrationTests.exe найден
)
echo.

REM Шаг 5: Запуск тестов
echo [5/5] Запуск тестов...
echo.
cd Win32\Debug
IntegrationTests.exe
cd ..\..

echo.
echo ========================================
echo   Тесты завершены
echo ========================================
echo.
echo Результаты: Win32\Debug\integration-test-results.xml
echo.

REM Остановка тестовой БД (опционально)
choice /C YN /M "Остановить тестовую БД?"
if errorlevel 1 (
    echo Остановка тестовой БД...
    docker-compose -f docker-compose.test.yml down
)

pause
