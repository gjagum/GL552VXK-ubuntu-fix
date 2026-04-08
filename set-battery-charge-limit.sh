#!/bin/bash
# ============================================================================
# ASUS ROG Battery Charge Limit Control Script
# ============================================================================
#
# PROBLEM: Battery charging limit feature not visible in desktop settings
# ROOT CAUSE: Hardware supports charge control via sysfs, but desktop GUI
#             (GNOME/upower) doesn't expose this setting.
# SOLUTION: Direct sysfs control with persistence across reboots.
#
# HARDWARE: ASUS ROG GL552VXK (and other ASUS laptops with ACPI battery driver)
# SOFTWARE: Ubuntu 25.10, Kernel 6.17.0-12-generic
#
# USAGE:
#   sudo ./set-battery-charge-limit.sh --set <percentage>
#   sudo ./set-battery-charge-limit.sh --status
#   sudo ./set-battery-charge-limit.sh --install-service
#   sudo ./set-battery-charge-limit.sh --remove-service
#
# DEFAULT THRESHOLD: 80% (recommended for battery health)
# VALID RANGE: 60-100 (some laptops may have different limits)
#
# PERSISTENCE: Install systemd service to apply threshold on every boot.
# ============================================================================

set -e

# Configuration
BATTERY_PATH="/sys/class/power_supply/BAT0"
THRESHOLD_FILE="$BATTERY_PATH/charge_control_end_threshold"
SERVICE_NAME="battery-charge-limit"
SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME.service"
SCRIPT_INSTALL_PATH="/usr/local/bin/$SERVICE_NAME.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Helper functions
error() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    exit 1
}

warning() {
    echo -e "${YELLOW}WARNING: $1${NC}" >&2
}

success() {
    echo -e "${GREEN}$1${NC}"
}

info() {
    echo -e "$1"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
    fi
}

# Check if battery exists and supports charge control (read-only)
check_battery_readonly() {
    if [[ ! -d "$BATTERY_PATH" ]]; then
        error "Battery device not found at $BATTERY_PATH"
    fi
    
    if [[ ! -f "$THRESHOLD_FILE" ]]; then
        error "Charge control not supported by this battery (missing $THRESHOLD_FILE)"
    fi
}

# Check if battery supports charge control and is writable
check_battery_writable() {
    check_battery_readonly
    
    if [[ ! -w "$THRESHOLD_FILE" ]]; then
        error "Cannot write to $THRESHOLD_FILE (check permissions)"
    fi
}

# Backward compatibility alias
check_battery_support() {
    check_battery_writable
}

# Get current threshold
get_threshold() {
    cat "$THRESHOLD_FILE"
}

# Set threshold (60-100)
set_threshold() {
    local threshold=$1
    
    # Validate input
    if [[ ! $threshold =~ ^[0-9]+$ ]]; then
        error "Threshold must be a number between 60 and 100"
    fi
    
    if [[ $threshold -lt 60 || $threshold -gt 100 ]]; then
        warning "Threshold $threshold% is outside recommended range (60-100)"
        echo "Are you sure you want to set threshold to $threshold%? (y/N)"
        read -r confirm
        if [[ ! $confirm =~ ^[Yy]$ ]]; then
            info "Operation cancelled"
            exit 0
        fi
    fi
    
    # Write to sysfs
    echo "$threshold" > "$THRESHOLD_FILE"
    
    # Verify
    local current=$(get_threshold)
    if [[ $current -eq $threshold ]]; then
        success "Battery charge limit set to ${threshold}%"
    else
        error "Failed to set threshold (current: ${current}%)"
    fi
}

# Install systemd service for persistence
install_service() {
    check_root
    check_battery_writable
    
    info "Installing battery charge limit service..."
    
    # Create the script that will be run at boot
    cat > "$SCRIPT_INSTALL_PATH" << 'EOF'
#!/bin/bash
# Battery charge limit application script
# This script is called by systemd service at boot

BATTERY_PATH="/sys/class/power_supply/BAT0"
THRESHOLD_FILE="$BATTERY_PATH/charge_control_end_threshold"
DEFAULT_THRESHOLD=80

# Check if threshold file exists and is writable
if [[ -f "$THRESHOLD_FILE" && -w "$THRESHOLD_FILE" ]]; then
    # Only set if current value is 100 (default)
    current=$(cat "$THRESHOLD_FILE" 2>/dev/null || echo "100")
    if [[ $current -eq 100 ]]; then
        echo "$DEFAULT_THRESHOLD" > "$THRESHOLD_FILE"
        echo "[$(date)] Set battery charge limit to ${DEFAULT_THRESHOLD}%" >> /var/log/battery-charge-limit.log
    fi
fi
EOF
    
    chmod +x "$SCRIPT_INSTALL_PATH"
    success "Created script: $SCRIPT_INSTALL_PATH"
    
    # Create systemd service
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Set battery charge limit to preserve battery health
After=multi-user.target
Before=graphical.target

[Service]
Type=oneshot
ExecStart=$SCRIPT_INSTALL_PATH
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME.service"
    systemctl start "$SERVICE_NAME.service"
    
    success "Created and enabled systemd service: $SERVICE_NAME.service"
    info "Service will set charge limit to 80% at every boot (if currently at 100%)"
    
    # Apply threshold now
    current=$(get_threshold)
    if [[ $current -eq 100 ]]; then
        set_threshold 80
    fi
}

