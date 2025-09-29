@echo off
setlocal enableextensions

set "SBOX=C:\Sandbox"
set "INIT=%SBOX%\Initialization"
set "LOGDIR=%SBOX%\Logs"
if not exist "%LOGDIR%" mkdir "%LOGDIR%"
set "LOGFILE=%LOGDIR%\launcher.log"

echo [%date% %time%] Launcher start >> "%LOGFILE%"

rem ===== MSI-only approach. No portable. No Tools\pwsh.exe. =====
set "PWSH=%ProgramFiles%\PowerShell\7\pwsh.exe"

if not exist "%PWSH%" (
  rem Find MSI in Initialization only
  for %%M in ("%INIT%\PowerShell-7*.msi") do (
    echo [%date% %time%] Installing PS7 from MSI: %%~nxM >> "%LOGFILE%"
    msiexec /i "%%~fM" /qn ADD_EXPLORER_CONTEXT_MENU_OPENPOWERSHELL=0 ENABLE_PSREMOTING=0 ADD_PATH=1
  )
)

rem Wait up to ~60s for pwsh to appear (installer commit lag)
set /a tries=0
:waitloop
if exist "%PWSH%" goto :runpwsh
set /a tries+=1
if %tries% gtr 60 (
  echo [%date% %time%] ERROR: pwsh.exe not found after MSI install >> "%LOGFILE%"
  echo PowerShell 7 was not installed to "%PWSH%". Check MSI location in C:\Sandbox\Initialization.
  exit /b 1
)
ping -n 2 127.0.0.1 >nul
goto :waitloop

:runpwsh
echo [%date% %time%] Using PWSH: %PWSH% >> "%LOGFILE%"
for %%I in ("%PWSH%") do set "PWSHDIR=%%~dpI"
set "PATH=%PWSHDIR%;%PATH%"

if /i "%SKIP_BOOTSTRAP%"=="1" (
  echo [%date% %time%] SKIP_BOOTSTRAP=1 -> launching raw PS7 >> "%LOGFILE%"
  "%PWSH%" -NoLogo -NoExit -ExecutionPolicy Bypass -Command "Write-Host 'PS7 launched (raw). Set SKIP_BOOTSTRAP=0 to run bootstrap.'"
  goto :end
)

rem Run bootstrap but keep the shell open no matter what
"%PWSH%" -NoLogo -NoExit -ExecutionPolicy Bypass -File "%INIT%\bootstrap.ps1" -LogDir "%LOGDIR%" -SandboxRoot "%SBOX%" >> "%LOGFILE%" 2>&1

:end
set ec=%ERRORLEVEL%
echo [%date% %time%] Launcher exit code: %ec% >> "%LOGFILE%"
endlocal & exit /b %ec%
