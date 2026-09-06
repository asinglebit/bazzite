#!/usr/bin/bash
# Install the Sway session and the surrounding desktop essentials.
set -euxo pipefail

CTX="${CTX:-/ctx}"

# Weak deps stay ON deliberately: that is how sway-config-fedora pulls in
# grimshot, rofi, qt5/qt6-qtwayland, xdg-user-dirs and sway-systemd. It also
# matches what Fedora Sway Atomic ships.
# --exclude is a dnf5 GLOBAL option: it has to come before the subcommand.
dnf5 --exclude=sway-config-upstream install -y \
    sway \
    sway-config-fedora \
    sway-systemd \
    swaybg \
    swayidle \
    swaylock \
    greetd \
    tuigreet \
    xdg-desktop-portal-wlr \
    xdg-desktop-portal-gtk \
    gnome-keyring \
    gnome-keyring-pam \
    mate-polkit \
    waybar \
    foot \
    rofi \
    mako \
    wlogout \
    Thunar \
    thunar-archive-plugin \
    xarchiver \
    gvfs-smb \
    gvfs-mtp \
    pavucontrol \
    imv \
    grim \
    slurp \
    grimshot \
    wl-clipboard \
    wlr-randr \
    kanshi \
    wlsunset \
    brightnessctl \
    playerctl \
    network-manager-applet \
    blueman \
    wev

# The terminal.
#
# ghostty is not in Fedora at all -- it comes from Terra (Fyra Labs), which the
# base image already ships at /etc/yum.repos.d/terra.repo with enabled=0, and
# whose signing key is already in /etc/pki/rpm-gpg/. Bazzite itself enables
# terra-mesa, so this is a repo the artifact already trusts rather than a new
# trust root.
#
# Deliberately its OWN transaction. --enable-repo is a dnf5 global like
# --exclude, so folding it into the list above would let Terra satisfy any
# package in that list and silently swap Fedora builds for Terra ones.
#
# ghostty-terminfo is a hard Requires, so it comes along on its own. That
# matters more than it looks: ghostty sets TERM=xterm-ghostty, and without the
# terminfo entry every ssh session and every curses app misbehaves in a way
# that looks nothing like a terminal problem.
dnf5 --enable-repo=terra install -y ghostty

rpm -q ghostty ghostty-terminfo
test -x /usr/bin/ghostty
test -f /usr/share/applications/com.mitchellh.ghostty.desktop
test -f /usr/share/terminfo/x/xterm-ghostty

# foot stays installed, just unbound, as a fallback: ghostty is GPU-accelerated
# and this is an NVIDIA box under --unsupported-gpu, and losing the only
# terminal on a tiling WM is a bad way to discover that. It is also a *weak*
# dependency of sway-config-fedora, so dropping it later needs foot added to
# the --exclude above -- deleting the line from the list is not enough.
rpm -q foot

# Point sway's $term at ghostty.
#
# This has to happen at the source, not in a config.d drop-in. sway expands
# `set` variables at parse time, and /etc/sway/config uses $term twice --
# `bindsym $mod+Return exec $term` and rofi's `-terminal '$term'` -- both baked
# long before the layered-include on the final line reads
# ~/.config/sway/config.d/. A late `set $term ghostty` there does nothing at all.
#
# Asserted because a silent no-op is invisible until you press $mod+Return and
# get foot.
sed -i 's|^set \$term foot$|set $term ghostty|' /etc/sway/config
grep -q '^set \$term ghostty$' /etc/sway/config

