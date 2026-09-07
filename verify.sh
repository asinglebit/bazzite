#!/usr/bin/bash
# Post-boot checks for the Bazzite-Sway image. Run this from inside a Sway
# session. Reports pass/fail per item; exits non-zero if anything critical fails.

pass=0; fail=0; warn=0
ok()   { printf '  \033[32mPASS\033[0m  %s\n' "$1"; pass=$((pass+1)); }
no()   { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; fail=$((fail+1)); }
meh()  { printf '  \033[33mWARN\033[0m  %s\n' "$1"; warn=$((warn+1)); }
head_() { printf '\n\033[1m%s\033[0m\n' "$1"; }

head_ "Image identity"
grep -q 'Bazzite Sway' /usr/lib/os-release && ok "os-release rebranded" || no "os-release not rebranded"
jq -e '."image-name" == "bazzite-sway"' /usr/share/ublue-os/image-info.json >/dev/null 2>&1 \
    && ok "image-info.json image-name" || no "image-info.json image-name"
jq -e '."base-image-name" == "kinoite"' /usr/share/ublue-os/image-info.json >/dev/null 2>&1 \
    && ok "image-info.json base-image-name still kinoite (DE oracle)" \
    || no "base-image-name changed -- bazzite scripts will take the GNOME branch"

head_ "Session"
[[ "${XDG_CURRENT_DESKTOP}" == *sway* ]] && ok "XDG_CURRENT_DESKTOP=${XDG_CURRENT_DESKTOP}" \
    || no "XDG_CURRENT_DESKTOP=${XDG_CURRENT_DESKTOP:-unset} (not a sway session?)"
[[ "${XDG_SESSION_TYPE}" == "wayland" ]] && ok "session type wayland" || no "session type ${XDG_SESSION_TYPE:-unset}"
swaymsg -t get_version >/dev/null 2>&1 && ok "sway IPC responding ($(swaymsg -t get_version -r | jq -r .human_readable 2>/dev/null))" \
    || no "sway IPC not responding"

head_ "Compositor (SwayFX)"
rpm -q --quiet swayfx && ok "swayfx installed ($(rpm -q swayfx))" \
    || no "swayfx NOT installed -- effects config in 25-effects.conf will fail to parse"
# The staleness tripwire, mirrored from build_files/15-swayfx.sh. The COPR RPM
# is a 2025-07 fc43 build linking libwlroots-0.19; F44 still ships that as a
# compat package, but nobody has rebuilt swayfx in over a year.
ldd /usr/bin/sway 2>/dev/null | grep -q 'libwlroots-0.19.so' \
    && ok "sway links libwlroots-0.19 (the ABI swayfx was built against)" \
    || no "sway does NOT link libwlroots-0.19 -- swayfx ABI drift, rebuild needed"
ldd /usr/bin/sway 2>/dev/null | grep -q 'libscenefx' \
    && ok "sway links libscenefx (the effects renderer)" || no "libscenefx missing"
grep -q '^WLR_RENDERER=gles2$' /etc/sway/environment \
    && ok "WLR_RENDERER=gles2 (SwayFX fx_renderer is GLES2-only)" \
    || no "WLR_RENDERER is not gles2 -- SwayFX will run and draw NO effects, silently"
# Proof the effects config was actually parsed, not just present on disk.
#
# NOT via `swaymsg -t get_config`, which is what this used to grep for
# corner_radius. That reply is the top-level /etc/sway/config and nothing else
# -- sway never concatenates the includes into it -- so the check could not pass
# whatever the session was doing, and spent its life reporting a warning that
# was never real. Read it back and you get 7921 chars against a 7923-byte file.
#
# What sway does leave behind is the include list layered-include generated for
# THIS session, under /run/user/$UID/sway/. A file in that list which failed to
# parse would have raised the swaynag error bar, which the next check catches,
# so "listed" plus "no error bar" is the proof.
if grep -qs '/sway/config\.d/25-effects\.conf' /run/user/"$(id -u)"/sway/layered-include-*.conf; then
    ok "25-effects.conf is in this session's include list"
