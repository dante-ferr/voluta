#!/usr/bin/env python3
"""Emit the wallust starship template with literal Nerd Font glyphs."""

TARGET = "/home/dante/imperivm-dotfiles/wallust/templates/colors-starship.toml"
# The config carries no palette placeholders any more, so the template and the
# live config are byte identical and this script can install both. Do not round
# trip prompt edits through `wallust cs`: that reapplies whichever colourscheme
# you name to every other target as well.
LIVE = "/home/dante/.config/starship.toml"

GLYPHS = {
    "@L@": "\ue0ba",          # slanted left cap
    "@R@": "\ue0bc",          # slanted right cap
    "@SEP@": "\ue0bb",        # thin slanted divider
    "@BRANCH@": "\ue0a0",     # powerline branch
    "@HOME@": "\uf19c",       # classical temple
    "@DESKTOP@": "\uf108",
    "@DOCS@": "\uf0f6",
    "@DOWNLOADS@": "\uf019",
    "@MUSIC@": "\uf001",
    "@PICTURES@": "\uf03e",
    "@VIDEOS@": "\uf008",
    "@PYTHON@": "\ue73c",
    "@NODE@": "\ue718",
    "@RUST@": "\ue7a8",
    "@GO@": "\ue626",
    "@LUA@": "\ue620",
    "@C@": "\ue61e",
    "@SHIELD@": "\uf132",
    "@SWORDS@": "\U000f0787",
    "@WARN@": "\uf071",
    "@PENCIL@": "\uf040",
    "@PLUS@": "\uf067",
    "@MINUS@": "\uf068",
    "@ARCHIVE@": "\uf187",
    "@USER@": "\U000f0018",
    "@HOST@": "\U000f048b",
    "@LOCK@": "\U000f033e",
    "@TIMER@": "\U000f051f",
    "@CLOCK@": "\U000f0954",
    "@VIM@": "\U000f02a0",
    "@CONDA@": "\U000f01a7",
}

TEMPLATE = r'''# /* wallust template - colors-starship */
# Starship Prompt - Dynamic Wallust Palette (Roman Imperium Cyber-Sacred Rice)
#
# Colours are ANSI palette indices, not hex, so the prompt follows the terminal
# palette live: after a wallpaper change wallust pushes the new colours to kitty
# and the whole scrollback recolours at once. Baked-in hex would leave every
# prompt already on screen stuck on the previous theme.
#
# NOTE: the separators/icons are Nerd Font glyphs, several of them in the
# private use area. Editors that strip those codepoints will silently gut the
# powerline caps, so regenerate this file rather than retyping the symbols.

add_newline = true
command_timeout = 5000
continuation_prompt = "[- ](bold fg:{{color5}})"

format = """
$username\
$hostname\
$directory\
$git_branch\
$git_status\
$git_state\
$conda\
$python\
$nodejs\
$rust\
$golang\
$lua\
$c\
$fill\
$cmd_duration\
$time\
$line_break\
$character"""

# Rule joining the left insignia to the right chronometer
[fill]
symbol = "-"
style = "fg:{{color6}}"

# Prompt Symbols
[character]
success_symbol = "[/ SPQR](bold fg:{{color1}})[ >](bold fg:{{color15}})"
error_symbol = "[x SPQR](bold fg:{{color15}})[ >](bold fg:{{color1}})"
vimcmd_symbol = "[@VIM@ SPQR](bold fg:{{color7}})[ <](bold fg:{{color15}})"

# User & Host
[username]
show_always = false
style_user = "bold fg:{{background}} bg:{{color2}}"
style_root = "bold fg:{{background}} bg:{{color2}}"
format = "[@L@](fg:{{color2}})[ @USER@ $user ]($style)[@R@](fg:{{color2}}) "
disabled = false

[hostname]
ssh_only = true
style = "bold fg:{{background}} bg:{{color2}}"
format = "[@L@](fg:{{color2}})[ @HOST@ $hostname ]($style)[@R@](fg:{{color2}}) "
disabled = false

# Directory / Arx
[directory]
truncation_length = 4
truncation_symbol = ".../"
home_symbol = "@HOME@ ~"
read_only = "@LOCK@ "
read_only_style = "bold fg:{{background}} bg:{{color1}}"
style = "bold fg:{{background}} bg:{{color1}}"
format = "[@L@](fg:{{color1}})[ $path ]($style)[$read_only]($read_only_style)[@R@](fg:{{color1}}) "

[directory.substitutions]
"Desktop" = "@DESKTOP@ Desktop"
"Documents" = "@DOCS@ Documents"
"Downloads" = "@DOWNLOADS@ Downloads"
"Music" = "@MUSIC@ Music"
"Pictures" = "@PICTURES@ Pictures"
"Videos" = "@VIDEOS@ Videos"

# Git Branch / Cohors
[git_branch]
symbol = "@BRANCH@"
style = "bold fg:{{background}} bg:{{color2}}"
format = "[@L@](fg:{{color2}})[ $symbol $branch ]($style)"

# Git Status / Tactical Military & Archival Indicators
# The closing cap lives here so the branch pill stays sealed on clean trees.
[git_status]
style = "bold fg:{{background}} bg:{{color2}}"
format = '([@SEP@](fg:{{color6}} bg:{{color2}})[ $all_status$ahead_behind]($style))[@R@](fg:{{color2}}) '
conflicted = "X ${count} "
ahead = "^ ${count} "
behind = "v ${count} "
diverged = "^ ${ahead_count} v ${behind_count} "
untracked = "? ${count} "
modified = "! ${count} "
staged = "+ ${count} "
renamed = "> ${count} "
deleted = "- ${count} "
stashed = "* ${count} "

[git_state]
style = "bold fg:{{background}} bg:{{color1}}"
format = '[@L@](fg:{{color1}})[ $state( $progress_current/$progress_total) ]($style)[@R@](fg:{{color1}}) '

# Command Duration / Celeritas
[cmd_duration]
min_time = 2000
style = "bold fg:{{background}} bg:{{color2}}"
format = "[@L@](fg:{{color2}})[ @TIMER@ $duration ]($style)[@R@](fg:{{color2}}) "

# Chronometer / Horologium
[time]
disabled = false
time_format = "%H:%M"
style = "bold fg:{{color15}} bg:{{color6}}"
format = "[@L@](fg:{{color6}})[ @CLOCK@ $time ]($style)[@R@](fg:{{color6}})"

# Package / Languages
[package]
disabled = true

[conda]
symbol = "@CONDA@"
style = "bold fg:{{color1}}"
format = "[$symbol]($style)[ $environment ](fg:{{color7}}) "

[lua]
symbol = "@LUA@"
style = "bold fg:{{color1}}"
format = "[$symbol]($style)[ $version ](fg:{{color7}}) "

[python]
symbol = "@PYTHON@"
style = "bold fg:{{color1}}"
format = "[$symbol]($style)[ $version ](fg:{{color7}}) "

[nodejs]
symbol = "@NODE@"
style = "bold fg:{{color1}}"
format = "[$symbol]($style)[ $version ](fg:{{color7}}) "

[golang]
symbol = "@GO@"
style = "bold fg:{{color1}}"
format = "[$symbol]($style)[ $version ](fg:{{color7}}) "

[rust]
symbol = "@RUST@"
style = "bold fg:{{color1}}"
format = "[$symbol]($style)[ $version ](fg:{{color7}}) "

[c]
symbol = "@C@"
style = "bold fg:{{color1}}"
format = "[$symbol]($style)[ $version ](fg:{{color7}}) "
'''

