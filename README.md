# bazzite-sway

A [Bazzite](https://bazzite.gg)-derived bootc image that runs **SwayFX** instead of KDE Plasma,
keeping Bazzite's gaming and hardware stack intact (ogc kernel, patched
mesa/Xwayland/bluez/wireplumber, Steam, gamescope, MangoHud, sched_ext, `ujust`).

The desktop is greyscale and deliberately flat: no window borders, one typeface pair (Hack
Nerd Font Mono and Inter), and every surface — bar, launcher, notification centre, power menu,
lock screen and login screen — drawn from the same seven-value palette. SwayFX supplies corner
radius, dim-inactive and blur on the chrome; application windows stay opaque.

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

Log in, pick **start-sway** in gtkgreet, then run `./verify.sh`. Once it's clean:

```bash
just build-nokde    # boot 2: Plasma removed
just switch sway
sudo systemctl reboot
```

If anything goes wrong: `just rollback`, or hold **Shift** at boot and pick the
`Bazzite Stable` GRUB entry (the new image labels itself `Bazzite Sway Stable`).
`just restore` goes all the way back to stock upstream Bazzite.

The image ships no per-user config and no toolchain — see
[Per-user setup](#per-user-setup-after-first-boot) for the two repos that supply those.

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

### Per-user setup, after first boot

The image carries the desktop; it deliberately carries none of the per-user config, and none
of the dev toolchain. Two repos supply that, and they are independent — run both:

```bash
# 1. Desktop config: monitor layout, appearance, effects, wallpaper, bar,
#    launcher, notifications, power menu, lock screen. From this repo.
#    Idempotent, backs up anything in the way.
#
#    The lock screen works without this -- the image ships a plain fallback at
#    /etc/xdg/hypr -- but this is what themes it and puts the wallpaper behind
#    it.
just link-dotfiles
swaymsg reload

# 2. Shell, toolchains and terminal config. Separate repo, portable across OSs.
git clone git@github.com:asinglebit/dotfiles.git ~/projects/personal/dotfiles
~/projects/personal/dotfiles/install.sh --dry-run   # review
~/projects/personal/dotfiles/install.sh
exec bash -l
```

The second one installs mise's config, and mise then provisions Go, Rust, Node and pnpm on the
next `mise install`. Nothing in the image depends on any of it, so skipping step 2 leaves a
working desktop with a bare shell.

Neither installer touches the other's paths — see
[Things that are load-bearing](#things-that-are-load-bearing-and-why).

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
| `build_files/10-sway-install.sh` | Sway session + desktop essentials, NVIDIA env, black Papirus folders |
| `build_files/15-swayfx.sh` | Swaps `sway` for `swayfx` from a COPR. Sets up the repo disabled, swaps in one transaction |
| `build_files/16-hyprlock.sh` | `hyprlock` + `hypridle` from a COPR, the `hypridle.service` enablement symlink, and the `/etc/xdg/hypr` fallback configs |
| `build_files/20-display-manager.sh` | greetd + a Sway-hosted **gtkgreet** become the DM |
| `build_files/30-kde-remove.sh` | Plasma removal (only when `REMOVE_KDE=1`) |
| `build_files/40-branding.sh` | os-release / image-info.json, removes the ublue MOTD banner, disables `uupd.timer` |
| `build_files/50-signing.sh` | Bakes in the cosign key, `registries.d` entry and `policy.json` block. No-ops on a local build |
| `.github/workflows/build.yml` | Nightly rebuild: build, rechunk, push to GHCR, cosign sign |
| `cosign.pub` | Public half of the CI signing key. Committed on purpose; `cosign.key` never is |
| `system_files/` | Files copied verbatim into the image |
| `dotfiles/` | Per-user **desktop** config (monitor layout, appearance, effects, wallpaper, theming, bar, launcher, notifications, power menu, lock screen), symlinked into `~/.config` by `just link-dotfiles`. Never enters the image. Desktop only — see below. |
| `verify.sh` | Post-boot checks |

## Things that are load-bearing, and why

**`dotfiles/` is scoped to the desktop, deliberately.** What lives here is what a functional
Bazzite/SwayFX session needs and nothing else: the compositor and its effects, the bar, the
wallpaper, the launcher, the notification centre, the power menu, the lock screen and its idle
daemon, GTK theming, and `xdg-terminals.list`, which is the XDG wiring that makes Ghostty the
default terminal. Everything that would still be useful on a different OS —
shell config, toolchain versions via mise, tmux, Neovim, and Ghostty's own appearance — lives in
[asinglebit/dotfiles](https://github.com/asinglebit/dotfiles) instead, which deploys with its
own `install.sh` and has a per-OS `linux/` and `macos/` split.

The two repos are independent on purpose: neither sources, references or requires the other,
and exactly one of them owns any given path under `~/.config`. That is the rule that keeps
`just link-dotfiles` and the dotfiles installer from fighting over the same symlink. Ghostty
is the case that made it concrete — its config moved out to the dotfiles repo, while
`xdg-terminals.list` stayed here, because one is a portable preference and the other is
desktop integration. `sway/wallpaper.png` is the same call in the other direction: an image is
portable in a way a sway config is not, but the `output * bg` line that names it is desktop
config and lives here, so the image sits beside that line rather than across the boundary.

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

**greetd, not SDDM or plasmalogin.** `sddm-wayland-sway` runs its greeter *as a Sway instance*
and gives you no way to pass flags to it, so it hits sway's own NVIDIA guard; `plasmalogin`
requires `kwin-wayland`, so it can't outlive Plasma. greetd is the one that lets us write the
greeter's command line ourselves, which is the only reason that guard is escapable at all.

**The greeter runs inside Sway, not on the VT.** A kernel console draws in cells of a fixed
*pixel* bitmap, so tuigreet's physical size tracked whichever mode the DRM fbdev helper picked
and the panel's PPI — the same 8x16 cell measured 7.36mm tall on the 81 PPI HP and 3.69mm on
the 160 PPI Dell. This kernel is built `# CONFIG_FONTS is not set`, so `fbcon=font:` has
nothing bigger to offer, and a userspace console font tops out at a 32px cell: half the gap,
not none of it. Nothing on the console is resolution-independent.

So greetd runs `start-sway -c /etc/greetd/sway-greeter.conf`, and since a compositor had to be
in the login path anyway, the greeter is **gtkgreet** rather than tuigreet — GTK3, so it
inherits `adw-gtk3-dark`, Papirus-Dark and Inter from the image and is styled from
`/etc/gtkgreet/style.css` in the same palette as the desktop. `start-sway` and never `sway`:
it sources `/etc/sway/environment` and passes `-c` through, so the greeter inherits the
`--unsupported-gpu -D noscanout` and `WLR_RENDERER=gles2` the session already proves work on
this GPU.

The cost is real and deliberate — the NVIDIA stack is now in the login path, so a driver
regression takes the login screen down with the session instead of leaving a working TTY
greeter behind. **tuigreet stays installed, unbound**, as the way back: `Ctrl+Alt+F2`, point
`command =` in `/etc/greetd/config.toml` at `tuigreet ... --cmd start-sway`, and
`systemctl restart greetd`.

**SwayFX costs the Vulkan renderer, and that is the price of the effects.** SwayFX implements
blur, corner radius, shadows and dim-inactive in its own `fx_renderer`, which is GLES2-only —
there is no Vulkan path. `/etc/sway/environment` therefore sets `WLR_RENDERER=gles2`, giving up
the renderer wlroots recommends on NVIDIA. Left at `vulkan` you get a compositor that starts,
works, and silently draws none of the effects.

The package is a genuine drop-in and that is what makes the swap small: swayfx carries
`Provides: sway = 1.11`, `Conflicts: sway`, and installs its binary at **`/usr/bin/sway`**, so
`start-sway`, greetd, `swaymsg` and `sway-systemd` all keep working untouched. `sway-config-fedora`
survives and `Provides: sway-config`, which is exactly what swayfx `Requires` — so the whole
layered-config machinery is undisturbed. Two consequences worth knowing: `30-kde-remove.sh` has
to assert `rpm -q --whatprovides sway` rather than `rpm -q sway`, and the COPR's RPM is a
**July 2025 `.fc43` build** that nobody has rebuilt since, so `15-swayfx.sh` asserts it still
links `libwlroots-0.19.so` — the day Fedora retires that compat package this must fail the
nightly build rather than ship a black screen.

**Three third-party repos now, up from one.** Terra (ghostty), `swayfx/swayfx` (the compositor)
and `scottames/hypr` (the locker). Terra was already trusted by the base image; neither COPR
is. All three ship **disabled** in the image and are enabled for exactly one transaction each,
because `--enable-repo` is a dnf5 global and a shared transaction would let any of them satisfy
an unrelated package. This is the largest single change to the project's trust surface, and the
locker's is the only one in the login path.

`solopasha/hyprland` is the obvious choice for the Hyprland ecosystem and is deliberately *not*
used: it builds for **rawhide only**, so its baseurl 404s on F44. Building hyprlock from source
is also closed off — 0.9.x needs `hyprutils >= 0.8.0` and `hyprwayland-scanner >= 0.4.4` while
F44 ships 0.7.1 and 0.4.2. Of the F44 COPRs that do carry a working build, `scottames/hypr` was
picked as the narrowest: 43 packages, and no `hyprland` compositor among them, so a repo left
lying disabled in `/etc/yum.repos.d` cannot satisfy "a compositor" on a machine running SwayFX.

**The locker is hyprlock, and it is why swayidle is gone.** swaylock cannot blur, so once the
bar, launcher and notification centre are frosted it is the one surface left that visibly
cannot match. hyprlock works here despite being a Hyprland project — its `CMakeLists.txt` binds
only `ext-session-lock-v1`, `wlr-screencopy`, `linux-dmabuf`, `viewporter`, `fractional-scale`,
`cursor-shape` and `tablet-v2`, all of which sway 1.11 provides, and no hyprland-\* protocol or
IPC.

But it has no daemonize flag, and Fedora's `90-swayidle.conf` runs `swayidle -w`, which blocks
until each command returns. `swaylock -f` forks once locked, so "the command exited" means "the
screen is locked"; hyprlock does not exit until you authenticate. Pointed at hyprlock, swayidle
blocks for the whole duration of the lock and the display-off timeout never fires — the
monitors stay on all night. So that drop-in is retired by a comment-only same-name override in
`dotfiles/sway/config.d/`, and **hypridle** replaces it as a systemd user unit.

Two hypridle features do not work on sway and are deliberately unused: `on_lock_cmd`,
`on_unlock_cmd` and `inhibit_sleep = 3` all need `hyprland-lock-notify-v1`. `inhibit_sleep` is
pinned to `1` (a plain logind delay inhibitor) rather than left at the default `2` ("auto"),
which resolves to the same thing here but silently. What is genuinely lost is swaylock's
`SIGUSR1` "unlock and exit": `loginctl unlock-session` no longer dismisses the locker, so you
authenticate at the keyboard.

**Neither locker config can be checked at build time, unlike the greeter.** `sway -C` validates
the greeter config without touching a device, but hypridle connects to Wayland *before* it
parses anything and hyprlock has no validate-only mode. hyprlang errors on unknown keys, so one
typo is a dead locker *and* a dead display-off timer, and the only symptom is silence. That is
why `verify.sh` checks `systemctl --user is-active hypridle`, and why it is the most important
line in the file.

A hyprlock config *can* be parse-checked outside the build, just not inside it — run it against
a throwaway headless nested sway, which needs no display and cannot touch the real session:

```bash
printf 'exec sh -c "timeout 6 hyprlock -c %s; swaymsg exit"\n' /etc/xdg/hypr/hyprlock.conf > /tmp/n.conf
WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 sway --unsupported-gpu -c /tmp/n.conf
```

A good file reaches `Locking session` and `PAMPROMPT: Password:`; a bad one exits 1 naming the
key it choked on. Two lines on the way out are noise and say nothing about the config —
`Failed to get backend DRM FD` from the headless backend, and `Unable to receive IPC response`
from `swaymsg exit` racing sway's own shutdown.

**Both locker configs have a floor in the image, at `/etc/xdg/hypr/`.** Neither binary has
built-in defaults, and `hypridle.service` carries `Restart=on-failure` — so five failures in ten
seconds hit systemd's default start limit and wedge the unit for the whole session. A login
*before* `just link-dotfiles` therefore used to get a desktop that never locked and never
blanked, with the only symptom being silence, and that made the dotfiles repo a hard dependency
of the desktop. `/etc/xdg/hypr` is the last entry in hyprutils' search order
(`$XDG_CONFIG_HOME/hypr` → `$HOME/.config/hypr` → `$XDG_CONFIG_DIRS/hypr` → `/etc/xdg/hypr`), so
`dotfiles/hypr/` still wins the moment it is linked. The fallbacks are deliberately not copies:
hypridle's keeps the same 300/360 timings so linking the dotfiles changes how the lock screen
looks and not when it fires, while hyprlock's drops the wallpaper (it cannot depend on a
dotfile) and shows password dots, because the fallback is what an unfamiliar or half-provisioned
machine gets and being able to see that the keyboard works matters more there.

**Black folders are baked into the image, not configured.** `papirus-folders` works by replacing
`folder*.svg` with symlinks inside `/usr/share/icons/Papirus/`, which is read-only at runtime —
so `10-sway-install.sh` runs it during the build, pinned by tag and sha256 like the Hack font.
It targets **`Papirus`, never `Papirus-Dark`**: Fedora ships the colour variants only in the
main package, and `Papirus-Dark` has nothing at all under `48x48/places/`, so aimed at the dark
theme the script finds no colours to offer. `papirus-icon-theme-dark` hard-Requires the main
package and inherits its `places/`, so recolouring the parent is what gives the dark theme
black folders.

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
- Screen sharing via `xdg-desktop-portal-wlr` is whole-output only — no window picker. The
  bar's `privacy` module is there because of this: when something is capturing, it is capturing
  everything.
- **No HDR and no Vulkan renderer** — the latter is SwayFX's GLES2-only `fx_renderer`, above.
- If the greeter ever fails to start you get a black screen, not a TTY: greetd is
  `Restart=always` with `StartLimitBurst=5` and `Conflicts=getty@tty1.service`, so five
  failures in thirty seconds leaves VT 1 dead. `Ctrl+Alt+F2` still works (logind keeps six auto
  VTs) — from there, point `command =` in `/etc/greetd/config.toml` back at `tuigreet` and
  `systemctl restart greetd`, or `just rollback`.
- `loginctl unlock-session` does not dismiss hyprlock — no `SIGUSR1` equivalent. Authenticate
  at the keyboard.
- Blur is only visible through a translucent surface, which is why `waybar/style.css`,
  `rofi/config.rasi` and `swaync/style.css` draw their backgrounds at alpha. Making any of them
  opaque does not disable blur, it just hides it — the compositor still pays for it.
- `rpm -V papirus-icon-theme` reports its `folder*.svg` as modified. That is the black-folder
  recolour, not corruption.
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
