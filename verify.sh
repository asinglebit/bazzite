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
# this desktop spawns swaynag -- $mod+Shift+e is the shell's session panel now --
# so a running one
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
# THE AGENT CHECK IS NOW A PROCESS CHECK, and that is a real loss of precision
# worth naming. mate-polkit had its own process and its own .wants symlink, so
# both halves were observable. noctalia registers a NoctaliaPolkitListener from
# inside the shell process, and polkit exposes no way to ask which agent is
# registered -- the only definitive probe is to call pkexec, which either pops a
# dialog or hangs, and neither belongs in this script.
#
# So if the shell is up, the agent is up; the Shell section below is where that
# is checked. This line exists to name the consequence, because with mate-polkit
# uninstalled and lxqt-policykit's drop-in retired there is nothing else on this
# machine that could answer.
pgrep -x noctalia >/dev/null \
    && ok "polkit agent: noctalia (the only one -- mate-polkit is gone)" \
    || no "no polkit agent -- pkexec, bazzite-user-setup and ujust will hang"
pgrep -f polkit-mate-authentication-agent >/dev/null \
    && meh "a mate-polkit agent is ALSO running -- two agents, one a leftover" \
    || ok "no second polkit agent"
# Installed because sway-config-fedora hard-Requires it, and ABI-broken against
# Qt 6.11 so it dies at exec. /etc/sway/config.d/95-autostart-policykit-agent.conf
# retires the sway drop-in that used to run it on every single login.
pgrep -f lxqt-policykit-agent >/dev/null \
    && no "lxqt-policykit-agent is running -- its sway drop-in was not retired" \
    || ok "lxqt-policykit correctly idle (installed, unstartable, retired)"
pgrep -x gnome-keyring-d >/dev/null && ok "gnome-keyring running (Secret portal backend)" \
    || meh "gnome-keyring not running -- app passwords will not persist"

# The notification bus name.
#
# mako and swaync both shipped a D-Bus service file claiming
# org.freedesktop.Notifications, and the whole reason swaync was started from
# sway-session.target was to take the name before activation could choose wrongly.
# Both are gone, and noctalia ships NO service file at all -- so nothing on this
# machine is activatable for that name. If the shell is down, notify-send is a
# silent no-op rather than a daemon start, and there is no fallback left.
if busctl --user --no-pager status org.freedesktop.Notifications >/dev/null 2>&1; then
    ok "org.freedesktop.Notifications has an owner"
else
    no "nothing owns org.freedesktop.Notifications -- notify-send will do nothing"
fi

# THE TRAY IS LOAD-BEARING FOR THE KEYRING, which is not obvious and is why it
# is checked here rather than left to the bar.
#
# /usr/share/sway/config.d/95-xdg-desktop-autostart.conf runs
# `wait-sni-ready && systemctl --user start sway-xdg-autostart.target`, and that
# helper gives up after 25s with a non-zero exit if no StatusNotifier HOST has
# appeared -- which kills the `&&`. waybar used to be that host; noctalia is now
# (asserted against the binary in 18-noctalia-shell.sh). If it ever stops being
# one, the symptom is not a missing tray, it is gnome-keyring's three autostart
# entries never running.
systemctl --user is-active --quiet sway-xdg-autostart.target \
    && ok "sway-xdg-autostart.target active (the SNI host was found)" \
    || no "sway-xdg-autostart.target inactive -- wait-sni-ready timed out; keyring autostart did not run"

# Inverted from a liveness check into a leak check. waybar cannot be uninstalled
# -- hard Requires of sway-config-fedora -- so the only thing keeping it off the
# screen is /etc/sway/config.d/90-bar.conf.
pgrep -x waybar >/dev/null \
    && no "waybar is RUNNING -- /etc/sway/config.d/90-bar.conf did not retire Fedora's bar; there are two" \
    || ok "waybar correctly idle (installed, retired by /etc/sway/config.d/90-bar.conf)"

