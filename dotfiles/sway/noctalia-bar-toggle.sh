#!/bin/sh
# Turns the bar off the way noctalia's settings window does -- `enabled = false` --
# rather than hiding it. A hidden bar keeps its layer surface, and SwayFX goes on
# blurring that surface, so the strip stays frosted with nothing drawn in it;
# disabled, the surface is gone and the top edge is just the wallpaper again.
#
#   noctalia-bar-toggle.sh         -- flip every bar in `order`, bound to $mod+period
#   noctalia-bar-toggle.sh print   -- say which bars are on, change nothing
#
# It writes the same file the settings window writes. noctalia watches that file
# and applies the change within a second, so the setting outlives a restarted
# shell -- unlike `noctalia msg bar-toggle`, which is runtime only.

set -eu

case "${1:-toggle}" in
    toggle|print) mode="${1:-toggle}" ;;
    *) echo "usage: ${0##*/} [print]" >&2; exit 2 ;;
esac

state="${XDG_STATE_HOME:-$HOME/.local/state}/noctalia/settings.toml"

# Read the effective value rather than that file, because settings.toml only holds
# what differs from ~/.config/noctalia/*.toml: a bar nobody has touched has no
# `enabled` key anywhere, and the default is on.
bars=$(noctalia config export full | awk '
    /^[[:space:]]*\[/ {
        tbl = $0
        sub(/^[[:space:]]*\[[[:space:]]*/, "", tbl)
        sub(/[[:space:]]*\].*$/, "", tbl)
        collecting = 0
        next
    }
    # The exporter wraps a long array over several lines, so read `order` to its
    # closing bracket instead of off the one line.
    tbl == "bar" && /^[[:space:]]*order[[:space:]]*=/ { collecting = 1 }
    collecting {
        n = split($0, q, "\"")
        for (i = 2; i <= n; i += 2) name[++count] = q[i]
        if (index($0, "]")) collecting = 0
        next
    }
    tbl ~ /^bar\./ && /^[[:space:]]*enabled[[:space:]]*=/ {
        v = $0
        sub(/^[^=]*=[[:space:]]*/, "", v)
        sub(/[[:space:]].*$/, "", v)
        on[substr(tbl, 5)] = v
    }
    END { for (i = 1; i <= count; i++) print name[i] (on[name[i]] == "false" ? " off" : " on") }
')

[ -n "$bars" ] || { echo "${0##*/}: noctalia reports no bars in \`order\`" >&2; exit 1; }

if [ "$mode" = print ]; then
    echo "$bars"
    exit 0
fi

# noctalia writes settings.toml itself on first run, so a missing one means the shell
# has never started; inventing it here would guess at the config_version it stamps on top.
[ -f "$state" ] || { echo "${0##*/}: $state does not exist -- start noctalia once" >&2; exit 1; }

# One bar still on is enough to make the keypress mean "off", so a half-and-half
# state collapses to all-off on the first press and all-on on the second.
if echo "$bars" | grep -qv ' off$'; then val=false; else val=true; fi
names=$(echo "$bars" | cut -d' ' -f1 | tr '\n' ' ')

# A rename rather than an edit in place, because noctalia is watching: a half-written
# file is a parse error that costs the whole settings layer.
tmp=$(mktemp "$state.XXXXXX")
trap 'rm -f "$tmp"' EXIT
awk -v names="$names" -v val="$val" '
    BEGIN { split(names, a, " "); for (i in a) if (a[i] != "") want["bar." a[i]] = 1 }
    /^[[:space:]]*\[/ {
        print
        tbl = $0
        sub(/^[[:space:]]*\[[[:space:]]*/, "", tbl)
        sub(/[[:space:]]*\].*$/, "", tbl)
        match($0, /^[[:space:]]*/)
        here = (tbl in want)
        # noctalia indents a key to match its own table header, so copy that.
        if (here) { print substr($0, 1, RLENGTH) "enabled = " val; seen[tbl] = 1 }
        next
    }
    # The old key, replaced by the one written just above it.
    here && /^[[:space:]]*enabled[[:space:]]*=/ { next }
    { print }
    END { for (t in want) if (!(t in seen)) printf "\n[%s]\nenabled = %s\n", t, val }
' "$state" > "$tmp"

chmod --reference="$state" "$tmp"
mv -- "$tmp" "$state"
trap - EXIT
