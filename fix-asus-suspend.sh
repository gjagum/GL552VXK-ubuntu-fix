#!/bin/bash
# ASUS ROG Suspend Fix Installation Script
# Run this script after fresh Ubuntu installation on ASUS laptops with NVIDIA/Intel dual graphics

set -e

echo "=========================================="
echo "ASUS ROG Suspend Fix Installation Script"
echo "=========================================="
echo ""
echo "This script will fix suspend issues on ASUS ROG laptops with NVIDIA/Intel graphics."
echo "It will:"
echo "1. Update GRUB configuration with optimized kernel parameters"
echo "2. Create wakeup configuration script"
echo "3. Install systemd service for automatic wakeup configuration"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root or with sudo"
    exit 1
fi

# Backup original files
BACKUP_DIR="/root/backup-suspend-fix-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo "Creating backup in: $BACKUP_DIR"

# Backup GRUB config
if [ -f "/etc/default/grub" ]; then
    cp /etc/default/grub "$BACKUP_DIR/grub.original"
fi

# ==========================================
# Step 1: Update GRUB Configuration
# ==========================================

echo ""
echo "Step 1: Updating GRUB configuration..."

GRUB_FILE="/etc/default/grub"
GRUB_BACKUP="$BACKUP_DIR/grub.modified"

# Create backup of current GRUB config
cp "$GRUB_FILE" "$GRUB_BACKUP"

# Check if parameters already exist
if grep -q "acpi_osi=" "$GRUB_FILE"; then
    echo "ACPI parameters already exist in GRUB. Updating..."
    # Remove existing parameters and add new ones
    sed -i 's/ acpi_osi=[^ ]*//g' "$GRUB_FILE"
    sed -i 's/ pcie_aspm=[^ ]*//g' "$GRUB_FILE"
    sed -i 's/ pcie_port_pm=[^ ]*//g' "$GRUB_FILE"
    sed -i 's/ nouveau.modeset=[^ ]*//g' "$GRUB_FILE"
    sed -i 's/ nvidia.NVreg_EnableS0ixPowerManagement=[^ ]*//g' "$GRUB_FILE"
    sed -i 's/ mem_sleep_default=[^ ]*//g' "$GRUB_FILE"
fi

# Find the GRUB_CMDLINE_LINUX_DEFAULT line and append parameters
if grep -q '^GRUB_CMDLINE_LINUX_DEFAULT=' "$GRUB_FILE"; then
    # Get current line
    CURRENT_LINE=$(grep '^GRUB_CMDLINE_LINUX_DEFAULT=' "$GRUB_FILE")
    
    # Remove quotes and trailing spaces
    CLEAN_LINE=$(echo "$CURRENT_LINE" | sed 's/^GRUB_CMDLINE_LINUX_DEFAULT=//' | sed 's/"//g' | sed 's/ $//')
    
    # Add new parameters
    NEW_LINE="$CLEAN_LINE acpi_osi=\\\"Windows 2020\\\" pcie_aspm=off pcie_port_pm=off nouveau.modeset=0 nvidia.NVreg_EnableS0ixPowerManagement=1 mem_sleep_default=deep"
    
    # Update the line
    sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$NEW_LINE\"|" "$GRUB_FILE"
else
    echo "Error: Could not find GRUB_CMDLINE_LINUX_DEFAULT in $GRUB_FILE"
    exit 1
fi

echo "Updated GRUB configuration:"
grep '^GRUB_CMDLINE_LINUX_DEFAULT=' "$GRUB_FILE"

# ==========================================
# Step 2: Create Wakeup Configuration Script
# ==========================================

echo ""
echo "Step 2: Creating wakeup configuration script..."

WAKEUP_SCRIPT="/usr/local/bin/configure-wakeup"

cat > "$WAKEUP_SCRIPT" << 'EOF'
#!/bin/bash
# Configure wakeup sources for ASUS ROG laptops
# Enable power button and lid wakeup, disable everything else

# Enable power button wakeup (PNP0C0C)
if [ -f "/sys/bus/acpi/devices/PNP0C0C:00/power/wakeup" ]; then
    echo enabled > "/sys/bus/acpi/devices/PNP0C0C:00/power/wakeup"
fi

# Enable lid wakeup (PNP0C0D)
if [ -f "/sys/bus/acpi/devices/PNP0C0D:00/power/wakeup" ]; then
    echo enabled > "/sys/bus/acpi/devices/PNP0C0D:00/power/wakeup"
fi

# Disable all USB wakeup
for wakeup in /sys/bus/usb/devices/*/power/wakeup; do
    if [ -f "$wakeup" ]; then
        echo disabled > "$wakeup" 2>/dev/null || true
    fi
done

# Disable problematic ACPI wakeup sources via /proc/acpi/wakeup
if [ -f "/proc/acpi/wakeup" ]; then
    # For XHC (USB controller), echo twice to ensure disabled
    echo "XHC" > "/proc/acpi/wakeup" 2>/dev/null || true
    echo "XHC" > "/proc/acpi/wakeup" 2>/dev/null || true
    
    # For PEG0 (PCIe graphics), RP01, RP04 (PCIe root ports)
    for dev in PEG0 RP01 RP04; do
        echo "$dev" > "/proc/acpi/wakeup" 2>/dev/null || true
    done
fi

# Disable PCI wakeup via sysfs
find /sys/devices -path "*/pci*/power/wakeup" -type f 2>/dev/null | while read wakeup; do
    if [ -f "$wakeup" ]; then
        echo disabled > "$wakeup" 2>/dev/null || true
    fi
