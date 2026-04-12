@echo off
setlocal

set "WORKER_DIR=C:\ReplayTrove\worker"
set "SCOREBOARD_DIR=C:\ReplayTrove\scoreboard"
set "LOGS2DROPBOX_DIR=C:\ReplayTrove\logs2dropbox"
set "CLEANER_SCRIPT=C:\ReplayTrove\cleaner\cleaner-bee.ps1"
set "OBS_DIR=C:\Program Files\obs-studio\bin\64bit"
set "WORKER_PYTHONW=%WORKER_DIR%\.venv\Scripts\pythonw.exe"
set "SCOREBOARD_PYTHONW=%SCOREBOARD_DIR%\.venv\Scripts\pythonw.exe"
set "LOGS2DROPBOX_PYTHONW=%LOGS2DROPBOX_DIR%\.venv\Scripts\pythonw.exe"
set "OBS_EXE=%OBS_DIR%\obs64.exe"
rem Never use --safe-mode here; we want full normal startup (plugins/scripts on).
rem --disable-shutdown-check skips unclean-shutdown dialog on OBS versions that still support it.
rem OBS 32+ removed that flag; removing .sentinel before launch is the usual workaround.
set "OBS_ARGS=--disable-shutdown-check"
set "OBS_SENTINEL=%APPDATA%\obs-studio\.sentinel"
set "STREAMDECK_EXE=C:\Program Files\Elgato\StreamDeck\StreamDeck.exe"

rem Interactive/default profile:
set "LAUNCH_DELAY_SECONDS=10"
set "SCOREBOARD_FOCUS_DELAY_SECONDS=2"
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

if not exist "%LOGS2DROPBOX_DIR%\main.py" (
    echo [ERROR] logs2dropbox not found at "%LOGS2DROPBOX_DIR%\main.py"
    set "ERROR_FOUND=1"
)

if not exist "%CLEANER_SCRIPT%" (
    echo [ERROR] Cleaner Bee script not found at "%CLEANER_SCRIPT%"
    set "ERROR_FOUND=1"
)

if not exist "%WORKER_PYTHONW%" (
    echo [ERROR] Worker PythonW not found at "%WORKER_PYTHONW%"
    set "ERROR_FOUND=1"
)

if not exist "%SCOREBOARD_PYTHONW%" (
    echo [ERROR] Scoreboard PythonW not found at "%SCOREBOARD_PYTHONW%"
    set "ERROR_FOUND=1"
)

if not exist "%LOGS2DROPBOX_PYTHONW%" (
    echo [ERROR] logs2dropbox PythonW not found at "%LOGS2DROPBOX_PYTHONW%"
    set "ERROR_FOUND=1"
)

if not exist "%OBS_EXE%" (
    echo [ERROR] OBS executable not found at "%OBS_EXE%"
    set "ERROR_FOUND=1"
)

if not exist "%STREAMDECK_EXE%" (
    echo [ERROR] Stream Deck executable not found at "%STREAMDECK_EXE%"
    set "ERROR_FOUND=1"
)

if "%ERROR_FOUND%"=="1" (
    if "%PAUSE_ON_ERROR%"=="1" pause
    exit /b 1
)

echo Launching worker...
start "ReplayTrove Worker" /D "%WORKER_DIR%" "%WORKER_PYTHONW%" "main.py"

echo Launching logs2dropbox...
start "ReplayTrove logs2dropbox" /D "%LOGS2DROPBOX_DIR%" "%LOGS2DROPBOX_PYTHONW%" "main.py"

echo Launching Cleaner Bee...
start "ReplayTrove Cleaner Bee" powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%CLEANER_SCRIPT%"

echo Launching OBS...
if exist "%OBS_SENTINEL%" rd /s /q "%OBS_SENTINEL%" 2>nul
start "OBS Studio" /MIN /D "%OBS_DIR%" "%OBS_EXE%" %OBS_ARGS%

echo Launching Stream Deck...
start "Elgato Stream Deck" /MIN "%STREAMDECK_EXE%"

if not "%LAUNCH_DELAY_SECONDS%"=="0" timeout /t %LAUNCH_DELAY_SECONDS% >nul

echo Launching scoreboard...
start "ReplayTrove Scoreboard" /D "%SCOREBOARD_DIR%" "%SCOREBOARD_PYTHONW%" "main.py"

start "" powershell -NoProfile -WindowStyle Hidden -Command "Start-Sleep -Seconds %SCOREBOARD_FOCUS_DELAY_SECONDS%; $ws=New-Object -ComObject WScript.Shell; [void]$ws.AppActivate('ReplayTrove Scoreboard')"
start "" powershell -NoProfile -WindowStyle Hidden -Command "$sig='[DllImport(\"user32.dll\")] public static extern bool ShowWindowAsync(IntPtr hWnd,int nCmdShow);'; Add-Type -MemberDefinition $sig -Name Win32Show -Namespace Native; 1..20 | %% { Start-Sleep -Milliseconds 500; Get-Process StreamDeck -ErrorAction SilentlyContinue | ? { $_.MainWindowHandle -ne 0 } | %% { [Native.Win32Show]::ShowWindowAsync($_.MainWindowHandle, 2) | Out-Null } }"

echo All apps launched.
exit /b 0
