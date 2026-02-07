# ASUS ROG GL552VXK Ubuntu Fix

Comprehensive fix for ASUS ROG GL552VXK laptop running Ubuntu Linux, addressing:
1. **ELAN1200 Touchpad** - Touchpad stops working after suspend/resume
2. **Suspend Issues** - System doesn't enter deep sleep, immediate wakeups, CPU/fan remain running

## Hardware & Software Environment
- **Laptop Model**: ASUS ROG GL552VXK
- **Graphics**: NVIDIA GTX 950M + Intel HD Graphics 630 (Optimus)
- **Touchpad**: ELAN1200 (04F3:3045) I2C HID device
- **Tested On**: Ubuntu 25.10, Kernel 6.17.0-12-generic
- **Date**: February 7, 2026

---

## 1. ELAN1200 Touchpad Fix

### Problem
Touchpad works after boot but stops working after resuming from suspend/sleep. No touchpad appears in `xinput list` after resume.

### Root Cause
ELAN1200 touchpad is an I2C HID device that should use the `i2c_hid_acpi` driver. After suspend/resume, driver binding fails or device enters unrecoverable power state.

### Solution
Automatic recovery system that:
1. Loads correct driver (`i2c_hid_acpi`) at boot
2. Power cycles device after resume
3. Reloads driver modules if needed
4. Comprehensive logging for troubleshooting

### Installation
Run the automated installer:
```bash
sudo bash install-asus-rog-touchpad-fix.sh
```

**Files Created:**
- `/etc/modules-load.d/elan-touchpad.conf` - Loads `i2c_hid_acpi` at boot
- `/usr/local/bin/fix-i2c-hid-acpi.sh` - Recovery script
- `/etc/systemd/system/fix-elantouchpad.service` - Systemd service
- `/lib/systemd/system-sleep/touchpad-fix` - Suspend/resume hook
- `/var/log/i2c-hid-fix.log` - Log file (auto-created)

### Verification
```bash
# Check driver binding
ls -la /sys/bus/i2c/devices/i2c-ELAN1200:00/driver

# Check input devices
find /sys/class/input -name 'event*' -exec cat {}/device/name \; 2>/dev/null | grep -i elan

# Check X11 input
xinput list | grep -i touchpad

# Check logs
tail -f /var/log/i2c-hid-fix.log
```

### Manual Recovery (If Needed)
```bash
sudo /usr/local/bin/fix-i2c-hid-acpi.sh
```

---

## 2. Suspend/Hibernate Fix

### Problem
- Immediate wakeups after suspend
- Only display turns off, CPU/fan remain running
- System hangs during suspend/resume
- Unwanted wakeups from USB/PCIe devices

### Root Causes
1. Incompatible sleep mode (default `s2idle` vs `deep` S3)
2. Wakeup sources enabled (USB devices, PCIe ports)
3. ACPI/PCIe power management issues
4. NVIDIA driver conflicts

### Solution
1. **GRUB Configuration** - Optimized kernel parameters for ACPI compatibility
2. **Wakeup Sources Management** - Enable only power button/lid wakeup
3. **Systemd Service** - Automatic wakeup configuration on boot

### Installation
Run the automated installer:
```bash
sudo bash fix-asus-suspend.sh
```

**GRUB Parameters Added:**
- `acpi_osi="Windows 2020"` - Better ACPI compatibility
- `pcie_aspm=off pcie_port_pm=off` - Disable problematic PCIe power management
- `nouveau.modeset=0` - Disable open-source NVIDIA driver
- `nvidia.NVreg_EnableS0ixPowerManagement=1` - Enable NVIDIA power management
- `mem_sleep_default=deep` - Use deep sleep (S3) instead of s2idle

**Files Created:**
- `/usr/local/bin/configure-wakeup` - Wakeup configuration script
- `/etc/systemd/system/configure-wakeup.service` - Systemd service
- `/usr/local/bin/test-suspend` - Test script
- Backup in `/root/backup-suspend-fix-*/`

