#!/usr/bin/bash
# Removes the Plasma session and KDE apps, but keeps the Qt libraries other tools still need.
# Every package is listed by name, because a glob would take things that are still wanted.
set -euxo pipefail

REMOVE=(
    # Plasma session core.
    plasma-workspace plasma-workspace-common plasma-workspace-libs
    plasma-workspace-wallpapers
    plasma-desktop plasma-desktop-doc
    plasma-lookandfeel-fedora plasma-setup plasma-milou
    kwin kwin-common kwin-libs
    powerdevil aurorae
    plasma-integration plasma-integration-qt5

    # Login manager; greetd already took over in the previous step.
    plasma-login-manager kcm-plasmalogin kde-settings-plasmalogin

    # Applets and services replaced by the Sway stack.
    plasma-nm plasma-nm-openconnect plasma-nm-openvpn plasma-nm-vpnc
    plasma-pa
    plasma-systemmonitor plasma-systemsettings
    plasma-print-manager plasma-print-manager-libs
    plasma-disks plasma-thunderbolt plasma-vault
    plasma-browser-integration plasma-keyboard
    plasma-foreground-booster-dmemcg
    bluedevil flatpak-kcm
    xdg-desktop-portal-kde
    kde-gtk-config kde-cli-tools kinfocenter kmenuedit

    # Bazzite's KDE-specific extras.
    steamdeck-kde-presets-desktop krunner-yafti krunner-bazaar

    # KDE applications.
    dolphin dolphin-libs dolphin-plugins
    konsole konsole-part
    kate kate-libs kate-plugins kate-krunner-plugin
    ark ark-libs
    filelight kfind khelpcenter kwrite spectacle
    kwalletmanager5
    krdc krdc-libs krfb krfb-libs
    kcm-fcitx5
)

# Only ask to remove what is actually installed, so an upstream drop is not a build failure.
INSTALLED=()
for pkg in "${REMOVE[@]}"; do
    if rpm -q "${pkg}" >/dev/null 2>&1; then
        INSTALLED+=("${pkg}")
    else
        echo "skip (not installed): ${pkg}"
    fi
done

# --no-autoremove, because the Qt stack is meant to be left behind.
dnf5 remove -y --no-autoremove "${INSTALLED[@]}"

# fcitx5 just lost its KDE settings window, so give it the GTK one.
if rpm -q fcitx5 >/dev/null 2>&1; then
    dnf5 install -y fcitx5-configtool
fi

# Everything below has to fail the build rather than surface later on a booted machine.
rpm -q xorg-x11-server-Xwayland
rpm -q xdg-desktop-portal xdg-desktop-portal-gtk xdg-desktop-portal-wlr
# --whatprovides, because the sway package was swapped for swayfx in an earlier step.
rpm -q --whatprovides sway
rpm -q sway-config-fedora sway-systemd greetd tuigreet
# Everything but the compositor is this one package, including the only password prompt.
rpm -q noctalia
test -L /usr/lib/systemd/user/sway-session.target.wants/noctalia.service
# A different product from the shell above, sharing only a name and a palette.
rpm -q noctalia-greeter
# These must STAY installed: they are retired by config instead, and a retirement file
# for a package that is gone looks exactly like one that is working.
rpm -q waybar swaylock swayidle grimshot lxqt-policykit
# The ones that genuinely went, so a deliberate removal stays distinguishable from an accident.
! rpm -q SwayNotificationCenter
! rpm -q mako
! rpm -q rofi
! rpm -q wlogout
! rpm -q cliphist
! rpm -q swappy
! rpm -q mate-polkit
# Nothing removes these any more, and "the script is gone" is not the same claim as "they are gone".
! rpm -q hyprlock
! rpm -q hypridle
test ! -f /etc/yum.repos.d/_copr_scottames-hypr.repo
rpm -q btrfs-assistant bazzite-updater
rpm -q steam

# And Plasma must no longer be offered as a session.
test ! -e /usr/share/wayland-sessions/plasma.desktop
test -e /usr/share/wayland-sessions/sway.desktop
