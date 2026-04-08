# Radio / LoFi Audio Effect for ASUS ROG GL552VXK

## Goal
Reduce bass and treble to:
1. Minimize speaker vibration (causes keyboard rattling)
2. Create "old radio" / lo-fi sound quality
3. Prevent distortion at high volumes

## Already Applied Fixes
The following improvements have been applied to reduce audio distortion:

1. **Driver Configuration** (`/etc/modprobe.d/alsa-cx20751.conf`):
   - Disabled audio power saving (`power_save=0`)
   - Disabled controller power saving (`power_save_controller=N`)
   - Enabled LPIB position fix (`position_fix=1`)
   - Auto-detected codec model (`model=auto`)

2. **PipeWire Buffer Adjustment** (`/etc/pipewire/pipewire.conf.d/10-audio-fix.conf`):
   - Increased buffer size from 1024 to 2048 frames
   - Locked sample rate to 48kHz
   - Reduces buffer underruns (common cause of crackling)

3. **Volume Settings**:
   - Master volume: 90%
   - Speaker volume: 90% (enabled)
   - Headphone volume: 0% (disabled)
   - Auto-Mute Mode: Disabled

## Radio Effect Options

### Option 1: EasyEffects (Recommended)
EasyEffects is installed and provides GUI equalizer with presets.

**Steps:**
```bash
# Launch EasyEffects (GUI required)
easyeffects

# In EasyEffects:
# 1. Go to "Presets" → "Import Preset"
# 2. Use the following JSON preset (save as "Old Radio.json"):

{
  "input": {
    "blocklist": [],
    "plugins": [
      {
        "name": "equalizer",
        "state": true,
        "bypass": false,
        "freq0": 200.0,
        "gain0": -20.0,
        "q0": 1.0,
        "type0": "High-pass",
        "freq1": 3000.0,
        "gain1": -20.0,
        "q1": 1.0,
        "type1": "Low-pass"
      }
    ]
  },
  "output": {
    "blocklist": [],
    "plugins": []
  }
}

# 3. Load the preset
# 4. Enable "Output" effects
# 5. Adjust gains as needed
```

**Alternative Quick Setup:**
```bash
# Create preset directory
mkdir -p ~/.config/easyeffects/output/

# Create radio preset
cat > ~/.config/easyeffects/output/Old\ Radio.json << 'EOF'
{
  "input": {
    "blocklist": [],
    "plugins": [
      {
        "name": "equalizer",
        "state": true,
        "bypass": false,
        "freq0": 200.0,
        "gain0": -20.0,
        "q0": 1.0,
        "type0": "High-pass",
        "freq1": 3000.0,
        "gain1": -20.0,
        "q1": 1.0,
        "type1": "Low-pass"
      }
    ]
  },
  "output": {
    "blocklist": [],
    "plugins": []
  }
}
EOF

# Load preset via CLI (may need EasyEffects running)
easyeffects -l "Old Radio"
```

### Option 2: PulseAudio Equalizer (GUI)
PulseAudio equalizer is installed and works with PipeWire-Pulse.

**Steps:**
```bash
# Launch equalizer GUI
qpaeq

# In the equalizer window:
# 1. Reduce bands 0-4 (50Hz-311Hz) to -20dB
# 2. Reduce bands 11-14 (3500Hz-20000Hz) to -20dB
# 3. Keep mid bands (440Hz-2500Hz) near 0dB
# 4. Click "Apply"
```

**Auto-apply on startup:**
```bash
# Save settings in ~/.config/pulse/equalizer.preset
# The equalizer should remember settings
```

### Option 3: ALSA Equalizer Plugin (Advanced)
Uses ALSA's equal plugin (15-band equalizer).