### Verification
```bash
# Check kernel parameters
cat /proc/cmdline | grep -o "acpi_osi[^ ]*\|pcie[^ ]*\|nvidia[^ ]*\|mem_sleep[^ ]*"

# Check sleep mode
cat /sys/power/mem_sleep  # Should show: s2idle [deep]

# Check wakeup sources (should only have power button/lid enabled)
grep "*enabled" /proc/acpi/wakeup

# Test suspend
sudo test-suspend
```

### Testing
```bash
# Quick test
systemctl suspend

# Wait 5 seconds, press power button to wake
# Verify CPU/fan stopped during suspend
```

---

## Complete Installation Sequence

For fresh Ubuntu installation:

1. **Install Ubuntu** with proprietary NVIDIA drivers
2. **Apply Touchpad Fix**
   ```bash
   sudo bash install-asus-rog-touchpad-fix.sh
   ```
3. **Apply Suspend Fix**
   ```bash
   sudo bash fix-asus-suspend.sh
   ```
4. **Reboot**
   ```bash
   sudo reboot
   ```
5. **Verify Both Fixes**
   ```bash
   # Touchpad check
   xinput list | grep -i touchpad
   
   # Suspend check
   sudo test-suspend
   ```

---

## Troubleshooting

### Touchpad Still Not Working After Suspend
1. Check logs: `tail -f /var/log/i2c-hid-fix.log`
2. Check kernel messages: `sudo dmesg | grep -i elan`
3. Manual debug:
   ```bash
   # Check device exists
   ls -la /sys/bus/i2c/devices/i2c-ELAN1200:00/
   
   # Check power state
   cat /sys/bus/i2c/devices/i2c-ELAN1200:00/power/control
   cat /sys/bus/i2c/devices/i2c-ELAN1200:00/power/runtime_status
   
   # Check ACPI status
   cat /sys/devices/LNXSYSTM:00/LNXSYBUS:00/PNP0A08:00/device:7a/ELAN1200:00/status
   ```

### Suspend Still Not Working
1. Check logs: `journalctl -b 0 | grep -i "suspend\|resume\|error"`
2. Check wakeup sources: `cat /proc/acpi/wakeup`
3. Try different sleep mode temporarily:
   ```bash
   echo s2idle | sudo tee /sys/power/mem_sleep
   systemctl suspend
   ```
4. Ensure NVIDIA proprietary driver is installed (not Nouveau):
   ```bash
   ubuntu-drivers devices
   sudo ubuntu-drivers autoinstall
   sudo reboot
   ```

### Common Issues
1. **"No such device" error** - Device may be in D3 (off) power state
   - Solution: Power cycle with `echo on > /sys/bus/i2c/devices/i2c-ELAN1200:00/power/control`
2. **Driver not binding** - Module dependencies outdated
   - Solution: Run `sudo depmod -a` and reboot
3. **Multiple touchpad entries in xinput** - Both `elan_i2c` and `i2c_hid_acpi` loaded
   - Solution: Ensure only `i2c_hid_acpi` is loaded, blacklist `elan_i2c` if needed
4. **Deep sleep not available** - BIOS may not support S3
   - Check: `dmesg | grep -i "S3\|suspend"`

---

## Reverting Changes

### Touchpad Fix
```bash
sudo systemctl disable fix-elantouchpad.service
sudo systemctl stop fix-elantouchpad.service
sudo rm /etc/systemd/system/fix-elantouchpad.service
sudo rm /usr/local/bin/fix-i2c-hid-acpi.sh
sudo rm /lib/systemd/system-sleep/touchpad-fix
sudo rm /etc/modules-load.d/elan-touchpad.conf
sudo systemctl daemon-reload
```

### Suspend Fix
```bash
# 1. Disable service
sudo systemctl disable configure-wakeup.service
sudo systemctl stop configure-wakeup.service

# 2. Remove files
sudo rm /etc/systemd/system/configure-wakeup.service
sudo rm /usr/local/bin/configure-wakeup
sudo rm /usr/local/bin/test-suspend
sudo systemctl daemon-reload

# 3. Restore GRUB from backup (check /root/backup-suspend-fix-*)
# 4. Update GRUB and reboot
sudo update-grub
sudo reboot
```

---

## Technical Details

