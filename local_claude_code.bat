@echo off
setlocal EnableDelayedExpansion

:: ─────────────────────────────────────────
:: Configuration
:: ─────────────────────────────────────────
set ANTHROPIC_BASE_URL=http://localhost:1234
set CLAUDE_CODE_ATTRIBUTION_HEADER=0

:: Configuration file for last directory
set CONFIG_FILE=%APPDATA%\local_claude_code\config.json

:: Dummy token for local endpoint
set ANTHROPIC_AUTH_TOKEN=lmstudio

:: ─────────────────────────────────────────
:: Check LM Studio CLI is available
:: ─────────────────────────────────────────
where lms >nul 2>&1
if !ERRORLEVEL! neq 0 (
    echo [ERROR] 'lms' not found in PATH. Make sure LM Studio CLI is installed and on your PATH.
    pause
    exit /b 1
)

:: ─────────────────────────────────────────
:: Start LM Studio server if not running
:: ─────────────────────────────────────────
set LMS_STARTED_BY_SCRIPT=0
lms status 2>nul | find /I "port:" >nul
if !ERRORLEVEL! neq 0 (
    lms server start
    if !ERRORLEVEL! neq 0 (
        echo [ERROR] Failed to start LM Studio server.
        pause & exit /b 1
    )
    set LMS_STARTED_BY_SCRIPT=1
) else (
    echo [WARN] LM Studio is already running. It will not be shut down when this script exits.
)


:: ─────────────────────────────────────────
:: Load or Check Model
:: ─────────────────────────────────────────
set MODEL_LOADED_BY_SCRIPT=0
set ACTIVE_MODEL=

:: If LMS was already running, check for a loaded model
if !LMS_STARTED_BY_SCRIPT! equ 0 (
    for /f "usebackq delims=" %%I in (`powershell -NoProfile -Command "$m = lms ps --json | ConvertFrom-Json; if ($m.Count -gt 0) { $m[0].modelKey }" 2^>nul`) do set "ACTIVE_MODEL=%%I"
    if defined ACTIVE_MODEL (
        echo [WARN] Model already loaded: !ACTIVE_MODEL!. Will use it as-is.
        goto model_selected
    )
)

:: No model loaded — let user pick interactively
:select_model
lms load
if !ERRORLEVEL! neq 0 (
    echo [WARN] No model selected.
    choice /m "Try again"
    if !ERRORLEVEL! equ 1 goto select_model
    echo [INFO] Exiting. & pause & exit /b 0
)
for /f "usebackq delims=" %%I in (`powershell -NoProfile -Command "(lms ps --json | ConvertFrom-Json)[0].modelKey" 2^>nul`) do set "ACTIVE_MODEL=%%I"
if not defined ACTIVE_MODEL (
    echo [ERROR] Could not determine loaded model.
    pause & exit /b 1
)
set MODEL_LOADED_BY_SCRIPT=1

:model_selected
echo [INFO] Active model: !ACTIVE_MODEL!

:: ─────────────────────────────────────────
:: Confirm or select working directory
:: ─────────────────────────────────────────
set WORK_DIR=
if exist "%CONFIG_FILE%" (
    for /f "usebackq delims=" %%I in (`powershell -NoProfile -Command "(Get-Content '%CONFIG_FILE%' | ConvertFrom-Json).dir" 2^>nul`) do set "SAVED_DIR=%%I"
    if defined SAVED_DIR (
        if exist "!SAVED_DIR!\" (
            set "WORK_DIR=!SAVED_DIR!"
        ) else (
            echo [WARN] Last directory no longer exists: !SAVED_DIR!
        )
    )
)

:select_dir
if defined WORK_DIR (
    echo [INFO] Last used directory: !WORK_DIR!
    choice /m "Use this directory"
    if !ERRORLEVEL! equ 1 goto use_dir
    set WORK_DIR=
)

for /f "usebackq delims=" %%I in (`powershell -noprofile -command "Add-Type -AssemblyName System.Windows.Forms; $f = New-Object System.Windows.Forms.FolderBrowserDialog; $f.Description = 'Select your project folder for Claude Code'; $f.ShowNewFolderButton = $true; if ($f.ShowDialog() -eq 'OK') { $f.SelectedPath } else { exit 1 }"`) do set "WORK_DIR=%%I"
if not defined WORK_DIR (
    echo [WARN] No folder selected.
    choice /m "Would you like to select a folder again"
    if !ERRORLEVEL! equ 1 goto select_dir
    echo [INFO] Exiting.
    pause
    exit /b 0
)

:: Save config for next run
if not exist "%APPDATA%\local_claude_code" mkdir "%APPDATA%\local_claude_code"
set ESCAPED_DIR=!WORK_DIR:\=\\!
(
    echo {
    echo     "dir": "!ESCAPED_DIR!"
    echo }
)>"%CONFIG_FILE%"

:use_dir
pushd "!WORK_DIR!"
if !ERRORLEVEL! neq 0 (
    echo [ERROR] Failed to change directory to: !WORK_DIR!
    set WORK_DIR=
    choice /m "Would you like to select a different folder"
    if !ERRORLEVEL! equ 1 goto select_dir
    pause
    exit /b 1
)
echo [INFO] Working directory: !WORK_DIR!

:: ─────────────────────────────────────────
:: Resume Session Options
:: ─────────────────────────────────────────
set CLAUDE_RESUME_FLAG=
echo.
echo [1] New session
echo [2] Resume last session  (--continue)
echo [3] Pick a session       (--resume)
choice /c 123 /m "Select an option"
if !ERRORLEVEL! equ 2 set CLAUDE_RESUME_FLAG=--continue
if !ERRORLEVEL! equ 3 set CLAUDE_RESUME_FLAG=--resume

:: ─────────────────────────────────────────
:: Launch Claude Code
:: ─────────────────────────────────────────
echo [INFO] Starting Claude Code with model: !ACTIVE_MODEL!
claude %CLAUDE_RESUME_FLAG% --model "!ACTIVE_MODEL!"

:: ─────────────────────────────────────────
:: Cleanup
:: ─────────────────────────────────────────
if !LMS_STARTED_BY_SCRIPT! equ 1 (
    taskkill /IM "LM Studio.exe" /F /FI "STATUS eq RUNNING" >nul 2>&1
    echo [INFO] LM Studio shut down.
) else (
    if !MODEL_LOADED_BY_SCRIPT! equ 1 (
        echo [INFO] Unloading model: !ACTIVE_MODEL!
        lms unload "!ACTIVE_MODEL!" >nul 2>&1
    ) else (
        echo [WARN] A model was already loaded before this script ran and may still be loaded in LM Studio.
    )
    echo [INFO] LM Studio was already running before this script. Leaving it open.
)
pause
endlocal