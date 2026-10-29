@echo off
setlocal
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0src\app\main.ps1" %*
set "APP_EXIT=%ERRORLEVEL%"
rem main.ps1 shows its own errors and exits 2; any other failure means PowerShell could not run it.
if not "%APP_EXIT%"=="0" if not "%APP_EXIT%"=="2" (
    echo Press any key to close . . .
    pause >nul
)
endlocal & exit /b %APP_EXIT%
