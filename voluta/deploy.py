"""Managed deployment, module activation, rollback and Arch dependency selection."""
import configparser
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

from cli import ROOT, atomic_write, resolve, read

CONFIGS = ('hypr', 'waybar', 'kitty', 'rofi', 'wallust', 'fastfetch', 'swaync', 'waypaper', 'wlogout', 'xdg-desktop-portal')
# Theme sources and runtime support must remain siblings in the installed tree.
SOURCES = (*CONFIGS, 'voluta', 'bin', 'dolphin', 'kvantum', 'deps', 'sddm', 'integrations', 'brave')
BASE_PACKAGES = ['hyprland', 'uwsm', 'hypridle', 'hyprlock', 'hyprsunset', 'waybar', 'python', 'python-pillow', 'librsvg', 'json-glib', 'swaync', 'wlogout', 'kitty', 'rofi', 'quickshell', 'zsh', 'starship', 'waypaper', 'wallust-git', 'swww', 'imagemagick', 'fastfetch', 'chafa', 'cliphist', 'wl-clipboard', 'wtype', 'grim', 'slurp', 'tesseract', 'tesseract-data-eng', 'playerctl', 'brightnessctl', 'btop', 'rofimoji', 'nwg-displays', 'jq', 'pipewire', 'wireplumber', 'ttf-jetbrains-mono', 'ttf-jetbrains-mono-nerd', 'ttf-firacode-nerd', 'make', 'gcc', 'pkgconf', 'gtk3', 'xdg-utils', 'qt6ct', 'kvantum', 'breeze-icons', 'capitaine-cursors', 'dolphin', 'xdg-desktop-portal-hyprland', 'xdg-desktop-portal-gtk']
MODULE_PACKAGES = {'dolphin': 'deps/dolphin.txt', 'rgb': ['openrgb', 'python-hidapi'], 'browser': ['gsettings-desktop-schemas', 'xsettingsd'], 'obs': ['obs-cmd'], 'developer_shell': ['fzf', 'zsh-autosuggestions'], 'sddm': ['sddm'], 'session_restore': ['dbus'], 'rice_switch': []}


def locations():
    home = Path.home()
    return (Path(os.environ.get('XDG_CONFIG_HOME', home / '.config')),
            Path(os.environ.get('XDG_DATA_HOME', home / '.local/share')) / 'voluta',
            Path(os.environ.get('XDG_STATE_HOME', home / '.local/state')) / 'voluta')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def package_list(settings):
    packages = list(BASE_PACKAGES)
    for module, enabled in settings['features'].items():
        if not enabled:
            continue
        source = MODULE_PACKAGES.get(module, [])
        if isinstance(source, str):
            source = [line.strip() for line in (ROOT / source).read_text().splitlines() if line.strip() and not line.startswith('#')]
        packages.extend(source)
    return list(dict.fromkeys(packages))


def wallust_binary():
    # Match the wallpaper refresher's preference for the user's Cargo v4 build.
    candidates = [Path(os.environ.get('CARGO_HOME', Path.home() / '.cargo')) / 'bin/wallust', shutil.which('wallust')]
    for candidate in candidates:
        if not candidate or not os.access(candidate, os.X_OK):
            continue
        try:
            result = subprocess.run([str(candidate), '--version'], capture_output=True, text=True, timeout=5)
        except (OSError, subprocess.TimeoutExpired):
            continue
        if result.returncode == 0 and result.stdout.startswith('wallust 4.'):
            return str(candidate)
    return None


def quickshell_works():
    binary = shutil.which('quickshell')
    if not binary:
        return False
    try:
        result = subprocess.run([binary, '--version'], capture_output=True, timeout=5)
    except (OSError, subprocess.TimeoutExpired):
        return False
    return result.returncode == 0


