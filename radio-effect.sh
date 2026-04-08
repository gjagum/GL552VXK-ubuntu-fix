#!/bin/bash
# Radio effect for ASUS ROG GL552VXK - LoFi, no bass, old radio sound
# Uses PipeWire filter-chain with LADSPA low-pass and high-pass filters

set -e

USER_ID=$(id -u)
RUNTIME_DIR="/run/user/$USER_ID"
export XDG_RUNTIME_DIR="$RUNTIME_DIR"
export DBUS_SESSION_BUS_ADDRESS="unix:path=$RUNTIME_DIR/bus"

# Module name
MODULE="libpipewire-module-filter-chain"
MODULE_ARGS=$(cat <<EOF
{
    "audio.channels": 2,
    "audio.position": [ "FL", "FR" ],
    "node.description": "Radio Effect (LoFi)",
    "media.name": "Radio Effect",
    "filter.graph": {
        "nodes": [
            {
                "name": "hpf",
                "type": "ladspa",
                "plugin": 1042,
                "label": "hpf",
                "control": {
                    "Cutoff Frequency (Hz)": 300.0
                }
            },
            {
                "name": "lpf",
                "type": "ladspa",
                "plugin": 1041,
                "label": "lpf",
                "control": {
                    "Cutoff Frequency (Hz)": 3000.0
                }
            }
        ],
        "links": [
            { "output": "hpf:Output", "input": "lpf:Input" }
        ],
        "inputs": [ "hpf:Input" ],
        "outputs": [ "lpf:Output" ]
    },
    "capture.props": {
        "node.name": "radio_effect_input",
        "media.class": "Audio/Sink",
        "node.passive": true
    },
    "playback.props": {
        "node.name": "radio_effect_output",
        "media.class": "Audio/Source/Virtual",
        "node.passive": true
    }
}
EOF
)

# Check if pw-cli is available
if ! command -v pw-cli &> /dev/null; then
    echo "Error: pw-cli not found"
    exit 1
fi

# Check if wpctl is available
if ! command -v wpctl &> /dev/null; then
    echo "Error: wpctl not found"
    exit 1
fi

case "$1" in
    start|enable|on)
        echo "Enabling radio effect..."
        # Load filter-chain module
        MODULE_ID=$(pw-cli load-module "$MODULE" "$MODULE_ARGS" 2>/dev/null | grep -o "[0-9]*" || true)
        if [ -z "$MODULE_ID" ]; then
            echo "Failed to load module. Maybe already loaded?"
            # Try to find existing module
            MODULE_ID=$(pw-cli ls 2>/dev/null | grep -B2 -A2 "description.*Radio Effect" | grep -o "id [0-9]*" | head -1 | awk '{print $2}' || true)
        fi
        
        if [ -n "$MODULE_ID" ]; then
            echo "Module loaded with ID: $MODULE_ID"
            # Wait a moment for node to appear
            sleep 1
            # Set radio effect as default sink
            wpctl set-default "$(wpctl status | grep -A5 "Sinks:" | grep "Radio Effect" | grep -o "[0-9]*\." | sed 's/\.//')" 2>/dev/null || true
            echo "Radio effect enabled. Audio will sound like old radio (300Hz-3000Hz bandpass)."
        else
            echo "Warning: Could not verify module load. You may need to restart PipeWire."
        fi
        ;;
    stop|disable|off)
        echo "Disabling radio effect..."
        # Find and unload module
        MODULE_ID=$(pw-cli ls 2>/dev/null | grep -B2 -A2 "description.*Radio Effect" | grep -o "id [0-9]*" | head -1 | awk '{print $2}' || true)
        if [ -n "$MODULE_ID" ]; then
            pw-cli unload-module "$MODULE_ID" 2>/dev/null || true
            echo "Module unloaded."
        else
            echo "Radio effect module not found."
        fi
        # Restore default sink to built-in audio
        DEFAULT_SINK=$(wpctl status | grep -A5 "Sinks:" | grep "Built-in Audio" | grep -o "[0-9]*\." | head -1 | sed 's/\.//')
        if [ -n "$DEFAULT_SINK" ]; then
            wpctl set-default "$DEFAULT_SINK" 2>/dev/null || true
            echo "Default sink restored to Built-in Audio."
        fi
        ;;
    status)
        echo "Radio effect status:"
        if pw-cli ls 2>/dev/null | grep -q "description.*Radio Effect"; then
            echo "  ACTIVE"
            wpctl status | grep -A2 -B2 "Radio Effect"
        else
            echo "  INACTIVE"
        fi
        ;;
    *)
        echo "Usage: $0 {start|stop|status}"
        echo ""
        echo "Commands:"
        echo "  start, enable, on   - Enable radio effect (bandpass 300Hz-3000Hz)"
        echo "  stop, disable, off  - Disable radio effect, restore normal audio"
        echo "  status              - Check if radio effect is active"
        echo ""
        echo "This effect reduces bass and treble to minimize speaker vibration"
        echo "and create old radio / lo-fi sound quality."
        exit 1
        ;;
esac