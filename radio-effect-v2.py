#!/usr/bin/env python3
"""
Radio effect using PipeWire filter-chain (based on sink-eq6.conf)
Bandpass 300Hz-3000Hz for old radio sound
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
    
    # Based on sink-eq6.conf structure
    module_args = {
        "node.description": "Radio Effect EQ",
        "media.name": "Radio Effect EQ",
        "filter.graph": {
            "nodes": [
                {
                    "type": "ladspa",
                    "name": "hpf",
                    "plugin": 1042,
                    "label": "hpf",
                    "control": {
                        "Cutoff Frequency (Hz)": 300.0
                    }
                },
                {
                    "type": "ladspa",
                    "name": "lpf",
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
        "audio.channels": 2,
        "audio.position": [ "FL", "FR" ],
        "capture.props": {
            "node.name": "effect_input.radio",
            "media.class": "Audio/Sink"
        },
        "playback.props": {
            "node.name": "effect_output.radio",
            "node.passive": True
        }
    }
    
    if action in ['start', 'enable', 'on']:
        print("Loading radio effect (v2)...")
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
            # Save module ID to file for later unload
            with open('/tmp/radio-effect-module.id', 'w') as f:
                f.write(module_id)
        
        # Wait for node to appear
        time.sleep(2)
        
        # Check if sink appears
        env = os.environ.copy()
        env['XDG_RUNTIME_DIR'] = f'/run/user/{os.getuid()}'
        env['DBUS_SESSION_BUS_ADDRESS'] = f'unix:path=/run/user/{os.getuid()}/bus'
        
        try:
            result = subprocess.run(['wpctl', 'status'], capture_output=True, text=True, env=env)
            lines = result.stdout.split('\n')
            sink_found = False
            for line in lines:
                if 'effect_input.radio' in line or 'Radio Effect' in line:
                    sink_found = True
                    # Extract sink ID (number followed by dot)
                    import re
                    match = re.search(r'(\d+)\.', line)
                    if match:
                        sink_id = match.group(1)
                        subprocess.run(['wpctl', 'set-default', sink_id], env=env)
                        print(f"Set default sink to Radio Effect (ID: {sink_id})")
                    break
            if not sink_found:
                print("Radio Effect sink not found in wpctl output.")
                print("You may need to manually set default sink.")
                print("List sinks: wpctl status")
        except Exception as e:
            print(f"Warning: {e}")
        
        print("Radio effect enabled. Audio now bandpassed 300Hz-3000Hz.")
        
    elif action in ['stop', 'disable', 'off']:
        # Try to unload module
        module_id = None
        try:
            with open('/tmp/radio-effect-module.id', 'r') as f:
                module_id = f.read().strip()
        except:
            pass
        
        if not module_id:
            # Find module by description
            stdout, stderr, code = run_pw_cli(['ls'])
            for line in stdout.split('\n'):
                if 'Radio Effect' in line:
                    # Look for id in previous lines? Complex.
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
        
        # Restore default sink to built-in audio
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
        if 'Radio Effect' in stdout:
            print("Radio effect: ACTIVE")
            # Find and print relevant lines
            for line in stdout.split('\n'):
                if 'Radio Effect' in line or 'effect_input.radio' in line:
                    print(line.strip())
        else:
            print("Radio effect: INACTIVE")
    
    else:
        print(f"Usage: {sys.argv[0]} {{start|stop|status}}")
        sys.exit(1)

if __name__ == '__main__':
    main()