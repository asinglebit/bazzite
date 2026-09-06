# bazzite-sway

A [Bazzite](https://bazzite.gg)-derived bootc image that runs **Sway** instead of KDE Plasma,
keeping Bazzite's gaming and hardware stack intact (ogc kernel, patched
mesa/Xwayland/bluez/wireplumber, Steam, gamescope, MangoHud, sched_ext, `ujust`).

Built for `ghcr.io/ublue-os/bazzite-nvidia-open:stable` on an RTX 4070 Ti
(nvidia-open 610.x), Fedora 44.

## Quick start

Already running it? Updates are `just update` — see [Updating](#updating). To install it on a
machine for the first time, see
[bootstrapping](#first-time-bootstrapping-onto-the-published-image).

To build and test locally, without GHCR involved:

```bash
just insurance      # pin the current deployment, stop uupd
just build          # boot 1: Sway added, Plasma kept as a fallback session
just switch plasma
sudo systemctl reboot
```

Log in, pick **Sway** in tuigreet, then run `./verify.sh`. Once it's clean:

```bash
just build-nokde    # boot 2: Plasma removed
just switch sway
sudo systemctl reboot
```

If anything goes wrong: `just rollback`, or hold **Shift** at boot and pick the
`Bazzite Stable` GRUB entry (the new image labels itself `Bazzite Sway Stable`).
`just restore` goes all the way back to stock upstream Bazzite.

## The published image

CI rebuilds both variants nightly against current upstream Bazzite, rechunks them, pushes to
GHCR and signs them with cosign.

| Tag | Build | What it is |
| --- | --- | --- |
| `ghcr.io/asinglebit/bazzite-sway:plasma` | `REMOVE_KDE=0` | Sway added, Plasma kept as a fallback session |
| `ghcr.io/asinglebit/bazzite-sway:sway` | `REMOVE_KDE=1` | Plasma stripped |

Both also get a dated tag (`plasma-20260906`), so a bad night can be pinned around.

**There is deliberately no `:latest`.** A bare `bootc switch
ghcr.io/asinglebit/bazzite-sway` resolves to it, and whichever variant it pointed at would be
the wrong one half the time — silently, on a command that looks harmless. Without the tag the
pull just fails and you name the variant you meant. The tags say which desktop you get, which
is the only thing that actually differs between them.

### Updating

```bash
just update-check    # anything new? metadata only, no layer download
just update          # stage it; applies at the next reboot
sudo systemctl reboot
./verify.sh
```

`just update-now` stages and reboots in one step. Because the nightly rebuild tracks
upstream, this is also how the ogc kernel, mesa and NVIDIA driver updates arrive.

Nothing fetches on its own — no timer, no update agent, deliberately. A bad nightly can never
quietly become your next boot. If one is bad, `just rollback`; to pin to a specific night,
`just switch-remote plasma-20260905`.

### First time: bootstrapping onto the published image

Make the package public first, or the pull gets a 401 — new GHCR packages are private even on
a public repo.

```bash
just switch-remote plasma
sudo systemctl reboot
```

One switch is enough, even though nothing on the machine trusts `ghcr.io/asinglebit` yet.
bootc's only pre-flight check on an `ostree-image-signed:` ref is that the policy's *top-level*
default isn't `insecureAcceptAnything` — Bazzite's is `reject`, so it passes — and the pull
itself then finds no rule for the namespace and falls through to the `""` catch-all.

So that first pull is trust-on-first-use. It has to be: the trust ships *inside* the image
being installed. Everything after it is verified, because bootc stores the whole
`ostree-image-signed:` ref and `bootc upgrade` reuses it verbatim.

If the first switch is refused for any reason, `just bootstrap-remote plasma` does the same pull
with a plain unverified ref; move to `just switch-remote` afterwards.

Don't reach for `bootc switch --enforce-container-sigpolicy` — it demands that the *default*
policy require signatures, which Bazzite's does not.

### Confirming verification is actually on

After the reboot, three checks. The first two can both pass while verification is silently
falling through to the catch-all, so the third is the one that proves it.

```bash
# 1. the rule is loaded
podman image trust show | grep asinglebit
#    repository   ghcr.io/asinglebit   sigstoreSigned

# 2. the policy is evaluated on a real pull — metadata only, no layers
just update-check

# 3. negative control: same policy, wrong key. Must be REFUSED, in about a
#    second — the signature is checked before a single blob is fetched.
jq '.transports.docker["ghcr.io/asinglebit"][0].keyPaths =
    ["/etc/pki/containers/ublue-os.pub"]' \
   /etc/containers/policy.json > /var/tmp/wrongkey.json
skopeo --policy /var/tmp/wrongkey.json copy \
   docker://ghcr.io/asinglebit/bazzite-sway:plasma dir:/var/tmp/sigproof
#    expect: Source image rejected: cryptographic signature verification failed
rm -rf /var/tmp/wrongkey.json /var/tmp/sigproof
```

If step 3 starts copying instead of failing, the rule is not matching and updates are going
through unverified. Note `skopeo inspect` is no use here — it does not apply the policy at all.

### Signing

`50-signing.sh` bakes in three files, mirroring how the base image already trusts
`ghcr.io/ublue-os`:

| File | Why |
| --- | --- |
| `/etc/pki/containers/asinglebit.pub` | the cosign public key (`cosign.pub` in this repo) |
| `/etc/containers/registries.d/asinglebit.yaml` | `use-sigstore-attachments: true` — without it the signature is never looked for, and verification silently passes on nothing |
| `/etc/containers/policy.json` | a `sigstoreSigned` + `matchRepository` block for the namespace |

`cosign.key` lives only in the repo's `SIGNING_SECRET` Actions secret and is gitignored. To
check a published image by hand:

```bash
cosign verify --key cosign.pub ghcr.io/asinglebit/bazzite-sway:plasma
```

A local `just build` passes no registry, so it skips all of this and stays unsigned — the
containers-storage ref it brands itself with matches that reality.

## Layout

| Path | What it does |
| --- | --- |
| `Containerfile` | `FROM ghcr.io/ublue-os/bazzite-nvidia-open:stable`; `ARG REMOVE_KDE`, `IMAGE_REGISTRY`, `IMAGE_TAG` |
| `build_files/10-sway-install.sh` | Sway session + desktop essentials, NVIDIA env |
| `build_files/20-display-manager.sh` | greetd + tuigreet become the DM |
| `build_files/30-kde-remove.sh` | Plasma removal (only when `REMOVE_KDE=1`) |
| `build_files/40-branding.sh` | os-release / image-info.json, removes the ublue MOTD banner, disables `uupd.timer` |
| `build_files/50-signing.sh` | Bakes in the cosign key, `registries.d` entry and `policy.json` block. No-ops on a local build |
| `.github/workflows/build.yml` | Nightly rebuild: build, rechunk, push to GHCR, cosign sign |
| `cosign.pub` | Public half of the CI signing key. Committed on purpose; `cosign.key` never is |
| `system_files/` | Files copied verbatim into the image |
| `dotfiles/` | Per-user **desktop** config (monitor layout, appearance, theming, launcher, lock screen), symlinked into `~/.config` by `just link-dotfiles`. Never enters the image. Desktop only — see below. |
| `verify.sh` | Post-boot checks |

## Things that are load-bearing, and why

**`dotfiles/` is scoped to the desktop, deliberately.** What lives here is what a functional
Bazzite/Sway session needs and nothing else: the compositor, the bar, the launcher, the lock
screen, GTK theming, and `xdg-terminals.list`, which is the XDG wiring that makes Ghostty the
default terminal. Everything that would still be useful on a different OS — shell config,
toolchain versions via mise, tmux, Neovim, and Ghostty's own appearance — lives in
[asinglebit/dotfiles](https://github.com/asinglebit/dotfiles) instead, which deploys with its
own `install.sh` and has a per-OS `linux/` and `macos/` split.

The two repos are independent on purpose: neither sources, references or requires the other,
and exactly one of them owns any given path under `~/.config`. That is the rule that keeps
`just link-dotfiles` and the dotfiles installer from fighting over the same symlink. Ghostty
is the case that made it concrete — its config moved out to the dotfiles repo, while
`xdg-terminals.list` stayed here, because one is a portable preference and the other is
desktop integration.

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

**ghostty comes from Terra, in its own transaction.** It is not in Fedora at all. Terra (Fyra
Labs) packages it, and the base image already carries `/etc/yum.repos.d/terra.repo` disabled
with its signing key in `/etc/pki/rpm-gpg/` — Bazzite enables `terra-mesa` itself, so this is a
repo the artifact already trusts rather than a new trust root. The install is deliberately a
separate `dnf5 --enable-repo=terra install -y ghostty` rather than folded into the main package
list: `--enable-repo` is a dnf5 global, so one combined call would let Terra satisfy *any*
package in that list and silently swap Fedora builds for Terra ones. This is the project's only
third-party repo dependency.

**`$term` is rewritten in `/etc/sway/config`, not overridden from `config.d`.** sway expands
`set` variables at parse time, and that file uses `$term` twice — the `$mod+Return` binding and
rofi's `-terminal` — both already baked by the time the layered include on the last line reads
`~/.config/sway/config.d/`. A late `set $term ghostty` there does nothing at all, which is why
the build seds the source line and asserts the result. `foot` stays installed but unbound as a
fallback, since ghostty is GPU-accelerated and this is an NVIDIA box; note it is a *weak*
dependency of `sway-config-fedora`, so dropping it later needs `--exclude=foot` rather than just
deleting the line from the list.

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