else
    meh "25-effects.conf not in this session's include list (reload after link-dotfiles?)"
fi
# sway conflates config WARNINGS with errors: an overwritten binding, or an
# i3-only directive such as client.background, raises the same "There are errors
# in your config file" swaynag bar that a syntax error does. Nothing else in
# this desktop spawns swaynag -- $mod+Shift+e is wlogout now -- so a running one
# means the config raised something. `bindsym --no-warn` is how a deliberate
# override says it meant it.
pgrep -x swaynag >/dev/null \
    && no "sway raised a config error/warning bar -- read it, or: sway --validate -d" \
    || ok "sway config raised no error or warning bar"

head_ "systemd user session (RHBZ 2481764 -- the portal depends on this)"
systemctl --user is-active graphical-session.target >/dev/null 2>&1 \
    && ok "graphical-session.target active" \
    || no "graphical-session.target INACTIVE -- portals, file dialogs and screen share will be broken"
systemctl --user is-active sway-session.target >/dev/null 2>&1 \
    && ok "sway-session.target active" || no "sway-session.target inactive (sway-systemd missing?)"
systemctl --user is-active xdg-desktop-portal.service >/dev/null 2>&1 \
    && ok "xdg-desktop-portal.service active" || no "xdg-desktop-portal.service inactive"
busctl --user list 2>/dev/null | grep -q 'impl.portal.desktop.wlr' \
    && ok "wlr portal backend on the bus" || meh "wlr portal backend not yet activated (starts on demand)"

head_ "Display manager"
dm=$(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null)
[[ "${dm}" == *greetd* ]] && ok "display-manager -> greetd" || no "display-manager -> ${dm:-none}"

head_ "Greeter (noctalia-greeter, own compositor)"
greeter_fail_at_start=$fail
# THIS SECTION AND `just greeter-preview` ARE THE ONLY CHECKS THAT SEE A LIVE
# GREETER. The build validates greeter.toml's syntax and palette and runs
# `noctalia-greeter sessions`, but it cannot start the greeter itself: the
# compositor wants DRM and a logind seat, and no subcommand reads the config. The
# sway-hosted gtkgreet this replaced could at least be parsed with `sway -C`. See
# the note at the end of build_files/17-noctalia-greeter.sh. Each of the checks
# below is a blank login screen if it fails.
command -v noctalia-greeter-session >/dev/null \
    && ok "noctalia-greeter present" || no "noctalia-greeter-session MISSING -- greetd has nothing to run"
command -v noctalia-greeter-compositor >/dev/null \
    && ok "greeter compositor present" \
    || no "noctalia-greeter-compositor MISSING -- the greeter has nothing to draw on"
test -d /usr/share/noctalia-greeter/assets \
    && ok "greeter assets present" || no "no /usr/share/noctalia-greeter/assets -- greeter loses its fonts and icons"
test -x /usr/libexec/noctalia-greeter-nvidia \
    && ok "GPU wrapper present" \
    || no "no /usr/libexec/noctalia-greeter-nvidia -- greetd's command line points at nothing"
grep -q '^command = "/usr/libexec/noctalia-greeter-nvidia"$' /etc/greetd/config.toml \
    && ok "greetd launches the greeter via the wrapper" \
    || no "greetd is not calling the wrapper -- the compositor gets none of this image's GPU environment"

