#!/bin/bash
# ============================================================================
# ASUS ROG ELAN1200 Touchpad Fix Installer
# ============================================================================
# 
# PROBLEM: ELAN1200 touchpad (04F3:3045) stops working after suspend/resume
# ROOT CAUSE: ELAN1200 uses i2c_hid_acpi driver, not elan_i2c. After suspend,
#             driver binding fails or device enters unrecoverable power state.
# SOLUTION: Create automatic recovery system with:
#           1. Driver loading at boot (i2c_hid_acpi)
#           2. Power cycling script for device recovery
#           3. Systemd service for boot-time recovery
#           4. Suspend/resume hook for post-resume recovery
#           5. Comprehensive logging for troubleshooting
#
# HARDWARE: ASUS ROG GL552VXK with ELAN1200 touchpad (04F3:3045)
# SOFTWARE: Ubuntu 25.10, Kernel 6.17.0-12-generic
# DEVICE: i2c-ELAN1200:00 (I2C HID device, not pure I2C)
# ACPI: ELAN1200, modalias: acpi:ELAN1200:PNP0C50:
#
# Run with sudo on fresh Ubuntu installation
# ============================================================================

set -e

echo "=== Installing ASUS ROG ELAN1200 Touchpad Fix ==="
echo "Hardware: ASUS ROG laptop with ELAN1200 touchpad"
echo "Issue: Touchpad stops working after suspend/resume"
echo "Solution: Automatic recovery system with power cycling and driver reload"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script must be run with sudo or as root"
    echo "Usage: sudo bash install-asus-rog-touchpad-fix.sh"
    exit 1
fi

# Check for ELAN1200 device
echo "Checking for ELAN1200 touchpad device..."
if [ ! -e "/sys/bus/i2c/devices/i2c-ELAN1200:00" ] && [ ! -e "/sys/devices/LNXSYSTM:00/LNXSYBUS:00/PNP0A08:00/device:7a/ELAN1200:00" ]; then
    echo "WARNING: ELAN1200 device not found in sysfs"
    echo "This script is for ASUS ROG laptops with ELAN1200 touchpad"
    echo "Continue anyway? (y/n)"
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo "Installation cancelled"
        exit 1
    fi
else
    echo "✓ ELAN1200 device detected"
fi

# 1. Create module loading configuration
echo ""
echo "1. Creating module loading configuration..."
echo "i2c_hid_acpi" > /etc/modules-load.d/elan-touchpad.conf
echo "  Created /etc/modules-load.d/elan-touchpad.conf"

# 2. Create fix script
echo ""
echo "2. Creating touchpad fix script..."
cat > /usr/local/bin/fix-i2c-hid-acpi.sh << 'EOF'
#!/bin/bash
# Fix i2c_hid_acpi suspend/resume for ELAN1200 touchpad
# Run with sudo - exit 0 even if partial recovery to avoid systemd failure

set -e

DEVICE="i2c-ELAN1200:00"
LOG="/var/log/i2c-hid-fix.log"
SUCCESS=0

echo "=== i2c_hid_acpi Fix $(date) ===" >> $LOG

# Check if touchpad input device exists
if find /sys/class/input -name "event*" -exec cat {}/device/name 2>/dev/null \; 2>/dev/null | grep -qi "ELAN.*Touchpad"; then
    echo "Touchpad already working, nothing to do" >> $LOG
    echo "Touchpad already working" >> $LOG
    exit 0
fi

echo "Touchpad not detected, attempting recovery..." >> $LOG

# Diagnostic information
echo "--- Diagnostics ---" >> $LOG
echo "Device: $DEVICE" >> $LOG
if [ -e "/sys/bus/i2c/devices/$DEVICE" ]; then
    echo "Device exists in sysfs" >> $LOG
    echo "Driver: $(readlink -f /sys/bus/i2c/devices/$DEVICE/driver 2>/dev/null || echo 'none')" >> $LOG
    echo "Power control: $(cat /sys/bus/i2c/devices/$DEVICE/power/control 2>/dev/null)" >> $LOG
else
    echo "Device not found in sysfs" >> $LOG
fi

# Check ACPI device
ACPI_DEVICE="/sys/devices/LNXSYSTM:00/LNXSYBUS:00/PNP0A08:00/device:7a/ELAN1200:00"
if [ -e "$ACPI_DEVICE" ]; then
    echo "ACPI status: $(cat $ACPI_DEVICE/status 2>/dev/null)" >> $LOG
fi

# Step 1: Unbind from i2c_hid_acpi if currently bound
if [ -e "/sys/bus/i2c/drivers/i2c_hid_acpi/$DEVICE" ]; then
    echo "Unbinding from i2c_hid_acpi" >> $LOG
    echo "$DEVICE" > "/sys/bus/i2c/drivers/i2c_hid_acpi/unbind" 2>> $LOG
    sleep 1
fi

# Step 2: Power cycle the device
if [ -e "/sys/bus/i2c/devices/$DEVICE/power/control" ]; then
    echo "auto" > "/sys/bus/i2c/devices/$DEVICE/power/control" 2>> $LOG
    sleep 0.5
    echo "on" > "/sys/bus/i2c/devices/$DEVICE/power/control" 2>> $LOG
    echo "Power cycled I2C device" >> $LOG
    sleep 1
fi