# foot is still in this list on purpose. It is no longer bound to anything, but
# it is kept installed as a fallback: ghostty is GPU-accelerated and this is an
# NVIDIA box, so losing it would mean no terminal at all.
#
# rofi, grimshot and swaylock are NOT in this list any more. Two of the three
# cannot leave the image, but asserting their presence here would read as an
# endorsement of tools nothing calls.
for b in ghostty foot Thunar wl-copy blueman-manager noctalia; do
    command -v "$b" >/dev/null && ok "$b present" || no "$b MISSING"
done

# ddcutil is how brightness works on this machine AT ALL: /sys/class/backlight is
# empty here -- both outputs are external -- so brightnessctl never had a device
# and 60-bindings-brightness.conf was a no-op for as long as it existed.
if command -v ddcutil >/dev/null; then
    if compgen -G '/dev/i2c-*' >/dev/null; then
        ok "ddcutil present with /dev/i2c-* (monitor brightness is possible)"
    else
        meh "ddcutil present but no /dev/i2c-* -- brightness keys will do nothing"
    fi
else
    meh "ddcutil missing -- there is no other brightness path on this hardware"
fi


# blueman's applet is INSTALLED and deliberately not autostarted: the shell
# draws bluetooth state itself, in its own icon font, and blueman's tray icon is
# full-colour artwork no stylesheet here can reach. Hidden=true in
# ~/.config/autostart overrides /etc/xdg/autostart by basename. If it comes back,
# the symptom is a duplicate icon in the tray rather than an error.
#
# nm-applet USED TO BE IN THIS LOOP and is not any more, because
# network-manager-applet is uninstalled -- so a Hidden=true override for it would
# be shadowing an /etc/xdg/autostart entry that no longer exists. What made the
# package removable is that noctalia registers as a real NetworkManager
# SecretAgent, which nm-applet was silently the only provider of; that is
# asserted against the binary in 18-noctalia-shell.sh, and the consequence is
# checked below rather than here.
if grep -qs '^Hidden=true' "$HOME/.config/autostart/blueman.desktop"; then
    ok "blueman applet suppressed (Hidden=true)"
else
    meh "blueman applet not suppressed -- expect a duplicate, unthemeable tray icon"
fi
rpm -q --quiet network-manager-applet \
    && meh "network-manager-applet is installed again -- it will race noctalia as NM's secret agent" \
    || ok "network-manager-applet gone (noctalia is the NM secret agent)"

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
# reformat of that line would do it -- $mod+Return quietly reverts to foot. The
# second consumer is gone with rofi; the binding is not.
grep -q '^set \$term ghostty$' /etc/sway/config \
    && ok "sway \$term is ghostty" \
    || no "sway \$term is not ghostty -- \$mod+Return will open foot"
infocmp xterm-ghostty >/dev/null 2>&1 && ok "xterm-ghostty terminfo present" \
    || no "xterm-ghostty terminfo MISSING -- ssh and curses apps will misbehave"

head_ "Shell (noctalia)"
# THE MOST IMPORTANT SECTION IN THIS FILE, and it inherits that title from the
# locker section it replaces.
#
# noctalia is the bar, the launcher, the notification daemon, the volume and
# brightness OSD, the clipboard history, the screenshot tool, the idle daemon,
# the lock screen and the only authentication agent on this machine -- nine
# subsystems behind one process. There is no mako left to take the notification
# bus name, no swaync to fall back to, nothing bound to swayidle, and nothing
# else that registers a polkit agent.
#
# The failure mode is the locker's, scaled up: the unit exits at startup and the
# only symptom is silence. No bar, no notifications, no OSD, no lock, and pkexec
# hangs instead of erroring. $mod+Return still opens a terminal -- that binding
# is in /etc/sway/config and does not go through the shell -- which is the one
# thing that makes this recoverable from inside the session.
#
# And nothing at build time has ever seen the config this session is running:
# dotfiles/ is excluded from the build context. `just check-shell-config` is the
# other half of this section.
noctalia_fail_at_start=$fail