# The state directory, which is the part that cannot be checked at build time at
# all: /var is not in the image, so tmpfiles.d recreates this on every boot.
# Upstream names a state directory the greeter cannot use as THE cause of a blank
# greeter, and all three properties below are ways to get there.
state=/var/lib/noctalia-greeter
if [[ -d "$state" ]]; then
    ok "state directory present"
    [[ "$(stat -c '%U %a' "$state")" == "greetd 750" ]] \
        && ok "state directory is greetd:0750" \
        || no "state directory is $(stat -c '%U:%G %a' "$state"), not greetd 750 -- greeter cannot use it"
    # greetd runs as xdm_t and /var/lib/greetd is xdm_var_lib_t; a directory
    # created here without the file_contexts alias 17-noctalia-greeter.sh installs
    # comes up var_lib_t, which xdm_t cannot write.
    [[ "$(ls -Zd "$state")" == *xdm_var_lib_t* ]] \
        && ok "state directory labelled xdm_var_lib_t" \
        || no "state directory is $(ls -Zd "$state" | awk '{print $1}') -- SELinux will deny the greeter"
    # Two things this check got wrong for as long as it has existed, both of
    # which made it fail on a perfectly healthy greeter.
    #
    # 1. IT NEEDS A PRIVILEGED READ. $state is 0750 greetd:greetd -- deliberately,
    #    three checks up -- so an unprivileged run has no search permission on it
    #    and `test -s` on anything inside can only ever return false. `sudo -n`,
    #    so this never sits at a password prompt; with no cached credential the
    #    two checks below are skipped rather than reported as broken, because a
    #    directory this script cannot read is not a broken login screen.
    #
    # 2. IT CANNOT EXPECT THE IMAGE'S FILE VERBATIM. The greeter rewrites
    #    greeter.toml when it starts, into its own canonical serialisation:
    #    comments stripped, keys sorted, the palette indented under
    #    [appearance.palette], and `scheme` dropped because that one is read from
    #    sync.toml. So `^surface` never matched -- what is on disk is
    #    `    surface = "#1a1a1a"`. The check is on the VALUE, leading whitespace
    #    allowed. (The header the greeter writes claims "UI and Sync never write
    #    this". It does: that header text is in the binary's own string table.)
    if greeter_toml="$(sudo -n cat "$state/greeter.toml" 2>/dev/null)"; then
        [[ -n "$greeter_toml" ]] \
            && ok "greeter.toml copied from the image" \
            || no "$state/greeter.toml is empty -- the tmpfiles copy did not fire, greeter comes up stock"
        grep -qE '^[[:space:]]*surface[[:space:]]*=[[:space:]]*"#1a1a1a"$' <<<"$greeter_toml" \
            && ok "greeter.toml is the greyscale copy" \
            || no "greeter.toml has no greyscale palette -- login screen will not match the desktop"
    elif sudo -n true 2>/dev/null; then
        no "no $state/greeter.toml -- the tmpfiles copy did not fire, greeter comes up stock"
    else
        meh "greeter.toml not checked -- $state is 0750 greetd:greetd; run 'sudo -v' first"
    fi

    # The user avatar, in two halves, because the greeter has no avatar key in
    # greeter.toml -- it asks AccountsService for IconFile. The image ships the
    # file; `just greeter-avatar` binds it to the account. The second half is
    # per-user state under /var, so it cannot be in the image, and its failure
    # mode is silent: the greeter falls back to its built-in line-art person
    # icon, which looks like a design choice rather than a missing step.
    avatar=/usr/share/bazzite-sway/greeter-avatar.svg
    if [[ -s "$avatar" ]]; then
        ok "greeter avatar present in the image"
        # Inverted, and nothing but. The source trace is a single black fill; a
        # stray coloured one here would be the only non-neutral thing on the
        # login screen that IS within our control.
        avatar_fills="$(grep -oE 'fill="[^"]*"' "$avatar" | sort -u | tr '\n' ' ')"
        [[ "$avatar_fills" == 'fill="#ffffff" ' ]] \
            && ok "greeter avatar inverted to white, and greyscale throughout" \
            || no "greeter avatar fills are [ ${avatar_fills}] -- expected only fill=\"#ffffff\""
        python3 -c 'import sys, xml.dom.minidom as m; m.parse(sys.argv[1])' "$avatar" 2>/dev/null \
            && ok "greeter avatar is well-formed XML" \
            || no "greeter avatar is not well-formed XML -- librsvg will draw nothing"
        # Bound to this account? Read it the way the greeter does, off the bus.
        acct_obj="$(busctl --system call org.freedesktop.Accounts /org/freedesktop/Accounts \
            org.freedesktop.Accounts FindUserByName s "$(id -un)" --json=short 2>/dev/null \
            | jq -r '.data[0]' 2>/dev/null)"
        icon_file="$(busctl --system get-property org.freedesktop.Accounts "${acct_obj:-/}" \
            org.freedesktop.Accounts.User IconFile --json=short 2>/dev/null \
            | jq -r '.data' 2>/dev/null)"
        if [[ "$icon_file" == "$avatar" ]]; then
            ok "AccountsService serves the image avatar to the greeter"
        else
            meh "AccountsService IconFile=${icon_file:-unset} -- login screen still shows the stock person icon; run 'just greeter-avatar'"
        fi
    else
        no "no $avatar -- 17-noctalia-greeter.sh did not install the greeter avatar"
    fi
else
    no "no $state -- tmpfiles.d did not run; greeter has no config and no state"
fi

# Behavioural, and the direct replacement for the old `sway -C` parse check:
# `sessions` reads the wayland-sessions entries and exits before wanting a
# display, so it runs from here. An empty list is a login screen you cannot log
# in from.
if sessions="$(noctalia-greeter sessions 2>&1)"; then
    grep -qi 'sway' <<<"$sessions" \
        && ok "greeter enumerates the Sway session" \
        || no "greeter lists no Sway session -- check /usr/share/wayland-sessions/sway.desktop"
    grep -qi 'plasma' <<<"$sessions" \
        && no "greeter still offers Plasma -- plasma.desktop outlived the KDE removal" \
        || ok "Sway is the only session offered"
else
    no "noctalia-greeter sessions failed -- $(head -1 <<<"$sessions")"
fi

# Kept, unbound, as the only fallback greeter -- see /etc/greetd/config.toml. It
# needs no compositor and no GPU, which is the whole reason it is the one kept.
command -v tuigreet >/dev/null && ok "tuigreet present (fallback)" \
    || no "tuigreet MISSING -- no fallback if the greeter fails"
command -v gtkgreet >/dev/null \
    && meh "gtkgreet still installed -- it was dropped with the sway greeter" \
    || ok "gtkgreet gone with the sway-hosted greeter"
# Both were shipped in /etc, so an upgraded system can keep them after they left
# the image. Harmless -- nothing reads them now -- but confusing to find.
{ test -e /etc/greetd/environments || test -e /etc/gtkgreet/style.css; } \
    && meh "leftover gtkgreet-era files in /etc (environments, gtkgreet/style.css) -- unused, safe to delete" \
    || ok "no gtkgreet-era leftovers in /etc"

# If the greeter did fail, the reason is in greetd's journal rather than on
# screen -- the login path has nowhere to print to.
if [[ $fail -gt $greeter_fail_at_start ]]; then
    printf '        --- journalctl -b -u greetd (last 10) ---\n'
    journalctl -b -u greetd --no-pager -n 10 2>/dev/null | sed 's/^/        /'
fi

head_ "Graphics"
swaymsg -t get_outputs -r 2>/dev/null | jq -r '.[] | "  output \(.name) \(.current_mode.width)x\(.current_mode.height)@\(.current_mode.refresh/1000)Hz  active=\(.active)"' 2>/dev/null
glxinfo -B 2>/dev/null | grep -q 'NVIDIA' && ok "GLX renderer is NVIDIA" || meh "glxinfo did not report NVIDIA (glxinfo installed?)"
vulkaninfo --summary 2>/dev/null | grep -q 'NVIDIA' && ok "Vulkan sees the NVIDIA GPU" || meh "vulkaninfo did not report NVIDIA"
pgrep -x Xwayland >/dev/null && ok "Xwayland running" || meh "Xwayland not running (no X11 client started yet)"

head_ "Desktop services"
pgrep -f polkit-mate-authentication-agent >/dev/null && ok "polkit agent running" \
    || no "no polkit agent -- pkexec, bazzite-user-setup and ujust will hang"
# Check the shipped .wants symlink directly: `is-enabled` reports vendor
# /usr/lib/*.wants links inconsistently across systemd versions, and what
# actually matters is that the link is there for the next login.
[ -L /usr/lib/systemd/user/sway-session.target.wants/polkit-mate-authentication-agent-1.service ] \
    && ok "polkit agent wanted by sway-session.target" \
    || no "polkit agent not wired to sway-session.target -- it will not return on next login"
pgrep -x gnome-keyring-d >/dev/null && ok "gnome-keyring running (Secret portal backend)" \
    || meh "gnome-keyring not running -- app passwords will not persist"
pgrep -x swaync >/dev/null && ok "swaync running (notification daemon)" \
    || no "swaync NOT running -- no notifications, and no volume/brightness OSD"
# Both mako and swaync ship a D-Bus service file claiming
# org.freedesktop.Notifications. swaync is started from sway-session.target so
# it takes the name first; if mako is up instead, that ordering broke.
pgrep -x mako >/dev/null \
    && no "mako is running INSTEAD of swaync -- the bus name was taken by the wrong daemon" \
    || ok "mako correctly idle (installed as the fallback only)"
pgrep -x waybar >/dev/null && ok "waybar running" || meh "waybar not running"
# foot is still in this list on purpose. It is no longer bound to anything, but
# it is kept installed as a fallback: ghostty is GPU-accelerated and this is an
# NVIDIA box, so losing it would mean no terminal at all.
for b in ghostty foot rofi Thunar grimshot wl-copy swaylock blueman-manager nm-applet; do
    command -v "$b" >/dev/null && ok "$b present" || no "$b MISSING"
done

# The bar's two helper scripts. Both are dotfiles, so a session that has never
# had `just link-dotfiles` run against it will fail these -- which is the point:
# without stats.sh the hardware glyph shows waybar's "unknown" and without
# toggle.sh every quick toggle in the notification panel silently reports off.
#
# The check is the OUTPUT, not the file: stats.sh has to emit a parseable waybar
# object (waybar keeps the last good value when a json module prints garbage, so
# a broken script leaves a stale tooltip with nothing to say it is stale), and
# toggle.sh has to answer `state` with exactly true or false, which is what
# swaync's update-command consumes.
if [ -x "$HOME/.config/waybar/stats.sh" ] \
   && "$HOME/.config/waybar/stats.sh" json | python3 -c 'import json,sys; d=json.load(sys.stdin); raise SystemExit(0 if d.get("text") and "tooltip" in d else 1)' 2>/dev/null; then
    ok "waybar/stats.sh emits a valid module object"
else
    no "waybar/stats.sh missing or not emitting valid JSON -- the bar's hardware glyph and its tooltip are dead (just link-dotfiles?)"
fi
for t in wifi bluetooth idle; do
    case $([ -x "$HOME/.config/swaync/toggle.sh" ] && "$HOME/.config/swaync/toggle.sh" "$t" state 2>/dev/null) in
        true|false) ok "swaync toggle.sh $t reports state" ;;
        *) no "swaync toggle.sh $t does NOT print true/false -- that toggle will show off whatever the hardware says" ;;
    esac
