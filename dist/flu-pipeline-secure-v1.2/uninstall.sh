#!/bin/bash
# uninstall.sh - Uninstaller for Influenza Sequencing Workflow

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🧬  Influenza Workflow Uninstaller"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

INSTALL_DIR="$HOME/.flu-pipeline"
BIN_DIR="$HOME/.local/bin"

echo "▶ Removing workflow installation from: $INSTALL_DIR"
if [ -d "$INSTALL_DIR" ]; then
    rm -rf "$INSTALL_DIR"
    echo "   ✓ Removed installation directory"
else
    echo "   ℹ  Installation directory not found"
fi

echo "▶ Removing wrapper commands from: $BIN_DIR"
if [ -f "$BIN_DIR/flu-pipeline" ]; then
    rm -f "$BIN_DIR/flu-pipeline"
    echo "   ✓ Removed flu-pipeline command"
fi

if [ -f "$BIN_DIR/flu-realign" ]; then
    rm -f "$BIN_DIR/flu-realign"
    echo "   ✓ Removed flu-realign command"
fi

echo "▶ Removing PATH entry from ~/.bashrc"
if grep -q "$BIN_DIR" "$HOME/.bashrc" 2>/dev/null; then
    sed -i "\|$BIN_DIR|d" "$HOME/.bashrc"
    echo "   ✓ Removed PATH entry from ~/.bashrc"
else
    echo "   ℹ  PATH entry not found in ~/.bashrc"
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Uninstallation Complete!"
echo ""
echo "Note: You may need to restart your terminal or run:"
echo "   source ~/.bashrc"
echo "to update your PATH."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Self-delete the uninstaller script
rm -f "$0"
