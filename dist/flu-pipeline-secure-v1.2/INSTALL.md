# Influenza Virus Sequencing Workflow - Installation Guide

## Overview
This workflow automates Nanopore influenza virus sequencing, subtyping, and phylogenetic analysis.

## System Requirements
- **Linux/WSL**: Bash, Python 3.6+, conda (recommended)
- **Windows**: WSL with Ubuntu, Python 3.6+, conda (recommended)
- **Tools**: IRMA, MAFFT, IQ-TREE (auto-installed via conda if missing)
- **Python packages**: openpyxl (auto-installed)

## Installation

### Option 1: Linux/WSL Installation
```bash
# Extract the package
tar -xzf flu-pipeline-v1.2.tar.gz
cd flu-pipeline-v1.2

# Run installer (requires sudo)
sudo ./install.sh
```

### Option 2: Windows Installation
```cmd
# Extract the package
tar -xzf flu-pipeline-v1.2.tar.gz
cd flu-pipeline-v1.2

# Run installer
install.bat
```

### Option 3: Manual Installation
```bash
# Create installation directory
mkdir -p ~/flu-pipeline
cp -r .references .scripts run_flu_irma_pipeline.sh metadata.xlsx ~/flu-pipeline/

# Add to PATH (add to ~/.bashrc)
export PATH="$PATH:$HOME/flu-pipeline"
```

## Usage

### Running the Workflow
```bash
# From installation directory
cd ~/flu-pipeline
bash run_flu_irma_pipeline.sh [options]

# Or if added to PATH
flu-pipeline [options]
```

### Workflow Options
- `--all` - Run full workflow (default)
- `--irma` - Run only Barcode mapping + IRMA assembly
- `--align` - Run only Alignment (based on existing results)
- `--tree` - Run only Phylogeny (based on existing alignments)
- `--fill` - Run only Metadata Excel filling
- `--map` - Run only Barcode-to-Sample mapping check
- `-h, --help` - Show help message

### Directory Structure
```
working_directory/
├── metadata.xlsx          # Sample metadata (required)
├── fastq_pass/            # Raw sequencing data
│   ├── Run141/
│   │   └── barcode01/
│   └── Run22/
│       └── barcode21/
├── concat/                # Concatenated FASTQ files
├── results_irma/          # Analysis results
│   ├── 01_irma_outputs/
│   ├── 03_consensus/
│   ├── 05_alignment/
│   ├── 06_trees/
│   └── QC/
└── run_flu_irma_pipeline.sh
```

## Metadata Format
The `metadata.xlsx` file must contain these columns:
- `Sample ID` - Unique sample identifier
- `Barcode` - Barcode folder name (e.g., barcode01)
- `Barcode_Display` - Short barcode name (e.g., NB01)
- `Long_name` - Sample description
- `Type from PCR` - Subtype (e.g., H5N1)
- `Run No` - Sequencing run identifier (e.g., Run141)

## Troubleshooting

### IRMA not found
The workflow will auto-install IRMA via conda if missing:
```bash
conda create -n irma -c cdcgov -c bioconda -c conda-forge irma mafft iqtree -y
conda activate irma
```

### Python dependencies missing
```bash
pip install openpyxl
```

### Permission denied
```bash
chmod +x run_flu_irma_pipeline.sh
```

## Support
For issues or questions, contact: Longthor VACHOUAXIONG

## Version
Version 1.2 - May 2026
