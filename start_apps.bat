@echo off
setlocal EnableExtensions

rem ReplayTrove launcher: sets paths and env, then runs supervisor (start_apps.ps1).
rem Uses powershell.exe consistently for all PowerShell work.
rem OBS %APPDATA%\obs-studio\.sentinel cleanup is done in start_apps.ps1 (Remove-Item -Force, same intent as del /f /q).

rem --- Paths (override here if your install differs) ---
set "REPLAYTROVE_WORKER_DIR=C:\ReplayTrove\worker"
set "REPLAYTROVE_SCOREBOARD_DIR=C:\ReplayTrove\scoreboard"
set "REPLAYTROVE_LOGS2DROPBOX_DIR=C:\ReplayTrove\logs2dropbox"
set "REPLAYTROVE_ENCODER_DIR=C:\ReplayTrove\encoder"
set "REPLAYTROVE_CLEANER_SCRIPT=C:\ReplayTrove\cleaner\cleaner-bee.ps1"
set "REPLAYTROVE_OBS_DIR=C:\Program Files\obs-studio\bin\64bit"
set "REPLAYTROVE_OBS_EXE=%REPLAYTROVE_OBS_DIR%\obs64.exe"
set "REPLAYTROVE_OBS_SENTINEL=%APPDATA%\obs-studio\.sentinel"
set "REPLAYTROVE_STREAMDECK_EXE=C:\Program Files\Elgato\StreamDeck\StreamDeck.exe"

rem --- Modes ---
rem Interactive default: pause on preflight/validation failure.
rem For Task Scheduler, set REPLAYTROVE_PAUSE_ON_ERROR=0 before calling this batch (or uncomment below).
set "REPLAYTROVE_PAUSE_ON_ERROR=1"
rem set "REPLAYTROVE_PAUSE_ON_ERROR=0"

rem Production uses pythonw.exe (no consoles). For visible Python errors use debug:
rem set "REPLAYTROVE_LAUNCHER_DEBUG=1"
rem Optional per-app toggles (1=enabled, 0=disabled):
rem set "REPLAYTROVE_ENABLE_WORKER=1"
rem set "REPLAYTROVE_ENABLE_LOGS2DROPBOX=1"
rem set "REPLAYTROVE_ENABLE_ENCODER=1"
rem set "REPLAYTROVE_ENABLE_CLEANER=1"
rem set "REPLAYTROVE_ENABLE_OBS=1"
rem set "REPLAYTROVE_ENABLE_STREAMDECK=1"
rem set "REPLAYTROVE_ENABLE_SCOREBOARD=1"
rem set "REPLAYTROVE_ENABLE_LAUNCHER_UI=1"

rem Optional tuning — see start_apps.ps1 for meaning (seconds / milliseconds).
rem set "REPLAYTROVE_READINESS_OBS_SEC=120"
rem set "REPLAYTROVE_READINESS_PYTHON_SEC=90"
rem set "REPLAYTROVE_READINESS_INTERVAL_SEC=1"
rem set "REPLAYTROVE_FOCUS_MAX_ATTEMPTS=40"
rem set "REPLAYTROVE_FOCUS_RETRY_MS=500"

set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0start_apps.ps1"
exit /b %ERRORLEVEL%
