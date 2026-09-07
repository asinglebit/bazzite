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
    wev \
    SwayNotificationCenter \
    cliphist \
    swappy \
    gtkgreet \
    adw-gtk3-theme \
    papirus-icon-theme-dark \
    rsms-inter-fonts

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

# Hack Nerd Font.
#
# Vendored from the upstream release, because no repo this image trusts carries
# a patched Hack: Fedora ships only cascadia-*-nf-fonts, and the che:nerd-fonts
# COPR that the base image already pulls `nerd-fonts` from builds ONLY that one
# symbols-only package -- there is no nerd-fonts-hack to install.
#
# That base `nerd-fonts` package is a *fallback*: Symbols Nerd Font, wired in by
# /etc/fonts/conf.d/10-nerd-font-symbols.conf, carrying icons and no Latin
# glyphs at all. It is why Nerd glyphs render on a stock image, and it is not a
# substitute for the patched face -- with it alone, text and icons come from two
# files with two sets of metrics.
#
# Pinned by version AND by checksum: this is the one artifact in the build that
# does not come from a GPG-verified repo, so the hash is what makes it
# reproducible. Bump both together.
#
# All three variants are extracted (2.7MB for the lot). Mono forces icons to a
# single cell, plain doubles them, Propo is proportional -- keeping all three
# makes switching a config edit rather than another image build.
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

# Asserted for the same reason as ghostty above: a font that fails to install
# does not break the build, it just silently falls back to Noto at runtime.
test -f /usr/share/fonts/hack-nerd-fonts/HackNerdFontMono-Regular.ttf
# fc-list -q rather than `fc-list | grep -q`: grep -q exits on its first
# match, fc-list takes SIGPIPE, and pipefail turns that into exit 141 --
# a green check that kills the build. -q is fontconfig's own match test.
fc-list -q 'Hack Nerd Font Mono'


# --- GTK theming, fonts and icons --------------------------------------------
#
# Asserted for the same reason as the font above: none of these failing breaks
# the build, they just silently fall back at runtime to something that looks
# almost right.
#
# adw-gtk3 is structural rather than cosmetic here. swaync is GTK4 +
# libadwaita; wlogout, swappy, Thunar, pavucontrol and blueman-manager are all
# GTK3. Without it the new UI is split across two GTK eras.
test -d /usr/share/themes/adw-gtk3-dark
test -d /usr/share/icons/Papirus-Dark
fc-list -q 'Inter'

# Black folder icons.
#
# papirus-folders is not packaged in any repo this image trusts, so it is
# vendored the same way the Hack font above is: pinned by version AND by
# checksum, fetched at a tag rather than as a generated tarball so the hash is
# stable. This and the font are the only two artifacts in the build that do not
# come from a GPG-verified repo.
#
# It has to run HERE, in the build, and not as a post-install step: the script
# works by replacing folder*.svg with symlinks inside
# /usr/share/icons/Papirus/*/places/, which is inside the ostree deployment and
# read-only at runtime.
PAPIRUS_FOLDERS_VERSION=1.14.0
PAPIRUS_FOLDERS_SHA256=b30a6848a00690302accffc050549218b0b114d3178b28bd3a16891817821b06

curl -fsSL -o /tmp/papirus-folders \
    "https://raw.githubusercontent.com/PapirusDevelopmentTeam/papirus-folders/v${PAPIRUS_FOLDERS_VERSION}/papirus-folders"
echo "${PAPIRUS_FOLDERS_SHA256}  /tmp/papirus-folders" | sha256sum -c -
chmod +x /tmp/papirus-folders

# -t Papirus, never Papirus-Dark. Fedora puts the colour variants ONLY in the
# main papirus-icon-theme -- 391 files match folder-black there against exactly
# one (a lone 16x16) in papirus-icon-theme-dark, which ships nothing at all
# under 48x48/places/. papirus-folders enumerates the colours it offers from
# folder-<color>-documents.svg in 48x48/places/, so aimed at the dark theme it
# finds no colours whatsoever. papirus-icon-theme-dark hard-Requires the main
# package and inherits its places/ through index.theme, so recolouring the
# parent gives Papirus-Dark black folders for free.
#
# This is the assertion that the variants are actually installed, and it fails
# loudly if that packaging split ever changes.
#
# Captured into a variable and matched with a here-string, NOT piped into
# `grep -q`. That pipe is the exact trap the fc-list note further up this file
# describes, and it is fatal here: grep -q exits on its first match,
# papirus-folders keeps writing into the closed pipe, takes SIGPIPE, and the
# `set -o pipefail` at the top turns a SUCCESSFUL check into exit 141 -- a
# passing assertion that kills the build.
papirus_colours="$(/tmp/papirus-folders -t Papirus -l)"
grep -qw black <<<"${papirus_colours}"

