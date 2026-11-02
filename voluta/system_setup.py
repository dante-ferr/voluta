"""Explicit, bounded system integration installation; does not restart SDDM."""
import argparse
import configparser
import os
from pathlib import Path
import shutil
import subprocess

from cli import ROOT


def replace(source, target):
    target.parent.mkdir(parents=True, exist_ok=True)
    saved = target.with_name(target.name + '.pre-voluta')
    if target.exists() and not saved.exists():
        shutil.copy2(target, saved)
    shutil.copy2(source, target)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('module', choices=('sddm', 'rgb'))
    parser.add_argument('--disable', action='store_true')
    parser.add_argument('--palette', type=Path)
    parser.add_argument('--root', type=Path, default=Path('/'), help='stage system files under a test root')
    args = parser.parse_args()
    if args.root == Path('/') and os.geteuid() != 0:
        raise SystemExit('System setup requires sudo')
    if args.module == 'rgb':
        target = args.root / 'etc/udev/rules.d/70-voluta-hyperx-mars.rules'
        if args.disable:
            target.unlink(missing_ok=True)
            saved = target.with_name(target.name + '.pre-voluta')
            if saved.exists():
                shutil.move(saved, target)
        else:
            replace(ROOT / 'integrations/70-voluta-hyperx-mars.rules', target)
        if args.root == Path('/'):
            subprocess.run(['udevadm', 'control', '--reload-rules'], check=True)
        print('Reconnect the keyboard to refresh access permissions')
    else:
        target = args.root / 'etc/sddm.conf.d/zz-voluta.conf'
        marker = target.with_name(target.name + '.voluta-created')
        if args.disable:
            target.unlink(missing_ok=True)
            marker.unlink(missing_ok=True)
            # Restore a pre-existing drop-in only when one was saved.
            backup = target.with_name(target.name + '.pre-voluta')
            if backup.exists():
                shutil.move(backup, target)
            return
        if args.palette is None or not args.palette.is_file():
            raise SystemExit('Render Wallust first; SDDM needs its generated palette')
        import re
        text = args.palette.read_text()
        colors = {}
        for name, value in re.findall(r"^(wc_\w+)=['\"]?([0-9a-fA-F]{6})['\"]?\s*$", text, re.M):
            colors[name] = '#' + value
        if not all(k in colors for k in ('wc_bg', 'wc_fg', 'wc_1')):
            raise SystemExit('Missing Wallust palette colors for SDDM')
        theme = args.root / 'usr/share/sddm/themes/voluta'
        theme.mkdir(parents=True, exist_ok=True)
        replace(ROOT / 'sddm/Main.qml', theme / 'Main.qml')
        replace(ROOT / 'sddm/metadata.desktop', theme / 'metadata.desktop')
        uid = int(os.environ.get('SUDO_UID', str(os.getuid())))
        palette_dir = args.root / f'var/lib/sddm/voluta-{uid}'
        palette_dir.mkdir(parents=True, exist_ok=True)
        palette_dir.chmod(0o755)
        if args.root == Path('/'):
            os.chown(palette_dir, uid, -1)
        shared_palette = palette_dir / 'theme.conf'
        shared_palette.write_text('[General]\nbgColor=' + colors['wc_bg'] + '\nfgColor=' + colors['wc_fg'] + '\naccentColor=' + colors['wc_1'] + '\n')
        shared_palette.chmod(0o644)
        if args.root == Path('/'):
            os.chown(shared_palette, uid, -1)
        (theme / 'theme.conf').unlink(missing_ok=True)
        (theme / 'theme.conf').symlink_to(shared_palette)
        wall = ROOT / 'hypr/assets/school-of-athens.jpg'
        if wall.exists():
            (theme / 'Backgrounds').mkdir(exist_ok=True)
            shutil.copy2(wall, theme / 'Backgrounds/wallpaper.jpg')
        target.parent.mkdir(parents=True, exist_ok=True)
        if target.exists() and not marker.exists() and not target.with_name(target.name + '.pre-voluta').exists():
            shutil.copy2(target, target.with_name(target.name + '.pre-voluta'))
        if not target.exists():
            marker.touch()
        target.write_text('[Theme]\nCurrent=voluta\n')
        print('Voluta SDDM theme installed; the running login manager was not restarted')


if __name__ == '__main__':
    main()
