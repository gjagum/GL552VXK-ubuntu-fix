# ASUS ROG Suspend Fix Guide
## Ubuntu Linux Suspend/Hibernate Fix for ASUS Laptops with NVIDIA/Intel Dual Graphics

**Laptop Model:** ASUS ROG with NVIDIA GTX 950M + Intel Integrated Graphics  
**Issue:** Suspend not working properly (immediate wakeups, CPU/fan remain running, system hangs)  
**Tested on:** Ubuntu 24.04 LTS with kernel 6.17.0-12-generic  
**Date:** February 7, 2026

---

## Problem Description

ASUS ROG laptops with NVIDIA Optimus (Intel + NVIDIA dual graphics) often have suspend issues on Linux:

1. **Immediate wakeups** - System wakes immediately after suspend
2. **Partial suspend** - Only display turns off, CPU/fan remain running
3. **System hangs** - System becomes unresponsive during suspend/resume
4. **Wake sources problems** - USB devices, PCIe ports cause unwanted wakeups

---

## Root Causes

1. **Incompatible sleep mode** - Default `s2idle` (shallow sleep) vs `deep` (S3) mode
2. **Wakeup sources enabled** - USB devices, PCIe ports can wake system
3. **ACPI/PCIe power management issues** - BIOS/ACPI compatibility problems
4. **NVIDIA driver conflicts** - Proprietary driver vs Nouveau open-source driver

---

## Complete Fix Solution

### 1. Update GRUB Configuration

Edit `/etc/default/grub` and update `GRUB_CMDLINE_LINUX_DEFAULT`:

```bash
# Backup current configuration
sudo cp /etc/default/grub /etc/default/grub.backup.$(date +%s)

# Edit GRUB configuration
sudo nano /etc/default/grub
```

Change this line:
```bash
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"
```

To:
```bash
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash acpi_osi=\"Windows 2020\" pcie_aspm=off pcie_port_pm=off nouveau.modeset=0 nvidia.NVreg_EnableS0ixPowerManagement=1 mem_sleep_default=deep"
```

**Parameter explanations:**
- `acpi_osi="Windows 2020"` - Better ACPI compatibility (pretends to be Windows 2020)
- `pcie_aspm=off pcie_port_pm=off` - Disable problematic PCIe Active State Power Management
- `nouveau.modeset=0` - Disable open-source NVIDIA driver (conflicts with proprietary driver)
- `nvidia.NVreg_EnableS0ixPowerManagement=1` - Enable NVIDIA power management
- `mem_sleep_default=deep` - Use deep sleep (S3) instead of s2idle

Update GRUB and reboot:
```bash
sudo update-grub
sudo reboot
```

### 2. Wakeup Sources Configuration Script

Create `/usr/local/bin/configure-wakeup`:

```bash
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

# Disable all USB wakeup (prevents wireless dongles, webcams from waking system)
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

# Disable PCI wakeup via sysfs (complementary to /proc/acpi/wakeup)
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
```

Make executable:
```bash
sudo chmod +x /usr/local/bin/configure-wakeup
```

### 3. Systemd Service for Automatic Configuration

Create `/etc/systemd/system/configure-wakeup.service`:

```bash
[Unit]
Description=Configure wakeup sources for deep sleep
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/configure-wakeup
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

Enable and start the service:
```bash
sudo systemctl daemon-reload
sudo systemctl enable configure-wakeup.service
sudo systemctl start configure-wakeup.service
```

### 4. Verify Configuration

Check current sleep mode:
```bash
cat /sys/power/mem_sleep
# Should show: s2idle [deep] or [s2idle] deep
```

Check wakeup sources:
```bash
# Check ACPI wakeup sources
cat /proc/acpi/wakeup

# Check power button and lid wakeup
cat /sys/bus/acpi/devices/PNP0C0C:00/power/wakeup
cat /sys/bus/acpi/devices/PNP0C0D:00/power/wakeup