def missing_packages(settings):
    wallust = wallust_binary()
    return [pkg for pkg in package_list(settings)
            if (not wallust if pkg == 'wallust-git' else
                not quickshell_works() if pkg == 'quickshell' else
                subprocess.run(['pacman', '-T', pkg], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode)]


def dependencies(settings):
    if not shutil.which('pacman'):
        raise ValueError('Arch Linux pacman is required')
    missing = missing_packages(settings)
    if not missing:
        return
    aur = [pkg for pkg in missing if subprocess.run(['pacman', '-Si', pkg], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode]
    helper = shutil.which('paru') or shutil.which('yay')
    if aur and (not helper or os.geteuid() == 0):
        raise ValueError('Install an AUR helper (paru/yay) as your regular user for: ' + ', '.join(aur) + '. Or install these manually and rerun.')
    # Reinstall a broken renderer even when pacman considers its package current.
    # Prefer the official package when replacing a stale third-party provider.
    flags = [] if 'quickshell' in missing else ['--needed']
    command = [helper, '-S', *flags, *missing] if aur and helper and os.geteuid() != 0 else ['pacman', '-S', *flags, *missing]
    if command[0] == 'pacman' and os.geteuid() != 0:
        command.insert(0, 'sudo')
    subprocess.run(command, check=True)
    if 'quickshell' in missing and not quickshell_works():
        raise ValueError('Quickshell still cannot start after installation. Run quickshell --version and repair its Qt dependencies before retrying.')


def load_manifest(state):
    path = state / 'install.json'
    return json.loads(path.read_text()) if path.exists() else {'files': {}, 'links': {}, 'version': 1}


def backup(path, state):
    target = state / 'backups' / (str(time.time_ns()) + '-' + path.name)
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(path), target)
    return str(target)


def link(path, source, manifest, state):
    source = source.absolute()
    key = str(path)
    if path.is_symlink() and path.resolve() == source.resolve():
        manifest['links'].setdefault(key, {'target': str(source), 'backup': None})
        return
    record = manifest['links'].get(key)
    old = record.get('backup') if record else None
    if path.exists() or path.is_symlink():
        old = backup(path, state)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.symlink_to(source, target_is_directory=source.is_dir())
    manifest['links'][key] = {'target': str(source), 'backup': old}


def ignored(path):
    return any(part in ('__pycache__', 'generated', 'wallust', '.git') for part in path.parts[1:]) or path.suffix in ('.pyc', '.so') or path.name in ('monitors.conf', 'workspaces.conf', 'current_styled.png', '01-Wallust.conf')


def write_managed(path, content, manifest, state, mode=None):
    key = str(path)
    previous = manifest['files'].get(key)
    if path.exists() and path.read_bytes() == content:
        manifest['files'][key] = digest(path)
        return
    # Preserve an application/user edit before replacing a managed default.
    if path.exists() and (previous is None or digest(path) != previous):
        saved = backup(path, state)
        manifest.setdefault('file_backups', {}).setdefault(key, saved)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + '.voluta-new')
    temporary.write_bytes(content)
    if mode is not None:
        temporary.chmod(mode)
    os.replace(temporary, path)
    manifest['files'][key] = digest(path)


def sync_sources(current, manifest, state):
    expected = set()
    for folder in SOURCES:
        source = ROOT / folder
        if not source.exists():
            continue
        for path in source.rglob('*'):
            relative = path.relative_to(ROOT)
            if not path.is_file() or path.is_symlink() or ignored(relative):
                continue
            destination = current / relative
            expected.add(str(destination))
            write_managed(destination, path.read_bytes(), manifest, state, path.stat().st_mode & 0o777)
    for name in ('zshrc', 'zprofile', 'starship.toml'):
        path = ROOT / name
        expected.add(str(current / name))
        write_managed(current / name, path.read_bytes(), manifest, state, 0o644)
    # Stale managed files are removed only if unchanged; preserve later edits.
    for name in list(manifest['files']):
        path = Path(name)
        if path.is_relative_to(current) and name not in expected:
            if path.exists():
                backup(path, state) if digest(path) != manifest['files'][name] else path.unlink()
            del manifest['files'][name]


def render_environment(settings, config, manifest, state):
    import shlex
    lines = ['# Generated by Voluta; edit companion environment settings instead.']
    for key, value in settings['environment'].items():
        lines.append(f'unset {key}' if value is None else f'export {key}={shlex.quote(value)}')
    write_managed(config / 'voluta-login-env.sh', ('\n'.join(lines) + '\n').encode(), manifest, state, 0o600)
    # Cursor preferences share the environment's existing companion precedence.
    for version in ('gtk-3.0', 'gtk-4.0'):
        path = config / version / 'settings.ini'
        parser = configparser.ConfigParser(interpolation=None)
        if path.exists():
            parser.read(path)
        if not parser.has_section('Settings'):
            parser.add_section('Settings')
        for env, key in (('XCURSOR_THEME', 'gtk-cursor-theme-name'),
                         ('XCURSOR_SIZE', 'gtk-cursor-theme-size')):
            value = settings['environment'].get(env)
            if value is not None:
                parser.set('Settings', key, value)
        import io
        output = io.StringIO()
        parser.write(output)
        write_managed(path, output.getvalue().encode(), manifest, state)



