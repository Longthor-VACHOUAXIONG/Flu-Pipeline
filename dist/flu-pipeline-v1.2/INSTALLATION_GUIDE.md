# Influenza Virus Sequencing Workflow - Installation Guide

## Quick Installation

### Linux/WSL
```bash
sudo ./install.sh
```

### Windows
```cmd
install.bat
```

## Manual Installation (if installers fail)

### Linux/WSL
```bash
# Create installation directory
mkdir -p ~/flu-pipeline
cp -r .references .scripts run_flu_irma_pipeline.sh metadata.xlsx ~/flu-pipeline/

# Make script executable
chmod +x ~/flu-pipeline/run_flu_irma_pipeline.sh

# Add to PATH (optional)
echo 'export PATH="$PATH:$HOME/flu-pipeline"' >> ~/.bashrc
source ~/.bashrc
```

### Windows
```cmd
# Create installation directory
mkdir %USERPROFILE%\flu-pipeline
xcopy /E /I /Y .references %USERPROFILE%\flu-pipeline\.references
xcopy /E /I /Y .scripts %USERPROFILE%\flu-pipeline\.scripts
copy run_flu_irma_pipeline.sh %USERPROFILE%\flu-pipeline\
copy metadata.xlsx %USERPROFILE%\flu-pipeline\metadata_template.xlsx

# Create wrapper script
echo @echo off > %USERPROFILE%\bin\flu-pipeline.bat
echo set "FLU_PIPELINE_DIR=%USERPROFILE%\flu-pipeline" >> %USERPROFILE%\bin\flu-pipeline.bat
echo bash "%%FLU_PIPELINE_DIR%%\run_flu_irma_pipeline.sh" %%* >> %USERPROFILE%\bin\flu-pipeline.bat
```

## Requirements
- Python 3.6+
- Bash (Linux/WSL) or WSL (Windows)
- conda (recommended for IRMA installation)

## First Run
The workflow will auto-install missing dependencies:
- IRMA (via conda)
- MAFFT (via conda)
- IQ-TREE (via conda)
- openpyxl (via pip)

## Usage
```bash
# From installation directory
cd ~/flu-pipeline  # or cd %USERPROFILE%\flu-pipeline on Windows
bash run_flu_irma_pipeline.sh --help

# Run full workflow
bash run_flu_irma_pipeline.sh --all
```

## Support
Version 1.2 - May 2026
