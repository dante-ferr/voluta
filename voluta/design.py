"""Shared design tokens for typography, density, shape, and glass."""

from __future__ import annotations

import copy
import math
import re

# Public defaults. Keep in sync with voluta/defaults.json appearance.*.
DEFAULTS = {
    "typography": {
        "ui": {
            "family": "Oxanium",
            "size_pt": 11,
            "fallback": ["sans-serif"],
        },
        "mono": {
            "family": "Monaspace Argon",
            "size_pt": 10,
            "fallback": ["JetBrainsMono Nerd Font", "monospace"],
        },
        "display": {
            "family": "Cinzel",
            "size_pt": 11.5,
            "weight": 700,
            "letter_spacing_px": 0.8,
            "fallback": [
                "JetBrainsMono Nerd Font",
                "FiraCode Nerd Font",
                "serif",
                "monospace",
            ],
        },
        "icon": {
            "family": "JetBrainsMono Nerd Font",
        },
    },
    "density": {
        "space_xs_px": 3,
        "space_sm_px": 6,
        "space_md_px": 12,
        "space_lg_px": 18,
    },
    "shape": {
        "radius_sharp_px": 0,
        "radius_sm_px": 5,
        "radius_md_px": 6,
        "radius_lg_px": 8,
        "radius_xl_px": 13,
    },
    "glass": {
        "body_alpha": 102,
        "chrome_alpha": 191,
        "stripe_alpha": 40,
    },
}

_TYPO_ROLES = {
    "ui": {"family", "size_pt", "fallback"},
    "mono": {"family", "size_pt", "fallback"},
    "display": {"family", "size_pt", "weight", "letter_spacing_px", "fallback"},
    "icon": {"family", "fallback"},
}
_DENSITY_KEYS = set(DEFAULTS["density"])
_SHAPE_KEYS = set(DEFAULTS["shape"])
_GLASS_KEYS = set(DEFAULTS["glass"])
_TOKEN_SECTIONS = {"typography", "density", "shape", "glass"}


def _finite_number(value, label, minimum=None, maximum=None):
    if type(value) not in (int, float) or isinstance(value, bool) or not math.isfinite(value):
        raise ValueError(f"{label} must be a finite number")
    if minimum is not None and value < minimum:
        raise ValueError(f"{label} must be >= {minimum}")
    if maximum is not None and value > maximum:
        raise ValueError(f"{label} must be <= {maximum}")
    return value


def _string(value, label):
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{label} must be a nonempty string")
    return value


def _fallback_list(value, label):
    if value is None:
        return []
    if not isinstance(value, list) or not value or any(not isinstance(item, str) or not item.strip() for item in value):
        raise ValueError(f"{label} must be a nonempty list of strings")
    return list(value)


def validate_design(appearance):
    """Validate design-token sections inside an appearance object."""
    unknown = set(appearance) - ({"background"} | _TOKEN_SECTIONS)
    if unknown:
        raise ValueError(f"appearance accepts background and design tokens; unknown: {', '.join(sorted(unknown))}")

    typography = appearance.get("typography", {})
    if not isinstance(typography, dict):
        raise ValueError("appearance.typography must be an object")
    unknown = set(typography) - set(_TYPO_ROLES)
    if unknown:
        raise ValueError(f"typography roles: {', '.join(sorted(unknown))}")
    for role, allowed in _TYPO_ROLES.items():
        if role not in typography:
            continue
        node = typography[role]
        if not isinstance(node, dict) or set(node) - allowed:
            raise ValueError(f"typography.{role} accepts {', '.join(sorted(allowed))}")
        if "family" in node:
            _string(node["family"], f"typography.{role}.family")
        if "size_pt" in node:
            _finite_number(node["size_pt"], f"typography.{role}.size_pt", minimum=1, maximum=72)
        if "weight" in node:
            _finite_number(node["weight"], f"typography.{role}.weight", minimum=100, maximum=900)
        if "letter_spacing_px" in node:
            _finite_number(node["letter_spacing_px"], f"typography.{role}.letter_spacing_px", minimum=0, maximum=8)
        if "fallback" in node:
            _fallback_list(node["fallback"], f"typography.{role}.fallback")

    for section, allowed, minimum, maximum in (
        ("density", _DENSITY_KEYS, 0, 64),
        ("shape", _SHAPE_KEYS, 0, 64),
    ):
        node = appearance.get(section, {})
        if not isinstance(node, dict) or set(node) - allowed:
            raise ValueError(f"appearance.{section} accepts {', '.join(sorted(allowed))}")
        for key, value in node.items():
            _finite_number(value, f"{section}.{key}", minimum=minimum, maximum=maximum)

    glass = appearance.get("glass", {})
    if not isinstance(glass, dict) or set(glass) - _GLASS_KEYS:
        raise ValueError(f"appearance.glass accepts {', '.join(sorted(_GLASS_KEYS))}")
    for key, value in glass.items():
        _finite_number(value, f"glass.{key}", minimum=0, maximum=255)
        if type(value) is float and not value.is_integer():
            raise ValueError(f"glass.{key} must be an integer alpha 0..255")


