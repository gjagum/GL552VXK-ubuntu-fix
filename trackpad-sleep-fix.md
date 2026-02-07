# ELAN1200 Trackpad Not Working - Fix

## Problem
ELAN1200 touchpad (04F3:3045) doesn't work on Linux - not detected by system.

## Root Cause
The `i2c_hid_acpi` driver required for ELAN1200 was not loaded. ELAN1200 uses the HID protocol with `PNP0C50` ACPI ID and should be handled by the generic `i2c_hid_acpi` driver, not the `elan_i2c` driver (which only supports ELAN0000, ELAN0100, ELAN06xx, and ELAN1000 models).

## Investigation Findings
- Touchpad model: ELAN1200:00 04F3:3045
- Required driver: i2c_hid_acpi (HID over I2C driver)
- Device ACPI ID: PNP0C50
- Incorrect assumption: Original troubleshooting assumed elan_i2c was needed
- Actual issue: Driver simply not loaded

## Permanent Fix

### Step 1: Load the driver
```bash
pkexec modprobe i2c_hid_acpi
```

### Step 2: Configure driver to load at boot
```bash
echo "i2c_hid_acpi" | pkexec tee /etc/modules-load.d/elan-touchpad.conf
```

### Step 3: Verify
```bash
cat /proc/bus/input/devices | grep ELAN
```

Should show both Mouse and Touchpad devices.

## Verification

### Check if driver is loaded
```bash
lsmod | grep i2c_hid
```

Should show: `i2c_hid_acpi` in the list.

### Check device binding
```bash
ls -la /sys/bus/i2c/drivers/i2c_hid_acpi/ | grep ELAN
```

Should show: `i2c-ELAN1200:00`

### Check input devices
```bash
cat /proc/bus/input/devices | grep -A 10 "ELAN1200:00 04F3:3045 Touchpad"
```

### Check module auto-load config
```bash
cat /etc/modules-load.d/elan-touchpad.conf
```

Should show: `i2c_hid_acpi`

## Notes

### Wayland vs X11
When running on Wayland, `xinput` will show a warning and may not list the touchpad. This is normal behavior - the touchpad still works through libinput. Use `libinput list-devices` to verify.

### Sleep/Wake
The `i2c_hid_acpi` driver properly handles sleep/resume cycles. No additional hooks or services are needed for sleep/wake functionality.

### Model Compatibility
- ELAN0000, ELAN0100, ELAN06xx, ELAN1000: Uses `elan_i2c` driver
- ELAN1200: Uses `i2c_hid_acpi` driver

Check your model with:
```bash
cat /sys/bus/i2c/devices/i2c-ELAN*/name
```

## Troubleshooting

### If trackpad still doesn't work after loading driver
Check the kernel logs:
```bash
dmesg | grep -i "elan\|i2c_hid" | tail -20
```

### Manually reload driver
```bash
pkexec modprobe -r i2c_hid_acpi
pkexec modprobe i2c_hid_acpi
```

### Check which driver supports which devices
```bash
modinfo elan_i2c | grep "alias:" | grep ELAN
modinfo i2c_hid_acpi | grep "alias:"
```

### Check device modalias
```bash
cat /sys/bus/i2c/devices/i2c-ELAN1200:00/modalias
```

Your device should show: `acpi:ELAN1200:PNP0C50:`

## Files Created

### /etc/modules-load.d/elan-touchpad.conf
Contains module name `i2c_hid_acpi` to ensure driver loads at system boot.
