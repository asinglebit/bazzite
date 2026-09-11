#!/bin/sh
# Per-screen workspace blocks.
#
# Every screen owns ten workspaces: the Nth screen from the left (0-based) owns
# N*10+1 .. N*10+10. So $mod+1..0 always means "this screen's 1..10" and a
# number key never moves focus to the other monitor. Which screen is which is
# worked out from `swaymsg -t get_outputs` at the moment the key is pressed --
# nothing here knows what is plugged in, there is no cache to go stale, and
# 10-outputs.conf pins no workspace to any monitor.
#
#   workspace-block.sh switch <1-10>   -- $mod+N
#   workspace-block.sh move   <1-10>   -- $mod+Shift+N, moves AND follows
#   workspace-block.sh print  <1-10>   -- the number those two would use; no IPC writes
#   workspace-block.sh reconcile [id]  -- startup and reload, see 10-outputs.conf
#
# jq, not the inline python3 that xwayland-primary.sh uses. That one runs once
# per session so an interpreter start costs nothing; this one runs on every
# workspace keypress, where python3 measures 17ms against jq's 5ms.

set -eu

usage() {
    echo "usage: ${0##*/} switch|move|print <1-10> | reconcile [identifier]" >&2
    exit 2
}

# Sorting is the whole rule, not a tidy-up: get_outputs does NOT reply in
# left-to-right order (on this desk it returns the right-hand screen first).
#
# select(.active) is the ONLY filter it may have. A screen asleep on the idle
# timeout stays active:true with its position intact, so filtering on .dpms
# would renumber every block the moment a screen blanks. A disabled screen is
# active:false with a zeroed rect, and a non-desktop screen (a VR headset)
# carries no "active" key at all -- both drop out here, neither shifts an index.
OUTPUTS='[ .[] | select(.active) ] | sort_by(.rect.x, .rect.y, .name)'

