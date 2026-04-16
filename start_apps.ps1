#Requires -Version 5.1
<#
.SYNOPSIS
  ReplayTrove launcher / supervisor: start apps, wait for readiness, validate processes, UI tweaks.

  Configure paths via environment (set in start_apps.bat) or defaults below.
  REPLAYTROVE_LAUNCHER_DEBUG=1  -> use python.exe and normal windows for Python apps.
  REPLAYTROVE_PAUSE_ON_ERROR=0 -> do not pause on validation failure (e.g. scheduled task).
#>

$ErrorActionPreference = 'Stop'

# --- Config (override with env vars from start_apps.bat) ---
$WorkerDir = if ($env:REPLAYTROVE_WORKER_DIR)         { $env:REPLAYTROVE_WORKER_DIR }         else { 'C:\ReplayTrove\worker' }
$ScoreboardDir   = if ($env:REPLAYTROVE_SCOREBOARD_DIR)     { $env:REPLAYTROVE_SCOREBOARD_DIR }     else { 'C:\ReplayTrove\scoreboard' }
$Logs2DropboxDir = if ($env:REPLAYTROVE_LOGS2DROPBOX_DIR)   { $env:REPLAYTROVE_LOGS2DROPBOX_DIR }   else { 'C:\ReplayTrove\logs2dropbox' }
$EncoderDir      = if ($env:REPLAYTROVE_ENCODER_DIR)        { $env:REPLAYTROVE_ENCODER_DIR }        else { 'C:\ReplayTrove\encoder' }
$CleanerScript   = if ($env:REPLAYTROVE_CLEANER_SCRIPT)      { $env:REPLAYTROVE_CLEANER_SCRIPT }      else { 'C:\ReplayTrove\cleaner\cleaner-bee.ps1' }
$LauncherUiBat   = if ($env:REPLAYTROVE_LAUNCHER_UI_BAT)      { $env:REPLAYTROVE_LAUNCHER_UI_BAT }      else { Join-Path $PSScriptRoot 'launcher_ui.bat' }
$ObsDir          = if ($env:REPLAYTROVE_OBS_DIR) { $env:REPLAYTROVE_OBS_DIR }             else { 'C:\Program Files\obs-studio\bin\64bit' }
$ObsExe          = if ($env:REPLAYTROVE_OBS_EXE)            { $env:REPLAYTROVE_OBS_EXE }            else { Join-Path $ObsDir 'obs64.exe' }
$StreamDeckExe   = if ($env:REPLAYTROVE_STREAMDECK_EXE)     { $env:REPLAYTROVE_STREAMDECK_EXE }     else { 'C:\Program Files\Elgato\StreamDeck\StreamDeck.exe' }
$ObsSentinel     = if ($env:REPLAYTROVE_OBS_SENTINEL)        { $env:REPLAYTROVE_OBS_SENTINEL }        else { Join-Path $env:APPDATA 'obs-studio\.sentinel' }

$DebugMode       = ($env:REPLAYTROVE_LAUNCHER_DEBUG -eq '1')
$PauseOnError    = ($env:REPLAYTROVE_PAUSE_ON_ERROR -ne '0')

function Test-AppEnabled {
  param(
    [string]$Name,
    [bool]$Default = $true
  )
  $raw = [Environment]::GetEnvironmentVariable("REPLAYTROVE_ENABLE_$Name")
  if ([string]::IsNullOrWhiteSpace($raw)) { return $Default }
  switch ($raw.Trim().ToLowerInvariant()) {
    '1' { return $true }
    'true' { return $true }
    'yes' { return $true }
    'on' { return $true }
    '0' { return $false }
    'false' { return $false }
    'no' { return $false }
    'off' { return $false }
    default { return $Default }
  }
}

$EnableWorker = Test-AppEnabled -Name 'WORKER'
$EnableLogs2Dropbox = Test-AppEnabled -Name 'LOGS2DROPBOX'
$EnableEncoder = Test-AppEnabled -Name 'ENCODER'
$EnableCleaner = Test-AppEnabled -Name 'CLEANER'
$EnableObs = Test-AppEnabled -Name 'OBS'
$EnableStreamDeck = Test-AppEnabled -Name 'STREAMDECK'
$EnableScoreboard = Test-AppEnabled -Name 'SCOREBOARD'
$EnableLauncherUi = Test-AppEnabled -Name 'LAUNCHER_UI'

