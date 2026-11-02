# Installation testing

Arch Linux is the supported platform. QEMU is installed; KVM was unavailable
from both the initial agent environment and the host check, so testing used TCG.

## Repeatable disposable guest

No VirtualBox project or installed guest disk is required for the config
acceptance suite. Supply an Arch ISO and run:

```sh
python3 tools/vm-test.py --iso /path/to/archlinux.iso
```

The helper snapshots committed HEAD, extracts the matching kernel/initramfs from
the ISO, boots disposable Arch live userspace, logs in on its serial console and
runs the acceptance suites automatically. KVM is selected when accessible;
otherwise software emulation is used. The guest sees only a read-only public
source share, has no network adapter, and cannot access the host’s home configs.
Logs are under `${XDG_CACHE_HOME:-~/.cache}/voluta/vm/last-run.log`. VM temporary
files are deleted afterward. `--source-dir` accepts an explicitly prepared public
snapshot when validating uncommitted implementation; never point it at personal
settings or an unrestricted home directory.

## Coverage

Automated tests exercise a clean unknown-host user home, installation twice,
updates with explicit preferences, skipped-then-enabled modules, disabling and
re-enabling, generated/app state preservation, backup/rollback, installed CLI
update delegation, companion host precedence, custom binding replacement and
Hyprland’s early-child-reaping behavior. System integration tests use a staging
root to verify narrow HID rules and SDDM palette/drop-in restoration.

The guest runs configuration-only installation (`--skip-deps`). This validates
file ownership and behavior, not downloading/building every AUR dependency, a full
graphical login, or a different distro. Native checks additionally cover Dolphin
theme generation, Lua/shell/Python syntax and SDDM QML. The running desktop was
reloaded and its input layout/options inspected explicitly; configerrors alone
misses a loader that silently falls back to public defaults.

## Hardware and publication limits

A VM cannot validate physical NVIDIA suspend/resume, notebook battery policy or
peripheral RGB. Both host profiles are stored in the private companion; install
it on the notebook before updating that machine. Physical RGB application still
requires dependencies and the owner’s privileged setup; see [RGB](../integrations/rgb.md).
Do not describe packet mocks as hardware tests or the live Arch suite as a full
fresh graphical-system installation. Public release still needs artwork/font
redistribution review and a user-selected remote/license policy.


## Recorded run: 2026-11-02

The final offline QEMU/TCG run passed 22 Voluta acceptance tests and 12 session
manager tests. The same 34 tests passed locally. Additional local checks passed:
Dolphin theme/Qt layout generation, fake-package-manager dependency checks,
Lua/Python/shell syntax, SDDM QML linting and the mdBook build. Live reload checks
confirmed loaded companion preferences, the original browser command, US/BR input
and Alt+Shift options, with no compositor configerrors. The temporary shortcut
regression was fixed by eliminating the unreliable pclose-status check and has
an explicit regression test. Privileged real-device RGB setup remains unverified.