case "${1:-}" in
switch|move|print)
    case "${2:-}" in [1-9]|10) ;; *) usage ;; esac

    # Empty if sway is unreachable, if jq is missing, or if no screen holds
    # focus mid-hotplug. Handled below rather than here.
    spec=$(swaymsg -t get_outputs -r 2>/dev/null | jq -r --argjson n "$2" "
        $OUTPUTS
        | (map(.focused) | index(true)) as \$i
        | select(\$i != null)
        | \"ws=\(\$i * 10 + \$n) out=\(.[\$i].name | @sh)\"
    " 2>/dev/null) || spec=""

    if [ "$1" = print ]; then
        # For verify.sh, which computes the same number independently and fails
        # if the two disagree. Silence is the answer when there is no focus.
        [ -n "$spec" ] || exit 0
        eval "$spec"
        echo "$ws"
        exit 0
    fi

    if [ -n "$spec" ]; then
        eval "$spec"
        # --no-auto-back-and-forth on every generated command. The setting is
        # off in this image, but if it were ever on, $mod+N pressed on the
        # workspace you are already on would jump to the PREVIOUS one, possibly
        # on the other screen -- and the repair below would then drag that
        # screen's workspace across. The flag makes the invariant independent
        # of a setting nothing here controls.
        #
        # The trailing `move workspace to output` is what makes "a number key
        # never leaves this screen" actually true, and is why no static pins are
        # needed. If the workspace had drifted -- sway's own startup numbering, a
        # screen unplugged and replugged, anything left from the old 1-5/6-10
        # split -- this pulls it home instead of throwing focus at the other
        # monitor. sway returns early when it is already there, which is the
        # normal case, so it costs nothing.
        #
        # It must come LAST: it acts on the FOCUSED workspace, so before the
        # switch it would target the workspace being left.
        cmd="workspace --no-auto-back-and-forth number $ws; move workspace to output \"$out\""
        [ "$1" = switch ] ||
            cmd="move --no-auto-back-and-forth container to workspace number $ws; $cmd"
    else
        # Never a dead key. A wrong screen is recoverable by pressing another
        # key; a binding that does nothing at all leaves no way to say so. This
        # is the stock binding from /etc/sway/config that these twenty replaced.
        cmd="workspace --no-auto-back-and-forth number $2"
        [ "$1" = switch ] ||
            cmd="move --no-auto-back-and-forth container to workspace number $2; $cmd"
    fi
    ;;
reconcile)
    outs=$(swaymsg -t get_outputs    -r 2>/dev/null) || exit 0
    wss=$( swaymsg -t get_workspaces -r 2>/dev/null) || exit 0

    # Fresh session or a reload? The marker is named after this sway instance's
    # IPC socket, so it cannot outlive the compositor that wrote it. On the
    # first run focus finishes on the screen named by $2 -- the job the old
    # `swaymsg 'workspace 6; workspace 1'` line did. On a reload it finishes
    # where it started, because yanking focus on every reload is the reason
    # that line was `exec` rather than `exec_always`.
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

        # Strays first, so the pass below never has to focus a workspace that is
        # still on the wrong screen. num is -1 for a named workspace, and
        # anything above 10*N is orphaned from a screen that is gone: both are
        # left alone rather than dragged somewhere arbitrary.
        | [ \$ws[]
            | select(.num >= 1 and .num <= \$n * 10)
            | ((.num - 1) / 10 | floor) as \$home
            | select(.output != \$o[\$home].name)
            | \"workspace --no-auto-back-and-forth number \(.num); move workspace to output \\\"\(\$o[\$home].name)\\\"\" ] as \$sweep

        # Then any screen showing a workspace that is not its own. sway names
        # the workspace it auto-creates on a screen after the lowest free
        # NUMBER unless a pin or a literal \`workspace <n>\` binding claims one,
        # and this config now has neither -- the bindings are \`exec\`, which
        # that scan cannot read -- so at startup the second screen comes up
        # owning \"2\", a number from the first screen's block. \`focus output\`
        # comes first because \`workspace number\` creates on the FOCUSED screen.
        # A screen already showing one of its own is not touched, which is what
        # makes a reload a no-op.
        | [ range(0; \$n) as \$i
            | ([ \$ws[] | select(.output == \$o[\$i].name and .visible) | .num ] | first) as \$cur
            | select(\$cur == null or \$cur < \$i * 10 + 1 or \$cur > \$i * 10 + 10)
            | ([ \$ws[] | select(.num >= \$i * 10 + 1 and .num <= \$i * 10 + 10) | .num ] | sort | first) as \$pick
            | \"focus output \\\"\(\$o[\$i].name)\\\"; workspace --no-auto-back-and-forth number \(\$pick // (\$i * 10 + 1))\" ] as \$seed

        # Where focus ends. The wanted screen is matched on EDID identifier, the
        # way 10-outputs.conf names a monitor, because \`focus output\` takes a
        # connector name and connectors re-enumerate. Not connected, or a
        # reload: back where focus already was.
        | ([ \$o[] | select(.make + \" \" + .model + \" \" + .serial == \$want) | .name ] | first) as \$main
        | ((\$o[] | select(.focused) | .name) // \$o[0].name) as \$here
        | (\$sweep + \$seed) as \$work
        | select((\$work | length) > 0 or \$main != null)
        | (\$work + [ \"focus output \\\"\(\$main // \$here)\\\"\" ])
        | join(\"; \")
    " 2>/dev/null) || cmd=""

    # Nothing had drifted and no screen to land on: a reload in steady state.
    [ -n "$cmd" ] || exit 0
    ;;
*)
    usage
    ;;
esac

# ONE swaymsg payload, never two. sway runs a whole command list inside a single
# event-loop iteration and commits one transaction after it, so the frame where
# focus passes through the other screen to collect a drifted workspace is never
# drawn. Two calls would draw it.
#
# Only CMD_INVALID -- an unknown command or a bad argument -- aborts the rest of
# a list. One that parses and then fails ("Can't move an empty workspace",
# "Can't switch workspaces while fullscreen global") is CMD_FAILURE and the list
# carries on, which is what makes these sequences safe to fire blind.
exec swaymsg -q -- "$cmd"
