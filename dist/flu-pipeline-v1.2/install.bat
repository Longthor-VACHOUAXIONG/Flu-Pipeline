@echo off
REM install.bat - Windows Installer for Influenza Sequencing Workflow

echo ============================================================
echo   Influenza Workflow Installer (Windows)
echo ============================================================
echo.

REM Set installation directory (user profile)
set "INSTALL_DIR=%USERPROFILE%\flu-pipeline"
set "BIN_DIR=%USERPROFILE%\bin"

echo Creating installation directory: %INSTALL_DIR%
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"

echo.
echo Building combined reference library...
if exist ".references\combined_flu_reference.fasta" del ".references\combined_flu_reference.fasta"
for %%f in (.references\A_*.fasta .references\B_*.fasta) do (
    type "%%f" >> .references\combined_flu_reference.fasta
    echo. >> .references\combined_flu_reference.fasta
)

echo.
echo Installing workflow components...
if exist "%INSTALL_DIR%\.references" rmdir /s /q "%INSTALL_DIR%\.references"
xcopy /E /I /Y ".references" "%INSTALL_DIR%\.references"
xcopy /E /I /Y ".scripts" "%INSTALL_DIR%\.scripts"
copy "run_flu_irma_pipeline.sh" "%INSTALL_DIR%\flu-pipeline.exec"
if exist "metadata.xlsx" copy "metadata.xlsx" "%INSTALL_DIR%\metadata_template.xlsx"

echo.
echo Creating bin directory...
if not exist "%BIN_DIR%" mkdir "%BIN_DIR%"

echo.
echo Creating wrapper batch file...
(
echo @echo off
echo set "FLU_PIPELINE_DIR=%INSTALL_DIR%"
echo bash "%%FLU_PIPELINE_DIR%%\flu-pipeline.exec" %%*
) > "%BIN_DIR%\flu-pipeline.bat"

echo.
echo ============================================================
echo   Installation Successful!
echo ============================================================
echo.
echo Workflow installed to: %INSTALL_DIR%
echo Wrapper script created: %BIN_DIR%\flu-pipeline.bat
echo.
echo To use the workflow from any directory:
echo   1. Add %BIN_DIR% to your PATH
echo   2. Run: flu-pipeline.bat [options]
echo.
echo Workflow options:
echo   --all         Run full workflow (default)
echo   --irma        Run only Barcode mapping + IRMA assembly
echo   --align       Run only Alignment (based on existing results)
echo   --tree        Run only Phylogeny (based on existing alignments)
echo   --fill        Run only Metadata Excel filling
echo   --map         Run only Barcode-to-Sample mapping check
echo.
echo Or run directly from installation directory:
echo   cd %INSTALL_DIR%
echo   bash flu-pipeline.exec [options]
echo.
echo ============================================================
pause