done

# nm-applet and blueman-applet are both INSTALLED and both deliberately not
# autostarted: waybar draws their state itself, in the bar font, and their own
# tray icons are full-colour artwork no stylesheet here can reach. Hidden=true in
# ~/.config/autostart overrides /etc/xdg/autostart by basename. If one of these
# comes back, the symptom is a duplicate icon in the tray rather than an error.
for a in nm-applet blueman; do
    if grep -qs '^Hidden=true' "$HOME/.config/autostart/$a.desktop"; then
        ok "$a applet suppressed (Hidden=true)"
    else
        meh "$a applet not suppressed -- expect a duplicate, unthemeable tray icon"
    fi
done

# Hack Nerd Font Mono is vendored from the upstream release by
# 10-sway-install.sh rather than installed as an RPM, since no repo this image
# trusts carries a patched Hack. If it goes missing, text silently falls back to
# Noto while icons keep working off the base image's symbols-only nerd-fonts
# package -- half-broken in a way that is easy not to notice.
fc-list -q 'Hack Nerd Font Mono' && ok "Hack Nerd Font Mono installed" \
    || no "Hack Nerd Font Mono MISSING -- bar, terminal and launcher fall back to Noto"

# 10-sway-install.sh rewrites `set $term foot` in /etc/sway/config. sway expands
# that variable at parse time into both `bindsym $mod+Return exec $term` and
# rofi's `-terminal`, so if the rewrite ever silently no-ops -- an upstream
# reformat of that line would do it -- both quietly revert to foot.
grep -q '^set \$term ghostty$' /etc/sway/config \
    && ok "sway \$term is ghostty" \
    || no "sway \$term is not ghostty -- \$mod+Return and rofi will open foot"
