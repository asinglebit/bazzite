#!/bin/sh
# Marks the main monitor as the Xwayland primary, so X11 apps like Steam open on it.
# wlroots never sets one and sway has no directive for it, hence exec_always.

set -eu

IDENT='Dell Inc. DELL U2718Q FN84K78S04DL'

# No X server this session, so there is nothing to do.
[ -n "${DISPLAY:-}" ] || exit 0

name=$(swaymsg -t get_outputs -r | python3 -c "
import json, sys
want = sys.argv[1]
for o in json.load(sys.stdin):
    if o['make'] + ' ' + o['model'] + ' ' + o['serial'] == want:
        print(o['name'])
        break
" "$IDENT")

# Monitor is unplugged, so leave whatever Xwayland picked.
[ -n "$name" ] || exit 0

exec xrandr --output "$name" --primary
