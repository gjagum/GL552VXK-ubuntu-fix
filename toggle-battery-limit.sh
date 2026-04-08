#!/bin/bash
# ============================================================================
# ASUS ROG Battery Charge Limit GUI Toggle
# ============================================================================
#
# Simple GUI to toggle battery charge limit between 80% (battery health)
# and 100% (full capacity) using zenity.
#
# Requires: zenity, sudo permissions
# ============================================================================

set -e

# Configuration
BATTERY_PATH="/sys/class/power_supply/BAT0"
THRESHOLD_FILE="$BATTERY_PATH/charge_control_end_threshold"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAIN_SCRIPT="$SCRIPT_DIR/set-battery-charge-limit.sh"

# Colors for terminal output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Check if running with GUI support
if [[ -z "$DISPLAY" ]]; then
    echo -e "${RED}Error: This script requires a graphical environment.${NC}"
    echo "Run the command-line version instead:"
    echo "  sudo $MAIN_SCRIPT --set <percentage>"
    exit 1
fi

# Check if zenity is available
if ! command -v zenity >/dev/null 2>&1; then
    echo -e "${RED}Error: zenity is not installed.${NC}"
    echo "Install with: sudo apt install zenity"
    exit 1
fi

# Check if main script exists
if [[ ! -f "$MAIN_SCRIPT" ]]; then
    zenity --error --width=300 --title="Error" \
        --text="Main script not found:\n$MAIN_SCRIPT\n\nPlease ensure set-battery-charge-limit.sh is in the same directory."
    exit 1
fi

# Get current threshold
get_current_threshold() {
    if [[ -f "$THRESHOLD_FILE" ]]; then
        cat "$THRESHOLD_FILE" 2>/dev/null || echo "100"
    else
        echo "100"
    fi
}

# Main GUI function
main() {
    local current=$(get_current_threshold)
    
    # Determine recommended action
    if [[ $current -eq 100 ]]; then
        local recommendation="80% (Recommended for battery health)"
        local default_option="80%"
    else
        local recommendation="100% (Full capacity for extended use)"
        local default_option="100%"
    fi
    
    # Show selection dialog
    local choice=$(zenity --list \
        --title="Battery Charge Limit" \
        --width=400 \
        --height=250 \
        --text="Current charge limit: <b>${current}%</b>\n\nSelect new charge limit:" \
        --column="Limit" --column="Description" \
        "80%" "Limit charging to 80% for battery health (recommended for daily use)" \
        "100%" "Charge to 100% for maximum capacity (use when you need full battery)" \
        --hide-header \
        --ok-label="Apply" \
        --cancel-label="Cancel" \
        --default-item="$default_option")
    
    if [[ -z "$choice" ]]; then
        zenity --info --width=300 --title="Cancelled" --text="No changes made."
        exit 0
    fi
    
    # Extract percentage number
    local percentage="${choice%%%*}"
    
    # Ask for sudo password via zenity
    local password=$(zenity --password --title="Authentication Required" \
        --text="This action requires administrator privileges.\n\nEnter your password:")
    
    if [[ -z "$password" ]]; then
        zenity --error --width=300 --title="Error" --text="Authentication failed."
        exit 1
    fi
    
    # Execute the main script with sudo
    echo "$password" | sudo -S "$MAIN_SCRIPT" --set "$percentage" 2>&1 | \
        tee /tmp/battery-limit-output.txt
    
    local result=$?
    
    if [[ $result -eq 0 ]]; then
        zenity --info --width=300 --title="Success" \
            --text="Battery charge limit set to ${percentage}%.\n\nYour battery will now stop charging at ${percentage}%."
    else
        local error_msg=$(cat /tmp/battery-limit-output.txt 2>/dev/null | head -5)
        zenity --error --width=400 --title="Error" \
            --text="Failed to set battery charge limit:\n\n${error_msg}"
        exit 1
    fi
}

# Run main function
main