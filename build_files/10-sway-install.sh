#!/usr/bin/bash
# Install the Sway session and the surrounding desktop essentials.
set -euxo pipefail

CTX="${CTX:-/ctx}"

# Optional dependencies are off in this base image, so everything needed must be named here.
# sway-config-fedora cannot be dropped and drags in waybar, swaylock and others; they are
# retired by config in 18-noctalia-shell.sh rather than excluded, since excluding a hard
# dependency would just fail the build.
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

# ghostty comes from Terra, which the base image already trusts.
# Its own transaction, so Terra cannot quietly satisfy anything in the list above.
# The terminfo package matters: without it every ssh session misbehaves in confusing ways.
dnf5 --enable-repo=terra install -y ghostty

rpm -q ghostty ghostty-terminfo
test -x /usr/bin/ghostty
test -f /usr/share/applications/com.mitchellh.ghostty.desktop
test -f /usr/share/terminfo/x/xterm-ghostty

# foot stays as a fallback terminal, because losing the only terminal is a bad way to find a bug.
rpm -q foot

# Hack Nerd Font, downloaded because no trusted repo carries it.
# Pinned by version and checksum, since this is one of only two things here not from a signed repo.
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

# Installing a theme is not choosing it: on Wayland GTK ignores settings.ini and asks the
# portal, which answers from dconf, where Plasma left its own values behind.
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

# Black folder icons, pinned like the font above.
# It has to run during the build, because it edits a directory that is read-only later.
PAPIRUS_FOLDERS_VERSION=1.14.0
PAPIRUS_FOLDERS_SHA256=b30a6848a00690302accffc050549218b0b114d3178b28bd3a16891817821b06

curl -fsSL -o /tmp/papirus-folders \
    "https://raw.githubusercontent.com/PapirusDevelopmentTeam/papirus-folders/v${PAPIRUS_FOLDERS_VERSION}/papirus-folders"
echo "${PAPIRUS_FOLDERS_SHA256}  /tmp/papirus-folders" | sha256sum -c -
chmod +x /tmp/papirus-folders

# Papirus, never Papirus-Dark: only the light package actually ships the colour variants,
# and the dark one inherits them, so recolouring the parent is what works.
papirus_colours="$(/tmp/papirus-folders -t Papirus -l)"
grep -qw black <<<"${papirus_colours}"

# -o skips a state file that would land in /var and be lost; -u rebuilds the icon caches.
/tmp/papirus-folders -t Papirus -C black -o -u -v

# About 400 symlinks get made, so check one of each kind.
test -L /usr/share/icons/Papirus/48x48/places/folder.svg
[[ "$(readlink /usr/share/icons/Papirus/48x48/places/folder.svg)"    == *folder-black* ]]
[[ "$(readlink /usr/share/icons/Papirus/48x48/places/user-home.svg)" == *user-black*   ]]

rm -f /tmp/papirus-folders

# Runs on every build, so an icon update is re-blackened; rpm reporting these as modified is this, not damage.


# Edited in place rather than overridden later, because sway reads $term before it
# ever gets to the drop-in directory, so setting it there would do nothing.
sed -i 's|^set \$term foot$|set $term ghostty|' /etc/sway/config
grep -q '^set \$term ghostty$' /etc/sway/config

# The password prompt is noctalia's, for three reasons: the obvious choice is broken on F44,
# every packaged agent is skipped because this desktop is called "sway", and the one that
# sway starts anyway is shadowed to nothing in /etc/sway/config.d/.
# A missing agent is silent until something calls pkexec, and then it hangs.

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
# Required: sway refuses to start on this driver without the first flag, and the second
# is the standard fix for flicker and black frames on NVIDIA.
SWAY_EXTRA_ARGS="$SWAY_EXTRA_ARGS --unsupported-gpu -D noscanout"

# GLES2 because SwayFX draws all its effects there; on Vulkan it starts and draws none of them.
WLR_RENDERER=gles2

# Hardware video decoding.
LIBVA_DRIVER_NAME=nvidia
NVD_BACKEND=direct

# Electron apps run on Wayland rather than Xwayland.
ELECTRON_OZONE_PLATFORM_HINT=auto

# Two more are deliberately unset: GBM_BACKEND is obsolete, and the cursor workaround
# is only needed if the cursor actually misbehaves.
################################################################################
ENVEOF
