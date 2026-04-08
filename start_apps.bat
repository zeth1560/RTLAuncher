@echo off
setlocal

set "WORKER_DIR=C:\ReplayTrove\worker"
set "SCOREBOARD_DIR=C:\ReplayTrove\scoreboard"
set "WORKER_PYTHON=%WORKER_DIR%\.venv\Scripts\python.exe"
set "SCOREBOARD_PYTHON=%SCOREBOARD_DIR%\.venv\Scripts\python.exe"

rem Interactive/default profile:
set "LAUNCH_DELAY_SECONDS=2"
set "PAUSE_ON_ERROR=1"
rem Scheduler/non-interactive profile (optional):
rem set "LAUNCH_DELAY_SECONDS=0"
rem set "PAUSE_ON_ERROR=0"

set "ERROR_FOUND=0"

echo ReplayTrove launcher starting...
echo Delay=%LAUNCH_DELAY_SECONDS%s  PauseOnError=%PAUSE_ON_ERROR%

if not exist "%WORKER_DIR%\main.py" (
    echo [ERROR] Worker app not found at "%WORKER_DIR%\main.py"
    set "ERROR_FOUND=1"
)

if not exist "%SCOREBOARD_DIR%\main.py" (
    echo [ERROR] Scoreboard app not found at "%SCOREBOARD_DIR%\main.py"
    set "ERROR_FOUND=1"
)

if not exist "%WORKER_PYTHON%" (
    echo [ERROR] Worker Python not found at "%WORKER_PYTHON%"
    set "ERROR_FOUND=1"
)

if not exist "%SCOREBOARD_PYTHON%" (
    echo [ERROR] Scoreboard Python not found at "%SCOREBOARD_PYTHON%"
    set "ERROR_FOUND=1"
)

if "%ERROR_FOUND%"=="1" (
    if "%PAUSE_ON_ERROR%"=="1" pause
    exit /b 1
)

echo Launching worker...
start "ReplayTrove Worker" /D "%WORKER_DIR%" "%WORKER_PYTHON%" "main.py"

if not "%LAUNCH_DELAY_SECONDS%"=="0" timeout /t %LAUNCH_DELAY_SECONDS% >nul

echo Launching scoreboard...
start "ReplayTrove Scoreboard" /D "%SCOREBOARD_DIR%" "%SCOREBOARD_PYTHON%" "main.py"

echo Both apps launched.
exit /b 0
