# Applications

## Flatpaks

Apps live outside the image. That keeps the image small, lets apps update without a
rebuild or a reboot, and is the sanctioned path on an atomic system — layering a GUI app
with `rpm-ostree` would make every future rebase carry it.

The cost is that a fresh install comes up without them, so `flatpaks.list` at the repo
root writes them down and `just install-flatpaks` reconciles. Two sections:

- **`[install]`** — apps this desktop adds. Only things Bazzite does *not* already ship;
  its own set lives at `/usr/share/ublue-os/bazzite/flatpak/install` and is reinstalled by
  `bazzite-flatpak-manager.service` on first boot, so repeating it here would be noise.
- **`[remove]`** — Bazzite defaults this desktop does without, which would otherwise come
  back on a reinstall. Uninstalling leaves `~/.var/app` alone, so their settings survive.

Those two sections are the only things the recipe acts on. An app installed by hand and
written down nowhere is *reported*, never removed — unlike a dangling symlink, a flatpak
can be holding the only copy of its own data.

Bazzite ships Flathub **filtered** through `/usr/share/ublue-os/flatpak-blocklist`, which
denies Steam and Lutris because the image already carries them. Those two can never be
installed from this list.

## The terminal

**ghostty**, from Terra, in its own dnf transaction so Terra cannot quietly satisfy
anything else in the image. `ghostty-terminfo` matters as much as the binary: without
`xterm-ghostty` in terminfo, every ssh session misbehaves in confusing ways.

`/etc/sway/config` is **edited in place** to set `$term ghostty` rather than overridden
from a drop-in, because sway reads `$term` before it ever reaches the drop-in directory.
Both the build and `verify.sh` grep for the edited line; if it ever stops matching,
`$mod+Return` quietly opens foot again.

**foot stays installed** as the fallback, deliberately — losing the only terminal is a bad
way to find a bug.

`dotfiles/xdg-terminals.list` tells `xdg-terminal-exec(1)` which one to open. The vendor
list still names foot and has no ghostty entry, so without it the spec falls back to
scanning every desktop entry with `Categories=TerminalEmulator` and picking one.

## What left with Plasma

`build_files/30-kde-remove.sh` removes the Plasma session and KDE applications by name —
never a glob, which would take things still wanted — and keeps the Qt libraries other
tools need (`--no-autoremove`).

Removed because noctalia does the same job: `SwayNotificationCenter`, `mako`, `rofi`,
`wlogout`, `cliphist`, `swappy`, `mate-polkit`. Also gone: `hyprlock` and `hypridle`, and
the hypr COPR with them, which took the image from three third-party repos down to two.

`rofi` needs an explicit `--exclude` at install time, because `sway-config-fedora`
recommends `rofi-wayland` and the `rofi` package *provides* that name.

Kept on purpose: `btrfs-assistant`, `bazzite-updater`, `kf6-kwallet`, and the whole
Bazzite gaming stack — Steam, gamescope, MangoHud, the ogc kernel, the patched Xwayland.
`verify.sh` checks all of it, because a broken versionlock would be easy to miss.

Lost with Plasma, and not replaced: Sunshine virtual monitors and KWin screencast,
`kscreen-doctor` custom resolutions, and `bazzite-powersave`'s qdbus path — `tuned-ppd`
still works.

## An unrelated tenant

`build_files/35-devel-install.sh` installs a handful of `-devel` headers (`gtk3`,
`webkit2gtk4.1`, `libsoup3`, `dbus`, `libappindicator-gtk3`, `libX11`) for building a
Tauri app that has nothing to do with this desktop. It is called out here so nobody
mistakes it for a desktop dependency and spends time working out what needs WebKit.

Related: [[Cadence]], [[Operations]], [[Decisions]].