infocmp xterm-ghostty >/dev/null 2>&1 && ok "xterm-ghostty terminfo present" \
    || no "xterm-ghostty terminfo MISSING -- ssh and curses apps will misbehave"

head_ "Locker (hyprlock + hypridle)"
# THE important line in this file.
#
# Neither hyprlock.conf nor hypridle.conf can be validated at build time --
# hypridle connects to Wayland before it parses anything, and hyprlock has no
# validate-only mode -- and hyprlang ERRORS on unknown keys. So a typo in either
# file means the unit exited at startup, and the only symptom is silence: no
# auto-lock, no display blanking, discovered five minutes after you walk away.
if systemctl --user is-active --quiet hypridle; then
    ok "hypridle active -- idle lock and DPMS are armed"
else
    no "hypridle NOT active -- NOTHING will lock or blank this session"
    printf '        last log lines:\n'
    journalctl --user -u hypridle -b --no-pager -n 5 2>/dev/null | sed 's/^/        /'
    # Restart=on-failure plus systemd's default start limit means five failures
    # in ten seconds wedge the unit for the rest of the session. That is what
    # happens when the config is linked AFTER login: hypridle died on a missing
    # ~/.config/hypr/hypridle.conf before `just link-dotfiles` created it, and
    # no later reload revives it. Clearing the limit is a separate step from
    # starting it again.
    printf '        wedged by the start limit? systemctl --user reset-failed hypridle \\\n'
    printf '                                   && systemctl --user start hypridle\n'