def resolve_design(appearance=None):
    """Return fully merged design tokens for generators."""
    appearance = appearance or {}
    validate_design({key: appearance[key] for key in appearance if key in ({"background"} | _TOKEN_SECTIONS)})
    result = copy.deepcopy(DEFAULTS)
    for section in _TOKEN_SECTIONS:
        override = appearance.get(section)
        if not isinstance(override, dict):
            continue
        if section == "typography":
            for role, values in override.items():
                if role in result["typography"] and isinstance(values, dict):
                    result["typography"][role] = {**result["typography"][role], **copy.deepcopy(values)}
        else:
            result[section].update(copy.deepcopy(override))
    return result


def css_font_stack(role):
    family = role["family"]
    fallback = role.get("fallback") or []
    parts = [f'"{family}"'] + [f'"{item}"' if " " in item and not item.startswith('"') else item for item in fallback]
    # Generic families (serif, sans-serif, monospace) stay unquoted.
    cleaned = []
    for part in parts:
        bare = part.strip('"')
        if bare in ("serif", "sans-serif", "monospace", "cursive", "fantasy", "system-ui"):
            cleaned.append(bare)
        elif part.startswith('"'):
            cleaned.append(part)
        else:
            cleaned.append(f'"{bare}"' if " " in bare else bare)
    return ", ".join(cleaned)


def css_px(value):
    if type(value) is float and value.is_integer():
        value = int(value)
    return f"{value}px"


def css_pt(value):
    if type(value) is float and value.is_integer():
        value = int(value)
    return f"{value}pt"


def qt_font(family, size_pt, weight=400):
    """Qt 6 QFont::toString() OpenType weight form used by qt6ct."""
    style = "Regular" if weight <= 400 else "Bold"
    return f"{family},{int(size_pt)},-1,5,{int(weight)},0,0,0,0,0,0,0,0,0,0,1,{style},0,0"


def rofi_font(family, size_pt, bold=False):
    weight = " Bold" if bold else ""
    size = int(size_pt) if float(size_pt).is_integer() else size_pt
    return f"{family}{weight} {size}"


def replace_marked_block(text, name, body):
    """Replace /* @@name:start */ ... /* @@name:end */ with a new body."""
    start = f"/* @@{name}:start */"
    end = f"/* @@{name}:end */"
    if start not in text or end not in text:
        raise ValueError(f"missing @@{name} markers")
    prefix, rest = text.split(start, 1)
    before_end, suffix = rest.split(end, 1)
    # Keep the end marker's original indentation (spaces before it on its line).
    pad_match = re.search(r"(?:\A|\n)([ \t]*)\Z", before_end)
    pad = pad_match.group(1) if pad_match else ""
    block = body if body.endswith("\n") else body + "\n"
    return f"{prefix}{start}\n{block}{pad}{end}{suffix}"


def export_payload(design, background=None, background_rgb=None, source_background=None):
    payload = {"version": 1, **copy.deepcopy(design)}
    if background is not None:
        payload["background"] = background
    if background_rgb is not None:
        payload["background_rgb"] = list(background_rgb)
    if source_background is not None:
        payload["source_background"] = source_background
    return payload


def theme_css(design, background=None):
    ui = design["typography"]["ui"]
    mono = design["typography"]["mono"]
    display = design["typography"]["display"]
    icon = design["typography"]["icon"]
    density = design["density"]
    shape = design["shape"]
    glass = design["glass"]
    lines = ["/* Generated from appearance design tokens. Do not edit. */"]
    if background:
        lines.append(f"@define-color voluta_background {background};")
    lines.extend([
        "",
        "/* CSS custom properties for consumers that expand var(). */",
        ":root {",
        f"  --voluta-font-ui: {css_font_stack(ui)};",
        f"  --voluta-font-ui-size: {css_pt(ui['size_pt'])};",
        f"  --voluta-font-mono: {css_font_stack(mono)};",
        f"  --voluta-font-mono-size: {css_pt(mono['size_pt'])};",
        f"  --voluta-font-display: {css_font_stack(display)};",
        f"  --voluta-font-display-size: {css_pt(display['size_pt'])};",
        f"  --voluta-font-display-weight: {int(display['weight'])};",
        f"  --voluta-font-display-tracking: {css_px(display['letter_spacing_px'])};",
        f"  --voluta-font-icon: {css_font_stack(icon)};",
        f"  --voluta-space-xs: {css_px(density['space_xs_px'])};",
        f"  --voluta-space-sm: {css_px(density['space_sm_px'])};",
        f"  --voluta-space-md: {css_px(density['space_md_px'])};",
        f"  --voluta-space-lg: {css_px(density['space_lg_px'])};",
        f"  --voluta-radius-sharp: {css_px(shape['radius_sharp_px'])};",
        f"  --voluta-radius-sm: {css_px(shape['radius_sm_px'])};",
        f"  --voluta-radius-md: {css_px(shape['radius_md_px'])};",
        f"  --voluta-radius-lg: {css_px(shape['radius_lg_px'])};",
        f"  --voluta-radius-xl: {css_px(shape['radius_xl_px'])};",
        f"  --voluta-glass-body: {int(glass['body_alpha'])};",
        f"  --voluta-glass-chrome: {int(glass['chrome_alpha'])};",
        f"  --voluta-glass-stripe: {int(glass['stripe_alpha'])};",
        "}",
        "",
    ])
    return "\n".join(lines)


