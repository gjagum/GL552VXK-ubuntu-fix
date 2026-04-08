#!/bin/bash
# Audio test script for ASUS ROG GL552VXK
# Tests for distortion/crackling after fixes

set -e

echo "=========================================="
echo "ASUS ROG GL552VXK Audio Test"
echo "=========================================="
echo ""
echo "This script will test audio output for distortion."
echo "Please listen carefully and note any crackling or buzzing."
echo ""

# Check if running as root (some commands need sudo)
if [ "$EUID" -ne 0 ]; then
    echo "Note: Some commands require sudo. Please enter password if prompted."
    echo ""
fi

echo "1. Checking current audio configuration..."
echo "------------------------------------------"
aplay -l 2>/dev/null || echo "aplay not available"
echo ""

echo "2. Checking driver parameters..."
echo "------------------------------------------"
if [ -f "/sys/module/snd_hda_intel/parameters/power_save" ]; then
    echo "power_save: $(cat /sys/module/snd_hda_intel/parameters/power_save)"
else
    echo "power_save file not found"
fi

if [ -f "/sys/module/snd_hda_intel/parameters/power_save_controller" ]; then
    echo "power_save_controller: $(cat /sys/module/snd_hda_intel/parameters/power_save_controller)"
else
    echo "power_save_controller file not found"
fi
echo ""

echo "3. Testing with sine waves..."
echo "------------------------------------------"
echo "You will hear a 440Hz tone for 5 seconds."
echo "Press Ctrl+C to skip any test."
echo ""

# Test frequencies
frequencies=(100 250 440 500 1000 2000 4000)
for freq in "${frequencies[@]}"; do
    read -p "Test $freq Hz? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Playing $freq Hz sine wave..."
        timeout 5 speaker-test -c 2 -l 1 -t sine -f $freq 2>/dev/null || \
            echo "speaker-test failed or interrupted"
        sleep 1
    fi
done

echo ""
echo "4. Testing with white noise..."
echo "------------------------------------------"
read -p "Test with white noise? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Playing white noise for 3 seconds..."
    timeout 3 speaker-test -c 2 -l 1 -t pink 2>/dev/null || \
        echo "speaker-test failed or interrupted"
fi

echo ""
echo "5. Checking mixer settings..."
echo "------------------------------------------"
amixer sget Master 2>/dev/null | grep -E "Playback|Mono" | head -2
amixer sget Speaker 2>/dev/null | grep -E "Playback|Front" | head -3
amixer sget 'Auto-Mute Mode' 2>/dev/null | grep "Item0"

echo ""
echo "=========================================="
echo "Test Complete"
echo "=========================================="
echo ""
echo "Results:"
echo "- Clean sound at all frequencies: ✓ Fix is working"
echo "- Distortion at specific frequencies: ✓ Possible hardware resonance"
echo "- Crackling throughout: ✗ Try additional fixes"
echo "- No sound: ✗ Check volume/mute settings"
echo ""
echo "Next steps:"
echo "1. Reboot to apply all configuration changes"
echo "2. Test with real audio (music, videos)"
echo "3. See AUDIO-FIX.md for more troubleshooting"
echo ""