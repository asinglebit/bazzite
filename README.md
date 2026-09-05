# bazzite-sway

A [Bazzite](https://bazzite.gg)-derived bootc image that runs **Sway** instead of KDE Plasma,
keeping Bazzite's gaming and hardware stack intact (ogc kernel, patched
mesa/Xwayland/bluez/wireplumber, Steam, gamescope, MangoHud, sched_ext, `ujust`).

Built for `ghcr.io/ublue-os/bazzite-nvidia-open:stable` on an RTX 4070 Ti
(nvidia-open 610.x), Fedora 44.

## Quick start

```bash
just insurance      # pin the current deployment, stop uupd
just build          # boot 1: Sway added, Plasma kept as a fallback session
just switch test
sudo systemctl reboot
```

Log in, pick **Sway** in tuigreet, then run `./verify.sh`. Once it's clean:

```bash
just build-nokde    # boot 2: Plasma removed
just switch latest
sudo systemctl reboot
```

If anything goes wrong: `just rollback`, or hold **Shift** at boot and pick the
`Bazzite Stable` GRUB entry (the new image labels itself `Bazzite Sway Stable`).
`just restore` goes all the way back to stock upstream Bazzite.

## Layout

| Path | What it does |
| --- | --- |
| `Containerfile` | `FROM ghcr.io/ublue-os/bazzite-nvidia-open:stable`, `ARG REMOVE_KDE` |
| `build_files/10-sway-install.sh` | Sway session + desktop essentials, NVIDIA env |
| `build_files/20-display-manager.sh` | greetd + tuigreet become the DM |
| `build_files/30-kde-remove.sh` | Plasma removal (only when `REMOVE_KDE=1`) |
| `build_files/40-branding.sh` | os-release / image-info.json, disables `uupd.timer` |
| `system_files/` | Files copied verbatim into the image |
| `dotfiles/` | Per-user config (monitor layout, waybar), symlinked into `~/.config` by `just link-dotfiles`. Never enters the image. |
| `verify.sh` | Post-boot checks |

## Things that are load-bearing, and why

**`--unsupported-gpu` is mandatory.** Sway 1.11 (what F44 ships) hard-exits when the DRM
driver is named `nvidia-drm`, and the *open* kernel modules match that check too. It goes
into `/etc/sway/environment` via `SWAY_EXTRA_ARGS`, alongside `-D noscanout` (the standard
wlroots-on-NVIDIA flicker fix). Miss this and you get a black screen. Sway 1.12 downgrades
it to a swaynag message, but that's F45+.

**`sway-systemd` is not optional.** `xdg-desktop-portal.service` carries
`Requisite=graphical-session.target` ([RHBZ 2481764][rhbz]), and `sway-session.target` is
what reaches that target. Without it the portal silently refuses to start, taking Flatpak
file dialogs, screen sharing and the Steam overlay with it. `sway-config-fedora` only
*Recommends* it, so it's installed explicitly.

**greetd, not SDDM or plasmalogin.** `sddm-wayland-sway` runs its greeter *as a Sway
instance*, so it would hit the same NVIDIA guard as the session; `plasmalogin` requires
`kwin-wayland`, so it can't outlive Plasma. tuigreet is a pure-TTY greeter — no compositor,
no driver involvement.

**KDE removal is an explicit package list, never a glob.** `plasma-*` would take
`plasma-foreground-booster-dmemcg`; `kde-*` would take `kde-settings`. Comps `group remove`
isn't tracked on an atomic image at all. Qt6/KF6 libraries are kept deliberately so
`btrfs-assistant`, `bazzite-updater` and KDE-flatpak theming keep working.

**`base-image-name` stays `kinoite`** in `image-info.json`. It's the runtime DE oracle read
by `bazzite-user-setup`, `80-bazzite.just` and `82-bazzite-sunshine.just`; any other value
drops them into the GNOME/dconf branch.

**Build as root.** `bootc` reads root's containers-storage at `/var/lib/containers/storage`;
a rootless build lands somewhere root can't see. Never `--squash` — it rewrites layer
diffids, which is the mechanism behind [`Missing ostree.final-diffid`][diffid] on
Bazzite-derived images. If `just switch` hits that, run `just rechunk` first.

**Rebuilding the same tag needs `bootc upgrade`, not `switch`.** `bootc switch` compares
the image *reference*, not its content — re-running it after a rebuild prints "Image
specification is unchanged" and silently leaves the previous build staged. `just switch`
detects that and falls through to `bootc upgrade`.

**`uupd.timer` is disabled** in the image. It fires at 04:00 against a `containers-storage`
ref it can't upgrade, and bootc warns that an active update agent can revert a queued
rollback.

## Known limitations

- **No HDR under gamescope** — `color-management-v1` landed in sway 1.12; F44 has 1.11.
  VRR (`--adaptive-sync`) does work.
- If gamescope crashes with `vkImportSemaphoreFdKHR failed`, set `ENABLE_GAMESCOPE_WSI=0`
  ([gamescope#1662][gs], still open).
- If the cursor misbehaves, add `WLR_NO_HARDWARE_CURSORS=1` to `/etc/sway/environment`.
- Screen sharing via `xdg-desktop-portal-wlr` is whole-output only — no window picker.
- Lost with Plasma: Sunshine virtual monitors / KWin screencast, `kscreen-doctor` custom
  resolutions, `bazzite-powersave`'s qdbus path (`tuned-ppd` still works).
- Don't use `ujust toggle-nvk` or the `40-nvidia.just` toggles — they do naive string
  substitution on the image URI and will break on a custom ref. `ujust verify-image` is
  safe; it no-ops on custom images.

## Not done yet

Publishing to GHCR with cosign signing and a nightly Actions rebuild. That needs a repo,
`/etc/pki/containers/<you>.pub`, a `policy.json` namespace block and
`/etc/containers/registries.d/<you>.yaml` baked into the image, plus one unsigned switch to
bootstrap the policy.

## Prior art

- [wayblueorg/wayblue](https://github.com/wayblueorg/wayblue) — sway/hyprland/river on
  Fedora Atomic; source of the NVIDIA environment settings.
- [gabeklavans/bazzite-niri](https://github.com/gabeklavans/bazzite-niri) — Bazzite-derived,
  Plasma removed, wlroots-family compositor.
- [ublue-os/image-template](https://github.com/ublue-os/image-template) — the Containerfile
  and Justfile shape.

[rhbz]: https://bugzilla.redhat.com/show_bug.cgi?id=2481764
[diffid]: https://github.com/ublue-os/bazzite/issues/1892
[gs]: https://github.com/ValveSoftware/gamescope/issues/1662
