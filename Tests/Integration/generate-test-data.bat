@echo off
REM =============================================================================
REM Скрипт генерации тестовых данных
REM =============================================================================
REM Создаёт тестовые файлы для интеграционных тестов
REM =============================================================================

echo ========================================
echo   Генерация тестовых данных
echo ========================================
echo.

REM Создаём папку TestData если её нет
if not exist "TestData" mkdir TestData

REM Генерируем sample.jpg (100 КБ)
echo [1/3] Создание sample.jpg (100 КБ)...
powershell -Command "$bytes = New-Object byte[] 102400; $bytes[0] = 0xFF; $bytes[1] = 0xD8; $bytes[2] = 0xFF; for ($i = 3; $i -lt 102400; $i++) { $bytes[$i] = $i %% 256 }; [System.IO.File]::WriteAllBytes('TestData\sample.jpg', $bytes)"
if %ERRORLEVEL% EQU 0 (
    echo      OK: TestData\sample.jpg создан
) else (
    echo      ОШИБКА: Не удалось создать sample.jpg
)

REM Генерируем sample_large.jpg (11 МБ)
echo [2/3] Создание sample_large.jpg (11 МБ)...
powershell -Command "$bytes = New-Object byte[] (11 * 1024 * 1024); $bytes[0] = 0xFF; $bytes[1] = 0xD8; $bytes[2] = 0xFF; for ($i = 3; $i -lt $bytes.Length; $i++) { $bytes[$i] = $i %% 256 }; [System.IO.File]::WriteAllBytes('TestData\sample_large.jpg', $bytes)"
if %ERRORLEVEL% EQU 0 (
    echo      OK: TestData\sample_large.jpg создан
) else (
    echo      ОШИБКА: Не удалось создать sample_large.jpg
)

REM Генерируем sample.png (1 КБ)
echo [3/3] Создание sample.png (1 КБ)...
powershell -Command "$bytes = New-Object byte[] 1024; $bytes[0] = 0x89; $bytes[1] = 0x50; $bytes[2] = 0x4E; $bytes[3] = 0x47; $bytes[4] = 0x0D; $bytes[5] = 0x0A; $bytes[6] = 0x1A; $bytes[7] = 0x0A; [System.IO.File]::WriteAllBytes('TestData\sample.png', $bytes)"
if %ERRORLEVEL% EQU 0 (
    echo      OK: TestData\sample.png создан
) else (
    echo      ОШИБКА: Не удалось создать sample.png
)

echo.
echo ========================================
echo   Генерация завершена!
echo ========================================
echo.
echo Созданные файлы:
dir /b TestData\*.jpg TestData\*.png 2>nul
echo.
echo Примечание: Тесты работают без этих файлов (генерируют данные в памяти)
echo.
pause
