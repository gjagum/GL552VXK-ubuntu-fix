#!/bin/bash
# Apply audio fixes for ASUS ROG GL552VXK distortion

set -e

echo "=========================================="
echo "ASUS ROG GL552VXK Audio Fix Application"
echo "=========================================="
echo ""
echo "This script will apply fixes for audio distortion/crackling."
echo ""

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root or with sudo"
    exit 1
fi

# Backup existing configs
BACKUP_DIR="/root/backup-audio-fix-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
echo "Backup directory: $BACKUP_DIR"

# 1. Driver configuration
echo ""
echo "1. Configuring audio drivers..."
DRIVER_CONF="/etc/modprobe.d/alsa-cx20751.conf"
if [ -f "$DRIVER_CONF" ]; then
    cp "$DRIVER_CONF" "$BACKUP_DIR/alsa-cx20751.conf.backup"
    echo "Backed up existing config"
fi

cat > "$DRIVER_CONF" << 'EOF'
# Fix for Conexant CX20751/2 audio distortion on ASUS ROG GL552VXK
options snd-hda-intel power_save=0 power_save_controller=N position_fix=1 probe_mask=1
options snd-hda-codec-conexant model=auto
EOF
echo "Created $DRIVER_CONF"

# 2. PipeWire configuration
echo ""
echo "2. Configuring PipeWire..."
PW_CONF_DIR="/etc/pipewire/pipewire.conf.d"
mkdir -p "$PW_CONF_DIR"
PW_CONF="$PW_CONF_DIR/10-audio-fix.conf"
if [ -f "$PW_CONF" ]; then
    cp "$PW_CONF" "$BACKUP_DIR/10-audio-fix.conf.backup"
    echo "Backed up existing PipeWire config"
fi

cat > "$PW_CONF" << 'EOF'
# Audio quality fix for distortion
context.properties = {
    default.clock.quantum = 2048
    default.clock.min-quantum = 1024
    default.clock.max-quantum = 8192
    default.clock.quantum-limit = 16384
    default.clock.rate = 48000
    default.clock.allowed-rates = [ 48000 ]
}
EOF
echo "Created $PW_CONF"

# 3. Current volume settings
echo ""
echo "3. Adjusting volume settings..."
# Enable speaker, disable headphone, set volumes
amixer -c 0 sset 'Speaker' on >/dev/null 2>&1 || true
amixer -c 0 sset 'Headphone' off >/dev/null 2>&1 || true
amixer -c 0 sset 'Master' 90% >/dev/null 2>&1 || true
amixer -c 0 sset 'Speaker' 90% >/dev/null 2>&1 || true
amixer -c 0 sset 'Auto-Mute Mode' Disabled >/dev/null 2>&1 || true
echo "Volume settings adjusted"

# 4. Disable runtime power saving
echo ""
echo "4. Disabling runtime power saving..."
echo 0 > /sys/module/snd_hda_intel/parameters/power_save 2>/dev/null || true
echo N > /sys/module/snd_hda_intel/parameters/power_save_controller 2>/dev/null || true
echo "Power saving disabled (runtime)"

echo ""
echo "=========================================="
echo "Fixes Applied"
echo "=========================================="
echo ""
echo "Changes made:"
echo "1. Driver config: $DRIVER_CONF"
echo "2. PipeWire config: $PW_CONF"
echo "3. Volume settings adjusted"
echo "4. Runtime power saving disabled"
echo ""
echo "Backup created in: $BACKUP_DIR"
echo ""
echo "IMPORTANT:"
echo "1. For full effect, REBOOT is required"
echo "2. After reboot, run test-audio.sh to verify improvement"
echo "3. See AUDIO-FIX.md for troubleshooting"
echo ""
echo "To revert changes:"
echo "sudo rm $DRIVER_CONF $PW_CONF"
echo "sudo systemctl --user restart pipewire pipewire-pulse wireplumber"
echo "sudo rmmod snd_hda_codec_conexant snd_hda_intel && sudo modprobe snd_hda_intel"
echo ""