# Remove systemd service
remove_service() {
    check_root
    
    info "Removing battery charge limit service..."
    
    if [[ -f "$SERVICE_FILE" ]]; then
        systemctl stop "$SERVICE_NAME.service" 2>/dev/null || true
        systemctl disable "$SERVICE_NAME.service" 2>/dev/null || true
        rm -f "$SERVICE_FILE"
        systemctl daemon-reload
        success "Removed systemd service: $SERVICE_NAME.service"
    else
        warning "Service file not found: $SERVICE_FILE"
    fi
    
    if [[ -f "$SCRIPT_INSTALL_PATH" ]]; then
        rm -f "$SCRIPT_INSTALL_PATH"
        success "Removed script: $SCRIPT_INSTALL_PATH"
    fi
    
    if [[ -f "/var/log/battery-charge-limit.log" ]]; then
        rm -f "/var/log/battery-charge-limit.log"
        success "Removed log file"
    fi
    
    info "Note: Battery charge threshold will remain at its current value."
    info "To reset to 100%, run: sudo $0 --set 100"
}

# Show status
show_status() {
    check_battery_readonly
    
    local current=$(get_threshold)
    local battery_status=$(cat "$BATTERY_PATH/status" 2>/dev/null || echo "unknown")
    local capacity=$(cat "$BATTERY_PATH/capacity" 2>/dev/null || echo "unknown")
    
    echo "========================================"
    echo "BATTERY CHARGE LIMIT STATUS"
    echo "========================================"
    echo "Current charge limit:   ${current}%"
    echo "Battery status:         ${battery_status}"
    echo "Battery capacity:       ${capacity}%"
    echo "Charge control file:    ${THRESHOLD_FILE}"
    
    if [[ -f "$SERVICE_FILE" ]]; then
        local service_status=$(systemctl is-active "$SERVICE_NAME.service" 2>/dev/null || echo "inactive")
        echo "Systemd service:        ${service_status}"
    else
        echo "Systemd service:        not installed"
    fi
    echo "========================================"
    
    if [[ $current -eq 100 ]]; then
        warning "Battery is set to charge to 100%, which may reduce long-term battery health."
        info "Consider setting limit to 80% with: sudo $0 --set 80"
    elif [[ $current -le 80 ]]; then
        success "Battery charge limit is set for optimal battery health."
    fi
}

# Show usage
usage() {
    echo "Usage: sudo $0 [OPTION]"
    echo ""
    echo "Options:"
    echo "  --set <percentage>    Set battery charge limit (60-100)"
    echo "  --status              Show current battery charge limit status"
    echo "  --install-service     Install systemd service for automatic limit at boot"
    echo "  --remove-service      Remove systemd service and scripts"
    echo "  --help               Show this help message"
    echo ""
    echo "Examples:"
    echo "  sudo $0 --set 80       # Limit charging to 80%"
    echo "  sudo $0 --status       # Show current limit"
    echo "  sudo $0 --install-service # Install automatic limit (80%) on boot"
    echo ""
    echo "Note: Some laptops may have different valid ranges (e.g., 60-80)."
}

# Main script logic
main() {
    case "$1" in
        --set)
            check_root
    check_battery_writable
            if [[ -z "$2" ]]; then
                error "Missing threshold value for --set option"
            fi
            set_threshold "$2"
            ;;
        --status)
            show_status
            ;;
        --install-service)
            install_service
            ;;
        --remove-service)
            remove_service
            ;;
        --help|-h)
            usage
            ;;
        *)
            if [[ -z "$1" ]]; then
                usage
            else
                error "Unknown option: $1"
            fi
            ;;
    esac
}

# Run main function with all arguments
main "$@"