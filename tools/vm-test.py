#!/usr/bin/env python3
"""Boot disposable Arch ISO userspace and run Voluta acceptance checks automatically."""
import argparse
import os
from pathlib import Path
import select
import shutil
import subprocess
import tarfile
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--iso', required=True, type=Path)
    parser.add_argument('--timeout', type=int, default=1200)
    parser.add_argument('--source-dir', type=Path, help='test an already prepared public-only snapshot instead of HEAD')
    args = parser.parse_args()
    for tool in ('qemu-system-x86_64', 'bsdtar', 'blkid'):
        if not shutil.which(tool):
            raise SystemExit(f'Missing {tool}')
    cache = Path(os.environ.get('XDG_CACHE_HOME', Path.home() / '.cache')) / 'voluta/vm'
    cache.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='run-', dir=cache) as directory:
        work = Path(directory)
        share = work / 'share'
        share.mkdir()
        if args.source_dir:
            shutil.copytree(args.source_dir, share / 'source', ignore=shutil.ignore_patterns('.git', '__pycache__'))
        else:
            archive = work / 'source.tar'
            with archive.open('wb') as output:
                subprocess.run(['git', '-C', str(ROOT), 'archive', 'HEAD'], stdout=output, check=True)
            (share / 'source').mkdir()
            with tarfile.open(archive) as source:
                source.extractall(share / 'source', filter='data')
        subprocess.run(['bsdtar', '-xf', str(args.iso.resolve()), '-C', str(work), 'arch/boot/x86_64/vmlinuz-linux', 'arch/boot/x86_64/initramfs-linux.img'], check=True)
        label = subprocess.check_output(['blkid', '-p', '-o', 'value', '-s', 'LABEL', str(args.iso)]).decode().strip()
        (share / 'guest-test.sh').write_text('''#!/bin/bash
set -e
cp -a /mnt/voluta/source /tmp/voluta-source
cd /tmp/voluta-source
python3 -m unittest discover -s tests -v
python3 -m unittest discover -s hypr/scripts/tests -v
printf '\\nVOLUTA_VM_TESTS_PASSED\\n'
systemctl poweroff
''')
        accelerator = 'kvm' if os.access('/dev/kvm', os.R_OK | os.W_OK) else 'tcg'
        command = ['qemu-system-x86_64', '-accel', accelerator, '-m', '2048', '-smp', '2', '-nographic', '-no-reboot',
                   '-kernel', str(work / 'arch/boot/x86_64/vmlinuz-linux'), '-initrd', str(work / 'arch/boot/x86_64/initramfs-linux.img'),
                   '-append', f'archisobasedir=arch archisolabel={label} console=ttyS0 systemd.wants=serial-getty@ttyS0.service systemd.mask=systemd-time-wait-sync.service systemd.mask=systemd-networkd-wait-online.service',
                   '-cdrom', str(args.iso.resolve()), '-nic', 'none', '-virtfs', f'local,path={share},mount_tag=voluta,security_model=none,readonly=on']
        log_path = cache / 'last-run.log'
        print(f'Booting disposable Arch guest ({accelerator}); log: {log_path}', flush=True)
        process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        logged_in = False
        launched = False
        passed = False
        buffer = b''
        deadline = time.monotonic() + args.timeout
        try:
            with log_path.open('wb') as log:
                while time.monotonic() < deadline:
                    ready, _, _ = select.select([process.stdout], [], [], 1)
                    if ready:
                        chunk = os.read(process.stdout.fileno(), 65536)
                        if not chunk:
                            break
                        log.write(chunk)
                        log.flush()
                        buffer = (buffer + chunk)[-20000:]
                        if not logged_in and b'login:' in buffer:
                            process.stdin.write(b'root\n'); process.stdin.flush()
                            logged_in = True
                            buffer = b''
                        if logged_in and not launched and b'@archiso' in buffer:
                            process.stdin.write(b'mkdir -p /mnt/voluta; mount -t 9p -o trans=virtio,version=9p2000.L,ro voluta /mnt/voluta && bash /mnt/voluta/guest-test.sh\n')
                            process.stdin.flush()
                            launched = True
                        if b'VOLUTA_VM_TESTS_PASSED' in buffer:
                            passed = True
                    if process.poll() is not None:
                        break
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill(); process.wait()
        if not passed:
            raise SystemExit(f'VM checks failed or timed out; inspect {log_path}')
        print('Arch guest installation/update/lifecycle acceptance checks passed')


if __name__ == '__main__':
    main()