$ReadinessObsSec = if ($env:REPLAYTROVE_READINESS_OBS_SEC) { [int]$env:REPLAYTROVE_READINESS_OBS_SEC } else { 120 }
$ReadinessPythonSec = if ($env:REPLAYTROVE_READINESS_PYTHON_SEC) { [int]$env:REPLAYTROVE_READINESS_PYTHON_SEC } else { 90 }
$ReadinessIntervalSec = if ($env:REPLAYTROVE_READINESS_INTERVAL_SEC) { [int]$env:REPLAYTROVE_READINESS_INTERVAL_SEC } else { 1 }
$FocusMaxAttempts = if ($env:REPLAYTROVE_FOCUS_MAX_ATTEMPTS) { [int]$env:REPLAYTROVE_FOCUS_MAX_ATTEMPTS } else { 40 }
$FocusRetryMs = if ($env:REPLAYTROVE_FOCUS_RETRY_MS) { [int]$env:REPLAYTROVE_FOCUS_RETRY_MS } else { 500 }

$LogDir = Join-Path $PSScriptRoot 'logs'
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$LogStamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$script:LaunchLog = Join-Path $LogDir "launcher-$LogStamp.log"

function Write-LauncherLog {
  param([string]$Message)
  $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $Message
  Add-Content -LiteralPath $script:LaunchLog -Encoding utf8 -Value $line
  Write-Host $line
}

function Wait-LauncherAck {
  param([string]$Prompt)
  if (-not $PauseOnError) { return }
  if (-not [Environment]::UserInteractive) {
    Write-LauncherLog 'Pause skipped (non-interactive session).'
    return
  }
  Read-Host $Prompt | Out-Null
}

function Get-PythonInterpreter {
  param([string]$AppDir)
  $name = if ($DebugMode) { 'python.exe' } else { 'pythonw.exe' }
  Join-Path $AppDir ".venv\Scripts\$name"
}

function Test-PythonAppRunning {
  param(
    [string]$FolderPath,
    [string]$ScriptName = 'main.py'
  )
  $leaf = Split-Path -Path $FolderPath -Leaf
  $procs = Get-CimInstance Win32_Process -Filter "Name = 'python.exe' OR Name = 'pythonw.exe'" -ErrorAction SilentlyContinue
  foreach ($p in $procs) {
    $cmd = $p.CommandLine
    if (-not $cmd) { continue }
    if ($cmd -like "*\$leaf\*" -and $cmd -like "*$ScriptName*") { return $true }
  }
  return $false
}

function Test-CleanerBeeRunning {
  $procs = Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue
  $leaf = Split-Path -Path $CleanerScript -Leaf
  foreach ($p in $procs) {
    if ($p.CommandLine -like "*$leaf*") { return $true }
  }
  return $false
}

function Wait-Readiness {
  param(
    [string]$Label,
    [scriptblock]$Test,
    [int]$TimeoutSec,
    [int]$IntervalSec
  )
  $deadline = (Get-Date).AddSeconds($TimeoutSec)
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  while ((Get-Date) -lt $deadline) {
    try {
      if (& $Test) {
        Write-LauncherLog ('Readiness OK: {0} ({1:0.###}s)' -f $Label, $sw.Elapsed.TotalSeconds)
        return $true
      }
    } catch {
      Write-LauncherLog "Readiness check error ($Label): $($_.Exception.Message)"
    }
    Start-Sleep -Seconds $IntervalSec
  }
  Write-LauncherLog "Readiness TIMEOUT: $Label (${TimeoutSec}s)"
  return $false
}

function Invoke-ScoreboardFocus {
  param([int]$MaxAttempts, [int]$RetryMs)
  $title = 'ReplayTrove Scoreboard'
  $ws = New-Object -ComObject WScript.Shell
  for ($i = 1; $i -le $MaxAttempts; $i++) {
    $ok = $false
    try { $ok = [bool]$ws.AppActivate($title) } catch { $ok = $false }
    if ($ok) {
      Write-LauncherLog "Scoreboard focus: AppActivate('$title') succeeded on attempt $i"
      return $true
    }
    Start-Sleep -Milliseconds $RetryMs
  }
  Write-LauncherLog "Scoreboard focus: AppActivate('$title') failed after $MaxAttempts attempts"
  return $false
}