rpm -q --quiet noctalia && ok "noctalia installed ($(rpm -q noctalia 2>/dev/null))" \
    || no "noctalia NOT installed -- there is no desktop shell on this image"
# Fedora, not Terra. The greeter comes from Terra and the shell does not; if
# Terra ever wins this name the vendor changes and the version line jumps.
if rpm -q --quiet noctalia; then
    [[ "$(rpm -q --queryformat '%{VENDOR}' noctalia)" == "Fedora Project" ]] \
        && ok "noctalia is the Fedora build" \
        || meh "noctalia vendor is $(rpm -q --queryformat '%{VENDOR}' noctalia) -- expected Fedora Project"
fi

# The successor to `systemctl --user is-active hypridle`, which the README calls
# the most important line in this file. Same reasoning, larger blast radius.
if systemctl --user is-active --quiet noctalia; then
    ok "noctalia.service active"
else
    no "noctalia.service NOT active -- no bar, no notifications, no lock, no polkit"
    journalctl --user -u noctalia -b -n 5 --no-pager 2>/dev/null | sed 's/^/      /'
fi
[ -L /usr/lib/systemd/user/sway-session.target.wants/noctalia.service ] \
    && ok "noctalia wanted by sway-session.target" \
    || no "noctalia not wired to sway-session.target -- it will not return on next login"

# Exactly one. The binary takes a single-instance lock and a second invocation
# exits with "noctalia is already running", so a second process is not a second
# shell -- but it holds a Wayland connection and it is evidence something is
# starting the shell twice.
noctalia_procs=$(pgrep -xc noctalia || true)
case "${noctalia_procs:-0}" in
    1) ok "exactly one noctalia process" ;;
    0) no "no noctalia process" ;;
    *) no "$noctalia_procs noctalia processes -- something starts the shell twice" ;;
esac

# The behavioural check, and the direct successor to `noctalia-greeter sessions`
# in the greeter section: it asks the running shell a question over its own IPC,
# so it fails if the process is up but wedged.
if noctalia msg status >/dev/null 2>&1; then
    ok "noctalia msg status answers"
else
    no "noctalia msg status does not answer -- the shell is up but not responding"
fi

# THE VALIDATOR, run against the config this session actually merged.
#
# This is the thing the README's load-bearing section says does not exist for
# anything in the login or lock path: hypridle connected to Wayland before
# parsing anything and hyprlock had no validate-only mode, so one typo was a
# dead locker with silence as the only symptom. `noctalia config validate` parses
# headlessly, reports file:line:column and exits 1 -- 18-noctalia-shell.sh proves
# that at build time against a known-good and a known-bad file, which is what
# makes this run meaningful.
if command -v noctalia >/dev/null; then
    if noctalia_validate=$(noctalia config validate 2>&1); then
        if [[ -n "$noctalia_validate" ]]; then
            meh "noctalia config validates with warnings"
            printf '%s\n' "$noctalia_validate" | sed 's/^/      /'
        else
            ok "noctalia config validates clean"
        fi
    else
        no "noctalia config is INVALID"
        printf '%s\n' "$noctalia_validate" | sed 's/^/      /'
    fi
fi

# THE GUI SHADOW, which is this shell's answer to the dconf-vs-settings.ini trap
# in the Theming section below, and just as silent.
#
# noctalia merges built-in defaults, then ~/.config/noctalia/*.toml, then
# ~/.local/state/noctalia/settings.toml -- and the last of those is written by
# clicking in the settings window and WINS. So a value tuned in the GUI silently
# outranks the repo, is not version-controlled, and cannot be found by reading
# dotfiles/. Deleting the file hands control back.
if [ -s "$HOME/.local/state/noctalia/settings.toml" ]; then
    meh "settings.toml exists and OUTRANKS dotfiles/noctalia -- rm ~/.local/state/noctalia/settings.toml to hand control back"
else
    ok "no GUI settings override (dotfiles/noctalia is what is running)"
