#!/bin/sh
# Dolphin's embedded terminal. Kitty is unchanged.
here=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
export STARSHIP_CONFIG="$here/starship.toml"
exec zsh
