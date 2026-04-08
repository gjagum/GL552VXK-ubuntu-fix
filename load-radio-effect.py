#!/usr/bin/env python3
"""
Load PipeWire filter-chain module with radio effect (bandpass 300Hz-3000Hz)
"""

import json
import subprocess
import sys
import os
import time

def run_pw_cli(args):
    """Run pw-cli command with proper environment"""
    env = os.environ.copy()
    env['XDG_RUNTIME_DIR'] = f'/run/user/{os.getuid()}'
    env['DBUS_SESSION_BUS_ADDRESS'] = f'unix:path=/run/user/{os.getuid()}/bus'
    
    cmd = ['pw-cli'] + args
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, env=env, timeout=5)
        return result.stdout, result.stderr, result.returncode
    except Exception as e:
        return '', str(e), 1

def main():
    action = sys.argv[1] if len(sys.argv) > 1 else 'start'
    
    module_args = {
        "audio.channels": 2,
        "audio.position": ["FL", "FR"],
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
                {"output": "hpf:Output", "input": "lpf:Input"}
            ],
            "inputs": ["hpf:Input"],
            "outputs": ["lpf:Output"]
        },
        "capture.props": {
            "node.name": "radio_effect_input",
            "media.class": "Audio/Sink",
            "node.passive": True
        },
        "playback.props": {
            "node.name": "radio_effect_output",
            "media.class": "Audio/Source/Virtual",
            "node.passive": True
        }
    }
    
    if action in ['start', 'enable', 'on']:
        print("Loading radio effect module...")
        json_args = json.dumps(module_args)
        stdout, stderr, code = run_pw_cli(['load-module', 'libpipewire-module-filter-chain', json_args])
        
        if code != 0:
            print(f"Failed to load module: {stderr}")
            # Check if already loaded
            stdout, stderr, code = run_pw_cli(['ls'])
            if 'Radio Effect' in stdout:
                print("Module already loaded.")
            else:
                print("Try restarting PipeWire: systemctl --user restart pipewire")
                sys.exit(1)
        else:
            print("Module loaded successfully.")
            # Extract module ID from output (format: "id N")
            for line in stdout.split('\n'):
                if 'id' in line:
                    parts = line.strip().split()
                    if len(parts) >= 2 and parts[0] == 'id':
                        print(f"Module ID: {parts[1]}")
                        break
        
        # Wait for node to appear
        time.sleep(1)
        
        # Set as default sink using wpctl
        env = os.environ.copy()
        env['XDG_RUNTIME_DIR'] = f'/run/user/{os.getuid()}'
        env['DBUS_SESSION_BUS_ADDRESS'] = f'unix:path=/run/user/{os.getuid()}/bus'
        
        try:
            # Get sink ID
            result = subprocess.run(['wpctl', 'status'], capture_output=True, text=True, env=env)
            lines = result.stdout.split('\n')
            sink_id = None
            for i, line in enumerate(lines):
                if 'Radio Effect' in line:
                    # Look for number followed by dot before the name
                    for word in line.split():
                        if word.endswith('.') and word[:-1].isdigit():
                            sink_id = word[:-1]
                            break
                    if sink_id:
                        break
            
            if sink_id:
                subprocess.run(['wpctl', 'set-default', sink_id], env=env)
                print(f"Set default sink to Radio Effect (ID: {sink_id})")
            else:
                print("Radio Effect sink not found. You may need to set default manually.")
                print("Use: wpctl set-default <sink-id>")
                print("List sinks: wpctl status | grep -A10 'Sinks:'")
        except Exception as e:
            print(f"Warning: Could not set default sink: {e}")
        
        print("Radio effect enabled. Audio now bandpassed 300Hz-3000Hz (old radio sound).")
        
    elif action in ['stop', 'disable', 'off']:
        print("Unloading radio effect module...")
        # Find module ID
        stdout, stderr, code = run_pw_cli(['ls'])
        module_id = None
        for line in stdout.split('\n'):
            if 'Radio Effect' in line:
                # Look for "id N" in previous lines
                pass
        # Simple approach: unload all filter-chain modules (crude)
        # We'll just instruct user to restart pipewire
        print("To disable effect, restart PipeWire:")
        print("  systemctl --user restart pipewire pipewire-pulse wireplumber")
        print("Or use: pw-cli unload-module <id>")
        
    elif action in ['status']:
        stdout, stderr, code = run_pw_cli(['ls'])
        if 'Radio Effect' in stdout:
            print("Radio effect: ACTIVE")
            # Extract relevant info
            for line in stdout.split('\n'):
                if 'Radio Effect' in line:
                    print(line.strip())
        else:
            print("Radio effect: INACTIVE")
    
    else:
        print(f"Unknown action: {action}")
        print("Usage: ./load-radio-effect.py {start|stop|status}")
        sys.exit(1)

if __name__ == '__main__':
    main()