# Step 3: Also power cycle ACPI device
if [ -e "$ACPI_DEVICE/power/control" ]; then
    echo "on" > "$ACPI_DEVICE/power/control" 2>> $LOG
    echo "Powered on ACPI device" >> $LOG
    sleep 0.5
fi

# Step 4: Reload i2c_hid and i2c_hid_acpi modules
echo "Reloading i2c_hid modules..." >> $LOG
modprobe -r i2c_hid_acpi i2c_hid 2>> $LOG || echo "Module remove failed (may not be loaded)" >> $LOG
sleep 1
modprobe i2c_hid 2>> $LOG || echo "i2c_hid load failed" >> $LOG
modprobe i2c_hid_acpi 2>> $LOG || echo "i2c_hid_acpi load failed" >> $LOG
sleep 3

# Step 5: Try to bind to i2c_hid_acpi (optional - may auto-bind)
if [ -e "/sys/bus/i2c/drivers/i2c_hid_acpi" ] && [ ! -e "/sys/bus/i2c/drivers/i2c_hid_acpi/$DEVICE" ]; then
    echo "Attempting bind to i2c_hid_acpi" >> $LOG
    echo "$DEVICE" > "/sys/bus/i2c/drivers/i2c_hid_acpi/bind" 2>> $LOG && echo "Manual bind successful" >> $LOG || echo "Manual bind failed (may auto-bind)" >> $LOG
fi

# Wait for device to initialize
sleep 5

# Step 6: Check if recovery succeeded
echo "--- Checking recovery ---" >> $LOG
if find /sys/class/input -name "event*" -exec cat {}/device/name 2>/dev/null \; 2>/dev/null | grep -qi "ELAN.*Touchpad"; then
    echo "SUCCESS: Touchpad detected after recovery" >> $LOG
    SUCCESS=1
else
    echo "FAILURE: Touchpad still not detected" >> $LOG
    # Additional diagnostics
    echo "Current driver binding: $(readlink -f /sys/bus/i2c/devices/$DEVICE/driver 2>/dev/null || echo 'none')" >> $LOG
    dmesg | tail -10 | grep -i elan >> $LOG 2>&1 || true
fi

echo "=== Fix completed $(date), success=$SUCCESS ===" >> $LOG
# Always exit 0 to avoid systemd failure - let the sleep hook handle retries
exit 0
EOF

chmod +x /usr/local/bin/fix-i2c-hid-acpi.sh
echo "  Created /usr/local/bin/fix-i2c-hid-acpi.sh"

# 3. Create systemd service
echo ""
echo "3. Creating systemd service..."
cat > /etc/systemd/system/fix-elantouchpad.service << 'EOF'
[Unit]
Description=Fix ELAN1200 touchpad after suspend/resume
After=multi-user.target
Before=graphical.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/fix-i2c-hid-acpi.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable fix-elantouchpad.service
echo "  Created and enabled systemd service: fix-elantouchpad.service"

# 4. Create suspend/resume hook
echo ""
echo "4. Creating suspend/resume hook..."
cat > /lib/systemd/system-sleep/touchpad-fix << 'EOF'
#!/bin/bash
case $1 in
    pre)
        # Before suspend - nothing needed
        ;;
    post)
        # After resume - fix touchpad
        sleep 2  # Wait for system to settle
        /usr/local/bin/fix-i2c-hid-acpi.sh
        ;;
esac
EOF

chmod +x /lib/systemd/system-sleep/touchpad-fix
echo "  Created suspend/resume hook: /lib/systemd/system-sleep/touchpad-fix"

# 5. Remove any conflicting configurations
echo ""
echo "5. Cleaning up conflicting configurations..."
rm -f /etc/modprobe.d/disable-i2c-hid-acpi.conf 2>/dev/null || true
rm -f /etc/modprobe.d/elan1200.conf 2>/dev/null || true
echo "  Removed conflicting configuration files"

# 6. Update module dependencies
echo ""
echo "6. Updating module dependencies..."
depmod -a
echo "  Updated module dependencies"

# 7. Test the fix script
echo ""
echo "7. Testing fix script..."
/usr/local/bin/fix-i2c-hid-acpi.sh
echo "  Fix script test completed"

echo ""
echo "=== Installation complete ==="
echo ""
echo "Files created/modified:"
echo "  /etc/modules-load.d/elan-touchpad.conf"
echo "  /usr/local/bin/fix-i2c-hid-acpi.sh"
echo "  /etc/systemd/system/fix-elantouchpad.service"
echo "  /lib/systemd/system-sleep/touchpad-fix"
echo "  /var/log/i2c-hid-fix.log (will be created on first run)"
echo ""
echo "Next steps:"
echo "  1. Reboot: sudo reboot"
echo "  2. After reboot, test touchpad works"
echo "  3. Test suspend/resume: systemctl suspend"
echo "  4. Check logs if issues: tail -f /var/log/i2c-hid-fix.log"
echo ""
echo "Verification commands:"
echo "  ls -la /sys/bus/i2c/devices/i2c-ELAN1200:00/driver"
echo "  xinput list | grep -i touchpad"
echo "  find /sys/class/input -name 'event*' -exec cat {}/device/name \\; 2>/dev/null | grep -i elan"
echo ""
echo "Documentation: See ASUS-ROG-ELAN1200-Touchpad-Fix.md"
echo ""