done

# Disable other miscellaneous wakeup sources
for dev in /sys/devices/platform/i8042/serio0 /sys/devices/pnp0/00:02/rtc/rtc0/alarmtimer.0.auto; do
    if [ -f "$dev/power/wakeup" ]; then
        echo disabled > "$dev/power/wakeup" 2>/dev/null || true
    fi
done

# Disable power supply wakeup
find /sys/devices -name wakeup -type f -path "*/power_supply/*" -exec grep -l enabled {} \; 2>/dev/null | while read file; do
    echo disabled > "$file" 2>/dev/null || true
done
EOF

chmod +x "$WAKEUP_SCRIPT"
echo "Created wakeup script: $WAKEUP_SCRIPT"

# ==========================================
# Step 3: Create Systemd Service
# ==========================================

echo ""
echo "Step 3: Creating systemd service..."

SERVICE_FILE="/etc/systemd/system/configure-wakeup.service"

cat > "$SERVICE_FILE" << 'EOF'
[Unit]
Description=Configure wakeup sources for deep sleep
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/configure-wakeup
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and enable service
systemctl daemon-reload
systemctl enable configure-wakeup.service
systemctl start configure-wakeup.service

echo "Created and enabled systemd service: $SERVICE_FILE"

# ==========================================
# Step 4: Update GRUB and Run Initial Config
# ==========================================

echo ""
echo "Step 4: Updating GRUB and running initial configuration..."

update-grub

# Run the wakeup configuration script
/usr/local/bin/configure-wakeup

# ==========================================
# Step 5: Verification
# ==========================================

echo ""
echo "Step 5: Verifying configuration..."
echo ""

echo "1. Checking kernel parameters:"
cat /proc/cmdline | grep -o "acpi_osi[^ ]*\|pcie[^ ]*\|nvidia[^ ]*\|mem_sleep[^ ]*" | sort | uniq

echo ""
echo "2. Checking sleep mode:"
cat /sys/power/mem_sleep

echo ""
echo "3. Checking wakeup sources:"
if [ -f "/proc/acpi/wakeup" ]; then
    echo "Enabled ACPI wakeup sources:"
    grep "*enabled" /proc/acpi/wakeup || echo "None (good!)"
else
    echo "/proc/acpi/wakeup not found"
fi

echo ""
echo "4. Checking power button wakeup:"
if [ -f "/sys/bus/acpi/devices/PNP0C0C:00/power/wakeup" ]; then
    cat "/sys/bus/acpi/devices/PNP0C0C:00/power/wakeup"
else
    echo "Power button wakeup file not found"
fi

echo ""
echo "5. Checking lid wakeup:"
if [ -f "/sys/bus/acpi/devices/PNP0C0D:00/power/wakeup" ]; then
    cat "/sys/bus/acpi/devices/PNP0C0D:00/power/wakeup"
else
    echo "Lid wakeup file not found"
fi

# ==========================================
# Step 6: Create Test Script
# ==========================================

echo ""
echo "Step 6: Creating test script..."

TEST_SCRIPT="/usr/local/bin/test-suspend"

cat > "$TEST_SCRIPT" << 'EOF'
#!/bin/bash
# Test suspend functionality

echo "Testing suspend functionality..."
echo "System will suspend in 5 seconds..."
echo "Press power button to wake up"
echo ""

sleep 5

echo "Initiating suspend..."
systemctl suspend

echo ""
echo "Resumed from suspend!"
echo "Check if CPU/fan stopped during suspend:"
echo "- If they stopped: Success!"
echo "- If they kept running: Check /var/log/syslog for errors"
EOF

chmod +x "$TEST_SCRIPT"

# ==========================================
# Final Instructions
# ==========================================

echo ""
echo "=========================================="
echo "INSTALLATION COMPLETE"
echo "=========================================="
echo ""
echo "What was done:"
echo "1. Updated GRUB with optimized kernel parameters"
echo "2. Created wakeup configuration script at $WAKEUP_SCRIPT"
echo "3. Installed systemd service to run on boot"
echo "4. Backup created in: $BACKUP_DIR"
echo "5. Test script created: $TEST_SCRIPT"
echo ""
echo "IMPORTANT: REBOOT REQUIRED!"
echo ""
echo "To test suspend after reboot:"
echo "1. Reboot: sudo reboot"
echo "2. After reboot, test: sudo test-suspend"
echo ""
echo "Configuration files:"
echo "- GRUB config: /etc/default/grub"
echo "- Wakeup script: /usr/local/bin/configure-wakeup"
echo "- Systemd service: /etc/systemd/system/configure-wakeup.service"
echo "- Test script: /usr/local/bin/test-suspend"
echo "- Documentation: See /home/$SUDO_USER/Documents/asus-rog-suspend-fix.md"
echo ""
echo "To revert changes:"
echo "1. Restore GRUB from backup: sudo cp $BACKUP_DIR/grub.original /etc/default/grub"
echo "2. Update GRUB: sudo update-grub"
echo "3. Disable service: sudo systemctl disable configure-wakeup.service"
echo "4. Remove service: sudo rm /etc/systemd/system/configure-wakeup.service"
echo "5. Remove scripts: sudo rm /usr/local/bin/configure-wakeup /usr/local/bin/test-suspend"
echo "6. Reboot"
echo ""
echo "=========================================="