**Setup:**
```bash
# Create ~/.asoundrc
cat > ~/.asoundrc << 'EOF'
ctl.equal {
    type equal;
}

pcm.plugequal {
    type equal;
    slave.pcm "plug:dmix";
}

pcm.equal {
    type plug;
    slave.pcm plugequal;
}

# Reduce bass (bands 0-4) and treble (bands 11-14)
# Band frequencies: 50,100,156,220,311,440,622,880,1250,1750,2500,3500,5000,10000,20000 Hz
ctl.equal.0 "-20"   # 50Hz
ctl.equal.1 "-20"   # 100Hz
ctl.equal.2 "-15"   # 156Hz
ctl.equal.3 "-10"   # 220Hz
ctl.equal.4 "-5"    # 311Hz
ctl.equal.5 "0"     # 440Hz
ctl.equal.6 "0"     # 622Hz
ctl.equal.7 "0"     # 880Hz
ctl.equal.8 "0"     # 1250Hz
ctl.equal.9 "0"     # 1750Hz
ctl.equal.10 "0"    # 2500Hz
ctl.equal.11 "-5"   # 3500Hz
ctl.equal.12 "-10"  # 5000Hz
ctl.equal.13 "-15"  # 10000Hz
ctl.equal.14 "-20"  # 20000Hz
EOF

# Test with aplay
aplay -D equal /usr/share/sounds/alsa/Front_Center.wav 2>/dev/null || echo "Test sound"
```

**Note:** PipeWire may not use this ALSA device automatically.

### Option 4: PipeWire Filter Chain (Experimental)
Scripts have been created but may need debugging.

**Files available:**
- `radio-effect.sh` - Bash script (may not work)
- `load-radio-effect.py` - Python script (may not work)
- `radio-effect-v2.py` - Updated version
- `radio-effect-eq.py` - Uses built-in biquad filters

**To try:**
```bash
# Make scripts executable
chmod +x radio-effect*.py radio-effect.sh

# Restart PipeWire first
systemctl --user restart pipewire pipewire-pulse wireplumber

# Try the biquad filter version (most promising)
./radio-effect-eq.py start

# Check if effect is active
./radio-effect-eq.py status

# If audio sounds filtered, success
# If not, check wpctl status for "Radio EQ" sink
```

**Debugging:**
```bash
# Check if module loaded
pw-cli ls | grep -i radio

# Check WirePlumber sinks
wpctl status | grep -A10 "Sinks"

# Unload if needed
./radio-effect-eq.py stop
```

## Testing the Effect

### Frequency Test
```bash
# Install sox if needed
sudo apt install sox

# Generate test tones
for freq in 50 100 200 500 1000 2000 4000 8000; do
    echo "Testing $freq Hz"
    play -n synth 3 sine $freq vol 0.5 2>/dev/null
    sleep 1
done
```

**Expected result:**
- 50-200Hz: Very quiet (bass reduced)
- 500-2000Hz: Normal volume (midrange preserved)
- 4000-8000Hz: Quieter (treble reduced)

### Vibration Test
Play low-frequency content (bass-heavy music) at moderate volume:
- Before effect: Keyboard/speaker vibration noticeable
- After effect: Vibration significantly reduced

## Reverting Changes

### Remove Driver Config
```bash
sudo rm /etc/modprobe.d/alsa-cx20751.conf
sudo rmmod snd_hda_codec_conexant snd_hda_intel
sudo modprobe snd_hda_intel
```

### Remove PipeWire Buffer Config
```bash
sudo rm /etc/pipewire/pipewire.conf.d/10-audio-fix.conf
systemctl --user restart pipewire pipewire-pulse wireplumber
```

### Unload Radio Effect
```bash
# For PipeWire filter chain
./radio-effect-eq.py stop

# For EasyEffects
easyeffects -q

# For PulseAudio equalizer
qpaeq (close window)
```

### Restore Default Sink
```bash
wpctl set-default $(wpctl status | grep "Built-in Audio Analog Stereo" | grep -o "[0-9]*\." | head -1 | sed 's/\.//')
```

## Hardware Considerations
If vibration persists after software fixes:
- **Test with headphones**: If vibration disappears, issue is with internal speakers
- **Physical damage**: Speakers may be damaged (rattling at specific frequencies)
- **External speakers**: Consider using USB/Bluetooth speakers if internal ones problematic

## Quick Start Recommendation
1. **For immediate effect**: Use EasyEffects GUI (`easyeffects`)
2. **For permanent solution**: Create EasyEffects preset and enable autostart
3. **For minimal setup**: Use PulseAudio equalizer (`qpaeq`)

## Support
If issues persist:
- Check kernel logs: `sudo dmesg | grep -i audio`
- Check PipeWire logs: `journalctl --user -u pipewire | tail -50`
- Verify driver parameters: `cat /sys/module/snd_hda_intel/parameters/power_save`

**Last Updated**: February 7, 2026  
**Tested on**: Ubuntu 25.10, Kernel 6.17.0-12, PipeWire 1.4.7