#!/bin/bash
# ============================================================================
# ASUS ROG Battery Charge Limit Installer
# ============================================================================
#
# PROBLEM: Battery charging limit feature not visible in desktop settings
# ROOT CAUSE: Hardware supports charge control via sysfs, but desktop GUI
#             (GNOME/upower) doesn't expose this setting.
# SOLUTION: Direct sysfs control with persistence across reboots and optional GUI.
#
# HARDWARE: ASUS ROG GL552VXK (and other ASUS laptops with ACPI battery driver)
# SOFTWARE: Ubuntu 25.10, Kernel 6.17.0-12-generic
#
# FEATURES:
#   1. Command-line control of battery charge limit (60-100%)
#   2. Systemd service for automatic limit application at boot
#   3. Optional GUI toggle (requires zenity)
#   4. Desktop application shortcut (optional)
#
# Run with sudo on Ubuntu systems with ASUS battery support
# ============================================================================

set -e

echo "=== Installing ASUS ROG Battery Charge Limit ==="
echo "Hardware: ASUS ROG laptop with ACPI battery control"
echo "Issue: Battery charging limit feature hidden in desktop settings"
echo "Solution: Sysfs control with persistence and optional GUI"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script must be run with sudo or as root"
    echo "Usage: sudo bash install-battery-charge-limit.sh"
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

# Check if battery supports charge control
echo "Checking for battery charge control support..."
BATTERY_PATH="/sys/class/power_supply/BAT0"
THRESHOLD_FILE="$BATTERY_PATH/charge_control_end_threshold"

if [[ ! -d "$BATTERY_PATH" ]]; then
    echo "WARNING: Battery device not found at $BATTERY_PATH"
    echo "This script is for laptops with ACPI battery control"
    echo "Continue anyway? (y/n)"
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo "Installation cancelled"
        exit 1
    fi
fi

if [[ ! -f "$THRESHOLD_FILE" ]]; then
    echo "ERROR: Charge control not supported by this battery"
    echo "Missing file: $THRESHOLD_FILE"
    echo "This feature requires ACPI battery driver with charge_control_end_threshold"
    exit 1
fi

if [[ ! -w "$THRESHOLD_FILE" ]]; then
    echo "ERROR: Cannot write to $THRESHOLD_FILE"
    echo "Check permissions. Try running with sudo."
    exit 1
fi

echo "✓ Battery charge control supported"

# Step 1: Install main script
echo ""
echo "Step 1: Installing main control script..."
if [[ ! -f "./$SCRIPT_NAME" ]]; then
    echo "ERROR: Main script not found: ./$SCRIPT_NAME"
    echo "Please run this installer from the directory containing $SCRIPT_NAME"
    exit 1
fi

cp "./$SCRIPT_NAME" "$INSTALL_DIR/$SCRIPT_NAME"
chmod +x "$INSTALL_DIR/$SCRIPT_NAME"
echo "✓ Installed $INSTALL_DIR/$SCRIPT_NAME"

# Step 2: Install systemd service using the script's built-in installer
echo ""
echo "Step 2: Installing systemd service for persistence..."
"$INSTALL_DIR/$SCRIPT_NAME" --install-service
echo "✓ Systemd service installed and enabled"

# Step 3: Install GUI toggle script (optional)
echo ""
echo "Step 3: Installing optional GUI toggle..."
if [[ -f "./$GUI_SCRIPT_NAME" ]]; then
    cp "./$GUI_SCRIPT_NAME" "$INSTALL_DIR/$GUI_SCRIPT_NAME"
    chmod +x "$INSTALL_DIR/$GUI_SCRIPT_NAME"
    echo "✓ Installed GUI toggle: $INSTALL_DIR/$GUI_SCRIPT_NAME"
    
    # Check if zenity is available
    if command -v zenity >/dev/null 2>&1; then
        echo "✓ zenity detected (GUI will work)"
    else
        echo "NOTE: zenity not installed. GUI will not work."
        echo "Install with: sudo apt install zenity"
    fi
    
    # Step 4: Create desktop shortcut (optional)
    echo ""
    echo "Step 4: Creating desktop shortcut..."
    if [[ -d "/usr/share/applications" ]]; then
        cat > "$DESKTOP_FILE" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Battery Charge Limit
Comment=Toggle battery charging limit between 80% and 100%
Exec=sudo $INSTALL_DIR/$GUI_SCRIPT_NAME
Icon=battery
Terminal=false
Categories=Utility;System;
Keywords=battery;charge;limit;asus;
EOF
        chmod +x "$DESKTOP_FILE" 2>/dev/null || true
        echo "✓ Desktop shortcut created: $DESKTOP_FILE"
        echo "  Note: You may need to log out and back in to see the shortcut."
    else
        echo "NOTE: /usr/share/applications not found, skipping desktop shortcut"
    fi
else
    echo "NOTE: GUI script not found, skipping GUI installation"
fi

# Step 5: Apply default threshold (80%) if currently at 100%
echo ""
echo "Step 5: Setting default charge limit (80%)..."
current=$(cat "$THRESHOLD_FILE")
if [[ $current -eq 100 ]]; then
    echo "Current limit is 100%, setting to 80% for battery health..."
    echo 80 > "$THRESHOLD_FILE"
    echo "✓ Battery charge limit set to 80%"
else
    echo "Current limit is already ${current}%, leaving as is."
fi

# Step 6: Create log file
echo ""
echo "Step 6: Setting up logging..."
touch "$LOG_FILE"
chmod 644 "$LOG_FILE"
echo "✓ Log file created: $LOG_FILE"

# Summary
echo ""
echo "========================================"
echo "INSTALLATION COMPLETE"
echo "========================================"
echo ""
echo "What was installed:"
echo "  • Main control script: $INSTALL_DIR/$SCRIPT_NAME"
echo "  • Systemd service: $SERVICE_FILE"
echo "  • Log file: $LOG_FILE"
if [[ -f "./$GUI_SCRIPT_NAME" ]]; then
    echo "  • GUI toggle script: $INSTALL_DIR/$GUI_SCRIPT_NAME"
    if [[ -f "$DESKTOP_FILE" ]]; then
        echo "  • Desktop shortcut: $DESKTOP_FILE"
    fi
fi
echo ""
echo "Usage:"
echo "  Command-line:"
echo "    sudo $INSTALL_DIR/$SCRIPT_NAME --set 80   # Limit to 80%"
echo "    sudo $INSTALL_DIR/$SCRIPT_NAME --set 100  # Limit to 100%"
echo "    sudo $INSTALL_DIR/$SCRIPT_NAME --status   # Show current limit"
echo ""
if [[ -f "$INSTALL_DIR/$GUI_SCRIPT_NAME" ]]; then
    echo "  GUI:"
    echo "    $INSTALL_DIR/$GUI_SCRIPT_NAME"
    echo "    (or search for 'Battery Charge Limit' in application menu)"
    echo ""
fi
echo "The battery charge limit will automatically be set to 80% on every boot."
echo "To change this default, edit $INSTALL_DIR/$SCRIPT_NAME or the systemd service."
echo ""
echo "For more information, run: sudo $INSTALL_DIR/$SCRIPT_NAME --help"
echo ""
echo "========================================"
echo "IMPORTANT: Reboot to ensure all changes take effect."
echo "========================================"