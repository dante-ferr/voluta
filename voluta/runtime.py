"""Runtime consumers of companion settings; polling avoids coupling to generators."""
import fcntl
import json
import os
from pathlib import Path
import subprocess
import sys
import time

from cli import ROOT, config_home, hostname, resolve


def publish_sddm(config):
    import re, tempfile
    target = Path(f'/var/lib/sddm/voluta-{os.getuid()}') / 'theme.conf'
    if not target.parent.is_dir() or not os.access(target.parent, os.W_OK):
        return
    text = (config / 'hypr/wallust/colors-shell.sh').read_text()
    colors = dict(re.findall(r"^(wc_\w+)=['\"]?([0-9a-fA-F]{6})['\"]?\s*$", text, re.M))
    if not all(key in colors for key in ('wc_bg', 'wc_fg', 'wc_1')):
        return
    with tempfile.NamedTemporaryFile(mode='w', dir=target.parent, delete=False) as output:
        output.write('[General]\nbgColor=#' + colors['wc_bg'] + '\nfgColor=#' + colors['wc_fg'] + '\naccentColor=#' + colors['wc_1'] + '\n')
        name = Path(output.name)
    name.chmod(0o644)
    os.replace(name, target)


def watch():
    runtime = os.environ.get('XDG_RUNTIME_DIR')
    instance = os.environ.get('HYPRLAND_INSTANCE_SIGNATURE', '')
    if not runtime or not instance or '/' in instance:
        return
    with (Path(runtime) / ('voluta-palette-' + instance + '.lock')).open('w') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return
        previous = None
        last_try = 0
        while (Path(runtime) / 'hypr' / instance / '.socket2.sock').exists():
            try:
                settings, _ = resolve(config_home(), hostname())
                config = Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config'))
                palette = config / 'hypr/wallust/colors-shell.sh'
                signature = (palette.stat().st_mtime_ns, json.dumps(settings, sort_keys=True))
                if signature != previous or time.monotonic() - last_try > 30:
                    if signature != previous and settings['features']['sddm']:
                        publish_sddm(config)
                    from rgb import apply
                    apply(config_home(), hostname())
                    if signature != previous and settings['features']['browser']:
                        script = ROOT / 'hypr/UserScripts/paint_brave_theme.py'
                        if script.exists():
                            subprocess.run([sys.executable, str(script)], timeout=30, check=False)
                    previous, last_try = signature, time.monotonic()
            except (OSError, ValueError, subprocess.SubprocessError) as error:
                print(f'Voluta palette: {error}', file=sys.stderr, flush=True)
            time.sleep(1)


def main():
    if sys.argv[1] == 'watch':
        watch()
    elif sys.argv[1] == 'waybar':
        settings, _ = resolve(config_home(), hostname())
        if not settings['waybar_output']:
            return 1
        data = json.loads(Path(sys.argv[2]).read_text())
        data['output'] = settings['waybar_output']
        target = Path(sys.argv[3])
        target.parent.mkdir(parents=True, exist_ok=True)
        from cli import atomic_write
        atomic_write(target, data)
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (OSError, ValueError) as error:
        print(f'Voluta runtime: {error}', file=sys.stderr)
        raise SystemExit(1)
