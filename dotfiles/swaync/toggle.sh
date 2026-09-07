#!/bin/sh
# Quick-toggle plumbing for swaync's buttons-grid.
#
# WHY A SCRIPT AND NOT AN INLINE COMMAND -- this is a bug fix, not tidying.
#
# swaync does not hand these strings to a shell. It expands the string itself
# and spawns an argv, and a one-liner carrying double quotes or a command
# substitution does not survive that. The previous version of config.json had
# the state queries inline, and every single time the control centre was opened
# the session log recorded
#
#     swaync[48806]: -g: -c: line 1: unexpected EOF while looking for matching `''
#     swaync[48807]: yes && echo true || echo false': -c: line 1: unexpected EOF ...
#
# -- the wifi and bluetooth `update-command`s being torn in half. Neither ever
# ran, so neither button ever reflected the radio: they both showed the
# `active: false` default, whatever the hardware was doing. The idle toggle
# looked fine only by luck, because its command happens to contain neither a
# double quote nor a $(...).
#
# So anything that needs quoting lives in a file. What config.json passes is
#
#     sh -c '<this script> <name> <verb>'
#
# which is one level of quoting, no substitution, and the shape proven to
# survive -- the same shape swaync/stats.sh is called with.
#
# Verbs:
#   state  print `true` or `false`, which is what update-command consumes.
#          swaync runs it on every visibility change of the panel, so the
#          buttons agree with the system even after a change made from a
#          terminal.
#   set    apply $SWAYNC_TOGGLE_STATE. swaync sets that to the state being
#          REQUESTED, not the state the toggle is in.

set -eu

name=${1:-}
verb=${2:-}
want=${SWAYNC_TOGGLE_STATE:-}

case "$name" in
wifi)
    # A radio toggle only: swaync's grid cannot show an SSID list. Choosing a
    # network is $mod+Shift+w or a right-click on the bar's network glyph, both
    # of which run sway/rofi-wifi.sh through the already-themed rofi.
    case "$verb" in
        state) [ "$(nmcli -g WIFI radio 2>/dev/null)" = enabled ] && echo true || echo false ;;
        set)   if [ "$want" = true ]; then nmcli radio wifi on; else nmcli radio wifi off; fi ;;
        *)     exit 1 ;;
    esac
    ;;
bluetooth)
    # bluetoothctl rather than rfkill. rfkill does work unprivileged here --
    # logind's uaccess ACL grants the active seat user rw on /dev/rfkill -- but
    # only while the seat IS active, whereas bluetoothctl talks to BlueZ over
    # D-Bus with polkit behind it, which is the path blueman-manager uses too.
    case "$verb" in
        state) bluetoothctl show 2>/dev/null | grep -q 'Powered: yes' && echo true || echo false ;;
        set)   if [ "$want" = true ]; then bluetoothctl power on >/dev/null
               else bluetoothctl power off >/dev/null; fi ;;
        *)     exit 1 ;;
    esac
    ;;
idle)
    # Idle management: auto-lock and display blanking, i.e. hypridle. Checked
    # means the unit is running. Unchecking it is the "do not lock while I watch
    # this" switch, and because it stops the unit rather than holding a Wayland
    # inhibitor it survives the video player exiting -- and a waybar restart,
    # which is why this is the one that stayed when the bar's idle_inhibitor
    # module was dropped. This is now the only idle control on the desktop.
    case "$verb" in
        state) systemctl --user is-active --quiet hypridle && echo true || echo false ;;
        set)   if [ "$want" = true ]; then systemctl --user start hypridle
               else systemctl --user stop hypridle; fi ;;
        *)     exit 1 ;;
    esac
    ;;
*)
    # An unknown name still has to answer `state` with something parseable.
    [ "$verb" = state ] && echo false || exit 1
    ;;
esac
