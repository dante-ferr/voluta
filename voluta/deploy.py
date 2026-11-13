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

from cli import ROOT, atomic_write, host_layer_path, layer_path, migrate_directory, resolve, read

CONFIGS = ('hypr', 'waybar', 'kitty', 'rofi', 'wallust', 'fastfetch', 'swaync', 'music', 'session-menu', 'waypaper', 'wlogout', 'xdg-desktop-portal', 'gsimplecal')
# Theme sources and runtime support must remain siblings in the installed tree.
SOURCES = (*CONFIGS, 'voluta', 'bin', 'dolphin', 'kvantum', 'deps', 'sddm', 'integrations', 'brave', 'packaging')
BASE_PACKAGES = ['hyprland', 'uwsm', 'hypridle', 'hyprlock', 'hyprsunset', 'waybar', 'gsimplecal', 'python', 'python-pillow', 'librsvg', 'json-glib', 'swaync', 'wlogout', 'kitty', 'rofi', 'quickshell', 'zsh', 'starship', 'waypaper', 'wallust-git', 'swww', 'imagemagick', 'fastfetch', 'chafa', 'cliphist', 'wl-clipboard', 'wtype', 'grim', 'slurp', 'tesseract', 'tesseract-data-eng', 'playerctl', 'brightnessctl', 'btop', 'rofimoji', 'nwg-displays', 'jq', 'pipewire', 'wireplumber', 'ttf-jetbrains-mono', 'ttf-jetbrains-mono-nerd', 'ttf-firacode-nerd', 'make', 'gcc', 'pkgconf', 'gtk3', 'xdg-utils', 'qt6ct', 'kvantum', 'breeze-icons', 'capitaine-cursors', 'dolphin', 'xdg-desktop-portal-hyprland', 'xdg-desktop-portal-gtk']
MODULE_PACKAGES = {'dolphin': 'deps/dolphin.txt', 'rgb': ['openrgb', 'python-hidapi'], 'browser': ['gsettings-desktop-schemas', 'xsettingsd'], 'karere': ['karere-custom-css'], 'obs': ['obs-cmd'], 'developer_shell': ['fzf', 'zsh-autosuggestions'], 'sddm': ['sddm'], 'session_restore': ['dbus'], 'rice_switch': []}
# External theme consumers: Wallust always writes files. Limusic stays user-installed;
# Karere theming of WhatsApp Web needs the karere feature (karere-custom-css).
THEME_ONLY_CONSUMERS = (
    {
        'name': 'limusic',
        'theme': 'limusic/matugen.css',
        'packages': ('limusic-bin', 'limusic'),
        'binaries': ('limusic-app', 'limusic'),
        'inactive_note': 'Theme file present; install Limusic (AUR: limusic-bin) and enable Matugen / Wallpaper palette. Voluta does not install this app.',
        'theme_missing_note': 'Limusic is installed but ~/.config/limusic/matugen.css is missing; run make theme or change the wallpaper.',
        'ready_note': 'Limusic is installed; enable Matugen / Wallpaper palette in the app if colors do not follow Wallust.',
    },
    {
        'name': 'karere',
        'theme': 'karere/custom.css',
        'packages': ('karere-custom-css', 'karere'),
        'binaries': ('karere',),
        'injector_packages': ('karere-custom-css',),
        'inactive_note': 'Theme file present; stock Karere ignores it. Run: voluta feature enable karere (installs karere-custom-css).',
        'theme_missing_note': 'Karere is installed but ~/.config/karere/custom.css is missing; run make theme or change the wallpaper.',
        'incomplete_note': 'Stock Karere is installed; it does not load custom.css. Run: voluta feature enable karere (replaces it with karere-custom-css).',
        'ready_note': 'karere-custom-css injects ~/.config/karere/custom.css while Karere is open.',
    },
)


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


