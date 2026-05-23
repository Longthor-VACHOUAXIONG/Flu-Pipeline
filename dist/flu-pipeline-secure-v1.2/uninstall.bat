@echo off
REM uninstall.bat - Windows Uninstaller for Influenza Sequencing Workflow

echo ============================================================
echo   Influenza Workflow Uninstaller (Windows)
echo ============================================================
echo.

set "INSTALL_DIR=%USERPROFILE%\.flu-pipeline"
set "BIN_DIR=%USERPROFILE%\.local\bin"

echo Removing workflow installation from: %INSTALL_DIR%
if exist "%INSTALL_DIR%" (
    rmdir /s /q "%INSTALL_DIR%"
    echo   Removed installation directory
) else (
    echo   Installation directory not found
)

echo.
echo Removing wrapper commands from: %BIN_DIR%
if exist "%BIN_DIR%\flu-pipeline.bat" (
    del "%BIN_DIR%\flu-pipeline.bat"
    echo   Removed flu-pipeline command
)

if exist "%BIN_DIR%\flu-realign.bat" (
    del "%BIN_DIR%\flu-realign.bat"
    echo   Removed flu-realign command
)

echo.
echo ============================================================
echo   Uninstallation Complete!
echo ============================================================
echo.
echo Note: You may need to remove %BIN_DIR% from your PATH manually.
echo.

REM Self-delete the uninstaller script
del "%~f0"
pause