# Symbols outside the private use area, kept here so the source stays ASCII.
TEXT_SYMBOLS = {
    'continuation_prompt = "[- ]': 'continuation_prompt = "[\u25b8\u25b8 ]',
    'symbol = "-"': 'symbol = "\u2500"',
    'truncation_symbol = ".../"': 'truncation_symbol = "\u2026/"',
    '"[/ SPQR]': '"[@SHIELD@ SPQR]',
    '"[x SPQR]': '"[@SWORDS@ SPQR]',
    '[ >](bold fg:{{color1}})': '[ \u276f](bold fg:{{color1}})',
    '[ >](bold fg:{{color15}})': '[ \u276f](bold fg:{{color15}})',
    '[ <](bold fg:{{color15}})': '[ \u276f](bold fg:{{color15}})',
    'conflicted = "X ': 'conflicted = "@WARN@ ',
    'ahead = "^ ': 'ahead = "\u21e1',
    'behind = "v ': 'behind = "\u21e3',
    'diverged = "^ ${ahead_count} v ${behind_count} "':
        'diverged = "\u21e1${ahead_count} \u21e3${behind_count} "',
    'untracked = "? ': 'untracked = "\u25c8 ',
    'modified = "! ': 'modified = "@PENCIL@ ',
    'staged = "+ ': 'staged = "@PLUS@ ',
    'renamed = "> ': 'renamed = "\u00bb ',
    'deleted = "- ': 'deleted = "@MINUS@ ',
    'stashed = "* ': 'stashed = "@ARCHIVE@ ',
}

# Emit ANSI palette indices rather than letting wallust bake in hex. Hex is
# absolute, so prompts already on screen keep their old colours forever and only
# repaint on the next render; indices are resolved by the terminal, so a
# `kitty @ set-colors` after a wallpaper change recolours the entire scrollback
# at once, the same way the fetch banner does.
PALETTE_TO_ANSI = {
    "{{background}}": "0",
    "{{foreground}}": "7",
    "{{color0}}": "0",
    "{{color1}}": "1",
    "{{color2}}": "2",
    "{{color3}}": "3",
    "{{color4}}": "4",
    "{{color5}}": "5",
    "{{color6}}": "6",
    "{{color7}}": "7",
    "{{color15}}": "15",
}

out = TEMPLATE
for token, glyph in TEXT_SYMBOLS.items():
    if token not in out:
        raise SystemExit("missing text token: " + token)
    out = out.replace(token, glyph)
for token, glyph in GLYPHS.items():
    out = out.replace(token, glyph)
for token, index in PALETTE_TO_ANSI.items():
    out = out.replace(token, index)
if "{{" in out:
    raise SystemExit("unresolved template token: " + out[out.index("{{"):][:40])

import os

for path in (TARGET, LIVE):
    if path is LIVE and not os.path.exists(path):
        continue
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(out)
    print("wrote", path)