fi

# THE PALETTE, asserted equal across the desktop and the login screen.
#
# The sixteen roles exist twice on purpose -- greeter.toml explains why sync is
# not used -- and nothing at runtime notices if they drift. The login screen just
# stops matching, which reads as a rendering difference rather than a bug.
noctalia_palette="$HOME/.config/noctalia/palettes/bazzite-grey.json"
noctalia_greeter_toml=/usr/share/factory/var/lib/noctalia-greeter/greeter.toml
if [ -r "$noctalia_palette" ] && [ -r "$noctalia_greeter_toml" ]; then
    if noctalia_pal_out=$(python3 - "$noctalia_palette" "$noctalia_greeter_toml" <<'PYEOF'
import json, sys, tomllib
shell = json.load(open(sys.argv[1]))["dark"]
greeter = tomllib.load(open(sys.argv[2], "rb"))["appearance"]["palette"]
camel = lambda k: "m" + "".join(p.capitalize() for p in k.split("_"))
bad = {k: (shell.get(camel(k)), v) for k, v in greeter.items() if shell.get(camel(k)) != v}
if bad:
    print("; ".join(f"{k}: shell={s} greeter={g}" for k, (s, g) in sorted(bad.items())))
    sys.exit(1)
print(f"{len(greeter)} roles")
PYEOF
    ); then
        ok "shell palette agrees with the greeter ($noctalia_pal_out)"
    else
        no "palette DRIFT between shell and greeter -- $noctalia_pal_out"
    fi
else
    meh "cannot compare palettes (run just link-dotfiles?)"
fi

