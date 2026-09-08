#!/bin/sh
# Mark the main monitor as the Xwayland RandR primary output.
#
# wlroots never sets one, so X11 clients that place windows on the primary
# output (game launchers, Steam, older toolkits) land wherever enumeration puts
# them. Sway has no directive for this, hence exec_always.
#
# The connector is looked up from the EDID identifier at runtime, so this
# survives the monitors moving ports.

set -eu

IDENT='Dell Inc. DELL U2718Q FN84K78S04DL'

# No X server for this session -- nothing to do.
[ -n "${DISPLAY:-}" ] || exit 0

name=$(swaymsg -t get_outputs -r | python3 -c "
import json, sys
want = sys.argv[1]
for o in json.load(sys.stdin):
    if o['make'] + ' ' + o['model'] + ' ' + o['serial'] == want:
        print(o['name'])
        break
" "$IDENT")

# Monitor not currently connected -- leave whatever Xwayland decided alone.
[ -n "$name" ] || exit 0

exec xrandr --output "$name" --primary