def module_links(settings, current, manifest, state):
    home = Path.home()
    data = Path(os.environ.get('XDG_DATA_HOME', home / '.local/share'))
    desired = {}
    if settings['features']['dolphin']:
        desired[home / '.local/bin/dolphin'] = current / 'dolphin/launch.sh'
        desktop = Path('/usr/share/applications/org.kde.dolphin.desktop')
        if desktop.exists():
            content = desktop.read_text().replace('Exec=dolphin ', f'Exec={home}/.local/bin/dolphin ').replace('DBusActivatable=true', 'DBusActivatable=false')
            write_managed(data / 'applications/org.kde.dolphin.desktop', content.encode(), manifest, state)
    for path, source in desired.items():
        link(path, source, manifest, state)
    wrapper = str(home / '.local/bin/dolphin')
    if wrapper not in map(str, desired) and wrapper in manifest['links']:
        record = manifest['links'].pop(wrapper)
        path = Path(wrapper)
        if path.is_symlink() and str(path.readlink()) == record['target']:
            path.unlink()
            if record['backup']:
                shutil.move(record['backup'], path)
    desktop = data / 'applications/org.kde.dolphin.desktop'
    if not settings['features']['dolphin'] and str(desktop) in manifest['files']:
        if desktop.exists() and digest(desktop) == manifest['files'][str(desktop)]:
            desktop.unlink()
        del manifest['files'][str(desktop)]


def _install(directory, host, skip_deps=False, dry_run=False):
    settings, initialized = resolve(directory, host)
    if not initialized:
        raise ValueError('initialize settings or attach a companion before installation')
    release = Path('/etc/os-release').read_text()
    if '\nID=arch\n' not in '\n' + release:
        raise ValueError('Voluta officially supports Arch Linux only')
    if dry_run:
        print(json.dumps({'config': str(locations()[0]), 'packages': package_list(settings), 'features': settings['features']}, indent=2))
        return
    if not skip_deps:
        dependencies(settings)
    config, data, state = locations()
    if (state / "rice.json").exists():
        raise ValueError("return to Voluta with rice-switch before updating managed configuration")
    current = data / 'current'
    manifest = load_manifest(state)
    # The deployed CLI can update config/modules without trying to copy over itself.
    if ROOT.resolve() != current.resolve():
        sync_sources(current, manifest, state)
    # Quickshell confines local QML imports to each entrypoint's directory.
    # Both consumers link the one shared effect source into that import root.
    for consumer in ('rofi', 'swaync'):
        link(current / consumer / 'effects', current / 'wallust/effects', manifest, state)
    if not skip_deps:
        subprocess.run(['make', '-C', str(current / 'waybar')], check=True)
    for local_name in ('monitors.conf', 'workspaces.conf'):
        previous = config / 'hypr' / local_name
        destination = current / 'hypr' / local_name
        if previous.is_file() and previous.resolve() != destination.resolve():
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(previous, destination)
    for name in CONFIGS:
        previous_generated = config / name / 'wallust'
        destination_generated = current / name / 'wallust'
        if previous_generated.is_dir() and previous_generated.resolve() != destination_generated.resolve():
            shutil.copytree(previous_generated, destination_generated, dirs_exist_ok=True)
        if name != 'waypaper':
            link(config / name, current / name, manifest, state)
    # Waypaper's GUI owns its preferences. Update only the integration hook.
    path = config / 'waypaper/config.ini'
    if (config / 'waypaper').is_symlink():
        old = backup(config / 'waypaper', state)
        shutil.copytree(Path(old).resolve(), config / 'waypaper', symlinks=False)
    path.parent.mkdir(parents=True, exist_ok=True)
    parser = configparser.ConfigParser(interpolation=None)
    if path.exists():
        parser.read(path)
    if not parser.has_section('Settings'):
        parser.add_section('Settings')
    parser.set('Settings', 'post_command', f'bash "{config}/hypr/UserScripts/combined_wallust.sh" "$wallpaper"')
    explicit_paths = {**read(directory / 'settings.json').get('paths', {}), **read(directory / 'hosts' / (host + '.json')).get('paths', {})}
    if 'wallpapers' in explicit_paths or not parser.has_option('Settings', 'folder'):
        parser.set('Settings', 'folder', settings['paths']['wallpapers'])
    if not parser.has_option('Settings', 'wallpaper'):
        parser.set('Settings', 'wallpaper', str(current / 'hypr/assets/school-of-athens.jpg'))
    if not parser.has_option('Settings', 'backend'):
        parser.set('Settings', 'backend', 'swww')
    import io
    output = io.StringIO()
    parser.write(output)
    write_managed(path, output.getvalue().encode(), manifest, state)
    for name in ('zshrc', 'zprofile'):
        link(Path.home() / ('.' + name), current / name, manifest, state)
    link(config / 'starship.toml', current / 'starship.toml', manifest, state)
    link(Path.home() / '.local/bin/voluta', current / 'bin/voluta', manifest, state)
    render_environment(settings, config, manifest, state)
    module_links(settings, current, manifest, state)
    if ROOT.resolve() != current.resolve():
        manifest['source'] = str(ROOT)
    manifest['skip_deps'] = skip_deps
    atomic_write(state / 'install.json', manifest)
    palette = config / 'hypr/wallust/colors-shell.sh'
    if not skip_deps and not palette.exists():
        wallust = wallust_binary()
        if wallust is None:
            raise ValueError('Voluta requires Wallust v4; install wallust-git before proceeding')
        subprocess.run([wallust, '-q', '-s', '--no-hooks', '-C', str(config / 'wallust/wallust.toml'), '--templates-dir', str(current / 'wallust/templates'), 'cs', str(current / 'wallust/colorschemes/imperium.json')], check=True)
    if palette.exists():
        from theme import publish
        publish(config=config, directory=directory, host=host)
    activate_system_modules(settings, manifest, skip_deps)
    atomic_write(state / 'install.json', manifest)
    print('Voluta configuration deployed. Existing files are backed up under ' + str(state / 'backups'))