### Touchpad Device Information
- **Device**: `i2c-ELAN1200:00` (I2C HID, not pure I2C)
- **Correct Driver**: `i2c_hid_acpi`, NOT `elan_i2c`
- **ACPI HID**: `ELAN1200`, modalias: `acpi:ELAN1200:PNP0C50:`
- **Vendor/Product**: `04F3:3045`

### Recovery Sequence (Touchpad)
1. Unbind from current driver
2. Power cycle I2C device
3. Power cycle ACPI device
4. Reload `i2c_hid_acpi` and `i2c_hid` modules
5. Attempt manual bind
6. Wait for input device registration

### Sleep Modes
- **`deep` (S3)**: CPU stops, maximum power savings, slower resume
- **`s2idle`**: CPU in low-power state, faster resume, less power savings

### Wakeup Sources
- **Enabled**: Power button (`PNP0C0C`), Lid (`PNP0C0D`)
- **Disabled**: All USB devices, PCIe ports, power supply, keyboard/mouse

---

## For AI/System Understanding

### Hardware/Software Configuration
- **Laptop Model**: ASUS ROG GL552VXK
- **CPU**: Intel Core i7 (7th generation)
- **Graphics**: NVIDIA GTX 950M (GM107M) + Intel HD Graphics 630 (Optimus)
- **Touchpad**: ELAN1200 (04F3:3045) I2C HID device
- **OS**: Ubuntu 25.10 (Codename: questing)
- **Kernel**: 6.17.0-12-generic
- **NVIDIA Driver**: 580.126.09
- **ACPI Compatibility**: Requires Windows 2020 emulation for proper suspend

### Problems Solved
1. **Touchpad After Suspend/Resume**
   - **Symptom**: Touchpad works after boot but stops after suspend/resume
   - **Root Cause**: ELAN1200 uses `i2c_hid_acpi` driver, not `elan_i2c`. After suspend, driver binding fails or device enters unrecoverable power state
   - **Device Path**: `/sys/bus/i2c/devices/i2c-ELAN1200:00/`
   - **ACPI Path**: `/sys/devices/LNXSYSTM:00/LNXSYBUS:00/PNP0A08:00/device:7a/ELAN1200:00/`

2. **Suspend/Hibernate Issues**
   - **Symptoms**: Immediate wakeups, CPU/fan remain running, system hangs
   - **Root Causes**: 
     - Wrong sleep mode (s2idle vs deep/S3)
     - Wakeup sources enabled (USB, PCIe ports)
     - ACPI/PCIe power management incompatibility
     - NVIDIA driver conflicts with Nouveau

### Solutions Implemented

#### Touchpad Fix Components:
1. **Driver Configuration**: `/etc/modules-load.d/elan-touchpad.conf` loads `i2c_hid_acpi` at boot
2. **Recovery Script**: `/usr/local/bin/fix-i2c-hid-acpi.sh` performs:
   - Device power cycling (`echo on > /sys/bus/i2c/devices/i2c-ELAN1200:00/power/control`)
   - Driver unbind/rebind
   - Module reload (`modprobe -r i2c_hid_acpi i2c_hid && modprobe i2c_hid i2c_hid_acpi`)
   - ACPI device power control
3. **Systemd Service**: `/etc/systemd/system/fix-elantouchpad.service` runs script at boot
4. **Suspend Hook**: `/lib/systemd/system-sleep/touchpad-fix` runs script after resume
5. **Logging**: `/var/log/i2c-hid-fix.log` records all recovery attempts

#### Suspend Fix Components:
1. **GRUB Configuration**: `/etc/default/grub` updated with:
   - `acpi_osi="Windows 2020"` (ACPI compatibility)
   - `pcie_aspm=off pcie_port_pm=off` (disable problematic PCIe power management)
   - `nouveau.modeset=0` (disable open-source NVIDIA driver)
   - `nvidia.NVreg_EnableS0ixPowerManagement=1` (enable NVIDIA power management)
   - `mem_sleep_default=deep` (use S3 sleep instead of s2idle)
2. **Wakeup Script**: `/usr/local/bin/configure-wakeup` configures:
   - Enable: Power button (`PNP0C0C`), Lid (`PNP0C0D`)
   - Disable: All USB devices, PCIe ports, power supply, keyboard/mouse
