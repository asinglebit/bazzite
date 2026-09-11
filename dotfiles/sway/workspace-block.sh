#!/bin/sh
# Gives every screen its own $mod+1..0: the leftmost screen owns workspaces
# 1-10, the next owns 11-20, and so on, worked out fresh on every keypress.
#
#   workspace-block.sh switch <1-10>   -- $mod+N
#   workspace-block.sh move   <1-10>   -- $mod+Shift+N, moves the window and follows it
#   workspace-block.sh print  <1-10>   -- says which workspace it would pick, changes nothing
#   workspace-block.sh reconcile [id]  -- tidy-up at startup and reload, see 10-outputs.conf
#
# jq rather than python3, because python needs 17ms to start against jq's 5ms.

set -eu

usage() {
    echo "usage: ${0##*/} switch|move|print <1-10> | reconcile [identifier]" >&2
    exit 2
}

# Screens sorted left to right; a sleeping one still counts, a switched-off one does not.
OUTPUTS='[ .[] | select(.active) ] | sort_by(.rect.x, .rect.y, .name)'

case "${1:-}" in
switch|move|print)
    case "${2:-}" in [1-9]|10) ;; *) usage ;; esac

    # Empty if sway cannot be reached or no screen has focus.
    spec=$(swaymsg -t get_outputs -r 2>/dev/null | jq -r --argjson n "$2" "
        $OUTPUTS
        | (map(.focused) | index(true)) as \$i
        | select(\$i != null)
        | \"ws=\(\$i * 10 + \$n) out=\(.[\$i].name | @sh)\"
    " 2>/dev/null) || spec=""

    if [ "$1" = print ]; then
        [ -n "$spec" ] || exit 0
        eval "$spec"
        echo "$ws"
        exit 0
    fi

    if [ -n "$spec" ]; then
        eval "$spec"
        # The last command drags the workspace back here if it had wandered to the other screen.
        cmd="workspace --no-auto-back-and-forth number $ws; move workspace to output \"$out\""
        [ "$1" = switch ] ||
            cmd="move --no-auto-back-and-forth container to workspace number $ws; $cmd"
    else
        # Fall back to the plain old binding, so the key is never dead.
        cmd="workspace --no-auto-back-and-forth number $2"
        [ "$1" = switch ] ||
            cmd="move --no-auto-back-and-forth container to workspace number $2; $cmd"
    fi
    ;;
reconcile)
    outs=$(swaymsg -t get_outputs    -r 2>/dev/null) || exit 0
    wss=$( swaymsg -t get_workspaces -r 2>/dev/null) || exit 0

    # Only the first run of a session jumps to the screen named by $2; a reload leaves focus alone.
    marker="${SWAYSOCK:-${XDG_RUNTIME_DIR:-/tmp}/sway}.blocks-seeded"
    if [ -e "$marker" ]; then
        want=""
    else
        want="${2:-}"
        : > "$marker" 2>/dev/null || true
    fi

    cmd=$(printf '%s' "$outs" | jq -r --argjson ws "$wss" --arg want "$want" "
        ($OUTPUTS) as \$o
        | (\$o | length) as \$n
        | select(\$n > 0)

        # Send any workspace sitting on the wrong screen back to its own.
        | [ \$ws[]
            | select(.num >= 1 and .num <= \$n * 10)
            | ((.num - 1) / 10 | floor) as \$home
            | select(.output != \$o[\$home].name)
            | \"workspace --no-auto-back-and-forth number \(.num); move workspace to output \\\"\(\$o[\$home].name)\\\"\" ] as \$sweep

        # Then give any screen showing someone else's workspace one of its own.
        | [ range(0; \$n) as \$i
            | ([ \$ws[] | select(.output == \$o[\$i].name and .visible) | .num ] | first) as \$cur
            | select(\$cur == null or \$cur < \$i * 10 + 1 or \$cur > \$i * 10 + 10)
            | ([ \$ws[] | select(.num >= \$i * 10 + 1 and .num <= \$i * 10 + 10) | .num ] | sort | first) as \$pick
            | \"focus output \\\"\(\$o[\$i].name)\\\"; workspace --no-auto-back-and-forth number \(\$pick // (\$i * 10 + 1))\" ] as \$seed

        # The wanted screen is named by monitor identifier, the way 10-outputs.conf names one.
        | ([ \$o[] | select(.make + \" \" + .model + \" \" + .serial == \$want) | .name ] | first) as \$main
        | ((\$o[] | select(.focused) | .name) // \$o[0].name) as \$here
        | (\$sweep + \$seed) as \$work
        | select((\$work | length) > 0 or \$main != null)
        | (\$work + [ \"focus output \\\"\(\$main // \$here)\\\"\" ])
        | join(\"; \")
    " 2>/dev/null) || cmd=""

    # Nothing had drifted, so there is nothing to do.
    [ -n "$cmd" ] || exit 0
    ;;
*)
    usage
    ;;
esac

# One payload, so sway shows the finished result instead of each step on the way.
exec swaymsg -q -- "$cmd"
