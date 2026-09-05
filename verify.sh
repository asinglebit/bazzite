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
pgrep -x mako >/dev/null && ok "mako running" || meh "mako not running"
pgrep -x waybar >/dev/null && ok "waybar running" || meh "waybar not running"
for b in foot rofi Thunar grimshot wl-copy swaylock blueman-applet nm-applet; do
    command -v "$b" >/dev/null && ok "$b present" || no "$b MISSING"
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
for p in kf6-kwallet btrfs-assistant bazzite-updater breeze-icon-theme; do
    rpm -q --quiet "$p" && ok "$p installed" || no "$p removed"
done

head_ "Sessions offered"
ls /usr/share/wayland-sessions/
if rpm -q --quiet plasma-workspace; then
    meh "Plasma still installed (expected on the :test image, not on :latest)"
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
