#!/usr/bin/env python3
"""
Radio effect using PipeWire built-in biquad filters (bq_lowshelf, bq_highshelf)
Reduces bass and treble for old radio sound
"""

import json
import subprocess
import sys
import os
import time

def run_pw_cli(args):
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
    
    # Using builtin biquad filters from sink-eq6.conf
    module_args = {
        "node.description": "Radio EQ (Bass/Treble Cut)",
        "media.name": "Radio EQ",
        "filter.graph": {
            "nodes": [
                {
                    "type": "builtin",
                    "name": "lowshelf",
                    "label": "bq_lowshelf",
                    "control": {
                        "Freq": 200.0,
                        "Q": 1.0,
                        "Gain": -20.0  # Cut bass by 20dB
                    }
                },
                {
                    "type": "builtin",
                    "name": "highshelf",
                    "label": "bq_highshelf",
                    "control": {
                        "Freq": 3000.0,
                        "Q": 1.0,
                        "Gain": -20.0  # Cut treble by 20dB
                    }
                }
            ],
            "links": [
                { "output": "lowshelf:Out", "input": "highshelf:In" }
            ],
            "inputs": [ "lowshelf:In" ],
            "outputs": [ "highshelf:Out" ]
        },
        "audio.channels": 2,
        "audio.position": [ "FL", "FR" ],
        "capture.props": {
            "node.name": "effect_input.radio_eq",
            "media.class": "Audio/Sink"
        },
        "playback.props": {
            "node.name": "effect_output.radio_eq",
            "node.passive": True
        }
    }
    
    if action in ['start', 'enable', 'on']:
        print("Loading radio EQ (biquad shelves)...")
        json_args = json.dumps(module_args)
        stdout, stderr, code = run_pw_cli(['load-module', 'libpipewire-module-filter-chain', json_args])
        
        if code != 0:
            print(f"Failed to load module: {stderr}")
            sys.exit(1)
        
        print("Module loaded.")
        # Extract module ID
        module_id = None
        for line in stdout.split('\n'):
            if line.strip().startswith('id'):
                parts = line.strip().split()
                if len(parts) >= 2:
                    module_id = parts[1]
                    break
        
        if module_id:
            print(f"Module ID: {module_id}")
            with open('/tmp/radio-eq-module.id', 'w') as f:
                f.write(module_id)
        
        time.sleep(2)
        
        # Try to set as default sink
        env = os.environ.copy()
        env['XDG_RUNTIME_DIR'] = f'/run/user/{os.getuid()}'
        env['DBUS_SESSION_BUS_ADDRESS'] = f'unix:path=/run/user/{os.getuid()}/bus'
        
        try:
            result = subprocess.run(['wpctl', 'status'], capture_output=True, text=True, env=env)
            lines = result.stdout.split('\n')
            sink_id = None
            for i, line in enumerate(lines):
                if 'effect_input.radio_eq' in line or 'Radio EQ' in line:
                    # Find the ID (number followed by dot)
                    import re
                    match = re.search(r'(\d+)\.', line)
                    if match:
                        sink_id = match.group(1)
                        break
            
            if sink_id:
                subprocess.run(['wpctl', 'set-default', sink_id], env=env)
                print(f"Set default sink to Radio EQ (ID: {sink_id})")
            else:
                print("Radio EQ sink not found in wpctl output.")
                print("You may need to manually redirect audio to the new sink.")
                print("List sinks: wpctl status")
                print("Look for 'effect_input.radio_eq' or 'Radio EQ'")
        except Exception as e:
            print(f"Warning: {e}")
        
        print("Radio EQ enabled. Bass and treble reduced by 20dB.")
        
    elif action in ['stop', 'disable', 'off']:
        module_id = None
        try:
            with open('/tmp/radio-eq-module.id', 'r') as f:
                module_id = f.read().strip()
        except:
            pass
        
        if module_id:
            stdout, stderr, code = run_pw_cli(['unload-module', module_id])
            if code == 0:
                print(f"Unloaded module {module_id}")
            else:
                print(f"Failed to unload: {stderr}")
        else:
            print("Module ID not found. To disable, restart PipeWire:")
            print("systemctl --user restart pipewire pipewire-pulse wireplumber")
        
        # Restore default sink
        env = os.environ.copy()
        env['XDG_RUNTIME_DIR'] = f'/run/user/{os.getuid()}'
        env['DBUS_SESSION_BUS_ADDRESS'] = f'unix:path=/run/user/{os.getuid()}/bus'
        try:
            result = subprocess.run(['wpctl', 'status'], capture_output=True, text=True, env=env)
            lines = result.stdout.split('\n')
            for line in lines:
                if 'Built-in Audio Analog Stereo' in line:
                    import re
                    match = re.search(r'(\d+)\.', line)
                    if match:
                        sink_id = match.group(1)
                        subprocess.run(['wpctl', 'set-default', sink_id], env=env)
                        print(f"Restored default sink to Built-in Audio (ID: {sink_id})")
                        break
        except:
            pass
        
    elif action == 'status':
        stdout, stderr, code = run_pw_cli(['ls'])
        if 'Radio EQ' in stdout:
            print("Radio EQ: ACTIVE")
            for line in stdout.split('\n'):
                if 'Radio EQ' in line or 'effect_input.radio_eq' in line:
                    print(line.strip())
        else:
            print("Radio EQ: INACTIVE")
    
    else:
        print(f"Usage: {sys.argv[0]} {{start|stop|status}}")
        sys.exit(1)

if __name__ == '__main__':
    main()