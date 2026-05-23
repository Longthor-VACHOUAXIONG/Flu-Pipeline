#!/bin/bash
# install-simple.sh - One-Click Installer for Influenza Sequencing Workflow

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🧬  Influenza Workflow - One-Click Installer"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check for sudo
if [ "$EUID" -ne 0 ]; then
  echo "❌ Please run with sudo: sudo ./install-simple.sh"
  exit 1
fi

INSTALL_DIR="/usr/local/lib/flu-pipeline"
BIN_DIR="/usr/local/bin"

echo "▶ Installing to system directory: $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"

# Determine which files to install (prefer compiled .x files if available)
PIPE_SRC="run_flu_irma_pipeline.sh"
[ -f "${PIPE_SRC}.x" ] && PIPE_SRC="${PIPE_SRC}.x"

TEST_SRC=".scripts/test_alignment.sh"
[ -f "${TEST_SRC}.x" ] && TEST_SRC="${TEST_SRC}.x"

echo "▶ Building combined reference library..."
for f in .references/A_*.fasta .references/B_*.fasta; do
    sed '$a\' "$f"
done > .references/combined_flu_reference.fasta 2>/dev/null

echo "▶ Installing workflow components..."
rm -rf "$INSTALL_DIR/.references"
cp -r .references "$INSTALL_DIR/"
cp -r .scripts "$INSTALL_DIR/"
cp "$PIPE_SRC" "$INSTALL_DIR/flu-pipeline.exec"
cp "$TEST_SRC" "$INSTALL_DIR/flu-realign.exec"
cp metadata.xlsx "$INSTALL_DIR/metadata_template.xlsx"

chmod +x "$INSTALL_DIR/flu-pipeline.exec"
chmod +x "$INSTALL_DIR/flu-realign.exec"
chmod a+r "$INSTALL_DIR/.references/combined_flu_reference.fasta"
chmod a+r "$INSTALL_DIR/metadata_template.xlsx"

echo "▶ Setting up global commands..."
rm -f "$BIN_DIR/flu-pipeline"
rm -f "$BIN_DIR/flu-realign"

cat <<EOF > "$BIN_DIR/flu-pipeline"
#!/bin/bash
export FLU_PIPELINE_DIR="$INSTALL_DIR"
exec "\$FLU_PIPELINE_DIR/flu-pipeline.exec" "\$@"
EOF

cat <<EOF > "$BIN_DIR/flu-realign"
#!/bin/bash
export FLU_PIPELINE_DIR="$INSTALL_DIR"
exec "\$FLU_PIPELINE_DIR/flu-realign.exec" "\$@"
EOF

chmod +x "$BIN_DIR/flu-pipeline"
chmod +x "$BIN_DIR/flu-realign"

echo "▶ Cleaning up installation files..."
rm -rf .references .scripts
rm -f run_flu_irma_pipeline.sh run_flu_irma_pipeline.sh.x
rm -f metadata.xlsx

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Installation Complete!"
echo "🚀 Ready to use immediately!"
echo ""
echo "Usage:"
echo "   flu-pipeline --help"
echo "   flu-pipeline --all"
echo ""
echo "Just put your metadata.xlsx in your working directory and run."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Self-delete the installer script
rm -f "$0"
