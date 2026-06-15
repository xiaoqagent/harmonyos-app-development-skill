@echo off
:: Deploy a HarmonyOS NEXT HAP to a connected device/emulator via hdc
:: Usage from WSL:
::   cmd.exe /c "pushd D:\ && D:\path\to\deploy_app.bat D:\05_HarmonyNext\YourProject"
::
:: Parameters:
::   %1 = Project root (e.g. D:\05_HarmonyNext\WorldCup2026)
::   %2 = Module name (default: entry)
::
set PROJECT_DIR=%~1
if "%PROJECT_DIR%"=="" set PROJECT_DIR=D:\05_HarmonyNext\WorldCup2026

set MODULE=%~2
if "%MODULE%"=="" set MODULE=entry

set HDC="D:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"

echo ===== Deploying %MODULE% HAP =====
echo Project: %PROJECT_DIR%

:: Find the signed HAP
set HAP_PATH=%PROJECT_DIR%\%MODULE%\build\default\outputs\default\%MODULE%-default-signed.hap
if not exist "%HAP_PATH%" (
  echo ERROR: HAP not found at %HAP_PATH%
  echo Make sure to build first (assembleApp debug)
  exit /b 1
)

echo HAP: %HAP_PATH%
%HDC% list targets 2>&1 | findstr "Connected" >nul
if %errorlevel% NEQ 0 (
  echo ERROR: No connected device. Run 'hdc list targets' to check.
  exit /b 1
)

echo Installing...
%HDC% install -r "%HAP_PATH%" 2>&1
set EXIT_CODE=%errorlevel%
if %EXIT_CODE% EQU 0 (
  echo ===== INSTALL SUCCESSFUL =====
) else (
  echo ===== INSTALL FAILED (code %EXIT_CODE%) =====
)
exit /b %EXIT_CODE%
