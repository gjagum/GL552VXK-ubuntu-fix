#!/bin/bash
# ============================================================================
# ASUS ROG Battery Charge Limit Uninstaller
# ============================================================================
#
# Removes all files and services installed by the battery charge limit fix.
#
# Run with sudo to completely remove the installation.
# ============================================================================

set -e

echo "=== Removing ASUS ROG Battery Charge Limit ==="
echo "This will remove all installed files and services."
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script must be run with sudo or as root"
    echo "Usage: sudo bash remove-battery-charge-limit.sh"
    exit 1
fi

# Configuration
INSTALL_DIR="/usr/local/bin"
SCRIPT_NAME="set-battery-charge-limit.sh"
GUI_SCRIPT_NAME="toggle-battery-limit.sh"
SERVICE_NAME="battery-charge-limit"
SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME.service"
DESKTOP_FILE="/usr/share/applications/battery-charge-limit.desktop"
LOG_FILE="/var/log/battery-charge-limit.log"

# Step 1: Stop and disable systemd service
echo "Step 1: Removing systemd service..."
if [[ -f "$SERVICE_FILE" ]]; then
    systemctl stop "$SERVICE_NAME.service" 2>/dev/null || true
    systemctl disable "$SERVICE_NAME.service" 2>/dev/null || true
    rm -f "$SERVICE_FILE"
    systemctl daemon-reload
    echo "✓ Removed systemd service: $SERVICE_FILE"
else
    echo "Systemd service not found: $SERVICE_FILE"
fi

# Step 2: Remove installed scripts
echo ""
echo "Step 2: Removing installed scripts..."
if [[ -f "$INSTALL_DIR/$SCRIPT_NAME" ]]; then
    rm -f "$INSTALL_DIR/$SCRIPT_NAME"
    echo "✓ Removed script: $INSTALL_DIR/$SCRIPT_NAME"
else
    echo "Script not found: $INSTALL_DIR/$SCRIPT_NAME"
fi

if [[ -f "$INSTALL_DIR/$GUI_SCRIPT_NAME" ]]; then
    rm -f "$INSTALL_DIR/$GUI_SCRIPT_NAME"
    echo "✓ Removed GUI script: $INSTALL_DIR/$GUI_SCRIPT_NAME"
fi

# Step 3: Remove desktop shortcut
echo ""
echo "Step 3: Removing desktop shortcut..."
if [[ -f "$DESKTOP_FILE" ]]; then
    rm -f "$DESKTOP_FILE"
    echo "✓ Removed desktop shortcut: $DESKTOP_FILE"
fi

# Step 4: Remove log file
echo ""
echo "Step 4: Removing log file..."
if [[ -f "$LOG_FILE" ]]; then
    rm -f "$LOG_FILE"
    echo "✓ Removed log file: $LOG_FILE"
fi

# Step 5: Note about battery threshold
echo ""
echo "Step 5: Battery charge threshold note..."
BATTERY_PATH="/sys/class/power_supply/BAT0"
THRESHOLD_FILE="$BATTERY_PATH/charge_control_end_threshold"
if [[ -f "$THRESHOLD_FILE" ]]; then
    current=$(cat "$THRESHOLD_FILE" 2>/dev/null || echo "100")
    echo "Current battery charge limit: ${current}%"
    echo "To reset to 100%, run: echo 100 > $THRESHOLD_FILE"
fi

echo ""
echo "========================================"
echo "UNINSTALLATION COMPLETE"
echo "========================================"
echo ""
echo "All installed files and services have been removed."
echo ""
echo "NOTE: The battery charge limit is still set to ${current}%."
echo "To change it manually, edit: $THRESHOLD_FILE"
echo "Example: echo 100 | sudo tee $THRESHOLD_FILE"
echo ""
echo "You may need to reboot for all changes to take effect."
echo "========================================"