fi
command -v hyprlock >/dev/null && ok "hyprlock present" || no "hyprlock MISSING"
# Neither binary has built-in defaults, so SOME config has to be findable or
# there is no locker at all. The image ships the floor at /etc/xdg/hypr
# (16-hyprlock.sh) -- the last entry in hyprutils' search order, so a linked
# dotfile shadows it. Without it, a login before `just link-dotfiles` never
# locks and never blanks.
for c in hypridle hyprlock; do
    test -s "/etc/xdg/hypr/$c.conf" \
        && ok "image fallback /etc/xdg/hypr/$c.conf present" \
        || no "image fallback $c.conf MISSING -- a login before link-dotfiles has no locker"
done
hl_user="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprlock.conf"
if test -s "$hl_user"; then
    ok "hyprlock.conf from dotfiles (shadows the image fallback)"
    hl_live="$hl_user"
elif test -s /etc/xdg/hypr/hyprlock.conf; then
    meh "no dotfiles hyprlock.conf -- running the image fallback (run: just link-dotfiles)"
    hl_live=/etc/xdg/hypr/hyprlock.conf
else
    no "no hyprlock.conf anywhere -- hyprlock exits 1 and there is NO lock screen"
    hl_live=""
fi
# $HOME expands in a hyprlock path via hyprlang's env substitution; ~ does not.
# A tilde here is the silent failure mode -- the background falls back to flat.
if [[ -n "$hl_live" ]] && grep -q '^\s*path\s*=\s*~' "$hl_live" 2>/dev/null; then
    no "hyprlock background path starts with ~ -- not expanded; use \$HOME"
