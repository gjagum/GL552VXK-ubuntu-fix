# ASUS ROG Suspend Fix for Ubuntu

This package contains everything needed to fix suspend issues on ASUS ROG laptops with NVIDIA/Intel dual graphics.

## Files Included

1. **asus-rog-suspend-fix.md** - Detailed documentation with all fixes and explanations
2. **fix-asus-suspend.sh** - Installation script to apply all fixes automatically
3. **README-SUSPEND-FIX.md** - This quick start guide

## Quick Installation

After fresh Ubuntu installation:

```bash
# 1. Make the script executable
chmod +x fix-asus-suspend.sh

# 2. Run as root (requires sudo password)
sudo ./fix-asus-suspend.sh

# 3. REBOOT (required for GRUB changes to take effect)
sudo reboot

# 4. After reboot, test suspend
sudo test-suspend
```

## What the Fix Does

The script applies three main fixes:

1. **GRUB Configuration** - Updates kernel parameters for better ACPI compatibility
2. **Wakeup Sources** - Configures which devices can wake the system (only power button/lid)
3. **Systemd Service** - Automatically applies wakeup settings on every boot

## Manual Installation (If Script Doesn't Work)

If the automatic script fails, refer to the detailed documentation:
```bash
# View detailed instructions
cat asus-rog-suspend-fix.md
```

Key files to check/update manually:
- `/etc/default/grub` - Kernel parameters
- `/usr/local/bin/configure-wakeup` - Wakeup configuration script
- `/etc/systemd/system/configure-wakeup.service` - Systemd service

## Testing

After installation and reboot:

1. **Quick test**: `sudo test-suspend`
2. **Manual test**: `systemctl suspend`
3. **Verify**: Check if CPU/fan stop during suspend

## Troubleshooting

If suspend still doesn't work:

1. **Check logs**: `journalctl -b 0 | grep -i "suspend\|resume\|error"`
2. **Check wakeup sources**: `cat /proc/acpi/wakeup`
3. **Try different sleep mode**: 
   ```bash
   # Temporary switch to s2idle
   echo s2idle | sudo tee /sys/power/mem_sleep
   systemctl suspend
   ```

## Support

For issues or questions:
1. Check the detailed documentation: `asus-rog-suspend-fix.md`
2. Look for error messages in system logs
3. Ensure you're using proprietary NVIDIA drivers, not Nouveau

## Reverting Changes

To remove the fix:
```bash
# Run these commands in order
sudo systemctl disable configure-wakeup.service
sudo systemctl stop configure-wakeup.service
sudo rm /etc/systemd/system/configure-wakeup.service
sudo rm /usr/local/bin/configure-wakeup
sudo rm /usr/local/bin/test-suspend
sudo systemctl daemon-reload

# Restore original GRUB from backup (check backup directory)
# Then run: sudo update-grub
# Finally: sudo reboot
```

---

**Important**: Always backup your system before making kernel/GRUB changes.

**Last Updated**: February 7, 2026  
**Tested On**: Ubuntu 24.04, Kernel 6.17.0-12, ASUS ROG with NVIDIA GTX 950M