#!/usr/bin/bash
# Post-boot checks, run from inside a Sway session; exits non-zero if anything critical fails.

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
# The staleness tripwire from the build, repeated here: swayfx needs an old wlroots.
ldd /usr/bin/sway 2>/dev/null | grep -q 'libwlroots-0.19.so' \
    && ok "sway links libwlroots-0.19 (the ABI swayfx was built against)" \
    || no "sway does NOT link libwlroots-0.19 -- swayfx ABI drift, rebuild needed"
ldd /usr/bin/sway 2>/dev/null | grep -q 'libscenefx' \
    && ok "sway links libscenefx (the effects renderer)" || no "libscenefx missing"
grep -q '^WLR_RENDERER=gles2$' /etc/sway/environment \
    && ok "WLR_RENDERER=gles2 (SwayFX fx_renderer is GLES2-only)" \
    || no "WLR_RENDERER is not gles2 -- SwayFX will run and draw NO effects, silently"
# Proof the effects config was read, not merely present: sway leaves its include list
# behind, and anything in it that failed to parse would have raised the bar checked below.
if grep -qs '/sway/config\.d/25-effects\.conf' /run/user/"$(id -u)"/sway/layered-include-*.conf; then
    ok "25-effects.conf is in this session's include list"
else
    meh "25-effects.conf not in this session's include list (reload after link-dotfiles?)"
fi
# sway puts up the same bar for a warning as for an error, and nothing else here raises one.
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
# This section and `just greeter-preview` are the only checks that see a real greeter,
# and each one below is a blank login screen if it fails.
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

