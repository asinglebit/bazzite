#!/bin/sh
# Wi-Fi picker, through the launcher.
#
# swaync's buttons-grid can only toggle the radio on and off; this is the part
# that picks a network. Like rofi-clipboard.sh it pipes into `rofi -dmenu`, so
# it inherits ~/.config/rofi/config.rasi and adds no new surface to theme.
#
# nmcli does the work. NetworkManager is what Bazzite already uses, and
# nm-applet is installed but shows no tray icon on this bar, so this is the only
# graphical path to joining a network.

set -eu

# --- Radio off? Offer to turn it on, and stop there. -------------------------
if [ "$(nmcli -g WIFI radio 2>/dev/null || echo disabled)" != "enabled" ]; then
    case $(printf 'Turn Wi-Fi on\nCancel' | rofi -dmenu -i -p 'Wi-Fi is off') in
        'Turn Wi-Fi on') nmcli radio wifi on ;;
    esac
    exit 0
fi

# --- Scan --------------------------------------------------------------------
#
# --rescan yes forces a fresh scan rather than showing a cached list, which is
# the difference between this being useful and it offering last week's networks.
#
# -t -f is terse, colon-separated output: IN-USE:SIGNAL:SECURITY:SSID. Sorting
# happens HERE, on that raw form, with an explicit -t: -- because the field
# positions are stable only before formatting. Sorting the formatted menu
# instead is a trap: the active row starts with "*" and the others with a space,
# so whitespace-delimited field 2 means SIGNAL on one row and SECURITY on the
# next, and `sort -n -u` then reads every inactive row as the number 0 and
# collapses them all into one.
#
# Two keys, and the first one is load-bearing rather than cosmetic. IN-USE
# descending puts the connected network at the top of the menu -- but more
# importantly it makes the "*" survive deduplication. A network you are joined
# to often also appears as a second, stronger row (the other band, or another
# AP on the same ESSID); sorted by signal alone that stronger row is seen first,
# the seen[] check drops the real one, and the connected network renders with no
# marker at all.
list=$(nmcli --rescan yes -t -f IN-USE,SIGNAL,SECURITY,SSID device wifi list 2>/dev/null \
       | sort -t: -k1,1r -k2,2nr) || {
    printf 'Scan failed\n' | rofi -dmenu -i -p 'Wi-Fi' >/dev/null
    exit 1
}

# Format to a FIXED-WIDTH prefix, so the SSID can be recovered by column rather
# than by re-parsing:
#
#   mark  1 char   +1 space
#   signal 3 chars (0-100, %3.3s)  +2 spaces
#   security 9 chars exactly (%-9.9s -- padded AND truncated)  +1 space
#   = 17 characters, so the SSID always begins at column 18.
#
# The truncation is the point. Security comes back as things like "WPA1 WPA2",
# with a space in it, so any attempt to strip three whitespace-separated columns
# back off leaves "WPA2 " glued to the front of the SSID. A fixed width has no
# such ambiguity, and it survives spaces and colons inside the SSID too.
#
# Escaped colons in an SSID arrive as "\:" and add fields, so fields 4..NF are
# rejoined before the backslashes are dropped.
#
# seen[] keeps the strongest AP per SSID: the list is already sorted by signal
# descending, so the first occurrence wins and the rest of the band/BSSID
# duplicates are skipped.
menu=$(printf '%s\n' "$list" | awk -F: '
    {
        inuse = $1; signal = $2; sec = $3;
        ssid = $4;
        for (i = 5; i <= NF; i++) ssid = ssid ":" $i;
        gsub(/\\/, "", ssid);
        if (ssid == "") next;              # hidden network: nothing to click
        if (seen[ssid]++) next;            # already listed, at better signal
        if (sec == "") sec = "open";
        gsub(/ /, "/", sec);               # "WPA1 WPA2" -> "WPA1/WPA2"
        mark = (inuse == "*") ? "*" : " ";
        printf "%s %3.3s  %-9.9s %s\n", mark, signal, sec, ssid;
    }')

[ -n "$menu" ] || { printf 'No networks found\n' | rofi -dmenu -i -p 'Wi-Fi' >/dev/null; exit 0; }

choice=$(printf '%s\n' "$menu" | rofi -dmenu -i -p 'Wi-Fi') || exit 0
[ -n "$choice" ] || exit 0

# Column 18 onwards, per the format string above.
ssid=$(printf '%s' "$choice" | cut -c18-)
[ -n "$ssid" ] || exit 0

# Already connected to this one -- offer to disconnect rather than re-auth.
case $choice in
    '*'*)
        case $(printf 'Disconnect\nCancel' | rofi -dmenu -i -p "$ssid") in
            Disconnect) nmcli connection down id "$ssid" >/dev/null 2>&1 || true ;;
        esac
        exit 0
        ;;
esac

# --- Connect -----------------------------------------------------------------
#
# A saved connection needs no password: try it bare first. This is also the
# open-network path.
if nmcli device wifi connect "$ssid" >/dev/null 2>&1; then
    notify-send -e -t 3000 'Wi-Fi' "Connected to $ssid" 2>/dev/null || true
    exit 0
fi

# Otherwise ask. -password makes rofi draw dots instead of the typed text.
# </dev/null so rofi reads its (empty) dmenu input from nowhere rather than
# inheriting this script's stdin.
pass=$(rofi -dmenu -password -p "Password for $ssid" </dev/null) || exit 0
[ -n "$pass" ] || exit 0

if nmcli device wifi connect "$ssid" password "$pass" >/dev/null 2>&1; then
    notify-send -e -t 3000 'Wi-Fi' "Connected to $ssid" 2>/dev/null || true
else
    notify-send -e -u critical -t 5000 'Wi-Fi' "Could not connect to $ssid" 2>/dev/null || true
fi