def _reconcile_if_installed(directory, host):
    config, data, state = locations()
    if not (state / 'install.json').exists():
        return
    settings, _ = resolve(directory, host)
    manifest = load_manifest(state)
    if not manifest.get('skip_deps'):
        dependencies(settings)
    module_links(settings, data / 'current', manifest, state)
    render_environment(settings, config, manifest, state)
    activate_system_modules(settings, manifest, manifest.get('skip_deps', False))
    if (config / 'hypr/wallust/colors-shell.sh').exists():
        from surfaces import publish
        publish(config=config, directory=directory, host=host)
    atomic_write(state / 'install.json', manifest)


def activate_system_modules(settings, manifest, skip_system):
    if skip_system:
        return
    active = manifest.setdefault('system_modules', {})
    selected = {
        'sddm': settings['features']['sddm'],
        'rgb': settings['features']['rgb'] and any(d.get('backend') == 'hyperx-mars' for d in settings['rgb'].get('devices', [])),
    }
    for name, wanted in selected.items():
        if active.get(name, False) == wanted:
            continue
        command = [sys.executable, str(ROOT / 'voluta/system_setup.py'), name]
        if not wanted:
            command.append('--disable')
        elif name == 'sddm':
            command.extend(['--palette', str(locations()[0] / 'hypr/wallust/colors-shell.sh')])
        if os.geteuid() != 0:
            command.insert(0, 'sudo')
        subprocess.run(command, check=True)
        active[name] = wanted


def _uninstall():
    _, _, state = locations()
    manifest = load_manifest(state)
    settings = {'features': {'sddm': False, 'rgb': False}, 'rgb': {'devices': []}}
    activate_system_modules(settings, manifest, False)
    for name, record in reversed(list(manifest['links'].items())):
        path = Path(name)
        if path.is_symlink() and str(path.readlink()) == record['target']:
            path.unlink()
            if record['backup'] and Path(record['backup']).exists():
                shutil.move(record['backup'], path)
    for name, saved in manifest.get('file_backups', {}).items():
        path = Path(name)
        if path.exists() and manifest['files'].get(name) == digest(path):
            path.unlink()
            if Path(saved).exists():
                shutil.move(saved, path)
    # Retain deployed files/backups: they may contain application state or edits.
    (state / 'install.json').unlink(missing_ok=True)
    print('Managed links removed and original links/files restored; settings and backups retained')


from contextlib import contextmanager
import fcntl

