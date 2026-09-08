#!/usr/bin/bash
# Install the Sway session and the surrounding desktop essentials.
set -euxo pipefail

CTX="${CTX:-/ctx}"

# WEAK DEPS ARE OFF: the Bazzite base sets install_weak_deps=False in
# /etc/dnf/dnf.conf, so nothing arrives via Recommends and every package this
# desktop needs must be named below.
#
# WHAT CANNOT BE REMOVED. sway-config-fedora owns /etc/sway/config, start-sway,
# layered-include and the wayland-sessions entry, so it cannot be dropped -- and
# it hard-Requires waybar, swaylock, swayidle, swaybg, grimshot (which drags grim
# and slurp), brightnessctl, playerctl and lxqt-policykit. Those are plain
# Requires: they stay installed no matter what this list says. What retires them
# is a comment-only file of the same name in /etc/sway/config.d/, shipped by
# 18-noctalia-shell.sh. DO NOT --exclude any of them -- excluding a hard
# dependency makes the transaction unresolvable, which is a failed build.
#
# rofi is the exception worth knowing: sway-config-fedora *Recommends*
# rofi-wayland, which does not exist in F44 -- the `rofi` package Provides that
# name. With weak deps off the Recommends is inert, so the exclude is only a
# guard for the day dnf.conf changes. It works because nothing else satisfies
# that provide.
#
# --exclude is a dnf5 GLOBAL option: it must come before the subcommand.
dnf5 --exclude=sway-config-upstream,rofi install -y \
    sway \
    sway-config-fedora \
    sway-systemd \
    swaybg \
    greetd \
    tuigreet \
    xdg-desktop-portal-wlr \
    xdg-desktop-portal-gtk \
    gnome-keyring \
    gnome-keyring-pam \
    noctalia \
    foot \
    Thunar \
    thunar-archive-plugin \
    xarchiver \
    gvfs-smb \
    gvfs-mtp \
    pavucontrol \
    imv \
    wl-clipboard \
    wtype \
    ddcutil \
    wlr-randr \
    kanshi \
    wlsunset \
    blueman \
    wev \
    adw-gtk3-theme \
    papirus-icon-theme-dark \
    rsms-inter-fonts

# ddcutil and wtype are noctalia *Recommends*, so with weak deps off they have to
# be named above: ddcutil is the only brightness control this desktop has
# (/sys/class/backlight is empty -- both outputs are external), and wtype is the
# clipboard panel's auto-paste. 18-noctalia-shell.sh asserts both.
rpm -q noctalia
test -x /usr/bin/noctalia

# ghostty is not in Fedora -- it comes from Terra, which the base image already
# ships disabled with its key already trusted.
#
# ITS OWN TRANSACTION, DELIBERATELY. --enable-repo is a dnf5 global like
# --exclude, so folding it into the list above would let Terra satisfy any
# package there and silently swap Fedora builds for Terra ones.
#
# ghostty-terminfo comes along as a hard Requires, and it matters: ghostty sets
# TERM=xterm-ghostty, and without the terminfo entry every ssh session and curses
# app misbehaves in a way that looks nothing like a terminal problem.
dnf5 --enable-repo=terra install -y ghostty

rpm -q ghostty ghostty-terminfo
test -x /usr/bin/ghostty
test -f /usr/share/applications/com.mitchellh.ghostty.desktop
test -f /usr/share/terminfo/x/xterm-ghostty

# foot stays installed but unbound, as a fallback: losing the only terminal on a
# tiling WM is a bad way to discover a GPU problem. It is a WEAK dependency of
# sway-config-fedora, so dropping it later needs foot added to the --exclude
# above; deleting it from the list is not enough.
rpm -q foot

# Hack Nerd Font, vendored: no repo this image trusts carries a patched Hack.
# The base `nerd-fonts` package is symbols-only with no Latin glyphs -- not a
# substitute for the patched face.
#
# Pinned by version AND checksum. This and papirus-folders below are the only
# two artifacts in the build that do not come from a GPG-verified repo, so the
# hash is what makes them reproducible. Bump both together.
#
# All three variants extracted (2.7MB): Mono forces icons to one cell, plain
# doubles them, Propo is proportional. Switching is then a config edit.
NERD_FONTS_VERSION=3.5.1
HACK_SHA256=cdd389472e10e2261520140ff1b382b4f8a226af5fd0b2735b975d31151d9c3c

curl -fsSL -o /tmp/Hack.tar.xz \
    "https://github.com/ryanoasis/nerd-fonts/releases/download/v${NERD_FONTS_VERSION}/Hack.tar.xz"
