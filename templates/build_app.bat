@echo off
:: Build a HarmonyOS NEXT app from WSL via PowerShell delegation
:: Usage from WSL:
::   cmd.exe /c "pushd D:\ && D:\path\to\build_app.bat D:\05_HarmonyNext\YourProject debug"
::   cmd.exe /c "pushd D:\ && D:\path\to\build_app.bat D:\05_HarmonyNext\YourProject release"
::
:: Parameters:
::   %1 = Project root (e.g. D:\05_HarmonyNext\WorldCup2026)
::   %2 = Build mode: debug or release (default: debug)
::
set PROJECT_DIR=%~1
if "%PROJECT_DIR%"=="" set PROJECT_DIR=D:\05_HarmonyNext\WorldCup2026

set BUILD_MODE=%~2
if "%BUILD_MODE%"=="" set BUILD_MODE=debug

set DEVECO_SDK_HOME=D:\Program Files\Huawei\DevEco Studio\sdk
set NODE_HOME=D:\Program Files\Huawei\DevEco Studio\tools\node
set JAVA_HOME=D:\Program Files\Huawei\DevEco Studio\jbr
set PATH=%JAVA_HOME%\bin;%NODE_HOME%;%DEVECO_SDK_HOME%\default\openharmony\toolchains;%PATH%

cd /d "%PROJECT_DIR%"

echo ===== Building %BUILD_MODE% =====
echo Project: %PROJECT_DIR%
echo SDK: %DEVECO_SDK_HOME%
echo.
"D:\Program Files\Huawei\DevEco Studio\tools\node\node.exe" "D:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.js" assembleApp -p product=default -p buildMode=%BUILD_MODE% 2>&1
set EXIT_CODE=%errorlevel%
if %EXIT_CODE% EQU 0 (
  echo ===== BUILD SUCCESSFUL =====
) else (
  echo ===== BUILD FAILED (code %EXIT_CODE%) =====
)
exit /b %EXIT_CODE%