else
    ok "hyprlock background path does not rely on ~ expansion"
fi
# swaylock and swayidle stay installed, unbound, as the fallback pair.
for p in swaylock swayidle; do
    rpm -q --quiet "$p" && ok "$p still installed (fallback)" || no "$p removed -- no way back if hyprlock breaks"
done
# Fedora's swayidle drop-in must be retired. The override is comment-only
# rather than zero bytes, so test for the absence of DIRECTIVES, not of bytes.
swayidle_override="${XDG_CONFIG_HOME:-$HOME/.config}/sway/config.d/90-swayidle.conf"
if [[ -f "$swayidle_override" ]]; then
    if grep -qvE '^[[:space:]]*(#|$)' "$swayidle_override"; then
        no "90-swayidle.conf has live directives -- swayidle and hypridle will both run"
    else
        ok "Fedora's swayidle drop-in retired (override has no directives)"
    fi
else
    no "no 90-swayidle.conf override -- Fedora's swayidle+swaylock drop-in is still active"
fi
pgrep -x swayidle >/dev/null \
    && no "swayidle is RUNNING alongside hypridle -- two idle daemons, both will lock" \
    || ok "swayidle correctly idle"

head_ "Theming"
fc-list -q 'Inter' && ok "Inter installed (GTK UI font)" || no "Inter MISSING -- GTK text falls back"
test -d /usr/share/themes/adw-gtk3-dark \
    && ok "adw-gtk3-dark present (GTK3 apps match the GTK4 ones)" || no "adw-gtk3-dark MISSING"
test -d /usr/share/icons/Papirus-Dark && ok "Papirus-Dark present" || no "Papirus-Dark MISSING"

# The greyscale palette. Two stylesheets, and they are the only thing that takes
# Adwaita's blue accent and blue-tinted greys out of GTK.
for f in gtk-3.0/gtk.css gtk-4.0/gtk.css; do
    test -e "${XDG_CONFIG_HOME:-$HOME/.config}/$f" \
        && ok "$f linked" \
        || no "$f NOT linked -- GTK keeps Adwaita's blue accent (run: just link-dotfiles)"
done

# THE ONE THAT BITES SILENTLY. On Wayland GTK takes the theme, icon theme,
# cursor theme and UI font from the XDG desktop portal, which answers them out
# of org.gnome.desktop.interface in dconf -- and the portal WINS over
# gtk-3.0/settings.ini for every key it serves. A stale dconf value therefore
# overrides this repo with nothing logged anywhere.
#
# It matters most for gtk-theme. dotfiles/gtk-3.0/gtk.css redefines libadwaita's
# colour names, and the GTK3 legacy names a widget actually asks for
# (theme_bg_color and the rest) are aliases of those only inside adw-gtk3-dark.
# Under stock Adwaita the stylesheet loads, parses clean, and half of it lands.
#
# The three non-default values here are Plasma-era leftovers from kde-gtk-config,
# which wrote into dconf where 30-kde-remove.sh could not follow.
while read -r key want; do
    have=$(gsettings get org.gnome.desktop.interface "$key" 2>/dev/null | tr -d "'")
    if [[ "$have" == "$want" ]]; then
        ok "portal $key = $have"
    else
        no "portal $key = ${have:-unset}, settings.ini asks for '$want' and LOSES -- gsettings set org.gnome.desktop.interface $key '$want'"
    fi
done <<'KEYS'
gtk-theme adw-gtk3-dark
icon-theme Papirus-Dark
cursor-theme Adwaita
font-name Inter 10
KEYS

