#!/usr/bin/env bash
# fetch.sh - Smart responsive Fastfetch runner with 100% original aspect ratio & colors

# Below this the info box wraps into a mess, so nothing is printed at all. zshrc
# reads the same two variables for its banner bookkeeping, so keep the names and
# the defaults in step with it.
MIN_COLS=${IMPERIUM_FETCH_MIN_COLS:-60}
MIN_LINES=${IMPERIUM_FETCH_MIN_LINES:-20}
FORCE=0
[[ "$1" == "--force" ]] && FORCE=1

# Ask the tty itself rather than trusting COLUMNS/LINES, which can be inherited
# stale from whatever spawned this and would then describe the wrong window.
TERM_COLS="" TERM_LINES=""
if size=$(stty size </dev/tty 2>/dev/null); then
    TERM_LINES=${size%% *}
    TERM_COLS=${size##* }
fi
[[ $TERM_COLS =~ ^[0-9]+$ && $TERM_COLS -gt 0 ]] || TERM_COLS=$(tput cols 2>/dev/null || echo 100)
[[ $TERM_LINES =~ ^[0-9]+$ && $TERM_LINES -gt 0 ]] || TERM_LINES=$(tput lines 2>/dev/null || echo 30)

if (( ! FORCE )) && (( TERM_COLS < MIN_COLS || TERM_LINES < MIN_LINES )); then
    exit 0
fi

CONFIG_FILE="$HOME/.config/fastfetch/config.jsonc"
ORIGINAL_IMG="$HOME/imperivm-dotfiles/fastfetch/assets/crown-angels.jpg"
[[ ! -f "$ORIGINAL_IMG" ]] && ORIGINAL_IMG="$HOME/.config/fastfetch/assets/crown-angels.jpg"

# Widest line the modules draw, which is the box rule in config.jsonc, and the
# gap that config keeps between the logo and it. The image gets the columns left
# over from these two; take one away and the box folds onto a second line.
BOX_COLS=56
LOGO_PAD=3
LOGO_ROWS=13

# How many columns the logo lands in. fastfetch scales the picture to LOGO_ROWS
# rows worth of pixels, keeps its aspect ratio, and divides back by the width of
# a cell, so the answer moves with the terminal font and not just with the file.
# This is that same arithmetic, off the pixel geometry fastfetch itself reads
# from the tty; a fixed column count could only ever be right for one font, and
# the one that was here let the image into windows too narrow to hold it.
logo_columns() {
    python3 - "$1" "$LOGO_ROWS" <<'PY' 2>/dev/null
import fcntl
import math
import struct
import sys
import termios


def image_pixels(path):
    with open(path, 'rb') as image:
        header = image.read(24)
        if header[:8] == b'\x89PNG\r\n\x1a\n':
            width, height = struct.unpack('>II', header[16:24])
            return width, height
        if header[:2] != b'\xff\xd8':
            raise ValueError('neither png nor jpeg')
        # Walk the JPEG segments to the frame header, the one that carries the
        # dimensions, skipping each segment by the length it declares.
        image.seek(2)
        while True:
            marker = image.read(2)
            if len(marker) < 2 or marker[0] != 0xFF:
                raise ValueError('no frame header')
            length = struct.unpack('>H', image.read(2))[0]
            if 0xC0 <= marker[1] <= 0xCF and marker[1] not in (0xC4, 0xC8, 0xCC):
                height, width = struct.unpack('>HH', image.read(5)[1:])
                return width, height
            image.seek(length - 2, 1)


with open('/dev/tty') as tty:
    rows, columns, x_pixels, y_pixels = struct.unpack(
        'HHHH', fcntl.ioctl(tty, termios.TIOCGWINSZ, b'\0' * 8))

# A terminal that reports no pixel geometry gives fastfetch nothing to scale
# against either, so it would not draw the image in the first place.
if not (x_pixels and y_pixels):
    sys.exit(1)

cell_width = x_pixels / columns
cell_height = y_pixels / rows
width, height = image_pixels(sys.argv[1])
logo_pixel_width = math.ceil(int(sys.argv[2]) * cell_height) * width / height
print(math.ceil(logo_pixel_width / cell_width))
PY
}

if [[ ! -f "$ORIGINAL_IMG" ]]; then
    fastfetch --config "$CONFIG_FILE"
    exit
fi

LOGO_COLS=$(logo_columns "$ORIGINAL_IMG")
# Nothing answered, so fall back to what the shipped 16:9 asset needs in a cell
# twice as tall as it is wide, which is a terminal font give or take.
[[ $LOGO_COLS =~ ^[0-9]+$ ]] || LOGO_COLS=47

if (( TERM_COLS < LOGO_COLS + LOGO_PAD + BOX_COLS )); then
    fastfetch --config "$CONFIG_FILE" --logo-type none
else
    # Height alone, so the width follows from the file's own proportions.
    fastfetch --config "$CONFIG_FILE" --logo "$ORIGINAL_IMG" --logo-type kitty --logo-height "$LOGO_ROWS"
fi