echo "${HACK_SHA256}  /tmp/Hack.tar.xz" | sha256sum -c -

install -d -m0755 /usr/share/fonts/hack-nerd-fonts
tar -xJf /tmp/Hack.tar.xz -C /usr/share/fonts/hack-nerd-fonts --no-same-owner
chmod 0644 /usr/share/fonts/hack-nerd-fonts/*
rm -f /tmp/Hack.tar.xz
fc-cache -f /usr/share/fonts/hack-nerd-fonts

# Asserted because a font that fails to install does not break the build, it
# silently falls back to Noto at runtime.
test -f /usr/share/fonts/hack-nerd-fonts/HackNerdFontMono-Regular.ttf
# `fc-list -q`, NOT `fc-list | grep -q`. grep -q exits on its first match,
# fc-list takes SIGPIPE, and pipefail turns that into exit 141 -- a green check
# that kills the build. Same trap as the papirus check below.
fc-list -q 'Hack Nerd Font Mono'


# Asserted for the same reason as the font: none of these failing breaks the
# build, they just fall back at runtime to something that looks almost right.
test -d /usr/share/themes/adw-gtk3-dark
test -d /usr/share/icons/Papirus-Dark
fc-list -q 'Inter'

# INSTALLING A THEME IS NOT CHOOSING IT. On Wayland GTK does not read
# gtk-theme-name, gtk-icon-theme-name, gtk-cursor-theme-name or gtk-font-name
# from settings.ini at all -- it asks the XDG portal, which answers from
# org.gnome.desktop.interface in dconf, and the portal wins for every key it
# serves. Before this override, settings.ini asked for adw-gtk3-dark /
# Papirus-Dark / Adwaita / Inter and GTK reported Adwaita / breeze-dark /
# breeze_cursors / Noto Sans -- Plasma-era values kde-gtk-config wrote into
# dconf, where 30-kde-remove.sh cannot follow.
install -Dpm0644 "${CTX}/system_files/usr/share/glib-2.0/schemas/90-bazzite-sway.gschema.override" \
                 /usr/share/glib-2.0/schemas/90-bazzite-sway.gschema.override
glib-compile-schemas /usr/share/glib-2.0/schemas/

# Read the result back rather than trusting the write: glib-compile-schemas
# WARNS about an override naming a missing schema or key and still exits 0, so a
# typo is not a build failure, it is a desktop in stock Adwaita with nothing to
# show why. The memory backend returns the compiled default and needs no dconf
# daemon.
while read -r key want; do
    got="$(GSETTINGS_BACKEND=memory gsettings get org.gnome.desktop.interface "$key" | tr -d "'")"
    [[ "${got}" == "${want}" ]] || {
        echo "gschema override did not take: ${key} is ${got}, wanted ${want}" >&2
        exit 1
    }
done <<'KEYS'
gtk-theme adw-gtk3-dark
icon-theme Papirus-Dark
cursor-theme Adwaita
color-scheme prefer-dark
font-name Inter 10
monospace-font-name Hack Nerd Font Mono 10
KEYS

# Black folder icons. Vendored and pinned like the font above, fetched at a tag
# rather than as a generated tarball so the hash is stable.
#
# HAS TO RUN IN THE BUILD: it replaces folder*.svg with symlinks inside
# /usr/share/icons/Papirus/*/places/, which is read-only at runtime.
PAPIRUS_FOLDERS_VERSION=1.14.0
PAPIRUS_FOLDERS_SHA256=b30a6848a00690302accffc050549218b0b114d3178b28bd3a16891817821b06

curl -fsSL -o /tmp/papirus-folders \
    "https://raw.githubusercontent.com/PapirusDevelopmentTeam/papirus-folders/v${PAPIRUS_FOLDERS_VERSION}/papirus-folders"
echo "${PAPIRUS_FOLDERS_SHA256}  /tmp/papirus-folders" | sha256sum -c -
chmod +x /tmp/papirus-folders

# -t Papirus, NEVER Papirus-Dark. Fedora puts the colour variants only in the
# main papirus-icon-theme; the dark package ships nothing under 48x48/places/,
# and papirus-folders enumerates its colours from there -- aimed at the dark
# theme it finds none at all. The dark package inherits places/ via index.theme,
# so recolouring the parent gives Papirus-Dark black folders for free.
#
# Captured into a variable and matched with a here-string, NOT piped into
# `grep -q`: that is the SIGPIPE trap described at the fc-list check above, and
# here it would turn a SUCCESSFUL assertion into exit 141.
papirus_colours="$(/tmp/papirus-folders -t Papirus -l)"
grep -qw black <<<"${papirus_colours}"