3. **Systemd Service**: `/etc/systemd/system/configure-wakeup.service` runs wakeup script at boot
4. **Test Script**: `/usr/local/bin/test-suspend` for verification

### Expected Outcomes
1. **Touchpad**: Works consistently after boot and suspend/resume cycles
2. **Suspend**: System enters deep sleep (S3), CPU/fan stop, only power button/lid can wake system
3. **Stability**: No immediate wakeups, no system hangs during suspend/resume

### Verification Commands
```bash
# Touchpad verification
ls -la /sys/bus/i2c/devices/i2c-ELAN1200:00/driver
find /sys/class/input -name 'event*' -exec cat {}/device/name \; 2>/dev/null | grep -i elan
xinput list | grep -i touchpad
tail -f /var/log/i2c-hid-fix.log

# Suspend verification
cat /proc/cmdline | grep -o "acpi_osi[^ ]*\|pcie[^ ]*\|nvidia[^ ]*\|mem_sleep[^ ]*"
cat /sys/power/mem_sleep
grep "*enabled" /proc/acpi/wakeup
sudo test-suspend
```

### Diagnostic Patterns for AI
- **Touchpad not detected**: Check `/sys/bus/i2c/devices/i2c-ELAN1200:00/power/control` and `/sys/bus/i2c/devices/i2c-ELAN1200:00/power/runtime_status`
- **Driver not bound**: Check `/sys/bus/i2c/devices/i2c-ELAN1200:00/driver` symlink
- **Immediate wakeups**: Check `/proc/acpi/wakeup` for enabled devices, disable all except `PNP0C0C` and `PNP0C0D`
- **Partial suspend**: Check sleep mode with `cat /sys/power/mem_sleep`, switch to `deep` if on `s2idle`
- **NVIDIA issues**: Ensure proprietary driver installed, not Nouveau: `lsmod | grep nouveau`

### Recovery Procedures
1. **Touchpad Recovery**: Run `/usr/local/bin/fix-i2c-hid-acpi.sh`
2. **Wakeup Reconfiguration**: Run `/usr/local/bin/configure-wakeup`
3. **Sleep Mode Switch**: `echo deep | sudo tee /sys/power/mem_sleep` (temporary) or update GRUB for permanent
4. **Driver Reload**: `sudo modprobe -r i2c_hid_acpi i2c_hid && sudo modprobe i2c_hid i2c_hid_acpi`

---

## Important Notes
1. **Deep sleep vs s2idle**: Use `deep` for maximum power savings; if issues, temporarily switch to `s2idle`
2. **Wakeup sources**: Only power button and lid are enabled. USB keyboard/mouse won't wake system.
3. **NVIDIA driver**: Must use proprietary NVIDIA driver, not Nouveau.
4. **BIOS settings**: Ensure "Deep Sleep" or "S3" is enabled in BIOS if available.
5. **Kernel updates**: Re-apply GRUB changes after kernel updates.

---

## References
- [Linux Kernel Documentation - Power Management](https://www.kernel.org/doc/html/latest/admin-guide/pm/sleep-states.html)
- [Arch Linux Wiki - Suspend and Hibernate](https://wiki.archlinux.org/title/Power_management/Suspend_and_hibernate)
- [NVIDIA Driver README - Power Management](https://us.download.nvidia.com/XFree86/Linux-x86_64/580.126.09/README/powermanagement.html)
- [ASUS Linux Support](https://www.asus.com/support/FAQ/1045143/)

---

## Support
If issues persist:
1. Check kernel logs: `sudo dmesg | grep -i "error\|warn\|fail"`
2. Check system logs: `journalctl -b 0 | tail -100`
3. Update BIOS to latest version
4. Try different kernel versions

**Last Updated**: February 7, 2026  
**Tested Configuration**: Ubuntu 25.10, Kernel 6.17.0-12, NVIDIA Driver 580.126.09

---

*This repository consolidates all fixes for ASUS ROG GL552VXK Ubuntu compatibility into a single comprehensive guide. Documentation is structured for AI/system understanding with clear problem definitions, root causes, solution components, and verification methods to enable automated re-application of fixes during system reinstallation.*