# -o  do NOT write the state file. It would land in /var/lib/papirus-folders,
#     and /var content in a bootc image is only applied on INITIAL provisioning
#     -- exactly the trap system_files/usr/lib/tmpfiles.d/bazzite-sway.conf
#     exists to work around. Nothing reads it at runtime; the symlinks are the
#     state.
# -u  rebuild the icon caches. Papirus ships a prebuilt icon-theme.cache and a
#     stale one shadows the new symlinks. v1.14.0 updates siblings too, which is
#     what reaches Papirus-Dark.
/tmp/papirus-folders -t Papirus -C black -o -u -v

# The mapping is not a plain folder-* rename -- the variant set is ~81 names
# across five sizes, ~400 symlinks, and it covers user-* as well (the script
# uses prefixes "folder-$color" and "user-$color"). Assert one of each: a
# folder, and the Home icon that only the user-* half provides.
# No pipes here either -- bash pattern matching on a captured value, which
# cannot SIGPIPE at all.
test -L /usr/share/icons/Papirus/48x48/places/folder.svg
[[ "$(readlink /usr/share/icons/Papirus/48x48/places/folder.svg)"    == *folder-black* ]]
[[ "$(readlink /usr/share/icons/Papirus/48x48/places/user-home.svg)" == *user-black*   ]]

# Not installed into the image. The symlinks are the product; nothing at runtime
# needs the tool.
rm -f /tmp/papirus-folders

# Re-run on every nightly rebuild, so a papirus-icon-theme update that restores
# the stock blue folder.svg is re-blackened in the same build rather than
# shipping. It does mean `rpm -V papirus-icon-theme` reports those files as
# modified -- that is this, not corruption.


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

# Give the launcher window switching.
#
# /etc/sway/config builds $menu as
#     rofi -terminal '$term' -show combi -combi-modes drun#run -modes combi
# and carries the comment "TODO: add window with the next release of
# rofi-wayland". F44 ships rofi 2.0.0, where that release has landed --
# `rofi -h` reports "Detected modes: +window +run +ssh" -- so the TODO is
# simply stale.
#
# Same reason as the $term rewrite above for doing it here rather than in a
# config.d drop-in: sway expands `set` variables at parse time, so $menu is
# already baked into the $mod+d binding long before the layered include reads
# ~/.config/sway/config.d/.
#
# Asserted because a silent no-op is invisible until you press $mod+d and get
# only applications.
sed -i 's|-combi-modes drun#run|-combi-modes drun#run#window|' /etc/sway/config
grep -q 'combi-modes drun#run#window' /etc/sway/config

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

# The notification daemon.
#
# mako and swaync BOTH ship a D-Bus service file declaring
# Name=org.freedesktop.Notifications -- fr.emersion.mako.service and
# org.erikreider.swaync.service. Different filenames, so there is no RPM
# conflict and both install cleanly, but which one D-Bus activates for a
# duplicated name is not something to build a desktop on.
#
# So do not rely on activation at all. Starting swaync from the session target
# means it owns the bus name before any application can ask for it, and mako's
# activation entry is then never reached. Same reasoning, same mechanism as the
# polkit agent above.
#
# mako stays installed and manually startable (`systemctl --user start mako`
# after stopping swaync) -- the foot precedent. dotfiles/mako/config themes it
# so that fallback is not the stock blue box either.
ln -sfn ../swaync.service \
    /usr/lib/systemd/user/sway-session.target.wants/swaync.service
test -L /usr/lib/systemd/user/sway-session.target.wants/swaync.service
test -f /usr/lib/systemd/user/swaync.service

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

# GLES2, not Vulkan, and this is a SwayFX constraint rather than a preference.
# SwayFX implements every effect (blur, corner radius, shadows, dim-inactive) in
# its own fx_renderer, which is GLES2-only -- there is no Vulkan code path. Left
# at vulkan you get a compositor that starts, works, and silently draws none of
# the effects, which is a nasty thing to debug from the config end.
#
# The cost is real and worth stating: vulkan is the renderer wlroots recommends
# on NVIDIA, and this gives it up. That is the price of build_files/15-swayfx.sh.
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
