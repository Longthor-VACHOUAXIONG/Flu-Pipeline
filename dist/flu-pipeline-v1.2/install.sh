#!/bin/bash
# install.sh - Installer for Influenza Sequencing Workflow

INSTALL_DIR="/usr/local/lib/flu-pipeline"
BIN_DIR="/usr/local/bin"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🧬  Influenza Workflow Installer"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 1. Check for sudo
if [ "$EUID" -ne 0 ]; then
  echo "❌ Please run with sudo: sudo ./install.sh"
  exit 1
fi

echo "▶ Preparing system directory: $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"

# 2. Determine which files to install (prefer compiled .x files if available)
PIPE_SRC="run_flu_irma_pipeline.sh"
[ -f "${PIPE_SRC}.x" ] && PIPE_SRC="${PIPE_SRC}.x"

TEST_SRC=".scripts/test_alignment.sh"
[ -f "${TEST_SRC}.x" ] && TEST_SRC="${TEST_SRC}.x"

# 3. Build the combined reference before copying
echo "▶ Building combined reference library..."
for f in .references/A_*.fasta .references/B_*.fasta; do
    sed '$a\' "$f"
done > .references/combined_flu_reference.fasta 2>/dev/null

# 4. Copy files to the permanent system directory
echo "▶ Installing workflow components..."
rm -rf "$INSTALL_DIR/.references"
cp -r .references "$INSTALL_DIR/"
cp -r .scripts "$INSTALL_DIR/"
cp "$PIPE_SRC" "$INSTALL_DIR/flu-pipeline.exec"
cp "$TEST_SRC" "$INSTALL_DIR/flu-realign.exec"
cp metadata.xlsx "$INSTALL_DIR/metadata_template.xlsx"

# Ensure they are executable
chmod +x "$INSTALL_DIR/flu-pipeline.exec"
chmod +x "$INSTALL_DIR/flu-realign.exec"
chmod a+r "$INSTALL_DIR/.references/combined_flu_reference.fasta"
chmod a+r "$INSTALL_DIR/metadata_template.xlsx"

# 4. Create Shell Wrappers in /usr/local/bin
echo "▶ Setting up global commands..."

# Remove old symlinks/files if they exist
rm -f "$BIN_DIR/flu-pipeline"
rm -f "$BIN_DIR/flu-realign"

# Wrapper for flu-pipeline
cat <<EOF > "$BIN_DIR/flu-pipeline"
#!/bin/bash
export FLU_PIPELINE_DIR="$INSTALL_DIR"
exec "\$FLU_PIPELINE_DIR/flu-pipeline.exec" "\$@"
EOF

# Wrapper for flu-realign
cat <<EOF > "$BIN_DIR/flu-realign"
#!/bin/bash
export FLU_PIPELINE_DIR="$INSTALL_DIR"
exec "\$FLU_PIPELINE_DIR/flu-realign.exec" "\$@"
EOF

chmod +x "$BIN_DIR/flu-pipeline"
chmod +x "$BIN_DIR/flu-realign"

if [ $? -eq 0 ]; then
    echo "▶ Cleaning up installation files to protect source code..."
    rm -rf .references .scripts
    rm -f run_flu_irma_pipeline.sh run_flu_irma_pipeline.sh.x
    rm -f metadata.xlsx
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "✅ Installation Successful!"
    echo "🚀 The workflow is now installed globally in a secure location."
    echo ""
    echo "Commands available from ANY folder:"
    echo "   - flu-pipeline : Run full sequencing workflow"
    echo "   - flu-realign  : Re-run only alignment & trees"
    echo ""
    echo "Workflow options:"
    echo "   --all         Run full workflow (default)"
    echo "   --irma        Run only Barcode mapping + IRMA assembly"
    echo "   --align       Run only Alignment (based on existing results)"
    echo "   --tree        Run only Phylogeny (based on existing alignments)"
    echo "   --fill        Run only Metadata Excel filling"
    echo "   --map         Run only Barcode-to-Sample mapping check"
    echo ""
    echo "ℹ  Note: The source files have been automatically removed."
    echo "   Only your metadata.xlsx and README remain for usage."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Self-delete the installer script
    rm -f "$0"
else
    echo "❌ Installation failed."
fi
