#!/bin/sh
# Clipboard history, through the launcher.
#
# cliphist stores every clipboard change (the `wl-paste --watch cliphist store`
# line in config.d/40-bindings.conf is the daemon half); this is the picker.
#
# Piped into `rofi -dmenu`, which reads ~/.config/rofi/config.rasi exactly like
# the $mod+d launcher does -- so this inherits the greyscale theme and there is
# no second UI to keep in sync. That is the whole reason it is a dmenu script
# rather than a GUI clipboard manager.
#
# The pipeline is cliphist's documented one, and each stage matters:
#   cliphist list    tab-separated "<id>\t<preview>" lines
#   rofi -dmenu      the chosen line, verbatim, including its id
#   cliphist decode  looks the id up and emits the ORIGINAL bytes -- which is
#                    why the preview being lossy (newlines collapsed, binary
#                    elided) does not corrupt what you paste
#   wl-copy          back onto the clipboard

set -eu

# -i case-insensitive. No -p prompt: the launcher shows none either.
sel=$(cliphist list | rofi -dmenu -i) || exit 0

# rofi exits 0 with empty output if the user accepts an empty filter.
[ -n "$sel" ] || exit 0

printf '%s' "$sel" | cliphist decode | wl-copy