# THE LAYER-SHELL NAMESPACES, checked against what the compositor actually did.
#
# 25-effects.conf blurs the shell's surfaces by namespace, and `layer_effects`
# takes a LITERAL string -- a wrong one is not an error, it is a panel that is
# quietly not frosted, and 25-effects.conf:143-149 says so at length. sway-ipc
# reports the effects it applied per surface, so this is the one check that can
# tell "the rule matched" from "the rule is a typo".
if command -v swaymsg >/dev/null && [ -n "${SWAYSOCK:-}" ]; then
    noctalia_surfaces=$(swaymsg -t get_outputs -r 2>/dev/null | python3 -c '
import json, sys
seen = {}
for o in json.load(sys.stdin):
    for s in o.get("layer_shell_surfaces", []):
        ns = s.get("namespace", "")
        if ns.startswith("noctalia"):
            seen[ns] = s.get("effects", {}).get("blur", False)
print(" ".join(f"{k}={'blur' if v else 'PLAIN'}" for k, v in sorted(seen.items())))
' 2>/dev/null)
    if [[ -z "$noctalia_surfaces" ]]; then
        no "no noctalia layer surfaces mapped -- the shell is not drawing anything"
    elif [[ "$noctalia_surfaces" == *PLAIN* ]]; then
        no "a noctalia surface is mapped but NOT blurred (namespace mismatch in 25-effects.conf): $noctalia_surfaces"
    else
        ok "noctalia layer surfaces blurred: $noctalia_surfaces"
    fi
fi

# The four gap widgets. Read the plugin's own manifest rather than a hardcoded
# list, so a widget dropped from the plugin shows up here instead of going quiet.
noctalia_plugin="$HOME/.config/noctalia/plugins/bazzite-sway"
if [ -r "$noctalia_plugin/plugin.toml" ]; then
    noctalia_missing=""
    while read -r entry; do
        [ -r "$noctalia_plugin/$entry" ] || noctalia_missing="$noctalia_missing $entry"
    done < <(python3 -c '
import tomllib, sys
d = tomllib.load(open(sys.argv[1], "rb"))
for w in d.get("widget", []):
    print(w["entry"])
' "$noctalia_plugin/plugin.toml" 2>/dev/null)
    if [ -z "$noctalia_missing" ]; then
        ok "bazzite-sway plugin entries all present"
    else
        no "bazzite-sway plugin entries MISSING:$noctalia_missing"
    fi
    # And that the shell actually loaded it. A path source that is not enabled
    # leaves the four widgets simply absent from the bar, with a validator
    # warning nobody reads.
    if noctalia msg plugins list 2>/dev/null | grep -q 'bazzite-sway'; then
        ok "bazzite-sway plugin loaded by the shell"
    else
        no "bazzite-sway plugin NOT loaded -- mode, scratchpad, failed-units and hardware are absent from the bar"
    fi
else
    meh "bazzite-sway plugin not linked (run just link-dotfiles?)"
fi

# The thresholds, which exist in two places for two consumers: [system.monitor]
# in 50-services.toml is what the control centre colours against, and the
# constants at the top of hardware.luau are what the bar glyph does. Two copies
# of a threshold that disagree are worse than one copy in the wrong place, and
# nothing at runtime would notice -- the bar would go bright at 80% while the
# panel still called it fine.
noctalia_luau="$noctalia_plugin/hardware.luau"
noctalia_svc="${XDG_CONFIG_HOME:-$HOME/.config}/noctalia/50-services.toml"
if [ -r "$noctalia_luau" ] && [ -r "$noctalia_svc" ]; then
    if noctalia_thr=$(python3 - "$noctalia_luau" "$noctalia_svc" <<'PYEOF'
import re, sys, tomllib
luau = open(sys.argv[1]).read()
def pair(name):
    m = re.search(rf"local {name}_WARN,?\s*{name}_CRIT\s*=\s*(\d+),\s*(\d+)", luau)
    if not m:
        m = re.search(rf"local {name}_WARN,\s+{name}_CRIT\s+=\s+(\d+),\s+(\d+)", luau)
    return (int(m.group(1)), int(m.group(2))) if m else None
mon = tomllib.load(open(sys.argv[2], "rb"))["system"]["monitor"]
want = {
    "TEMP": (mon["cpu_temp_activity_threshold"], mon["cpu_temp_critical_threshold"]),
    "CPU":  (mon["cpu_usage_activity_threshold"], mon["cpu_usage_critical_threshold"]),
    "MEM":  (mon["ram_pct_activity_threshold"],   mon["ram_pct_critical_threshold"]),
}
bad = []
for k, (w, c) in want.items():
    got = pair(k)
    if got is None:
        bad.append(f"{k}: not found in hardware.luau")
    elif got != (int(w), int(c)):
        bad.append(f"{k}: luau={got} config=({int(w)},{int(c)})")
if bad:
    print("; ".join(bad)); sys.exit(1)
print("temp/cpu/mem agree")
PYEOF
    ); then
        ok "hardware thresholds agree with [system.monitor] ($noctalia_thr)"
    else
        no "hardware threshold DRIFT -- $noctalia_thr"
    fi
fi

# The retired Fedora drop-ins, and the two processes that come back if one of
# them stops matching. Generalises the old `pgrep -x swayidle` check, which
# existed for exactly this reason.
for f in 90-bar.conf 90-swayidle.conf 95-autostart-policykit-agent.conf \
         60-bindings-screenshot.conf 60-bindings-volume.conf \
         60-bindings-brightness.conf 60-bindings-media.conf; do
    if [ ! -f "/etc/sway/config.d/$f" ]; then
        no "/etc/sway/config.d/$f is GONE -- Fedora's $f is live again"
    elif [ ! -f "/usr/share/sway/config.d/$f" ]; then
        no "/usr/share/sway/config.d/$f no longer exists -- the retirement matches nothing (upstream rename?)"
    elif grep -qvE '^[[:space:]]*(#|$)' "/etc/sway/config.d/$f"; then
        no "/etc/sway/config.d/$f has live directives -- it is meant to be comment-only"
    else
        ok "$f retired"
    fi
done
pgrep -x swayidle >/dev/null \
    && no "swayidle is running -- two idle daemons, both locking the screen" \
    || ok "swayidle correctly idle"

# Stale symlinks, which are not merely untidy in one directory.
#
# just link-dotfiles now prunes these, so a survivor means it has not been re-run
# since the shell swap deleted twenty-one dotfiles. In ~/.config/sway/config.d/ a
# dangling link is worse than clutter: layered-include globs the directory and
# matches the link by name, so it SHADOWS the /etc or /usr/share drop-in of the
# same name and sway says nothing.
noctalia_stale=$(find "$HOME/.config" -xtype l 2>/dev/null | wc -l)
if [ "$noctalia_stale" -eq 0 ]; then
    ok "no dangling symlinks in ~/.config"
else
    meh "$noctalia_stale dangling symlink(s) in ~/.config -- run just link-dotfiles to prune"
    find "$HOME/.config" -xtype l 2>/dev/null | sed 's/^/      /'
fi

if [[ $fail -gt $noctalia_fail_at_start ]]; then
    printf '    recent noctalia journal:\n'
    journalctl --user -u noctalia -b -n 10 --no-pager 2>/dev/null | sed 's/^/      /'
fi


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
#
# Three states, not two. The effective value is what GTK uses, but WHERE it
# comes from decides whether anything is left to clean up:
#
#   effective wrong                  FAIL. The desktop is not themed.
#   effective right, written in dconf WARN. Correct, but shadowing the image
#                                    default with a copy of it -- `dconf reset`
#                                    hands the key back to the override and is
#                                    the state to end at.
#   effective right, dconf empty     PASS. Coming from the image.
while read -r key want; do
    have=$(gsettings get org.gnome.desktop.interface "$key" 2>/dev/null | tr -d "'")
    user=$(dconf read "/org/gnome/desktop/interface/$key" 2>/dev/null | tr -d "'")
    if [[ "$have" != "$want" ]]; then
        no "portal $key = ${have:-unset}, wanted '$want' and the portal LOSES to nothing -- gsettings set org.gnome.desktop.interface $key '$want'"
    elif [[ -n "$user" ]]; then
        meh "portal $key = $have, but from dconf rather than the image override -- dconf reset /org/gnome/desktop/interface/$key"
    else
        ok "portal $key = $have (from the image override)"
    fi
done <<'KEYS'
gtk-theme adw-gtk3-dark
icon-theme Papirus-Dark
cursor-theme Adwaita
color-scheme prefer-dark
font-name Inter 10
monospace-font-name Hack Nerd Font Mono 10
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
# What is left of this list after the shell swap. swaync-client, cliphist,
# swappy and wlogout are all uninstalled; nmcli survives because it is still how
# a network is configured from a script, and wtype because the clipboard's
# auto-paste needs it.
for b in nmcli wtype; do
    command -v "$b" >/dev/null && ok "$b present" || no "$b MISSING"
done

# The linked-dotfile check, glob-driven rather than a hardcoded list. The old
# list named five files by hand and would have gone stale silently; this asks
# whether the shell's config is linked at all, which is the thing that actually
# stops the desktop looking like this repo.
noctalia_cfg="${XDG_CONFIG_HOME:-$HOME/.config}/noctalia"
if compgen -G "$noctalia_cfg/*.toml" >/dev/null; then
    noctalia_unlinked=""
    for f in "$noctalia_cfg"/*.toml; do
        [ -L "$f" ] || noctalia_unlinked="$noctalia_unlinked $(basename "$f")"
    done
    if [ -z "$noctalia_unlinked" ]; then
        ok "noctalia config linked ($(compgen -G "$noctalia_cfg/*.toml" | wc -l) files)"
    else
        # Not a failure: a real file here outranks nothing and may be deliberate.
        # But it is not this repo any more, and `just link-dotfiles` would rename
        # it to .bak-<stamp> rather than merge it.
        meh "noctalia config files are NOT symlinks:$noctalia_unlinked"
    fi
else
    no "no noctalia config in $noctalia_cfg -- the shell is running on its own defaults; run: just link-dotfiles"
fi

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