def theme_sh(design, background=None, background_rgb=None):
    ui = design["typography"]["ui"]
    mono = design["typography"]["mono"]
    display = design["typography"]["display"]
    icon = design["typography"]["icon"]
    density = design["density"]
    shape = design["shape"]
    glass = design["glass"]
    lines = []
    if background:
        lines.append(f"voluta_bg='{background.lstrip('#')}'")
    if background_rgb is not None:
        lines.append(f"voluta_bg_rgb='{','.join(map(str, background_rgb))}'")
    lines.extend([
        f"voluta_font_ui='{ui['family']}'",
        f"voluta_font_ui_pt='{ui['size_pt']}'",
        f"voluta_font_mono='{mono['family']}'",
        f"voluta_font_mono_pt='{mono['size_pt']}'",
        f"voluta_font_display='{display['family']}'",
        f"voluta_font_display_pt='{display['size_pt']}'",
        f"voluta_font_icon='{icon['family']}'",
        f"voluta_space_xs_px='{density['space_xs_px']}'",
        f"voluta_space_sm_px='{density['space_sm_px']}'",
        f"voluta_space_md_px='{density['space_md_px']}'",
        f"voluta_space_lg_px='{density['space_lg_px']}'",
        f"voluta_radius_sharp_px='{shape['radius_sharp_px']}'",
        f"voluta_radius_sm_px='{shape['radius_sm_px']}'",
        f"voluta_radius_md_px='{shape['radius_md_px']}'",
        f"voluta_radius_lg_px='{shape['radius_lg_px']}'",
        f"voluta_radius_xl_px='{shape['radius_xl_px']}'",
        f"voluta_glass_body_alpha='{int(glass['body_alpha'])}'",
        f"voluta_glass_chrome_alpha='{int(glass['chrome_alpha'])}'",
        f"voluta_glass_stripe_alpha='{int(glass['stripe_alpha'])}'",
        "",
    ])
    return "\n".join(lines)


def swaync_tokens_block(design):
    mono = design["typography"]["mono"]
    shape = design["shape"]
    return (
        f"    border-radius: {css_px(shape['radius_sharp_px'])};\n"
        f"    font-family: {css_font_stack(mono)};\n"
        f"    font-size: {css_pt(mono['size_pt'])};\n"
        f"    font-weight: 400;\n"
        f"    letter-spacing: 0;\n"
        f"    text-shadow: none;\n"
        f"    box-shadow: none;\n"
    )


def gsimplecal_font_block(design):
    ui = design["typography"]["ui"]
    return f"    font-family: {css_font_stack(ui)};\n"


def gtk_font_block(design):
    ui = design["typography"]["ui"]
    return (
        "/* Shared UI font from appearance.typography.ui */\n"
        "window, window.background, .background, headerbar, label, button, entry, menuitem {\n"
        f"    font-family: {css_font_stack(ui)};\n"
        "}\n"
    )


def apply_kitty_fonts(text, design):
    mono = design["typography"]["mono"]
    family = mono["family"]
    size = mono["size_pt"]
    size_text = str(int(size) if float(size).is_integer() else size)
    replacements = {
        r'^font_family\s+.*$': f'font_family      family="{family}" style="Regular"',
        r'^bold_font\s+.*$': f'bold_font        family="{family}" style="Bold"',
        r'^italic_font\s+.*$': f'italic_font      family="{family}" style="Italic"',
        r'^bold_italic_font\s+.*$': f'bold_italic_font family="{family}" style="Bold Italic"',
        r'^font_size\s+.*$': f"font_size        {size_text}",
    }
    for pattern, value in replacements.items():
        text = re.sub(pattern, value, text, count=1, flags=re.M)
    return text


def apply_rofi_fonts(text, design):
    mono = design["typography"]["mono"]
    family = mono["family"]

    def repl(match):
        prefix, old, size, suffix = match.group(1), match.group(2), match.group(3), match.group(4)
        bold = " Bold" if "Bold" in old or "bold" in old else ""
        return f'{prefix}{family}{bold} {size}{suffix}'

    return re.sub(
        r'(font:\s*")([^"]+?)(\d+(?:\.\d+)?)("\s*;)',
        repl,
        text,
    )


def load_design_from_settings(directory=None, host=None):
    from cli import config_home, hostname, resolve

    settings, _ = resolve(directory if directory is not None else config_home(), hostname(host))
    return resolve_design(settings.get("appearance", {}))
