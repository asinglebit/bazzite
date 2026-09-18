#!/bin/sh
# Turns the bar off with `enabled = false` rather than hiding it, because a hidden bar
# keeps its layer surface and SwayFX goes on blurring an empty strip.
#
#   noctalia-bar-toggle.sh         -- flip every bar in `order`, bound to $mod+period
#   noctalia-bar-toggle.sh print   -- say which bars are on, change nothing
#
# It writes the same file the settings window writes, so the change outlives a restarted shell.

set -eu

case "${1:-toggle}" in
    toggle|print) mode="${1:-toggle}" ;;
    *) echo "usage: ${0##*/} [print]" >&2; exit 2 ;;
esac

state="${XDG_STATE_HOME:-$HOME/.local/state}/noctalia/settings.toml"

# Read the effective value, because settings.toml only holds what differs from the config.
bars=$(noctalia config export full | awk '
    /^[[:space:]]*\[/ {
        tbl = $0
        sub(/^[[:space:]]*\[[[:space:]]*/, "", tbl)
        sub(/[[:space:]]*\].*$/, "", tbl)
        collecting = 0
        next
    }
    # The exporter wraps long arrays, so read `order` to its closing bracket.
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

# A missing settings.toml means the shell never started, and inventing one would guess its version.
[ -f "$state" ] || { echo "${0##*/}: $state does not exist -- start noctalia once" >&2; exit 1; }

# One bar still on makes the keypress mean "off", so a mixed state collapses to all-off first.
if echo "$bars" | grep -qv ' off$'; then val=false; else val=true; fi
names=$(echo "$bars" | cut -d' ' -f1 | tr '\n' ' ')

# A rename, not an edit in place, because noctalia watches and a half-written file is a parse error.
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
