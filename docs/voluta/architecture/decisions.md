# Decisions and scope

The owner intends to publish this cyber baroque desktop configuration. It is
currently a personal setup shared between a desktop and a notebook. The selected
public name is **Voluta**. A public core plus private companion repository and
separation of public defaults from personal configuration have been accepted;
implementation and the exact core/optional feature boundary remain pending.

The current authorized scope is repository auditing, agent documentation, and
collecting the owner's decisions. Do not implement the configuration migration,
rename paths or identifiers, create a remote repository/fork, or build/install
RGB integration as part of this planning task. Record answers below as they
arrive; distinguish accepted decisions from proposals still awaiting a choice.
This boundary applies to this planning task, not to unrelated authorized work.

Preserve pre-existing working-tree changes. Inspect `git status` before editing;
do not stage, revert, or commit another task's changes incidentally.

## Decision record

| Decision | Choice / remaining question | Status |
| --- | --- | --- |
| Repository relationship | Public core plus a separate private companion repo containing personal preferences and host profiles. | Accepted |
| Persistent settings location | Under `${XDG_CONFIG_HOME:-$HOME/.config}/voluta/`, outside the core checkout; the companion repo can manage these files. | Accepted |
| Public scope | A complete themed desktop with optional integrations; the specific core/optional classification below still needs review. | Broad scope accepted; boundary pending |
| Supported platform | Arch Linux only for the initial public release. Other distributions, including Arch derivatives, are outside the initial support commitment. | Accepted |
| Update policy | Updated defaults apply to unset preferences; explicit user overrides survive, with migrations for renamed/removed keys. | Accepted |
| Optional feature lifecycle | Features declined during installation can be enabled later without reinstalling; support independent disable/re-enable and preserve explicit selections across updates. | Accepted |
| Dolphin default | Dolphin customization enabled by default, with the integration still disableable. | Accepted |
| Session restoration default | Optional; disabled unless selected for a new public install. Preserve the owner’s existing choice during migration. | Accepted |
| Project name | Voluta. Name availability has not been checked. | Accepted |

Use `voluta` as the planned settings namespace. Naming approval does not authorize
renaming existing `imperium`/`imperivm` paths or identifiers during this planning
task. Companion architecture alone does not protect preferences: loaders,
generators, installers and migrations must all respect the accepted update policy.