def package_installed(name):
    if not shutil.which('pacman'):
        return False
    return subprocess.run(['pacman', '-Q', name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0


def any_package_installed(names):
    return any(package_installed(name) for name in names)


def any_binary_present(names):
    return any(shutil.which(name) for name in names)


def theme_only_consumer_status(spec, config, *, feature_enabled=False):
    theme_path = config / spec['theme']
    theme_present = theme_path.is_file()
    packages = spec['packages']
    binaries = spec['binaries']
    app_installed = any_package_installed(packages) or any_binary_present(binaries)
    injector_names = spec.get('injector_packages') or ()
    injector_installed = True if not injector_names else any_package_installed(injector_names)
    if not app_installed:
        status = 'inactive'
        note = spec['inactive_note'] if theme_present else (
            f"{spec['name']}: optional theme-only consumer; install the app yourself if you want it themed."
        )
    elif not theme_present:
        status = 'theme_missing'
        note = spec['theme_missing_note']
    elif not injector_installed:
        status = 'incomplete'
        note = (
            f"features.{spec['name']} is enabled but {'/'.join(injector_names)} is missing; run: voluta deps"
            if feature_enabled and injector_names else spec['incomplete_note']
        )
    else:
        status = 'ready'
        note = spec.get('ready_note')
    report = {
        'name': spec['name'],
        'theme': str(theme_path),
        'theme_present': theme_present,
        'app_installed': app_installed,
        'status': status,
        'note': note,
    }
    if injector_names:
        report['injector_installed'] = injector_installed
        report['injector_packages'] = list(injector_names)
    return report


def doctor_report(settings, host, config=None):
    config = config or locations()[0]
    missing = missing_packages(settings) if shutil.which('pacman') else []
    features = settings.get('features') or {}
    consumers = [
        theme_only_consumer_status(spec, config, feature_enabled=bool(features.get(spec['name'])))
        for spec in THEME_ONLY_CONSUMERS
    ]
    notes = [item['note'] for item in consumers if item.get('note') and item['status'] != 'ready']
    if missing:
        notes.insert(0, 'Missing selected packages: ' + ', '.join(missing))
    quickshell_ok = quickshell_works()
    wallust = wallust_binary()
    if not quickshell_ok and 'quickshell' not in missing:
        notes.insert(0, 'Quickshell is missing or cannot start; selector effects need a working quickshell.')
    if wallust is None and 'wallust-git' not in missing:
        notes.insert(0, 'Wallust v4 is missing; install wallust-git or put a v4 wallust on PATH.')
    return {
        'host': host,
        'settings_valid': True,
        'missing_packages': missing,
        'wallust_v4': wallust is not None,
        'quickshell_ok': quickshell_ok,
        'kvm': os.access('/dev/kvm', os.R_OK | os.W_OK),
        'theme_only_consumers': consumers,
        'notes': notes,
    }


def _doctor_mark(ok):
    return 'ok' if ok else 'FAIL'


def format_doctor_report(report):
    status_labels = {
        'ready': 'ready',
        'inactive': 'inactive (optional)',
        'theme_missing': 'theme file missing',
        'incomplete': 'incomplete',
    }
    lines = [
        f"Voluta doctor — host {report['host']}",
        '',
        'Core',
        f"  settings          {_doctor_mark(report['settings_valid'])}",
        f"  Wallust v4        {_doctor_mark(report['wallust_v4'])}",
        f"  Quickshell        {_doctor_mark(report['quickshell_ok'])}",
        f"  KVM (/dev/kvm)    {'yes' if report['kvm'] else 'no'}",
    ]
    missing = report['missing_packages']
    if missing:
        lines.append(f"  packages          FAIL ({len(missing)} missing)")
        for name in missing:
            lines.append(f"    - {name}")
    else:
        lines.append('  packages          ok (selected deps present)')
    lines.extend(['', 'Optional themed apps'])
    for item in report['theme_only_consumers']:
        label = status_labels.get(item['status'], item['status'])
        lines.append(f"  {item['name']:<16} {label}")
        lines.append(f"    theme file      {'present' if item['theme_present'] else 'missing'} ({item['theme']})")
        lines.append(f"    app             {'installed' if item['app_installed'] else 'not installed'}")
        if 'injector_installed' in item:
            needed = ', '.join(item.get('injector_packages') or [])
            state = 'installed' if item['injector_installed'] else f'not installed ({needed})'
            lines.append(f"    CSS injector    {state}")
        if item.get('note') and item['status'] != 'ready':
            lines.append(f"    note            {item['note']}")
    notes = [note for note in report.get('notes', []) if note]
    if notes:
        lines.extend(['', 'Notes'])
        for note in notes:
            lines.append(f"  - {note}")
    healthy = not report['missing_packages'] and report['quickshell_ok'] and report['wallust_v4']
    lines.extend(['', 'Result: ' + ('healthy' if healthy else 'needs attention')])
    return '\n'.join(lines) + '\n'


def _run_visible(command):
    # Ask for the password on the real terminal first. The install itself is
    # streamed below; capturing sudo's prompt makes the command look frozen.
    if command and command[0] == 'sudo':
        subprocess.run(['sudo', '-v'], check=True)
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    lines = []
    assert process.stdout is not None
    for line in process.stdout:
        sys.stdout.write(line)
        sys.stdout.flush()
        lines.append(line)
    return subprocess.CompletedProcess(command, process.wait(), ''.join(lines), '')


def _install_packages(packages, *, force_quickshell=False, overwrite=False):
    if not packages:
        return
    # The AUR package fails to compile on rustc 1.94. Build the repo overlay,
    # which applies that fix, and install only after the package file exists.
    if packages == ['karere-custom-css']:
        script = ROOT / 'packaging/karere/install.sh'
        if not script.is_file():
            raise ValueError('missing Karere package script: ' + str(script))
        return _run_visible(['bash', str(script)])
    aur = [pkg for pkg in packages
           if subprocess.run(['pacman', '-Si', pkg], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode]
    helper = shutil.which('paru') or shutil.which('yay')
    if aur and (not helper or os.geteuid() == 0):
        raise ValueError('Install an AUR helper (paru/yay) as your regular user for: '
                         + ', '.join(aur) + '. Or install these manually and rerun.')
    # Reinstall a broken renderer even when pacman considers its package current.
    # Prefer the official package when replacing a stale third-party provider.
    flags = ['--noconfirm']
    if not force_quickshell:
        flags.append('--needed')
    if overwrite:
        flags.extend(['--overwrite', '*'])
    command = ([helper, '-S', *flags, *packages] if aur and helper and os.geteuid() != 0
               else ['pacman', '-S', *flags, *packages])
    if command[0] == 'pacman' and os.geteuid() != 0:
        command.insert(0, 'sudo')
    return _run_visible(command)


def dependencies(settings):
    if not shutil.which('pacman'):
        raise ValueError('Arch Linux pacman is required')
    missing = missing_packages(settings)
    if not missing:
        return
    # Install one package at a time so an orphaned-file conflict on one name
    # cannot roll back siblings that were otherwise ready (e.g. cursors).
    failures = []
    for package in missing:
        result = _install_packages([package], force_quickshell=(package == 'quickshell'))
        if result.returncode == 0:
            continue
        combined = (result.stdout or '') + (result.stderr or '')
        if 'conflicting files' in combined and 'exists in filesystem' in combined:
            # Adopt unpackaged leftovers into the official package.
            retry = _install_packages([package], force_quickshell=(package == 'quickshell'), overwrite=True)
            if retry.returncode == 0:
                continue
            combined = (retry.stdout or '') + (retry.stderr or '')
            result = retry
        failures.append((package, combined.strip() or f'exit {result.returncode}'))
    if failures:
        detail = '; '.join(f'{name}: {error.splitlines()[-1] if error else "failed"}'
                           for name, error in failures)
        raise ValueError('Could not install: ' + detail)
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


def iter_managed_sources(root):
    for folder in SOURCES:
        source = root / folder
        if not source.exists():
            continue
        for path in source.rglob('*'):
            relative = path.relative_to(root)
            if path.is_file() and not path.is_symlink() and not ignored(relative):
                yield path, relative
    for name in ('zshrc', 'zprofile', 'starship.toml'):
        path = root / name
        if path.is_file() and not path.is_symlink():
            yield path, Path(name)


def _file_stat(path):
    try:
        st = path.stat()
    except OSError:
        return f'{path}:missing'
    return f'{path}:{st.st_size}:{st.st_mtime_ns}'


def checkout_status(root, current):
    """Return a source stamp and whether any deployed copy is missing.

    The stamp follows source size and mtime, so an unchanged checkout does not
    read every file. A missing deployed file still requests a copy.
    """
    rows = []
    missing = False
    for path, relative in iter_managed_sources(root):
        rows.append(f'{relative.as_posix()}:{_file_stat(path)}')
        if not (current / relative).is_file():
            missing = True
    rows.sort()
    return hashlib.sha256('\n'.join(rows).encode()).hexdigest(), missing


def publish_stamp(config, root, policy):
    """Identity of the palette, background policy, artwork, and publishers."""
    from surfaces import ASSETS, MUSIC_FRAME, NOTIFICATION_FRAME, SELECTOR_FRAME, SESSION_FRAME
    rows = [json.dumps(policy, sort_keys=True, separators=(',', ':'))]
    rows.append(_file_stat(config / 'hypr/wallust/colors-shell.sh'))
    assets = root / 'wallust/assets'
    for name in (*ASSETS, 'patera.svg'):
        rows.append(_file_stat(assets / name))
    for relative in (SELECTOR_FRAME, NOTIFICATION_FRAME, MUSIC_FRAME, SESSION_FRAME,
                     Path('voluta/surfaces.py'), Path('voluta/theme.py'), Path('voluta/menus.py')):
        rows.append(_file_stat(root / relative))
    return hashlib.sha256('\n'.join(rows).encode()).hexdigest()


def sync_sources(current, manifest, state):
    expected = set()
    fixed_mode = {'zshrc', 'zprofile', 'starship.toml'}
    for path, relative in iter_managed_sources(ROOT):
        destination = current / relative
        expected.add(str(destination))
        mode = 0o644 if relative.as_posix() in fixed_mode else path.stat().st_mode & 0o777
        write_managed(destination, path.read_bytes(), manifest, state, mode)
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
    migrated = migrate_directory(directory)
    settings, initialized = resolve(directory, host)
    if not initialized:
        raise ValueError('initialize settings or attach a companion before installation')
    release = Path('/etc/os-release').read_text()
    if '\nID=arch\n' not in '\n' + release:
        raise ValueError('Voluta officially supports Arch Linux only')
    if dry_run:
        print(json.dumps({'config': str(locations()[0]), 'packages': package_list(settings), 'features': settings['features']}, indent=2))
        return
    if migrated:
        print('Migrated personal settings to TOML: ' + ', '.join(str(path) for path in migrated))
    config, data, state = locations()
    if (state / "rice.json").exists():
        raise ValueError("return to Voluta with rice-switch before updating managed configuration")
    current = data / 'current'
    manifest = load_manifest(state)
    # Running inside the deployment must not copy that tree onto itself.
    # The command entry point re-executes the recorded checkout before this.
    # An unchanged checkout keeps its deployed mtimes, so Waybar's makefile
    # does not rebuild the shim just because the files were copied again.
    if ROOT.resolve() != current.resolve():
        stamp, missing = checkout_status(ROOT, current)
        if missing or stamp != manifest.get('source_stamp'):
            sync_sources(current, manifest, state)
            stamp, missing = checkout_status(ROOT, current)
        if missing:
            manifest.pop('source_stamp', None)
        else:
            manifest['source_stamp'] = stamp
    # Quickshell confines local QML imports to each entrypoint's directory.
    # Both consumers link the one shared effect source into that import root.
    for consumer in ('rofi', 'swaync', 'music', 'session-menu'):
        link(current / consumer / 'effects', current / 'wallust/effects', manifest, state)
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
    # Scope the low-latency GTK renderer to SwayNC, including D-Bus activation.
    launcher = json.dumps(str(current / 'swaync/launch.sh').replace('%', '%%'), ensure_ascii=False)
    service = '[Service]\nExecStart=\nExecStart=/bin/sh ' + launcher + '\n'
    write_managed(config / 'systemd/user/swaync.service.d/10-voluta.conf', service.encode(), manifest, state)
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
    shared_layer = layer_path(directory, 'settings')
    host_layer = host_layer_path(directory, host)
    explicit_paths = {
        **(read(shared_layer).get('paths', {}) if shared_layer else {}),
        **(read(host_layer).get('paths', {}) if host_layer else {}),
    }
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
    # Packages, the Waybar shim and privileged modules run after the copy.
    # A failure here must not hide keybindings and modules already deployed.
    runtime_error = None
    try:
        if not skip_deps:
            dependencies(settings)
            subprocess.run(['make', '-C', str(current / 'waybar')], check=True)
            subprocess.run(['make', '-C', str(current / 'gsimplecal')], check=True)
            subprocess.run(['systemctl', '--user', 'daemon-reload'], check=False)
        palette = config / 'hypr/wallust/colors-shell.sh'
        if not skip_deps and not palette.exists():
            wallust = wallust_binary()
            if wallust is None:
                raise ValueError('Voluta requires Wallust v4; install wallust-git before proceeding')
            subprocess.run([wallust, '-q', '-s', '--no-hooks', '-C', str(config / 'wallust/wallust.toml'), '--templates-dir', str(current / 'wallust/templates'), 'cs', str(current / 'wallust/colorschemes/imperium.json')], check=True)
        if palette.exists():
            stamp = publish_stamp(config, ROOT, settings['appearance']['background'])
            if stamp != manifest.get('publish_stamp'):
                from theme import publish
                publish(config=config, directory=directory, host=host)
                manifest['publish_stamp'] = publish_stamp(config, ROOT, settings['appearance']['background'])
        activate_system_modules(settings, manifest, skip_deps)
        atomic_write(state / 'install.json', manifest)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        runtime_error = error
        atomic_write(state / 'install.json', manifest)
    if runtime_error is None:
        print('Voluta configuration deployed. Existing files are backed up under ' + str(state / 'backups'))
    else:
        print('Voluta configuration deployed, but setup did not finish.', file=sys.stderr)
    return runtime_error


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


def refresh_session(force_frames=False):
    if not os.environ.get('HYPRLAND_INSTANCE_SIGNATURE') or not shutil.which('hyprctl'):
        return
    script = locations()[0] / 'hypr/scripts/Refresh.sh'
    env = {**os.environ, 'VOLUTA_REFRESH_SKIP_SYNC': '1'}
    # Install already published frames. Ask Refresh to filter them only when
    # that publish did not finish, and to reload the session either way.
    if force_frames:
        env['VOLUTA_REFRESH_FORCE_FRAMES'] = '1'
    if script.is_file():
        result = subprocess.run(['bash', str(script)], env=env, check=False)
        if result.returncode != 0:
            print('Voluta files are deployed, but the session refresh failed.', file=sys.stderr)
    else:
        subprocess.run(['hyprctl', 'reload'], check=False)


def install(directory, host, skip_deps=False, dry_run=False, no_session_refresh=False):
    if dry_run:
        return _install(directory, host, skip_deps, True)
    with deployment_lock():
        runtime_error = _install(directory, host, skip_deps, False)
    # Refresh after the lock is released. Frame filtering takes that same lock,
    # and only a deploy that failed before publish still needs it.
    if not no_session_refresh:
        refresh_session(force_frames=runtime_error is not None)
    if runtime_error:
        raise runtime_error


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
                if args.no_session_refresh:
                    command.append('--no-session-refresh')
                subprocess.run(command, check=True)
            else:
                install(directory, host, args.skip_deps, args.dry_run, args.no_session_refresh)
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
            report = doctor_report(settings, host)
            sys.stdout.write(format_doctor_report(report))
            # Theme-only consumer notes are advisory; only selected deps fail the check.
            return int(bool(report['missing_packages']) or not report['quickshell_ok'] or not report['wallust_v4'])
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