function Invoke-StreamDeckMinimize {
  param([int]$MaxAttempts, [int]$RetryMs)
  Add-Type -Namespace Win32 -Name Show -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
'@ | Out-Null
  $SW_MINIMIZE = 6
  for ($i = 1; $i -le $MaxAttempts; $i++) {
    $sd = Get-Process -Name 'StreamDeck' -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero }
    if ($sd) {
      $hwnd = $sd[0].MainWindowHandle
      $called = [Win32.Show]::ShowWindowAsync($hwnd, $SW_MINIMIZE)
      Write-LauncherLog "Stream Deck minimize: ShowWindowAsync attempt $i, hwnd=$hwnd, result=$called"
      if ($called) { return $true }
    } else {
      Write-LauncherLog "Stream Deck minimize: no main window yet (attempt $i/$MaxAttempts)"
    }
    Start-Sleep -Milliseconds $RetryMs
  }
  Write-LauncherLog 'Stream Deck minimize: failed after all attempts'
  return $false
}

# --- Preflight ---
Write-LauncherLog "ReplayTrove launcher starting (supervisor). Log: $script:LaunchLog"
Write-LauncherLog "Mode: $(if ($DebugMode) { 'DEBUG (python.exe)' } else { 'PRODUCTION (pythonw.exe)' })"

$pyWorker = Get-PythonInterpreter $WorkerDir
$pyScore  = Get-PythonInterpreter $ScoreboardDir
$pyLogs = Get-PythonInterpreter $Logs2DropboxDir
$pyEncoder = Get-PythonInterpreter $EncoderDir

$preflight = @()
if ($EnableWorker) {
  $preflight += @{ Path = (Join-Path $WorkerDir 'main.py'); Label = 'Worker main.py' }
  $preflight += @{ Path = $pyWorker; Label = 'Worker venv Python' }
}
if ($EnableScoreboard) {
  $preflight += @{ Path = (Join-Path $ScoreboardDir 'main.py'); Label = 'Scoreboard main.py' }
  $preflight += @{ Path = $pyScore; Label = 'Scoreboard venv Python' }
}
if ($EnableLogs2Dropbox) {
  $preflight += @{ Path = (Join-Path $Logs2DropboxDir 'main.py'); Label = 'logs2dropbox main.py' }
  $preflight += @{ Path = $pyLogs; Label = 'logs2dropbox venv Python' }
}
if ($EnableEncoder) {
  $preflight += @{ Path = (Join-Path $EncoderDir 'operator_long_only.py'); Label = 'Encoder operator_long_only.py' }
  $preflight += @{ Path = $pyEncoder; Label = 'Encoder venv Python' }
}
if ($EnableCleaner) {
  $preflight += @{ Path = $CleanerScript; Label = 'Cleaner Bee script' }
}
if ($EnableObs) {
  $preflight += @{ Path = $ObsExe; Label = 'OBS executable' }
}
if ($EnableStreamDeck) {
  $preflight += @{ Path = $StreamDeckExe; Label = 'Stream Deck executable' }
}
if ($EnableLauncherUi) {
  $preflight += @{ Path = $LauncherUiBat; Label = 'Launcher UI batch' }
}

foreach ($item in $preflight) {
  if (-not (Test-Path -LiteralPath $item.Path)) {
    Write-LauncherLog "PREFLIGHT FAIL: $($item.Label) not found at $($item.Path)"
    Wait-LauncherAck 'Preflight failed; press Enter to exit'
    exit 1
  }
}

# --- Sentinel (equivalent to: del /f /q "%OBS_SENTINEL%") ---
if ($EnableObs -and (Test-Path -LiteralPath $ObsSentinel)) {
  try {
    Remove-Item -LiteralPath $ObsSentinel -Recurse -Force -ErrorAction Stop
    Write-LauncherLog "OBS sentinel removed: $ObsSentinel"
  } catch {
    Write-LauncherLog "WARN: could not remove OBS sentinel: $($_.Exception.Message)"
  }
}

$pyWindowStyle = if ($DebugMode) { 'Normal' } else { 'Hidden' }
# --verbose: richer OBS logs under %APPDATA%\obs-studio\logs (Help → Log Files in OBS).
$obsArgs = @('--disable-shutdown-check', '--startreplaybuffer', '--verbose')

if ($EnableWorker) {
  Write-LauncherLog 'Launching worker...'
  Start-Process -WorkingDirectory $WorkerDir -FilePath $pyWorker -ArgumentList @('main.py') -WindowStyle $pyWindowStyle | Out-Null
} else {
  Write-LauncherLog 'Skipping worker (disabled by REPLAYTROVE_ENABLE_WORKER=0)'
}

