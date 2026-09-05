#!/bin/sh
# Mark the main monitor as the Xwayland RandR "primary" output.
#
# Sway/wlroots never sets a RandR primary -- with a stock config, `xrandr` under
# Xwayland reports neither monitor as primary. Some X11 clients (game launchers,
# Steam, older toolkits) place their windows on, or read the geometry of, the
# primary output, so leaving it unset lands them on whichever screen happens to
# come first. Sway has no config directive for this, hence the exec_always.
#
# The connector name is looked up from the stable EDID identifier at runtime, so
# this keeps working if the monitors move to different ports.

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
