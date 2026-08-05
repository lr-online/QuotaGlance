@echo off
setlocal
echo ============================================
echo QuotaGlance Windows - Build Installers
echo ============================================
echo.

cd /d %~dp0
bash scripts/build-windows.sh
if %ERRORLEVEL% neq 0 (
    echo.
    echo ============================================
    echo BUILD FAILED
    echo ============================================
    echo.
    pause
    exit /b 1
)

echo.
echo ============================================
echo BUILD SUCCEEDED
echo ============================================
echo.
echo EXE:   Windows\target\release\quotaglance.exe
echo NSIS:  Windows\target\x86_64-pc-windows-msvc\release\bundle\nsis\QuotaGlance_0.1.0_x64-setup.exe
echo MSI:   Windows\target\x86_64-pc-windows-msvc\release\bundle\msi\QuotaGlance_0.1.0_x64_en-US.msi
echo MSI:   Windows\target\x86_64-pc-windows-msvc\release\bundle\msi\QuotaGlance_0.1.0_x64_zh-CN.msi
echo.
pause
