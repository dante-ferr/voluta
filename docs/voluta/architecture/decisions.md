# Decisions and scope

The owner intends to publish this cyber baroque desktop configuration. It is
currently a personal setup shared between a desktop and a notebook. The selected
public name is **Voluta**. A public core plus private companion repository and
separation of public defaults from personal configuration have been accepted;
implementation is authorized, with the module boundary described in
[Core and optional features](features.md).

On 2026-11-02 the owner authorized implementation and requested committing this
work while leaving all Brave-related changes uncommitted for another agent.
The owner then authorized completing the implementation and confirmed QEMU was
installed. Arch guest acceptance checks are now available. Distinguish automated
VM checks from physical peripheral and notebook validation. Remote repository creation
and publication need a concrete destination and are not part of the local foundation.

Preserve pre-existing working-tree changes. Inspect `git status` before editing;
do not stage, revert, or commit another task's changes incidentally.

## Decision record

| Decision | Choice / remaining question | Status |
| --- | --- | --- |
| Repository relationship | Public core plus a separate private companion repo containing personal preferences and host profiles. | Accepted |
| Persistent settings location | Under `${XDG_CONFIG_HOME:-$HOME/.config}/voluta/`, outside the core checkout; the companion repo can manage these files. | Accepted |
| Personal settings format | Human-edited personal/host overlays use TOML (`settings.toml`, `hosts/<hostname>.toml`). Public machine defaults remain `voluta/defaults.json`. Legacy personal JSON still loads; TOML wins when both exist; init/update can migrate JSON→TOML. | Accepted |
| Public scope | A complete themed desktop with optional integrations; the core/optional classification is described in features.md. | Accepted |
| Supported platform | Arch Linux only for the initial public release. Other distributions, including Arch derivatives, are outside the initial support commitment. | Accepted |
| Update policy | Updated defaults apply to unset preferences; explicit user overrides survive, with migrations for renamed/removed keys. | Accepted |
| Optional feature lifecycle | Features declined during installation can be enabled later without reinstalling; support independent disable/re-enable and preserve explicit selections across updates. | Accepted |
| Dolphin default | Dolphin customization enabled by default, with the integration still disableable. | Accepted |
| Session restoration default | Optional; disabled unless selected for a new public install. Preserve the owner’s existing choice during migration. | Accepted |
| Implementation | Begin building; use isolated local checks until the VM is available. Keep the other agent’s Brave work uncommitted. | Accepted |
| Project name | Voluta. Name availability has not been checked. | Accepted |
| Framed-menu edges | The Hyprland window grid (monitor reserved area plus live `general:gaps_out`) is the only inset for left, top, right, and bottom anchors. | Accepted |

Use `voluta` as the settings namespace. Migrate existing `imperium`/`imperivm`
paths and identifiers deliberately with compatibility for existing installations. Companion architecture alone does not protect preferences: loaders,
generators, installers and migrations must all respect the accepted update policy.
