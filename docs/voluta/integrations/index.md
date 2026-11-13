# Integrations

Reusable integration code belongs in the public project; personal selections and
hardware identifiers belong in companion settings. Optional integrations must not
prevent the core desktop from starting when unavailable.

| Document | Purpose |
| --- | --- |
| [Integration categories](../architecture/integration_categories.md) | Theme-only apps vs feature modules vs soft presence checks. |
| [Shared appearance](theme.md) | Shared background policy plus design tokens (fonts, spacing, radii, glass) for rice consumers. |
| [Brave with Prismwing and Gallery](brave.md) | User setup for Brave GTK theming, Prismwing favicons, and the Gallery New Tab page. |
| [Architectural surfaces and Gallery](surfaces.md) | Stepped launcher, notification, and music frames, the shared window-grid insets, plus Gallery geometry, motion, and storage. |
| [Wallust RGB integration](rgb.md) | Preset gallery, native animations, palette fidelity and desktop scoping. |
| [Custom animation research](rgb_research.md) | Stock protocol evidence, alternative mouse SDKs and remaining firmware leads. |

Existing component notes remain alongside their code:
[Brave](../../../brave/README.md), [Dolphin](../../../dolphin/README.md),
[Waybar](../../../waybar/README.md), and
[session restoration](../../../hypr/scripts/SESSION_RESTORE.md).
