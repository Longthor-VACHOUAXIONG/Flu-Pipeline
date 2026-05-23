# Influenza Virus Sequencing Workflow - Secure Installation

## Important Notice
This is a secure distribution package. The source code has been obfuscated for protection. You can install and use the workflow without accessing the original source code.

## Quick Installation (One-Click)

### Linux/WSL
```bash
sudo ./install-simple.sh
```

That's it! Ready to use immediately.

### Windows
```cmd
install.bat
```

## What's Included
- **Obfuscated workflow script** (run_flu_irma_pipeline.sh.x)
- **Reference library** (.references/)
- **Python processing scripts** (.scripts/)
- **Installation scripts** (install-simple.sh, install.bat)
- **Documentation** (README.md, INSTALL.md)

## Installation Details
- **Linux/WSL**: Installs to `/usr/local/lib/flu-pipeline` (system-wide)
- **Windows**: Installs to `%USERPROFILE%\.flu-pipeline` (hidden directory)
- **Commands**: Available from any directory immediately
- **No PATH setup required**: Uses standard system directories

## Usage
After installation, the workflow can be used from any directory:
```bash
flu-pipeline --help
flu-pipeline --all
```

## Uninstallation

### Linux/WSL
```bash
./uninstall.sh
```

### Windows
```cmd
uninstall.bat
```

This will remove:
- Installation directory (~/.flu-pipeline or %USERPROFILE%\.flu-pipeline)
- Wrapper commands
- PATH entries

## System Requirements
- Python 3.6+
- Bash (Linux/WSL) or WSL (Windows)
- conda (recommended for IRMA installation)

## Support
Version 1.2 - May 2026
