# Voluta

Voluta is the selected name for this cyber baroque Hyprland desktop. The checkout
still uses Imperium/Imperivm identifiers. The first settings/companion foundation
is implemented; full host extraction, installer migration and branding changes
remain in progress.

This documentation follows ai-delver's structure: a project documentation root,
`index.md` overview pages, a `SUMMARY.md` navigation tree, and topic directories.
It lives in this repository under `docs/voluta/`; there is no separate docs remote.

## Agent starting points

Read [AGENTS.md](../../AGENTS.md) first, then choose the relevant topic. Detailed
specifications belong here rather than in the root agent instructions.

| Task | Read |
| --- | --- |
| Use the settings CLI and companion | [Settings ownership and updates](architecture/settings.md) |
| Understand approved direction and remaining decisions | [Decisions and scope](architecture/decisions.md) |
| Design loaders, companion settings, or update behavior | [Settings ownership and updates](architecture/settings.md) |
| Classify or introduce an optional module | [Core and optional features](architecture/features.md) |
| Extract personal or machine-specific configuration | [Configuration separation audit](engineering/configuration_audit.md) |
| Change login, GPU, locking, or suspend behavior | [Runtime and hardware constraints](engineering/runtime_constraints.md) |
| Plan installation validation in a VM | [Installation testing](engineering/installation_testing.md) |
| Implement device lighting after authorization | [Wallust RGB integration](integrations/rgb.md) |

Use the [complete summary](SUMMARY.md) for navigation.

## Documentation conventions

- Mark accepted decisions, proposals, deferred work, and verified current behavior
  explicitly. A design document is not evidence that a feature is implemented.
- Update the relevant specification and navigation when changing the design.
- Keep machine observations dated and recheck them before relying on them.
- Preserve component READMEs near their code; link them instead of duplicating them.
- Keep credentials, session snapshots, generated assets, and VM images out of docs.

## Preview

With mdBook installed, run `mdbook build docs` or `mdbook serve docs`. Build output
is ignored under `docs/book/`. Markdown navigation also works without mdBook.
