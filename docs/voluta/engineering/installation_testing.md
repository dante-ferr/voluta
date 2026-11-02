# Installation testing

Status: proposed workflow; no VM has been created or tested.

The initial public release officially supports Arch Linux only. Use a clean Arch
guest as the installation and update acceptance target. Other distributions and
Arch derivatives are outside the initial support commitment; do not add package
manager abstractions or distribution-specific installers for them in this phase.

The owner wants a minimal VM workflow instead of manually configuring VirtualBox.
Recommend QEMU/KVM with Quickemu for convenient interactive setup, followed by a
reproducible Arch guest image and disposable qcow2 overlays for repeated tests.
`systemd-vmspawn` is another image-oriented frontend worth evaluating, not a
replacement for preparing the guest image or satisfying QEMU/KVM requirements.
No VM has been created or tested; installation work remains deferred.

Use SSH for unattended installation checks and a graphical guest for login,
Hyprland and visual checks. Test a fresh public-only install with an unknown
hostname and non-owner username, repeat installation, update without overrides,
update with overrides, and a companion-enabled install. Verify optional modules
can remain absent and can be enabled after being declined at install, disabled,
and re-enabled without reinstalling. Check that default-enabled Dolphin can be
disabled and session restoration stays off unless selected on a fresh install. Use fake host/device fixtures to test profile selection without
applying the physical desktop's GPU settings inside the VM. Keep disk images,
downloads and VM state outside the core repo. A VM cannot establish correctness
of physical NVIDIA suspend/resume or real peripheral RGB behavior.

Initial read-only inspection found `systemd-vmspawn` and VirtualBox commands but
no `qemu-system-x86_64` or Quickemu in PATH, and `/dev/kvm` was not visible from
the agent environment. Recheck on the actual host before claiming accelerated
VM support is available; sandbox visibility is not proof of BIOS/module status.