@contextmanager
def deployment_lock():
    state = locations()[2]
    state.mkdir(parents=True, exist_ok=True)
    with (state / 'deployment.lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        yield


def install(directory, host, skip_deps=False, dry_run=False):
    if dry_run:
        return _install(directory, host, skip_deps, True)
    with deployment_lock():
        return _install(directory, host, skip_deps, False)


def reconcile_if_installed(directory, host):
    if not (locations()[2] / 'install.json').exists():
        return
    with deployment_lock():
        return _reconcile_if_installed(directory, host)


def uninstall():
    with deployment_lock():
        return _uninstall()


def switch_rice(directory, host):
    settings, _ = resolve(directory, host)
    if not settings['features']['rice_switch']:
        raise ValueError('enable the rice_switch feature first')
    config, _, state = locations()
    record = state / 'rice.json'
    if record.exists():
        previous = json.loads(record.read_text())
        for name, target in previous.items():
            path = Path(name)
            if path.is_symlink():
                path.unlink()
                path.symlink_to(target)
        record.unlink()
        print('Returned to Voluta; reload the compositor to apply')
        return
    target = Path(settings['paths'].get('other_rice', '')).expanduser()
    if not target.is_dir() or not str(settings['paths'].get('other_rice', '')):
        raise ValueError('set paths.other_rice to an existing rice checkout')
    previous = {}
    for name in CONFIGS:
        path = config / name
        source = target / name
        if not source.exists():
            source = target / 'config' / name
        if source.exists() and path.is_symlink():
            previous[str(path)] = str(path.readlink())
    if not previous:
        raise ValueError('no managed config symlinks can be switched')
    atomic_write(record, previous)
    for name in previous:
        path = Path(name)
        source = target / path.name
        if not source.exists():
            source = target / 'config' / path.name
        path.unlink()
        path.symlink_to(source.absolute())
    print('External rice selected; run voluta rice-switch again to return')


def dispatch(args, directory, host):
    try:
        if args.command in ('install', 'update'):
            current = locations()[1] / 'current'
            manifest = load_manifest(locations()[2])
            source = Path(manifest.get('source', str(ROOT)))
            if ROOT.resolve() == current.resolve() and source.resolve() != ROOT.resolve():
                command = [str(source / 'bin/voluta'), '--config-dir', str(directory), '--host', host, args.command]
                if args.skip_deps:
                    command.append('--skip-deps')
                if args.dry_run:
                    command.append('--dry-run')
                subprocess.run(command, check=True)
            else:
                install(directory, host, args.skip_deps, args.dry_run)
        elif args.command == 'uninstall':
            uninstall()
        elif args.command == 'rice-switch':
            switch_rice(directory, host)
        elif args.command == 'system-setup':
            settings, _ = resolve(directory, host)
            if not args.disable and not settings['features'][args.module]:
                raise ValueError('enable the feature before system setup')
            command = [sys.executable, str(ROOT / 'voluta/system_setup.py'), args.module]
            if args.disable:
                command.append('--disable')
            if args.module == 'sddm' and not args.disable:
                command.extend(['--palette', str(locations()[0] / 'hypr/wallust/colors-shell.sh')])
            if os.geteuid() != 0:
                command.insert(0, 'sudo')
            subprocess.run(command, check=True)
        elif args.command == 'deps':
            settings, _ = resolve(directory, host)
            dependencies(settings)
            print('Voluta dependencies are ready.')
        elif args.command == 'doctor':
            settings, _ = resolve(directory, host)
            missing = []
            if shutil.which('pacman'):
                missing = missing_packages(settings)
            print(json.dumps({'host': host, 'settings_valid': True, 'missing_packages': missing, 'kvm': os.access('/dev/kvm', os.R_OK | os.W_OK)}, indent=2))
            return int(bool(missing))
        elif args.command == 'rgb':
            from rgb import apply
            results = apply(directory, host, args.dry_run, args.force)
            return int(any(item["status"] == "unavailable" for item in results))
        elif args.command == 'apply':
            reconcile_if_installed(directory, host)
            from rgb import apply
            apply(directory, host)
            if os.environ.get('HYPRLAND_INSTANCE_SIGNATURE') and shutil.which('hyprctl'):
                subprocess.run(['hyprctl', 'reload'], check=True)
        return 0
    except subprocess.CalledProcessError as error:
        raise ValueError(f'command failed ({error.returncode}): {error.cmd[0]}') from error