# The state directory, which the build cannot check because /var is not in the image.
# A greeter that cannot use it comes up blank, and all three checks below are ways to get there.
state=/var/lib/noctalia-greeter
if [[ -d "$state" ]]; then
    ok "state directory present"
    [[ "$(stat -c '%U %a' "$state")" == "greetd 750" ]] \
        && ok "state directory is greetd:0750" \
        || no "state directory is $(stat -c '%U:%G %a' "$state"), not greetd 750 -- greeter cannot use it"
    # Without the SELinux alias from the build, this directory gets a label the greeter cannot write.
    [[ "$(ls -Zd "$state")" == *xdm_var_lib_t* ]] \
        && ok "state directory labelled xdm_var_lib_t" \
        || no "state directory is $(ls -Zd "$state" | awk '{print $1}') -- SELinux will deny the greeter"
    # Needs a privileged read, because this directory is not world-readable; with no cached
    # sudo it is skipped rather than failed, since unreadable is not the same as broken.
    # The value is matched loosely, because the greeter rewrites this file in its own style.
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

    # The image ships the avatar and `just greeter-avatar` binds it to the account;
    # if the second half is missing you just get the stock person icon, which looks deliberate.
    avatar=/usr/share/bazzite-sway/greeter-avatar.svg
    if [[ -s "$avatar" ]]; then
        ok "greeter avatar present in the image"
        # White and nothing else, since this is the only colour on the login screen we control.
        avatar_fills="$(grep -oE 'fill="[^"]*"' "$avatar" | sort -u | tr '\n' ' ')"
        [[ "$avatar_fills" == 'fill="#ffffff" ' ]] \
            && ok "greeter avatar inverted to white, and greyscale throughout" \
            || no "greeter avatar fills are [ ${avatar_fills}] -- expected only fill=\"#ffffff\""
        python3 -c 'import sys, xml.dom.minidom as m; m.parse(sys.argv[1])' "$avatar" 2>/dev/null \
            && ok "greeter avatar is well-formed XML" \
            || no "greeter avatar is not well-formed XML -- librsvg will draw nothing"
        # Read the way the greeter reads it, off the bus.
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

# Listing sessions needs no screen, so it runs here; an empty list is a login screen you cannot use.
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

# The fallback greeter, kept because it needs no compositor and no GPU.
command -v tuigreet >/dev/null && ok "tuigreet present (fallback)" \
    || no "tuigreet MISSING -- no fallback if the greeter fails"
command -v gtkgreet >/dev/null \
    && meh "gtkgreet still installed -- it was dropped with the sway greeter" \
    || ok "gtkgreet gone with the sway-hosted greeter"
# These can survive an upgrade after leaving the image; harmless, but confusing to find.
{ test -e /etc/greetd/environments || test -e /etc/gtkgreet/style.css; } \
    && meh "leftover gtkgreet-era files in /etc (environments, gtkgreet/style.css) -- unused, safe to delete" \
    || ok "no gtkgreet-era leftovers in /etc"

# If the greeter failed, the reason is in the journal, because it has nowhere to print.
if [[ $fail -gt $greeter_fail_at_start ]]; then
    printf '        --- journalctl -b -u greetd (last 10) ---\n'
    journalctl -b -u greetd --no-pager -n 10 2>/dev/null | sed 's/^/        /'
fi

head_ "Graphics"
swaymsg -t get_outputs -r 2>/dev/null | jq -r '.[] | "  output \(.name) \(.current_mode.width)x\(.current_mode.height)@\(.current_mode.refresh/1000)Hz  active=\(.active)"' 2>/dev/null
glxinfo -B 2>/dev/null | grep -q 'NVIDIA' && ok "GLX renderer is NVIDIA" || meh "glxinfo did not report NVIDIA (glxinfo installed?)"
vulkaninfo --summary 2>/dev/null | grep -q 'NVIDIA' && ok "Vulkan sees the NVIDIA GPU" || meh "vulkaninfo did not report NVIDIA"
pgrep -x Xwayland >/dev/null && ok "Xwayland running" || meh "Xwayland not running (no X11 client started yet)"

head_ "Workspaces (a block of ten per screen)"
# The layout is no longer written down anywhere, so these checks are the only statement of it.
ws_cfg="${XDG_CONFIG_HOME:-$HOME/.config}/sway"

# A helper that is not executable fails inside sway's `sh -c` with nothing on screen.
for h in workspace-block.sh xwayland-primary.sh; do
    if [ ! -e "$ws_cfg/$h" ]; then
        no "$h missing from ~/.config/sway -- run: just link-dotfiles"
    elif [ ! -L "$ws_cfg/$h" ]; then
        meh "$h is a real file, not a link into this repo -- what runs is not what is committed"
    elif [ ! -x "$ws_cfg/$h" ]; then
        no "$h is NOT executable -- sway's exec fails silently; chmod +x in dotfiles/ and commit the mode"
    else
        ok "$h linked and executable"
    fi
done

# One leftover pin would nail one number to one monitor while the other nine follow focus.
ws_read=$(awk -F"'" '/^include /{print $2}' /run/user/"$(id -u)"/sway/layered-include-*.conf 2>/dev/null)
if [ -z "$ws_read" ]; then
    meh "no layered-include list in /run/user/$(id -u)/sway -- cannot tell which drop-ins this session read"
else
    ws_pins=$(printf '%s\n/etc/sway/config\n' "$ws_read" \
        | xargs -d '\n' grep -lE '^[[:space:]]*workspace[[:space:]]+[0-9]+[[:space:]]+output' 2>/dev/null)
    [ -z "$ws_pins" ] \
        && ok "no per-monitor workspace pins in any file sway included" \
        || no "workspace N output pins survive -- those numbers ignore the blocks: $(echo $ws_pins | tr '\n' ' ')"
fi

# The swaynag check further up stops working once the bar is dismissed; this one does not.
ws_conf="$ws_cfg/config.d/40-bindings.conf"
if [ ! -r "$ws_conf" ]; then
    no "40-bindings.conf not readable at $ws_conf -- run: just link-dotfiles"
else
    ws_n=$(grep -cE '^bindsym .*workspace-block\.sh' "$ws_conf")
    ws_bare=$(grep -E '^bindsym .*workspace-block\.sh' "$ws_conf" | grep -cv -- '--no-warn' || true)
    if [ "$ws_n" -ne 20 ]; then
        no "$ws_n workspace bindings in 40-bindings.conf, expected 20 (\$mod+1..0 and \$mod+Shift+1..0)"
    elif [ "$ws_bare" -ne 0 ]; then
        no "$ws_bare workspace binding(s) without --no-warn -- each overwrites /etc/sway/config and raises the error bar"
    else
        ok "20 workspace bindings, all --no-warn"
    fi
fi

if [ -x "$ws_cfg/workspace-block.sh" ] && [ -n "${SWAYSOCK:-}" ]; then
    # The sorting rule lives here as well as in the helper, so check the two agree.
    ws_calc=$(swaymsg -t get_outputs -r 2>/dev/null | jq -r '
        [ .[] | select(.active) ] | sort_by(.rect.x, .rect.y, .name)
        | (map(.focused) | index(true)) as $i
        | select($i != null) | $i * 10 + 1' 2>/dev/null)
    ws_say=$("$ws_cfg/workspace-block.sh" print 1 2>/dev/null)
    if [ -z "$ws_say" ] || [ -z "$ws_calc" ]; then
        no "workspace-block.sh print 1 said nothing -- \$mod+1 falls back to one global set of ten"
    elif [ "$ws_say" != "$ws_calc" ]; then
        no "block DRIFT: workspace-block.sh puts \$mod+1 at $ws_say, left-to-right order says $ws_calc"
    else
        ok "\$mod+1 on the focused screen is workspace $ws_say (its block is $ws_say-$((ws_say + 9)))"
    fi

    # A warning, not a failure: unplugging a screen strands its workspaces on the survivor.
    ws_stray=$(swaymsg -t get_outputs -r 2>/dev/null | jq -r --argjson w "$(swaymsg -t get_workspaces -r 2>/dev/null)" '
        ([ .[] | select(.active) ] | sort_by(.rect.x, .rect.y, .name)) as $o
        | [ $w[] | select(.num >= 1 and .num <= ($o | length) * 10)
            | ((.num - 1) / 10 | floor) as $home
            | select(.output != $o[$home].name)
            | "\(.num) on \(.output), owned by \($o[$home].name)" ] | join("; ")' 2>/dev/null)
    [ -z "$ws_stray" ] \
        && ok "every workspace is on the screen that owns its block" \
        || meh "workspace on the wrong screen: $ws_stray (swaymsg reload repairs)"
fi

# Checked in the linked file, so the GUI state override warned about below can still beat it.
ws_bar="${XDG_CONFIG_HOME:-$HOME/.config}/noctalia/30-bar.toml"
grep -qE '^show_all_outputs[[:space:]]*=[[:space:]]*false' "$ws_bar" 2>/dev/null \
    && ok "bar lists only its own screen's workspaces" \
    || meh "show_all_outputs is not false in 30-bar.toml -- each bar draws both screens' blocks"

head_ "Desktop services"
# Only a process check, because polkit offers no way to ask which agent is registered
# short of calling pkexec and seeing whether it hangs.
pgrep -x noctalia >/dev/null \
    && ok "polkit agent: noctalia (the only one -- mate-polkit is gone)" \
    || no "no polkit agent -- pkexec, bazzite-user-setup and ujust will hang"
pgrep -f polkit-mate-authentication-agent >/dev/null \
    && meh "a mate-polkit agent is ALSO running -- two agents, one a leftover" \
    || ok "no second polkit agent"
# Installed because it cannot be removed, broken so it could not work anyway, and retired by config.
pgrep -f lxqt-policykit-agent >/dev/null \
    && no "lxqt-policykit-agent is running -- its sway drop-in was not retired" \
    || ok "lxqt-policykit correctly idle (installed, unstartable, retired)"
pgrep -x gnome-keyring-d >/dev/null && ok "gnome-keyring running (Secret portal backend)" \
    || meh "gnome-keyring not running -- app passwords will not persist"

# Nothing can start on demand to answer this, so with the shell down notify-send silently does nothing.
if busctl --user --no-pager status org.freedesktop.Notifications >/dev/null 2>&1; then
    ok "org.freedesktop.Notifications has an owner"
else
    no "nothing owns org.freedesktop.Notifications -- notify-send will do nothing"
fi

# The tray is load-bearing for the keyring: a Fedora drop-in waits for a tray host before
# starting the autostart apps, so no tray means no keyring rather than no tray.
systemctl --user is-active --quiet sway-xdg-autostart.target \
    && ok "sway-xdg-autostart.target active (the SNI host was found)" \
    || no "sway-xdg-autostart.target inactive -- wait-sni-ready timed out; keyring autostart did not run"

# waybar cannot be uninstalled, so one config file is all that keeps it off the screen.
pgrep -x waybar >/dev/null \
    && no "waybar is RUNNING -- /etc/sway/config.d/90-bar.conf did not retire Fedora's bar; there are two" \
    || ok "waybar correctly idle (installed, retired by /etc/sway/config.d/90-bar.conf)"

# foot is in this list on purpose, as the fallback if the GPU-accelerated terminal fails.
for b in ghostty foot Thunar wl-copy blueman-manager noctalia; do
    command -v "$b" >/dev/null && ok "$b present" || no "$b MISSING"
done

# The only way brightness works here at all, since both monitors are external.
if command -v ddcutil >/dev/null; then
    if compgen -G '/dev/i2c-*' >/dev/null; then
        ok "ddcutil present with /dev/i2c-* (monitor brightness is possible)"
    else
        meh "ddcutil present but no /dev/i2c-* -- brightness keys will do nothing"
    fi
else
    meh "ddcutil missing -- there is no other brightness path on this hardware"
fi


# The applet is installed but not autostarted, because the bar already draws bluetooth
# and blueman's icon is full-colour artwork nothing here can restyle.
if grep -qs '^Hidden=true' "$HOME/.config/autostart/blueman.desktop"; then
    ok "blueman applet suppressed (Hidden=true)"
else
    meh "blueman applet not suppressed -- expect a duplicate, unthemeable tray icon"
fi
rpm -q --quiet network-manager-applet \
    && meh "network-manager-applet is installed again -- it will race noctalia as NM's secret agent" \
    || ok "network-manager-applet gone (noctalia is the NM secret agent)"

# Downloaded rather than packaged, and if it vanishes the icons keep working while the
# text quietly falls back, which is easy to miss.
fc-list -q 'Hack Nerd Font Mono' && ok "Hack Nerd Font Mono installed" \
    || no "Hack Nerd Font Mono MISSING -- bar, terminal and launcher fall back to Noto"

# If the build's edit to this line ever stops matching, $mod+Return quietly opens foot again.
grep -q '^set \$term ghostty$' /etc/sway/config \
    && ok "sway \$term is ghostty" \
    || no "sway \$term is not ghostty -- \$mod+Return will open foot"
infocmp xterm-ghostty >/dev/null 2>&1 && ok "xterm-ghostty terminfo present" \
    || no "xterm-ghostty terminfo MISSING -- ssh and curses apps will misbehave"

head_ "Shell (noctalia)"
# The most important section here: nine subsystems sit behind this one process with no fallback,
# and when it dies there is simply no bar, no notifications and no lock, with no error anywhere.
# $mod+Return still opens a terminal, which is what makes that recoverable.
noctalia_fail_at_start=$fail

rpm -q --quiet noctalia && ok "noctalia installed ($(rpm -q noctalia 2>/dev/null))" \
    || no "noctalia NOT installed -- there is no desktop shell on this image"
# Must be the Fedora build; the greeter comes from Terra and this deliberately does not.
if rpm -q --quiet noctalia; then
    [[ "$(rpm -q --queryformat '%{VENDOR}' noctalia)" == "Fedora Project" ]] \
        && ok "noctalia is the Fedora build" \
        || meh "noctalia vendor is $(rpm -q --queryformat '%{VENDOR}' noctalia) -- expected Fedora Project"
fi

# The single most important line in this file.
if systemctl --user is-active --quiet noctalia; then
    ok "noctalia.service active"
else
    no "noctalia.service NOT active -- no bar, no notifications, no lock, no polkit"
    journalctl --user -u noctalia -b -n 5 --no-pager 2>/dev/null | sed 's/^/      /'
fi
[ -L /usr/lib/systemd/user/sway-session.target.wants/noctalia.service ] \
    && ok "noctalia wanted by sway-session.target" \
    || no "noctalia not wired to sway-session.target -- it will not return on next login"

# A second process is not a second shell, but it is evidence something starts it twice.
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
# 18-noctalia-shell.sh proves at build time that it works in both directions,
# which is what makes this run meaningful.
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

# Anything changed in the settings window lands in a file that outranks this whole repo,
# is not version-controlled, and cannot be found by reading dotfiles/; deleting it hands control back.
if [ -s "$HOME/.local/state/noctalia/settings.toml" ]; then
    meh "settings.toml exists and OUTRANKS dotfiles/noctalia -- rm ~/.local/state/noctalia/settings.toml to hand control back"
else
    ok "no GUI settings override (dotfiles/noctalia is what is running)"
fi

# The palette exists twice on purpose, and if the copies drift the login screen just
# stops matching, which reads as a rendering quirk rather than a bug.
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

# A misspelled namespace in 25-effects.conf is not an error, just a panel that is never
# frosted, so ask the compositor what it actually applied.
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

# Read from the plugin's own manifest, so a widget dropped from it shows up here.
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
    # And that the shell loaded it, since otherwise the widgets are just absent from the bar.
    if noctalia msg plugins list 2>/dev/null | grep -q 'bazzite-sway'; then
        ok "bazzite-sway plugin loaded by the shell"
    else
        no "bazzite-sway plugin NOT loaded -- mode, scratchpad, failed-units and hardware are absent from the bar"
    fi
else
    meh "bazzite-sway plugin not linked (run just link-dotfiles?)"
fi

# The thresholds are written twice, and nothing at runtime would notice them disagreeing:
# the bar would go bright while the panel still called the machine fine.
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

# The retired Fedora drop-ins, and the processes that come back if one stops matching.
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

# Not merely untidy: in sway/config.d/ a dangling link hides the real drop-in of the
# same name, and sway says nothing about it.
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

# These two stylesheets are the only thing taking Adwaita's blue out of GTK.
for f in gtk-3.0/gtk.css gtk-4.0/gtk.css; do
    test -e "${XDG_CONFIG_HOME:-$HOME/.config}/$f" \
        && ok "$f linked" \
        || no "$f NOT linked -- GTK keeps Adwaita's blue accent (run: just link-dotfiles)"
done

# The silent one: on Wayland GTK asks the portal for these, and the portal beats
# settings.ini every time without logging anything.
# Three outcomes, because where the value came from decides whether there is anything to clean up:
# wrong is a failure, right but written in dconf is a warning, right from the image passes.
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

# One old-style colour block themes GTK3 and GTK4 alike only because libadwaita still
# reads it; if that stops, the GTK4 stylesheet silently themes nothing.
if gresource extract /usr/lib64/libadwaita-1.so.0 /org/gnome/Adwaita/styles/gtk.css 2>/dev/null \
     | grep -q -- '--window-bg-color:[[:space:]]*@window_bg_color'; then
    ok "libadwaita still sources its CSS variables from @define-color"
else
    no "libadwaita no longer sources --window-bg-color from @window_bg_color -- gtk-4.0/gtk.css needs a :root block for every colour"
fi
# Baked in at build time, since the icon directory is read-only later.
# Check a user icon as well, because that one only exists if the full set was linked.
if readlink /usr/share/icons/Papirus/48x48/places/folder.svg 2>/dev/null | grep -q 'folder-black'; then
    ok "Papirus folders are black"
else
    no "Papirus folders are NOT black -- papirus-folders did not run, or was reverted by an update"
fi
readlink /usr/share/icons/Papirus/48x48/places/user-home.svg 2>/dev/null | grep -q 'user-black' \
    && ok "user-* icons recoloured too (Home, Desktop)" \
    || meh "user-home.svg not recoloured -- only the folder* half was linked"

head_ "New helpers"
# What is left of this list after the shell swap: scripting the network, and clipboard pasting.
for b in nmcli wtype; do
    command -v "$b" >/dev/null && ok "$b present" || no "$b MISSING"
done

# Globbed rather than a hardcoded list, which would go stale without saying so.
noctalia_cfg="${XDG_CONFIG_HOME:-$HOME/.config}/noctalia"
if compgen -G "$noctalia_cfg/*.toml" >/dev/null; then
    noctalia_unlinked=""
    for f in "$noctalia_cfg"/*.toml; do
        [ -L "$f" ] || noctalia_unlinked="$noctalia_unlinked $(basename "$f")"
    done
    if [ -z "$noctalia_unlinked" ]; then
        ok "noctalia config linked ($(compgen -G "$noctalia_cfg/*.toml" | wc -l) files)"
    else
        # Not a failure, but it is not this repo any more, and link-dotfiles would rename it.
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
# Plasma's icons and cursors are deliberately not in this list any more; nothing uses them.
for p in kf6-kwallet btrfs-assistant bazzite-updater; do
    rpm -q --quiet "$p" && ok "$p installed" || no "$p removed"
done

head_ "Sessions offered"
# This directory is the login screen's entire session list, and nothing else is read.
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
