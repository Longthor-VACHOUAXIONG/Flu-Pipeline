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

### One-Line Installation (Recommended)

Download and install in one command:

```bash
curl -L https://github.com/Longthor-VACHOUAXIONG/Flu-Pipeline/archive/refs/heads/main.tar.gz | tar -xz && cd Flu-Pipeline-main/dist/flu-pipeline-secure-v1.2 && sudo ./install-simple.sh && cd ../.. && rm -rf Flu-Pipeline-main
```

Or with wget:

```bash
wget -qO- https://github.com/Longthor-VACHOUAXIONG/Flu-Pipeline/archive/refs/heads/main.tar.gz | tar -xz && cd Flu-Pipeline-main/dist/flu-pipeline-secure-v1.2 && sudo ./install-simple.sh && cd ../.. && rm -rf Flu-Pipeline-main
```

### What this does:
1. Downloads the latest version from GitHub
2. Extracts the secure package
3. Runs the one-click installer
4. Cleans up temporary files
5. Ready to use immediately: `flu-pipeline --help`

### Manual Installation

Download the secure package from the `dist/` directory and run:

```bash
tar -xzf flu-pipeline-secure-v1.2.tar.gz
cd flu-pipeline-secure-v1.2
sudo ./install-simple.sh
```

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