# The tripwire under dotfiles/gtk-4.0/gtk.css. libadwaita deprecated
# @define-color in 1.6 for CSS custom properties, but through 1.9.3 the
# properties are still SOURCED from the old names -- the library ships
# `--window-bg-color: @window_bg_color` in its own stylesheet -- which is the
# only reason one @define-color block themes GTK3, plain GTK4 and libadwaita
# alike. If a release stops doing that, the GTK4 file silently themes nothing
# and every colour there has to be restated as a :root variable.
if gresource extract /usr/lib64/libadwaita-1.so.0 /org/gnome/Adwaita/styles/gtk.css 2>/dev/null \
     | grep -q -- '--window-bg-color:[[:space:]]*@window_bg_color'; then
    ok "libadwaita still sources its CSS variables from @define-color"
else
    no "libadwaita no longer sources --window-bg-color from @window_bg_color -- gtk-4.0/gtk.css needs a :root block for every colour"
fi
# The black folders are symlinks baked in at build time, because
# /usr/share/icons is read-only at runtime. Check a folder AND a user-* icon:
# the latter only exists if the full variant set was linked, not just folder*.
if readlink /usr/share/icons/Papirus/48x48/places/folder.svg 2>/dev/null | grep -q 'folder-black'; then
    ok "Papirus folders are black"
else
    no "Papirus folders are NOT black -- papirus-folders did not run, or was reverted by an update"
fi
readlink /usr/share/icons/Papirus/48x48/places/user-home.svg 2>/dev/null | grep -q 'user-black' \
    && ok "user-* icons recoloured too (Home, Desktop)" \
    || meh "user-home.svg not recoloured -- only the folder* half was linked"

head_ "New helpers"
for b in swaync-client cliphist swappy wlogout nmcli; do
    command -v "$b" >/dev/null && ok "$b present" || no "$b MISSING"
done
grep -q 'combi-modes drun#run#window' /etc/sway/config \
    && ok "rofi combi includes window mode" \
    || no "rofi window mode lost -- \$mod+d will not list open windows"
for f in swaync/style.css swaync/config.json wlogout/layout mako/config hypr/hypridle.conf; do
    test -e "${XDG_CONFIG_HOME:-$HOME/.config}/$f" \
        && ok "$f linked" || no "$f NOT linked -- run: just link-dotfiles"
done

head_ "Bazzite gaming stack intact"
for b in steam gamescope mangohud; do
    command -v "$b" >/dev/null && ok "$b present" || no "$b MISSING"
done
rpm -q --quiet xorg-x11-server-Xwayland && \
    { rpm -q xorg-x11-server-Xwayland | grep -q bazzite \
        && ok "Xwayland is still Bazzite's patched build" \
        || no "Xwayland is NOT the Bazzite build -- a versionlock was broken"; }
uname -r | grep -q ogc && ok "Bazzite ogc kernel ($(uname -r))" || no "not on the ogc kernel: $(uname -r)"

head_ "Qt keepers (should survive KDE removal)"
# breeze-icon-theme is deliberately NOT in this list any more: gtk-*/settings.ini
# moved to Papirus-Dark and Adwaita cursors, so nothing depends on Plasma's
# icon or cursor sets and 30-kde-remove.sh no longer asserts them.
for p in kf6-kwallet btrfs-assistant bazzite-updater; do
    rpm -q --quiet "$p" && ok "$p installed" || no "$p removed"
done

head_ "Sessions offered"
# This directory IS the login screen's session list -- noctalia-greeter scans it
# and reads nothing else. Anything that lands here is offered; anything that does
# not, cannot be logged into.
ls /usr/share/wayland-sessions/
if rpm -q --quiet plasma-workspace; then
    no "Plasma still installed -- 30-kde-remove.sh should always run now"
else
    ok "Plasma removed"
fi

head_ "Failed units"
if systemctl --failed --no-legend | grep -q .; then
    no "system units failed:"; systemctl --failed --no-legend
else ok "no failed system units"; fi
if systemctl --user --failed --no-legend | grep -q .; then
    meh "user units failed:"; systemctl --user --failed --no-legend
else ok "no failed user units"; fi

printf '\n\033[1m%d passed, %d failed, %d warnings\033[0m\n' "$pass" "$fail" "$warn"
exit $(( fail > 0 ? 1 : 0 ))