if ($EnableLogs2Dropbox) {
  Write-LauncherLog 'Launching logs2dropbox...'
  Start-Process -WorkingDirectory $Logs2DropboxDir -FilePath $pyLogs -ArgumentList @('main.py') -WindowStyle $pyWindowStyle | Out-Null
} else {
  Write-LauncherLog 'Skipping logs2dropbox (disabled by REPLAYTROVE_ENABLE_LOGS2DROPBOX=0)'
}

if ($EnableEncoder) {
  Write-LauncherLog 'Launching encoder operator...'
  Start-Process -WorkingDirectory $EncoderDir -FilePath $pyEncoder -ArgumentList @('operator_long_only.py') -WindowStyle $pyWindowStyle | Out-Null
} else {
  Write-LauncherLog 'Skipping encoder (disabled by REPLAYTROVE_ENABLE_ENCODER=0)'
}

$cleanerProc = $null
if ($EnableCleaner) {
  Write-LauncherLog 'Launching Cleaner Bee...'
  $cleanerProc = Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
    -ArgumentList @(
      '-NoProfile',
      '-WindowStyle', 'Hidden',
      '-ExecutionPolicy', 'Bypass',
      '-File', $CleanerScript
    ) `
    -WindowStyle Hidden `
    -PassThru
  if (-not $cleanerProc) {
    Write-LauncherLog 'ERROR: Cleaner Bee Start-Process did not return a process handle'
  }
} else {
  Write-LauncherLog 'Skipping Cleaner Bee (disabled by REPLAYTROVE_ENABLE_CLEANER=0)'
}

if ($EnableWorker) {
  $workerReady = Wait-Readiness -Label 'Worker (python main.py)' -TimeoutSec $ReadinessPythonSec -IntervalSec $ReadinessIntervalSec -Test {
    Test-PythonAppRunning -FolderPath $WorkerDir
  }
  if (-not $workerReady) {
    Write-LauncherLog 'ERROR: Worker process not detected in time'
  }
}

if ($EnableLogs2Dropbox) {
  $logs2Ready = Wait-Readiness -Label 'logs2dropbox (python main.py)' -TimeoutSec $ReadinessPythonSec -IntervalSec $ReadinessIntervalSec -Test {
    Test-PythonAppRunning -FolderPath $Logs2DropboxDir
  }
  if (-not $logs2Ready) {
    Write-LauncherLog 'ERROR: logs2dropbox process not detected in time'
  }
}

if ($EnableEncoder) {
  $encoderReady = Wait-Readiness -Label 'Encoder (python operator_long_only.py)' -TimeoutSec $ReadinessPythonSec -IntervalSec $ReadinessIntervalSec -Test {
    Test-PythonAppRunning -FolderPath $EncoderDir -ScriptName 'operator_long_only.py'
  }
  if (-not $encoderReady) {
    Write-LauncherLog 'ERROR: Encoder process not detected in time'
  }
}

if ($EnableObs) {
  Write-LauncherLog 'Launching OBS...'
  Start-Process -WorkingDirectory $ObsDir -FilePath $ObsExe -ArgumentList $obsArgs -WindowStyle Minimized | Out-Null
} else {
  Write-LauncherLog 'Skipping OBS (disabled by REPLAYTROVE_ENABLE_OBS=0)'
}

if ($EnableStreamDeck) {
  Write-LauncherLog 'Launching Stream Deck...'
  Start-Process -FilePath $StreamDeckExe -WindowStyle Minimized | Out-Null
} else {
  Write-LauncherLog 'Skipping Stream Deck (disabled by REPLAYTROVE_ENABLE_STREAMDECK=0)'
}

if ($EnableLauncherUi) {
  Write-LauncherLog 'Launching Launcher UI...'
  Start-Process -FilePath $LauncherUiBat | Out-Null
} else {
  Write-LauncherLog 'Skipping Launcher UI (disabled by REPLAYTROVE_ENABLE_LAUNCHER_UI=0)'
}

# Readiness: OBS should be running before scoreboard (replaces fixed long sleep).
if ($EnableObs) {
  $obsReady = Wait-Readiness -Label 'OBS (obs64)' -TimeoutSec $ReadinessObsSec -IntervalSec $ReadinessIntervalSec -Test {
    $null -ne (Get-Process -Name 'obs64' -ErrorAction SilentlyContinue)
  }
  if (-not $obsReady) {
    Write-LauncherLog 'ERROR: OBS did not become ready in time'
  }
}

