#!/bin/sh
# Hardware readout for waybar's custom/hardware module.
#
# cpu, memory and temperature used to be three text labels on the bar, behind a
# hover drawer -- about a fifth of the right-hand side spent saying "everything
# is fine". They are one glyph now, and the numbers are in its tooltip.
#
# WHY NOT IN THE NOTIFICATION PANEL, which is where they were meant to go and
# where the volume slider and the radio toggles live: swaync 0.12.6 cannot
# render a live number. `label` is a static string from config.json with no
# runtime setter, and `slider` -- whose cmd_getter is documented as running on
# every visibility change, which would have been exactly right -- runs the
# command and then discards the result. Verified rather than assumed: a getter
# that touched a file proved it runs, and gauges fed `echo 25`, `printf 40` and
# `echo 100` in both 0-100 and 0-1 ranges all stayed pinned at the minimum.
# swaync/config.json carries the same note next to the widget list, and the
# `cpu`/`mem`/`temp` verbs below still print exactly what a 0-100 slider would
# want, so a later swaync that fixes it needs no new code here.
#
# Verbs: cpu | mem | temp print one integer. json prints the waybar object --
# text, tooltip and a class for the alert states.
#
# Nothing here sleeps, forks a pipeline, or shells out to anything but awk:
# `json` runs on waybar's interval, forever.

set -eu

# Load average per core, not an instantaneous sample. An instantaneous figure
# means reading /proc/stat twice a fraction of a second apart, and every one of
# those fractions is a sleep on the bar's own thread. The 1-minute average costs
# one read of one file, and for a glance -- "is something eating this machine?"
# -- it is the steadier number anyway. That does mean this reads near zero on an
# idle 24-thread box, and near zero is the truth; the raw load figures are in
# the tooltip next to it so the number can be checked against something.
#
# Clamped at 100: load can exceed core count, a gauge or a percentage cannot.
cpu_pct() {
    awk -v n="$(nproc)" '{ v = $1 / n * 100; if (v > 100) v = 100; printf "%d\n", v }' /proc/loadavg
}

# MemAvailable rather than MemFree. Free excludes the page cache, so on any
# machine that has been up for an hour it reads as almost full; available is the
# figure that answers "can I start something big".
mem_pct() {
    awk '/^MemTotal:/ { t = $2 } /^MemAvailable:/ { a = $2 } END { printf "%d\n", (t - a) * 100 / t }' /proc/meminfo
}

# Found by NAME, never by index. thermal_zone0 on this box is acpitz, a chassis
# sensor that sits near 28C whatever the CPU is doing -- the package sensor is
# zone 1 *today*, and nothing promises it stays there across a kernel update or
# on another machine. Reading each zone's `type` finds it anywhere; the hwmon
# loop is the fallback for a kernel that registers coretemp but no package zone.
temp_c() {
    t=
    for z in /sys/class/thermal/thermal_zone*; do
        [ -r "$z/type" ] && [ -r "$z/temp" ] || continue
        case "$(cat "$z/type")" in
            x86_pkg_temp|k10temp|cpu-thermal|soc_thermal) t=$(cat "$z/temp"); break ;;
        esac
    done
    if [ -z "$t" ]; then
        for h in /sys/class/hwmon/hwmon*; do
            [ -r "$h/name" ] && [ -r "$h/temp1_input" ] || continue
            case "$(cat "$h/name")" in
                coretemp|k10temp|zenpower) t=$(cat "$h/temp1_input"); break ;;
            esac
        done
    fi
    [ -n "$t" ] || t=0
    # Millidegrees to degrees. 0-100 is the useful range for a CPU: every part
    # this image runs on throttles before 100C.
    awk -v t="$t" 'BEGIN { v = t / 1000; if (v > 100) v = 100; if (v < 0) v = 0; printf "%d\n", v }'
}

case "${1:-}" in
cpu)  cpu_pct ;;
mem)  mem_pct ;;
temp) temp_c ;;
json)
    c=$(cpu_pct); m=$(mem_pct); t=$(temp_c)
    load=$(awk '{ printf "%s %s %s", $1, $2, $3 }' /proc/loadavg)
    ram=$(awk '/^MemTotal:/ { t = $2 } /^MemAvailable:/ { a = $2 } END { printf "%.1fG / %.1fG", (t - a) / 1048576, t / 1048576 }' /proc/meminfo)

    # The alert classes are the whole reason this module is on the bar at all
    # rather than only in a panel: a reading you have to hover to see is no use
    # as an alarm. style.css takes .warning to the bright grey and .critical to
    # white, so the glyph goes loud before anything is hovered.
    #
    # 85C is where this box's part starts pulling clocks back; 95% of 24
    # threads means the machine is not yours any more.
    cls=""
    if [ "$t" -ge 75 ] || [ "$c" -ge 80 ] || [ "$m" -ge 85 ]; then cls="warning"; fi
    if [ "$t" -ge 85 ] || [ "$c" -ge 95 ] || [ "$m" -ge 95 ]; then cls="critical"; fi

    # \n in the tooltip is a JSON escape, so printf has to emit a literal
    # backslash-n rather than a newline -- hence \\n in the format. A real
    # newline in a JSON string would make waybar drop the whole object.
    printf '{"text":"󰻠","tooltip":"cpu  %3d%%   load %s\\nram  %3d%%   %s\\ntemp %3d°C","class":"%s"}\n' \
        "$c" "$load" "$m" "$ram" "$t" "$cls"
    ;;
*)
    # An unknown verb still has to print something parseable: waybar keeps the
    # last good value if a json module prints nothing, which would leave a
    # stale tooltip with no way to tell.
    echo 0
    ;;
esac
