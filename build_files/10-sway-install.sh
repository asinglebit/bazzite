#!/usr/bin/bash
# Install the Sway session and the surrounding desktop essentials.
set -euxo pipefail

CTX="${CTX:-/ctx}"

# Optional dependencies are off in this base image, so everything needed must be named here.
# sway-config-fedora drags in waybar and swaylock, which config retires rather than excludes.
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

# ddcutil and wtype are optional deps of noctalia, so they had to be named above.
rpm -q noctalia
test -x /usr/bin/noctalia

# Its own transaction, so Terra cannot quietly satisfy anything in the list above.
dnf5 --enable-repo=terra install -y ghostty

rpm -q ghostty ghostty-terminfo
test -x /usr/bin/ghostty
test -f /usr/share/applications/com.mitchellh.ghostty.desktop
test -f /usr/share/terminfo/x/xterm-ghostty

# foot stays as a fallback terminal, because losing the only terminal is a bad way to find a bug.
rpm -q foot

# Downloaded because no trusted repo carries it, so it is pinned by checksum.
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

# A font that failed to install would not break the build, it would just silently fall back.
test -f /usr/share/fonts/hack-nerd-fonts/HackNerdFontMono-Regular.ttf
# Never pipe this into `grep -q`, which fails the build on a check that actually passed.
fc-list -q 'Hack Nerd Font Mono'


# Same reason as the font: failing these looks almost right rather than broken.
test -d /usr/share/themes/adw-gtk3-dark
test -d /usr/share/icons/Papirus-Dark
fc-list -q 'Inter'

# On Wayland GTK ignores settings.ini and asks the portal, which answers from dconf.
install -Dpm0644 "${CTX}/system_files/usr/share/glib-2.0/schemas/90-bazzite-sway.gschema.override" \
                 /usr/share/glib-2.0/schemas/90-bazzite-sway.gschema.override
glib-compile-schemas /usr/share/glib-2.0/schemas/

# Read back rather than trusted, because a typo here only warns and still exits 0.
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

# Runs during the build, because it edits a directory that is read-only later.
PAPIRUS_FOLDERS_VERSION=1.14.0
PAPIRUS_FOLDERS_SHA256=b30a6848a00690302accffc050549218b0b114d3178b28bd3a16891817821b06

curl -fsSL -o /tmp/papirus-folders \
    "https://raw.githubusercontent.com/PapirusDevelopmentTeam/papirus-folders/v${PAPIRUS_FOLDERS_VERSION}/papirus-folders"
echo "${PAPIRUS_FOLDERS_SHA256}  /tmp/papirus-folders" | sha256sum -c -
chmod +x /tmp/papirus-folders

# Papirus, never Papirus-Dark: only the light package ships the colour variants.
papirus_colours="$(/tmp/papirus-folders -t Papirus -l)"
grep -qw black <<<"${papirus_colours}"

# -o skips a state file that would land in /var and be lost; -u rebuilds the icon caches.
/tmp/papirus-folders -t Papirus -C black -o -u -v

# About 400 symlinks get made, so check one of each kind.
test -L /usr/share/icons/Papirus/48x48/places/folder.svg
[[ "$(readlink /usr/share/icons/Papirus/48x48/places/folder.svg)"    == *folder-black* ]]
[[ "$(readlink /usr/share/icons/Papirus/48x48/places/user-home.svg)" == *user-black*   ]]

rm -f /tmp/papirus-folders

# rpm reports these icons as modified, which is this script, not damage.


# sway reads $term before the drop-in directory, so a drop-in would do nothing.
sed -i 's|^set \$term foot$|set $term ghostty|' /etc/sway/config
grep -q '^set \$term ghostty$' /etc/sway/config

# noctalia is the only polkit agent here, and a missing one hangs pkexec silently.

# This autostart entry is X11-only and fails on every login, so hide it properly.
if [[ -f /etc/xdg/autostart/nvidia-settings-load.desktop ]]; then
    cat > /etc/xdg/autostart/nvidia-settings-load.desktop <<'DESKEOF'
[Desktop Entry]
Type=Application
Name=NVIDIA X Server Settings
Exec=/usr/bin/nvidia-settings --load-config-only
# X11-only, and this session is Wayland.
Hidden=true
DESKEOF
fi

# Without sway-systemd the portal never starts, which quietly breaks file dialogs and screen sharing.
rpm -q sway-systemd

# sway ships its own portals config, so there is nothing to write.
test -f /usr/share/xdg-desktop-portal/sway-portals.conf

# start-sway sources this file.
cat >> /etc/sway/environment <<'ENVEOF'

### Bazzite-Sway: NVIDIA (nvidia-open, Ada) ####################################
# sway refuses to start on this driver without the first flag; the second fixes NVIDIA flicker.
SWAY_EXTRA_ARGS="$SWAY_EXTRA_ARGS --unsupported-gpu -D noscanout"

# On Vulkan SwayFX starts and draws none of its effects.
WLR_RENDERER=gles2

# Hardware video decoding.
LIBVA_DRIVER_NAME=nvidia
NVD_BACKEND=direct

# Electron apps run on Wayland rather than Xwayland.
ELECTRON_OZONE_PLATFORM_HINT=auto

# GBM_BACKEND is deliberately unset, because it is obsolete.
################################################################################
ENVEOF