# Check USB wakeup sources
cat /sys/bus/usb/devices/*/power/wakeup
```

Test suspend:
```bash
systemctl suspend
```

### 5. Manual Testing Commands

Temporarily change sleep mode:
```bash
# Switch to deep sleep
echo deep | sudo tee /sys/power/mem_sleep

# Switch to s2idle (shallow sleep)
echo s2idle | sudo tee /sys/power/mem_sleep
```

Check suspend statistics:
```bash
cat /sys/power/suspend_stats/success
cat /sys/power/suspend_stats/fail
```

View suspend/resume logs:
```bash
journalctl -b 0 | grep -i "suspend\|resume\|sleep"
sudo dmesg | grep -i "suspend\|resume\|s3\|deep"
```

---

## Alternative Solutions (If Above Doesn't Work)

### Option A: Different ACPI OSI Strings
Try different `acpi_osi` values in GRUB:
- `acpi_osi=!` (disable all OSI strings)
- `acpi_osi='Windows 2015'`
- `acpi_osi='Windows 2012'`
- `acpi_osi='Windows 2009'`

### Option B: Additional NVIDIA Parameters
Add to GRUB if still having issues:
```bash
nvidia-drm.modeset=1 nvidia.NVreg_PreserveVideoMemoryAllocations=1
```

### Option C: Disable Wake on LAN
If Ethernet is waking system:
```bash
sudo ethtool -s enp4s0f1 wol d
```

### Option D: Check for Specific Wake Sources
Find what's waking the system:
```bash
# Check last wakeup interrupt
cat /sys/power/pm_wakeup_irq

# Find all enabled wakeup sources
find /sys/devices -name wakeup -type f -exec grep -l enabled {} \;
```

---

## Troubleshooting

### Problem: System hangs during suspend
**Solution:** Try switching to `s2idle` mode temporarily:
```bash
echo s2idle | sudo tee /sys/power/mem_sleep
```

### Problem: Can't wake with keyboard/mouse
**Solution:** Re-enable USB wakeup for specific device:
```bash
# Find USB device path
ls /sys/bus/usb/devices/*/product

# Enable wakeup for that device
echo enabled | sudo tee /sys/bus/usb/devices/<device-path>/power/wakeup
```

### Problem: Immediate wakeups persist
**Solution:** Check for newly connected USB devices or check kernel logs:
```bash
sudo dmesg | grep -i "wake\|pcie\|error"
journalctl -b 0 | grep -i "suspend\|wake"
```

### Problem: Deep sleep not available
**Solution:** Check if BIOS supports S3 sleep:
```bash
dmesg | grep -i "S3\|suspend"
```

---

## Files Modified/Created

### Configuration Files
1. `/etc/default/grub` - GRUB boot parameters
2. `/usr/local/bin/configure-wakeup` - Wakeup configuration script
3. `/etc/systemd/system/configure-wakeup.service` - Systemd service

### System Files (Read-Only)
1. `/sys/power/mem_sleep` - Current sleep mode
2. `/proc/acpi/wakeup` - ACPI wakeup sources
3. `/sys/bus/acpi/devices/*/power/wakeup` - Device wakeup controls
4. `/sys/bus/usb/devices/*/power/wakeup` - USB wakeup controls

---

## Verification Commands

After applying all fixes, verify with:

```bash
# 1. Check kernel parameters
cat /proc/cmdline | grep -o "acpi_osi.*\|pcie.*\|nvidia.*\|mem_sleep.*"

# 2. Check sleep mode
cat /sys/power/mem_sleep

# 3. Check wakeup sources (should only have power button/lid enabled)
grep "*enabled" /proc/acpi/wakeup

# 4. Test suspend
systemctl suspend
# Wait 5 seconds, press power button to wake
# Check if CPU/fan stopped during suspend
```

---

## Important Notes

1. **Deep sleep vs s2idle**: 
   - `deep` (S3): CPU stops, maximum power savings, slower resume
   - `s2idle`: CPU in low-power state, faster resume, less power savings

2. **Wakeup sources**: Only power button and lid are enabled. USB keyboard/mouse won't wake system.

3. **NVIDIA driver**: Must use proprietary NVIDIA driver, not Nouveau.

4. **BIOS settings**: Ensure "Deep Sleep" or "S3" is enabled in BIOS if available.

5. **Kernel updates**: Re-apply GRUB changes after kernel updates.

---

## Reverting Changes

To revert to original configuration:

```bash
# 1. Restore original GRUB configuration
sudo cp /etc/default/grub.backup* /etc/default/grub
sudo update-grub

# 2. Disable and remove systemd service
sudo systemctl disable configure-wakeup.service
sudo systemctl stop configure-wakeup.service
sudo rm /etc/systemd/system/configure-wakeup.service
sudo systemctl daemon-reload

# 3. Remove scripts
sudo rm /usr/local/bin/configure-wakeup
```

---

## References

1. [Linux Kernel Documentation - Power Management](https://www.kernel.org/doc/html/latest/admin-guide/pm/sleep-states.html)
2. [Arch Linux Wiki - Suspend and Hibernate](https://wiki.archlinux.org/title/Power_management/Suspend_and_hibernate)
3. [NVIDIA Driver README](https://us.download.nvidia.com/XFree86/Linux-x86_64/525.60.11/README/powermanagement.html)
4. [ASUS Linux Support](https://www.asus.com/support/FAQ/1045143/)

---

## Support

If issues persist:
1. Check kernel logs: `sudo dmesg | grep -i "error\|warn\|fail"`
2. Check system logs: `journalctl -b 0 | tail -100`
3. Update BIOS to latest version
4. Try different kernel versions

**Last Updated:** February 7, 2026  
**Tested Configuration:** Ubuntu 24.04, Kernel 6.17.0-12, NVIDIA Driver 525.60.11