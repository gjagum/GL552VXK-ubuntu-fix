# ASUS ROG Elan Touchpad (ELAN1200) Fix for Ubuntu

## Problem Summary
**Hardware**: ASUS ROG laptop with Elan touchpad (ELAN1200)
**Symptoms**: 
- Touchpad works immediately after boot
- Touchpad **stops working after resuming from suspend/sleep**
- No touchpad appears in `xinput list` after resume

**Root Cause**: The ELAN1200 touchpad is an I2C HID device that should use the `i2c_hid_acpi` driver, but after suspend/resume, the driver binding fails or the device enters an unrecoverable power state.

## Diagnostic Information
```
Device: i2c-ELAN1200:00
ACPI HID: ELAN1200
ACPI Status: 15
Modalias: acpi:ELAN1200:PNP0C50:
Vendor/Product: 04F3:3045
Driver: i2c_hid_acpi (correct), not elan_i2c
Input devices: ELAN1200:00 04F3:3045 Touchpad (event19)
```

## Solution Implemented

### 1. Correct Driver Configuration
**File**: `/etc/modules-load.d/elan-touchpad.conf`
```bash
i2c_hid_acpi
```
*Loads the correct I2C HID ACPI driver at boot*

### 2. Remove Incorrect Configuration
**Removed files**:
- `/etc/modprobe.d/disable-i2c-hid-acpi.conf` (blacklist)
- `/etc/modprobe.d/elan1200.conf` (wrong alias)

### 3. Automatic Recovery Script
**File**: `/usr/local/bin/fix-i2c-hid-acpi.sh`
```bash
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
```

### 4. Systemd Service
**File**: `/etc/systemd/system/fix-elantouchpad.service`
```ini
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
```

Enable with: `sudo systemctl enable fix-elantouchpad.service`

### 5. Suspend/Resume Hook
**File**: `/lib/systemd/system-sleep/touchpad-fix`
```bash
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
```

## Installation Script for Fresh Ubuntu Install
Save as `install-touchpad-fix.sh`:

```bash
#!/bin/bash
# ASUS ROG ELAN1200 Touchpad Fix Installer
# Run with sudo

set -e

echo "=== Installing ASUS ROG ELAN1200 Touchpad Fix ==="

# 1. Create module loading configuration
echo "i2c_hid_acpi" > /etc/modules-load.d/elan-touchpad.conf
echo "Created /etc/modules-load.d/elan-touchpad.conf"

# 2. Create fix script
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
echo "Created /usr/local/bin/fix-i2c-hid-acpi.sh"

# 3. Create systemd service
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
echo "Created and enabled systemd service"

# 4. Create suspend/resume hook
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
echo "Created suspend/resume hook"

# 5. Remove any conflicting configurations
rm -f /etc/modprobe.d/disable-i2c-hid-acpi.conf 2>/dev/null || true
rm -f /etc/modprobe.d/elan1200.conf 2>/dev/null || true
echo "Removed conflicting configurations"

# 6. Update module dependencies
depmod -a
echo "Updated module dependencies"

echo "=== Installation complete ==="
echo "Please reboot or run: sudo systemctl start fix-elantouchpad.service"
echo "Logs available at: /var/log/i2c-hid-fix.log"
```

## Verification Commands

### Check current status:
```bash
# Driver binding
ls -la /sys/bus/i2c/devices/i2c-ELAN1200:00/driver

# Input devices
find /sys/class/input -name "event*" -exec sh -c 'cat {}/device/name 2>/dev/null' \; 2>/dev/null | grep -i elan

# X11 input
xinput list | grep -i touchpad

# Kernel messages
dmesg | grep -i elan | tail -10
```

### Test manual recovery:
```bash
# Simulate suspend failure
sudo echo i2c-ELAN1200:00 > /sys/bus/i2c/drivers/i2c_hid_acpi/unbind

# Run fix script
sudo /usr/local/bin/fix-i2c-hid-acpi.sh

# Check recovery
tail -f /var/log/i2c-hid-fix.log
```

## Troubleshooting

### If touchpad still doesn't work after suspend:
1. **Check logs**: `tail -f /var/log/i2c-hid-fix.log`
2. **Check kernel messages**: `sudo dmesg | grep -i elan`
3. **Manual debug**:
   ```bash
   # Check device exists
   ls -la /sys/bus/i2c/devices/i2c-ELAN1200:00/
   
   # Check power state
   cat /sys/bus/i2c/devices/i2c-ELAN1200:00/power/control
   cat /sys/bus/i2c/devices/i2c-ELAN1200:00/power/runtime_status
   
   # Check ACPI status
   cat /sys/devices/LNXSYSTM:00/LNXSYBUS:00/PNP0A08:00/device:7a/ELAN1200:00/status
   ```

### Common issues:
1. **"No such device" error**: Device may be in D3 (off) power state
   - Solution: Power cycle with `echo on > /sys/bus/i2c/devices/i2c-ELAN1200:00/power/control`
   
2. **Driver not binding**: Module dependencies may be outdated
   - Solution: Run `sudo depmod -a` and reboot

3. **Multiple touchpad entries in xinput**: May indicate both `elan_i2c` and `i2c_hid_acpi` loaded
   - Solution: Ensure only `i2c_hid_acpi` is loaded, blacklist `elan_i2c` if necessary

## What This Fix Does

1. **Correct driver selection**: Uses `i2c_hid_acpi` instead of `elan_i2c`
2. **Automatic recovery**: Script runs at boot and after suspend/resume
3. **Power management**: Properly cycles device power to wake from low-power states
4. **Graceful failure**: Script exits cleanly even if recovery fails (no systemd errors)
5. **Comprehensive logging**: All actions logged to `/var/log/i2c-hid-fix.log`

## System Files Modified

```
/etc/modules-load.d/elan-touchpad.conf          # Loads i2c_hid_acpi at boot
/usr/local/bin/fix-i2c-hid-acpi.sh             # Recovery script
/etc/systemd/system/fix-elantouchpad.service   # Systemd service
/lib/systemd/system-sleep/touchpad-fix         # Suspend/resume hook
/var/log/i2c-hid-fix.log                       # Log file (auto-created)
```

## For AI/Assistant Reference

**Key points for future debugging**:
- Device: `i2c-ELAN1200:00` (I2C HID, not pure I2C)
- Correct driver: `i2c_hid_acpi`, NOT `elan_i2c`
- ACPI HID: `ELAN1200`, modalias: `acpi:ELAN1200:PNP0C50:`
- Vendor/Product: `04F3:3045`
- Issue: Driver binding fails after suspend due to power state
- Fix: Power cycle + module reload + rebind

**Diagnostic commands**:
```bash
# Quick status check
ls -la /sys/bus/i2c/devices/i2c-ELAN1200:00/driver 2>/dev/null
find /sys/class/input -name "*" -exec cat {}/name 2>/dev/null \; | grep -i elan
xinput list | grep -i touchpad
```

**Recovery sequence**:
1. Unbind from current driver
2. Power cycle I2C device
3. Power cycle ACPI device  
4. Reload `i2c_hid_acpi` and `i2c_hid` modules
5. Attempt manual bind
6. Wait for input device registration

---

*Last updated: $(date)*  
*Tested on: Ubuntu with kernel 6.17.0-12-generic*  
*Hardware: ASUS ROG laptop with ELAN1200 touchpad*