# -o  do not write the state file. It would land in /var, whose content a bootc
#     image only applies on INITIAL provisioning. The symlinks are the state.
# -u  rebuild the icon caches -- Papirus ships a prebuilt one and a stale cache
#     shadows the new symlinks. v1.14.0 updates siblings, which reaches
#     Papirus-Dark.
/tmp/papirus-folders -t Papirus -C black -o -u -v

# The variant set covers user-* as well as folder-*, ~400 symlinks across five
# sizes, so assert one of each. Pattern matching on a captured value, which
# cannot SIGPIPE.
test -L /usr/share/icons/Papirus/48x48/places/folder.svg
[[ "$(readlink /usr/share/icons/Papirus/48x48/places/folder.svg)"    == *folder-black* ]]
[[ "$(readlink /usr/share/icons/Papirus/48x48/places/user-home.svg)" == *user-black*   ]]

rm -f /tmp/papirus-folders

# Re-running on every nightly rebuild means a papirus-icon-theme update that
# restores the stock blue folder.svg is re-blackened in the same build. It also
# means `rpm -V papirus-icon-theme` reports those files as modified -- that is
# this, not corruption.


# THIS HAS TO HAPPEN AT THE SOURCE, not in a config.d drop-in: sway expands
# `set` variables at PARSE TIME, and /etc/sway/config uses $term long before the
# layered-include on its last line reads ~/.config/sway/config.d/. A late
# `set $term ghostty` there does nothing. (A `bindsym` in a later drop-in DOES
# win, which is why nothing else here needs a sed.)
#
# Asserted because a silent no-op is invisible until you press $mod+Return.
sed -i 's|^set \$term foot$|set $term ghostty|' /etc/sway/config
grep -q '^set \$term ghostty$' /etc/sway/config

# THE POLKIT AGENT is noctalia, and three traps make that load-bearing. A
# missing agent is silent until something calls pkexec, and then it HANGS rather
# than failing.
#
#  1. lxqt-policykit, the obvious choice, is BROKEN on F44: it links libQt6Xdg,
#     which uses Qt private API and has not been rebuilt against qt6-qtbase
#     6.11, so it installs fine and fails only at exec. It also cannot be
#     excluded -- sway-config-fedora hard-Requires it.
#  2. Every packaged agent's /etc/xdg/autostart entry is guarded by OnlyShowIn=
#     (LXQt;, MATE;, KDE;). XDG_CURRENT_DESKTOP is "sway", so the systemd XDG
#     autostart generator skips all of them and the session comes up with NO
#     agent. That is why noctalia is bound to sway-session.target in
#     18-noctalia-shell.sh instead.
#  3. /usr/share/sway/config.d/95-autostart-policykit-agent.conf execs
#     lxqt-policykit from sway's own config, bypassing OnlyShowIn entirely, so
#     dotfiles/sway/config.d/95-autostart-policykit-agent.conf shadows it to
#     nothing. verify.sh checks lxqt-policykit is installed and NOT running,
#     which is the only way that shadow file's absence would show.

# nvidia-settings' autostart runs an X11-only operation and exits 1 under
# Wayland, leaving a permanently failed user unit on every login. Hidden=true is
# the XDG-specified retirement and the systemd generator emits no unit at all.
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
# xdg-desktop-portal.service refuses to start (Requisite=graphical-session.target,
# RHBZ 2481764), silently breaking Flatpak file dialogs, screen sharing and the
# Steam overlay.
rpm -q sway-systemd

# sway ships its own portals config, so there is none to write here.
test -f /usr/share/xdg-desktop-portal/sway-portals.conf

# start-sway sources this file.
cat >> /etc/sway/environment <<'ENVEOF'

### Bazzite-Sway: NVIDIA (nvidia-open, Ada) ####################################
# MANDATORY: sway 1.11 hard-exits when the DRM driver is named "nvidia-drm", and
# the open kernel modules match that check too. -D noscanout disables direct
# scanout, the standard wlroots-on-NVIDIA fix for flicker and black frames.
SWAY_EXTRA_ARGS="$SWAY_EXTRA_ARGS --unsupported-gpu -D noscanout"

# GLES2, not Vulkan, and this is a SwayFX constraint rather than a preference:
# every effect lives in its fx_renderer, which is GLES2-only. Left at vulkan you
# get a compositor that starts, works, and silently draws none of the effects.
# The cost is real -- vulkan is what wlroots recommends on NVIDIA.
WLR_RENDERER=gles2

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
