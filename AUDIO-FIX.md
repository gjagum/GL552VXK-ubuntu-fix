# ASUS ROG GL552VXK Audio Fix for Distortion/Crackling

## Problem
Audio output is distorted/crackling ("meh" quality). Possible causes:
1. Power saving causing buffer underruns
2. Incorrect driver parameters
3. Sample rate mismatches
4. Hardware issues (speaker damage)

## Applied Fixes

### 1. Driver Configuration
Created `/etc/modprobe.d/alsa-cx20751.conf`:
```
# Fix for Conexant CX20751/2 audio distortion on ASUS ROG GL552VXK
options snd-hda-intel power_save=0 power_save_controller=N position_fix=1 probe_mask=1
options snd-hda-codec-conexant model=auto
```

**Effects:**
- `power_save=0`: Disables audio power saving (common cause of crackling)
- `power_save_controller=N`: Disables controller power saving
- `position_fix=1`: Uses LPIB position fix (better buffer handling)
- `model=auto`: Auto-detects codec model

### 2. PipeWire Buffer Adjustment
Created `/etc/pipewire/pipewire.conf.d/10-audio-fix.conf`:
```
# Audio quality fix for distortion
context.properties = {
    default.clock.quantum = 2048
    default.clock.min-quantum = 1024
    default.clock.max-quantum = 8192
    default.clock.quantum-limit = 16384
    default.clock.rate = 48000
    default.clock.allowed-rates = [ 48000 ]
}
```

**Effects:**
- Increases buffer size from 1024 to 2048 frames (reduces underruns)
- Locks sample rate to 48kHz (prevents resampling artifacts)

### 3. Current Volume Settings
- Master volume: 90%
- Speaker volume: 90% (enabled)
- Headphone volume: 0% (disabled)
- Auto-Mute Mode: Disabled

## Testing Audio Quality

### Quick Test Commands:
```bash
# Test with sine wave (440Hz for 5 seconds)
speaker-test -c 2 -l 1 -t sine -f 440

# Test with different frequencies (listen for distortion)
for freq in 100 250 500 1000 2000 4000; do
    echo "Testing $freq Hz"
    speaker-test -c 2 -l 1 -t sine -f $freq
    sleep 2
done

# Play a test sound file (if available)
aplay /usr/share/sounds/alsa/Front_Center.wav 2>/dev/null || echo "Test sound not found"
```

### Using Sox for Comprehensive Test:
```bash
# Generate and play test tones
sox -n -r 48000 -b 16 -c 2 test_100hz.wav synth 3 sine 100
sox -n -r 48000 -b 16 -c 2 test_1khz.wav synth 3 sine 1000
sox -n -r 48000 -b 16 -c 2 test_sweep.wav synth 5 sine 100-3000

# Play them
aplay test_100hz.wav
aplay test_1khz.wav
aplay test_sweep.wav
```

## Verification Steps

1. **Check driver parameters:**
   ```bash
   cat /sys/module/snd_hda_intel/parameters/power_save
   cat /sys/module/snd_hda_intel/parameters/power_save_controller
   ```

2. **Check PipeWire settings:**
   ```bash
   pw-metadata | grep clock.quantum
   ```

3. **Check audio device info:**
   ```bash
   aplay -l
   cat /proc/asound/card0/codec#0 | head -20
   ```

## Revert Changes

If audio quality worsens or issues arise:

1. Remove driver config:
   ```bash
   sudo rm /etc/modprobe.d/alsa-cx20751.conf
   ```

2. Remove PipeWire config:
   ```bash
   sudo rm /etc/pipewire/pipewire.conf.d/10-audio-fix.conf
   ```

3. Reload drivers (or reboot):
   ```bash
   sudo rmmod snd_hda_codec_conexant snd_hda_intel
   sudo modprobe snd_hda_intel
   ```

4. Restore default PipeWire settings:
   ```bash
   sudo systemctl --user restart pipewire pipewire-pulse wireplumber
   ```

## Additional Troubleshooting

### If distortion persists:
1. **Test with headphones** - If headphones sound clean, issue may be with internal speakers (hardware)
2. **Check for physical damage** - Listen for rattling/buzzing at specific frequencies
3. **Try different audio output** - Test HDMI audio if available
4. **Check kernel logs**:
   ```bash
   sudo dmesg | grep -i "audio\|snd\|hda"
   ```

### Advanced fixes to try:
1. **Different position_fix values** (0=auto, 1=LPIB, 2=POSBUF, 3=VIACOMBO, 4=COMBO):
   ```bash
   echo "options snd-hda-intel position_fix=2" | sudo tee -a /etc/modprobe.d/alsa-cx20751.conf
   ```

2. **Adjust buffer sizes**:
   ```bash
   echo "options snd-hda-intel bdl_pos_adj=32" | sudo tee -a /etc/modprobe.d/alsa-cx20751.conf
   ```

3. **Try different model quirks**:
   ```bash
   echo "options snd-hda-intel model=generic" | sudo tee -a /etc/modprobe.d/alsa-cx20751.conf
   ```

## Hardware Considerations
- "Vibrate the keys" may indicate speaker vibration causing keyboard resonance
- If speakers are physically damaged, distortion may be permanent
- Consider using external speakers/headphones if hardware issue confirmed

## Next Steps
1. Reboot to apply all changes
2. Test audio with various content (music, videos, system sounds)
3. Report if distortion improves/worsens

**Note:** Changes require reboot to take full effect. Test after reboot.