if ($EnableScoreboard) {
  Write-LauncherLog 'Launching scoreboard...'
  Start-Process -WorkingDirectory $ScoreboardDir -FilePath $pyScore -ArgumentList @('main.py') -WindowStyle $pyWindowStyle | Out-Null

  $sbReady = Wait-Readiness -Label 'Scoreboard (python main.py)' -TimeoutSec $ReadinessPythonSec -IntervalSec $ReadinessIntervalSec -Test {
    Test-PythonAppRunning -FolderPath $ScoreboardDir
  }
  if (-not $sbReady) {
    Write-LauncherLog 'ERROR: Scoreboard process not detected in time'
  }
} else {
  Write-LauncherLog 'Skipping scoreboard (disabled by REPLAYTROVE_ENABLE_SCOREBOARD=0)'
}

# Post-launch validation (snapshot after short settle)
Start-Sleep -Seconds $ReadinessIntervalSec

Write-LauncherLog 'Post-launch validation...'
$validation = [ordered]@{}
if ($EnableWorker) { $validation['Worker'] = { Test-PythonAppRunning -FolderPath $WorkerDir } }
if ($EnableLogs2Dropbox) { $validation['logs2dropbox'] = { Test-PythonAppRunning -FolderPath $Logs2DropboxDir } }
if ($EnableEncoder) { $validation['Encoder'] = { Test-PythonAppRunning -FolderPath $EncoderDir -ScriptName 'operator_long_only.py' } }
if ($EnableScoreboard) { $validation['Scoreboard'] = { Test-PythonAppRunning -FolderPath $ScoreboardDir } }
if ($EnableObs) { $validation['OBS'] = { $null -ne (Get-Process -Name 'obs64' -ErrorAction SilentlyContinue) } }
if ($EnableStreamDeck) { $validation['StreamDeck'] = { $null -ne (Get-Process -Name 'StreamDeck' -ErrorAction SilentlyContinue) } }

$allOk = $true
foreach ($key in $validation.Keys) {
  try {
    $ok = & $validation[$key]
  } catch {
    $ok = $false
    Write-LauncherLog "Validation error [$key]: $($_.Exception.Message)"
  }
  Write-LauncherLog "Validation: $key = $(if ($ok) { 'OK' } else { 'FAIL' })"
  if (-not $ok) { $allOk = $false }
}

if ($EnableCleaner) {
  # Cleaner Bee: still running, or exited successfully (one-shot script)
  $cleanerOk = $false
  if ($cleanerProc) {
    try {
      $cleanerProc.Refresh()
      if (-not $cleanerProc.HasExited) {
        $cleanerOk = $true
        Write-LauncherLog 'Validation: Cleaner Bee = OK (still running)'
      } else {
        $code = $cleanerProc.ExitCode
        $cleanerOk = ($code -eq 0)
        Write-LauncherLog "Validation: Cleaner Bee = $(if ($cleanerOk) { 'OK' } else { 'FAIL' }) (exited, code $code)"
      }
    } catch {
      Write-LauncherLog "Validation: Cleaner Bee = indeterminate ($($_.Exception.Message)); checking WMI fallback"
      $cleanerOk = Test-CleanerBeeRunning
      Write-LauncherLog "Validation: Cleaner Bee (WMI fallback) = $(if ($cleanerOk) { 'OK' } else { 'FAIL' })"
    }
  } else {
    $cleanerOk = Test-CleanerBeeRunning
    Write-LauncherLog "Validation: Cleaner Bee (no PassThru proc) = $(if ($cleanerOk) { 'OK' } else { 'FAIL' }) (WMI)"
  }

  if (-not $cleanerOk) { $allOk = $false }
}

if (-not $allOk) {
  Write-LauncherLog 'SUPERVISOR: one or more validations failed.'
  Wait-LauncherAck 'Validation failed; press Enter to exit'
  exit 2
}

Write-LauncherLog 'Post-launch validation passed; UI focus/minimize...'
if ($EnableScoreboard) {
  Invoke-ScoreboardFocus -MaxAttempts $FocusMaxAttempts -RetryMs $FocusRetryMs | Out-Null
}
if ($EnableStreamDeck) {
  Invoke-StreamDeckMinimize -MaxAttempts $FocusMaxAttempts -RetryMs $FocusRetryMs | Out-Null
}

Write-LauncherLog 'All apps launched and validated.'
exit 0