# The polkit authentication agent.
#
# Two separate traps here, both of which cost a boot to find:
#
#  1. lxqt-policykit -- the obvious LXQt-agnostic choice -- is BROKEN on F44.
#     It links libQt6Xdg, which uses Qt *private* API and has not been rebuilt
#     against qt6-qtbase 6.11:
#       symbol lookup error: /usr/lib64/libQt6Xdg.so.4: undefined symbol:
#       _ZN14QObjectPrivateC2E16QtPrivate_6_11_2, version Qt_6.11_PRIVATE_API
#     It installs fine and fails only at exec. mate-polkit is GTK3 and needs
#     nothing that Thunar/nm-applet/blueman have not already pulled in.
#     NOTE: lxqt-policykit stays installed regardless -- sway-config-fedora
#     *hard-Requires* it, so it cannot be dropped without dropping the Fedora
#     sway config. That is harmless: OnlyShowIn=LXQt means it never starts.
#     Do not waste time trying to exclude it.
#
#  2. Every packaged polkit agent ships an /etc/xdg/autostart entry guarded by
#     OnlyShowIn= (LXQt;, MATE;, KDE;). XDG_CURRENT_DESKTOP is "sway", so the
#     systemd XDG autostart generator skips all of them and the session comes
#     up with NO agent at all -- pkexec, ujust and bazzite-user-setup then hang
#     with no error. Bind the agent to sway-session.target instead of fighting
#     OnlyShowIn.
rpm -q mate-polkit
test -x /usr/libexec/polkit-mate-authentication-agent-1

install -Dpm0644 \
    "${CTX}/system_files/usr/lib/systemd/user/polkit-mate-authentication-agent-1.service" \
    /usr/lib/systemd/user/polkit-mate-authentication-agent-1.service

# Ship the enablement symlink directly rather than relying on a user preset:
# `systemctl --global enable` writes into /etc, which bootc then has to 3-way
# merge on every upgrade, and user presets only run for users created later.
install -d /usr/lib/systemd/user/sway-session.target.wants
ln -sfn ../polkit-mate-authentication-agent-1.service \
    /usr/lib/systemd/user/sway-session.target.wants/polkit-mate-authentication-agent-1.service

# nvidia-settings' autostart entry runs `nvidia-settings --load-config-only`,
# which is an X11-only operation and exits 1 under a Wayland session. Harmless,
# but it leaves a permanently failed user unit on every login. Hidden=true is
# the XDG-specified way to retire an autostart entry; the systemd
# xdg-autostart-generator honours it and emits no unit at all.
if [[ -f /etc/xdg/autostart/nvidia-settings-load.desktop ]]; then
    cat > /etc/xdg/autostart/nvidia-settings-load.desktop <<'DESKEOF'
[Desktop Entry]
Type=Application
Name=NVIDIA X Server Settings
Exec=/usr/bin/nvidia-settings --load-config-only
# X11-only; this session is Wayland. See bazzite-sway build_files/10-sway-install.sh
Hidden=true
DESKEOF
fi

# sway-systemd is what reaches graphical-session.target. Without it
# xdg-desktop-portal.service refuses to start (it carries
# Requisite=graphical-session.target, RHBZ 2481764), which silently breaks
# Flatpak file dialogs, screen sharing and the Steam overlay.
rpm -q sway-systemd

# sway ships /usr/share/xdg-desktop-portal/sway-portals.conf itself
# (gtk for everything, wlr for ScreenCast/Screenshot, gnome-keyring for Secret),
# so there is no portals config to write here.
test -f /usr/share/xdg-desktop-portal/sway-portals.conf

# NVIDIA. start-sway sources this file, and so would an SDDM sway greeter.
cat >> /etc/sway/environment <<'ENVEOF'

### Bazzite-Sway: NVIDIA (nvidia-open, Ada) ####################################
# sway 1.11 hard-exits when the DRM driver is named "nvidia-drm" — the open
# kernel modules are matched by that check too, so this flag is mandatory.
# -D noscanout disables direct scanout, the standard wlroots-on-NVIDIA fix for
# flicker and black frames.
SWAY_EXTRA_ARGS="$SWAY_EXTRA_ARGS --unsupported-gpu -D noscanout"

# Vulkan renderer is the recommended one on NVIDIA.
WLR_RENDERER=vulkan

# VA-API through the already-installed libva-nvidia-driver.
LIBVA_DRIVER_NAME=nvidia
NVD_BACKEND=direct

# Electron apps on native Wayland rather than Xwayland.
ELECTRON_OZONE_PLATFORM_HINT=auto

# Deliberately NOT set:
#   GBM_BACKEND=nvidia-drm      obsolete since glvnd picks the backend itself
#   WLR_NO_HARDWARE_CURSORS=1   only needed if the cursor misbehaves on 610.x
################################################################################
ENVEOF
