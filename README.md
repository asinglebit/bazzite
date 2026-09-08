# Bazzite noctalia swayfx image


<img width="1536" height="864" alt="image (1)" src="https://github.com/user-attachments/assets/ddd9ff47-8579-4152-9553-3b005620f3a0" />


A [Bazzite](https://bazzite.gg)-derived bootc image running [SwayFX][swayfx] — a fork of
[Sway][sway] with blur, rounded corners and shadows — instead of KDE Plasma, with Bazzite's gaming
and hardware stack intact: ogc kernel, patched mesa/Xwayland/bluez/wireplumber, Steam, gamescope,
MangoHud, sched_ext, `ujust`.

Everything that is not the compositor is [noctalia][noctalia]: bar, launcher, notifications and
control centre, session menu, lock screen, OSD, clipboard, screenshots and the polkit agent, all
from one TOML directory and one palette. `noctalia-greeter` is the login screen. The look is
greyscale and flat; the desktop's half of it is `dotfiles/`, the login screen's is in the image.

Built for `ghcr.io/ublue-os/bazzite-nvidia-open:stable` on an RTX 4070 Ti (nvidia-open 610.x),
Fedora 44.

## Quick start

| Task | Command |
| --- | --- |
| Install it | `just switch-remote sway` then `sudo systemctl reboot` |
| Update | `just update` then `sudo systemctl reboot` (or `just update-now`) |
| Is there an update? | `just update-check` — metadata only, no layers |
| Build locally | `just insurance`, `just build`, `just switch`, `sudo systemctl reboot` |
| Check a booted image | `./verify.sh` |
| Tune the login screen | `just greeter-preview` |
| Undo | `just rollback`, or hold **Shift** at boot and pick `Bazzite Stable` |
| Undo everything | `just restore` — back to stock upstream Bazzite |

Sway is the only session offered. The image carries no per-user config and no toolchain; see
[Per-user setup](#per-user-setup).

**If the login screen is black:** `Ctrl+Alt+F2`, point `command =` in `/etc/greetd/config.toml`
at the `tuigreet` line written in its comments, `systemctl restart greetd`. greetd is
`Restart=always` with `StartLimitBurst=5` and `Conflicts=getty@tty1.service`, so five failures
in thirty seconds leaves VT 1 dead — logind's other five VTs still work.

## The published image

CI rebuilds nightly against current upstream Bazzite, rechunks, pushes to GHCR and signs with
cosign. One tag, `ghcr.io/asinglebit/bazzite-sway:sway`, plus a dated one (`sway-20260906`) so a
bad night can be pinned around with `just switch-remote sway-20260905`.

There is deliberately **no `:latest`** — deployments track the `:sway` ref, and a bare
`bootc switch ghcr.io/asinglebit/bazzite-sway` resolving elsewhere would silently change what the
machine follows. Nothing fetches on its own: no timer, no update agent. Because the nightly
tracks upstream, `just update` is also how kernel, mesa and NVIDIA driver updates arrive.

### First install

Make the GHCR package public first, or the pull gets a 401 — new packages are private even on a
public repo. Then `just switch-remote sway` and reboot. That first pull is trust-on-first-use,
because the trust ships *inside* the image being installed; everything after it is verified,
since bootc stores the whole `ostree-image-signed:` ref and reuses it verbatim. If the switch is
refused, `just bootstrap-remote sway` does the same pull unverified — move to `just switch-remote`
afterwards. Don't use `bootc switch --enforce-container-sigpolicy`: it demands that the *default*
policy require signatures, which Bazzite's does not.

### Signing, and confirming verification is on

`50-signing.sh` installs the cosign public key at `/etc/pki/containers/asinglebit.pub`, a
`registries.d` entry setting `use-sigstore-attachments: true` (without it the signature is never
looked for and verification silently passes on nothing), and a `sigstoreSigned` +
`matchRepository` block in `policy.json`. A local `just build` passes no registry and skips all
of it.

The first two checks below can both pass while verification falls through to the catch-all. The
third is the one that proves it:

```bash
podman image trust show | grep asinglebit    # 1. rule loaded
just update-check                            # 2. policy evaluated on a real pull

# 3. negative control: same policy, wrong key. Must be REFUSED in about a second.
jq '.transports.docker["ghcr.io/asinglebit"][0].keyPaths =
    ["/etc/pki/containers/ublue-os.pub"]' \
   /etc/containers/policy.json > /var/tmp/wrongkey.json
skopeo --policy /var/tmp/wrongkey.json copy \
   docker://ghcr.io/asinglebit/bazzite-sway:sway dir:/var/tmp/sigproof
#    expect: Source image rejected: cryptographic signature verification failed
rm -rf /var/tmp/wrongkey.json /var/tmp/sigproof
```

If step 3 copies instead of failing, updates are going through unverified. `skopeo inspect` is no
use here — it does not apply the policy at all. To check a published image by hand:
`cosign verify --key cosign.pub ghcr.io/asinglebit/bazzite-sway:sway`.

## Per-user setup

```bash
just link-dotfiles && swaymsg reload   # desktop config from this repo
just greeter-avatar                    # bind the login-screen avatar to this account
just check-shell-config                # optional: validate the config as committed
```

`link-dotfiles` is idempotent, backs up anything in the way, and prunes symlinks this repo no
longer ships. The desktop works without it — the image retires the Fedora sway drop-ins in `/etc`,
so a first login gets a working bar and launcher on stock defaults. What it adds is the palette,
the layout, and the plugins.

`greeter-avatar` cannot be part of the image: the greeter reads the user's `IconFile` from
AccountsService, which is per-user state under `/var`. Without it the login screen draws its stock
line-art person. Re-run after a reinstall; `verify.sh` reports whether it has been.

Shell, toolchains (mise), tmux, Neovim and Ghostty's own config live in
[asinglebit/dotfiles](https://github.com/asinglebit/dotfiles), which deploys with its own
`install.sh` and is portable across OSs. The two repos are independent — exactly one owns any
given path under `~/.config` — so nothing here depends on it and skipping it leaves a working
desktop with a bare shell.

## Layout

| Path | What it does |
| --- | --- |
| `Containerfile` | `FROM ghcr.io/ublue-os/bazzite-nvidia-open:stable`; `ARG IMAGE_REGISTRY`, `IMAGE_TAG`, `CTX_DIGEST` |
| `Justfile` | Every recipe above. `build-image` is the one build path, so CI and `just build` produce the same image |
| `build_files/10-sway-install.sh` | Sway session + desktop packages, NVIDIA env, Inter, Hack Nerd Font, black Papirus folders |
| `build_files/15-swayfx.sh` | Swaps `sway` for `swayfx` from a COPR, enabled for that one transaction |
| `build_files/17-noctalia-greeter.sh` | `noctalia-greeter` from Terra, its GPU wrapper, its greyscale `greeter.toml`, the avatar asset, the SELinux alias its state dir needs |
| `build_files/18-noctalia-shell.sh` | The shell's systemd unit, the `/etc/sway/config.d/` retirements, and the build-time config-validator proof |
| `build_files/20-display-manager.sh` | greetd becomes the DM, pointed at the greeter wrapper |
| `build_files/30-kde-remove.sh` | Plasma removal |
| `build_files/35-devel-install.sh` | The one script here unrelated to the desktop: `-devel` headers a Tauri project on this machine needs to compile |
| `build_files/40-branding.sh` | os-release / image-info.json, removes the ublue MOTD banner, disables `uupd.timer` |
| `build_files/45-bazzite-user-setup.sh` | Patches a bash syntax error in upstream's `/usr/libexec/bazzite-user-setup`, which fails at every login otherwise |
| `build_files/50-signing.sh` | cosign key, `registries.d` entry, `policy.json` block. No-ops on a local build |
| `system_files/` | Files copied verbatim into the image |
| `dotfiles/` | Per-user **desktop** config: outputs, appearance, effects, wallpaper, GTK theming, and `noctalia/`. Symlinked into `~/.config`; never enters the image |
| `verify.sh` | Post-boot checks: the assertions that need a running session, a GPU and a seat, which the build cannot make |
| `.github/workflows/build.yml` | Nightly rebuild: build, rechunk, push, sign |
| `cosign.pub` | Public half of the CI key. `cosign.key` lives only in the `SIGNING_SECRET` Actions secret |

## Things worth knowing

### Compositor

- **`--unsupported-gpu` is mandatory.** Sway 1.11 hard-exits when the DRM driver is named
  `nvidia-drm`, open modules included. It is in `/etc/sway/environment` via `SWAY_EXTRA_ARGS`
  alongside `-D noscanout`. Miss it and you get a black screen.
- **`WLR_RENDERER=gles2`, not vulkan.** SwayFX's `fx_renderer` has no Vulkan path. At vulkan the
  compositor starts, works, and silently draws none of the effects.
- **`sway-systemd` is not optional.** `xdg-desktop-portal.service` carries
  `Requisite=graphical-session.target` ([RHBZ 2481764][rhbz]) and `sway-session.target` is what
  reaches it. Without it the portal refuses to start, taking Flatpak file dialogs, screen sharing
  and the Steam overlay with it. `sway-config-fedora` only *Recommends* it.
- **swayfx is a drop-in.** It `Provides: sway`, `Conflicts: sway`, and installs at
  `/usr/bin/sway`, so `start-sway`, greetd, `swaymsg` and `sway-systemd` are untouched — but
  `rpm -q --whatprovides sway`, not `rpm -q sway`. The COPR RPM is an `.fc43` build linking
  `libwlroots-0.19.so`; `15-swayfx.sh` asserts that, so the day Fedora retires the compat package
  the nightly fails instead of shipping a black screen.
- **`$term` is set by sed in `/etc/sway/config`, not from `config.d`.** sway expands `set`
  variables at parse time, so a late `set $term` does nothing. A later `bindsym` *does* win, which
  is why key bindings are overridden normally.

### Login screen

- **greetd, not SDDM or plasmalogin.** It is the only one that lets us write the greeter's command
  line. `sddm-wayland-sway` runs its greeter *as a Sway instance* and hits sway's NVIDIA guard;
  `plasmalogin` requires kwin-wayland.
- **noctalia-greeter hosts itself.** It is a native EGL/GLES2 Wayland client shipping its own
  wlroots 0.20 compositor, and scans `/usr/share/wayland-sessions` directly — so there is no
  `/etc/greetd/environments` and no `bash -l` escape hatch at the prompt. Fedora's `wlroots` is
  0.20 and its `wlroots0.19` compat package is what SwayFX links; `17-` asserts both sonames.
- **greetd runs `/usr/libexec/noctalia-greeter-nvidia`**, not the session script directly. The
  bundled compositor is a separate wlroots instance and inherits nothing from
  `/etc/sway/environment`, and greetd's TOML cannot set env vars. The wrapper pins
  `WLR_RENDERER=gles2`; the escalation inside it is `WLR_DRM_NO_MODIFIERS=1`.
- **tuigreet stays installed and unbound** as the only rung below it, chosen because it needs no
  compositor and no GPU. A GPU stack is on the login path, so a driver regression takes the login
  screen down with the session.
- **`greeter.toml` is unvalidatable.** Neither greeter subcommand reads it, so a misspelled key is
  ignored in silence. `17-` checks it as TOML and asserts the palette;
  `noctalia-greeter sessions` is the one behavioural check that runs in a container.
- **`just greeter-preview`** runs the real greeter nested (`WLR_BACKENDS=wayland`) against
  `fakegreet` instead of greetd, on a throwaway copy of the shipped `greeter.toml`. Log in as
  `user` / `password`; the sum is `9`. It only runs from a deployment that already has the
  greeter, exercises no DRM/KMS/renderer selection, and is a re-theming tool rather than a
  pre-flight check.

### The shell

- **One unit, no rung below it.** `noctalia.service`, wanted by `sway-session.target`, is the bar,
  launcher, notification daemon, OSD, clipboard, screenshot tool, idle daemon, lock screen and the
  only authentication agent on the machine — so `pkexec`, `ujust` and `bazzite-user-setup` hang
  rather than fail if it dies. If it is dead the session is a compositor and a wallpaper and
  **the only symptom is silence**. `$mod+Return` still opens a terminal; that binding is in
  `/etc/sway/config` and does not go through the shell.
- **Eight packages are retired, not removed.** `sway-config-fedora` owns `/etc/sway/config`,
  `start-sway`, `layered-include` and the wayland-sessions entry, and hard-`Requires` waybar,
  swaylock, swayidle, swaybg, grimshot, brightnessctl, playerctl and lxqt-policykit — so they
  cannot leave. They are neutralised by comment-only files of the same name in
  `/etc/sway/config.d/`, which `layered-include` reads after `/usr/share/sway/config.d`.

  **That is the way back without a rollback.** `sudo rm /etc/sway/config.d/90-bar.conf` and log out
  gives stock waybar back; `90-swayidle.conf` for swayidle + swaylock, `60-bindings-screenshot.conf`
  for grimshot. bootc 3-way merges `/etc`, so the deletions persist across upgrades, and
  `verify.sh` reports each missing file.
- **`noctalia config validate` is the only validator in the session path**, and `18-` proves at
  build time that it works, against a known-good and a known-bad file. It cannot see this repo's
  config — `.containerignore` excludes `dotfiles/` — so `just check-shell-config` validates what is
  committed (with `NOCTALIA_CONFIG_HOME` pointed at the repo, bypassing GUI state) and `verify.sh`
  validates what the running session merged.
- **Layer-shell namespaces are literal strings.** `25-effects.conf` blurs noctalia's surfaces by
  namespace, so a rename upstream is not an error — it silently stops blurring one surface, and
  nothing at build time can see a layer surface. `verify.sh` compares the file against what
  `swaymsg -t get_outputs` reports the compositor actually applied.
- **The palette is stated twice and asserted equal**, in `system_files/.../greeter.toml` for the
  login screen and `dotfiles/noctalia/palettes/bazzite-grey.json` for the desktop.
  `noctalia msg greeter-sync` is deliberately unused: `tmpfiles.d` recreates the greeter's `/var`
  copy from `/usr/share/factory` on every boot, so a sync write would not survive. `verify.sh` and
  `just check-shell-config` both compare the two files role by role.
- **Five of six plugins are fetched from GitHub.** Only `asinglebit/bazzite-sway` (sway binding
  mode, scratchpad count, failed units, hardware readings) is in this repo, as a `path` source. The
  other five resolve from github.com at first use and cache under
  `~/.local/state/noctalia/plugin-cache` — outside the image, untracked, unpinned and unverified;
  `verify.sh` checks only `bazzite-sway`. `auto_update` is `"none"`, so nothing re-fetches on its
  own. Vendor one into `dotfiles/noctalia/plugins/` and add a path source to change that.

  `noctalia config validate` warns `unrecognized widget type` for the one git-sourced widget on the
  bar. That is expected — it parses headlessly and never fetches. `noctalia msg plugins list` asks
  the running shell and is the check that answers.
- **Workspaces come over i3 IPC**, via `$SWAYSOCK`, because SwayFX does not advertise
  `ext_workspace_manager_v1`. It does not advertise `ext_background_effect_manager_v1` either, so
  the shell cannot blur behind its own surfaces; every blurred surface is a `layer_effects` line in
  `25-effects.conf` instead.

### Packaging and build

- **Two third-party RPM repos**, both shipped **disabled** and enabled for exactly one transaction
  each, because `--enable-repo` is a dnf5 global and a shared transaction would let either satisfy
  an unrelated package: Terra (ghostty and the greeter — already trusted by the base image, key in
  `/etc/pki/rpm-gpg/`) and `swayfx/swayfx` (the compositor). noctalia itself is in Fedora proper,
  vendor `Fedora Project`, asserted in CI.
- **Weak dependencies are off** (`install_weak_deps=False` in the base), so every package is in the
  install list by name. Two are load-bearing and asserted: `ddcutil` is the *only* brightness path
  on this hardware — `/sys/class/backlight` is empty, both outputs being external, so
  `brightnessctl` has no device — and `wtype` is the clipboard panel's auto-paste.
- **Two of the four fonts are unchecked.** Inter and Hack Nerd Font Mono are installed by the
  build and asserted by it, CI and `verify.sh`. The two the shell names in `dotfiles/` are not:
  they come from the base image, and a miss is not an error — it is the whole shell rendering in
  the fallback. `fc-match "Noto Sans CJK SC"` must answer `NotoSansCJK-Regular.ttc`.
- **GTK reads dconf, not `settings.ini`.** On Wayland GTK takes theme, icon theme, cursor theme
  and font from the XDG desktop portal, which answers out of `org.gnome.desktop.interface` —
  silently. The configuration is therefore the gschema override in the image, and `settings.ini` is
  documentation. It sets a *default*, so a key some earlier tool wrote explicitly still wins until
  `dconf reset`; `verify.sh` prints each one still overridden.
- **Black folders are baked in.** `papirus-folders` rewrites `/usr/share/icons/Papirus/`, which is
  read-only at runtime, so it runs at build time and `rpm -V papirus-icon-theme` reports those
  files as modified afterwards.
- **KDE removal is an explicit package list, never a glob.** `plasma-*` would take
  `plasma-foreground-booster-dmemcg`; `kde-*` would take `kde-settings`. Qt6/KF6 libraries stay so
  `btrfs-assistant`, `bazzite-updater` and KDE-flatpak theming keep working.
- **`base-image-name` stays `kinoite`** in `image-info.json` — it is the runtime DE oracle read by
  `bazzite-user-setup`, `80-bazzite.just` and `82-bazzite-sunshine.just`, and any other value drops
  them into the GNOME/dconf branch.
- **Build as root.** bootc reads root's containers-storage at `/var/lib/containers/storage`; a
  rootless build lands where root cannot see it. Never `--squash` — it rewrites layer diffids,
  which is the mechanism behind [`Missing ostree.final-diffid`][diffid]. If `just switch` hits
  that, run `just rechunk` first.
- **Rebuilding the same tag needs `bootc upgrade`, not `switch`.** `switch` compares the image
  *reference*, not its content, and prints "Image specification is unchanged" while leaving the
  previous build staged. `just switch` detects that and falls through to `upgrade`.
- **`uupd.timer` is disabled.** It fires at 04:00 against a `containers-storage` ref it cannot
  upgrade, and bootc warns that an active update agent can revert a queued rollback.

## Known limitations

- **The settings GUI outranks this repo.** noctalia merges its defaults, then
  `~/.config/noctalia/*.toml`, then `~/.local/state/noctalia/settings.toml` — and the last is
  written by clicking in the settings window and wins. A value tuned there silently shadows
  `dotfiles/noctalia/` and is not version-controlled. `verify.sh` reports the file if it exists;
  deleting it hands control back, and `just check-shell-config` ignores it either way.
- **A rollback restores the image, not `dotfiles/`.** The two roll back separately and neither
  knows about the other.
- **No HDR** — `color-management-v1` landed in sway 1.12 and F44 has 1.11. VRR
  (`--adaptive-sync`) does work.
- **No Vulkan renderer**, which is SwayFX's GLES2-only `fx_renderer`.
- **No screen recording.** noctalia's capture is stills; `grim`, `slurp` and `grimshot` are on disk
  but nothing is bound to them.
- **Screen sharing is whole-output only** — `xdg-desktop-portal-wlr` has no window picker. The
  bar's `privacy` widget exists because of that: it appears only while something is capturing, and
  what is capturing is capturing everything.
- **The login screen does not match the desktop exactly.** noctalia-greeter treats
  `[appearance.palette]` as seed colours and tone-adjusts them, and its text caret ignores the
  palette outright with no key to override it. Everything stays neutral grey; it just is not the
  same grey.
- **The `dark_mode` control-centre shortcut will make the desktop pale.** The palette defines no
  light variant, which is why `20-theme.toml` pins the mode to dark. Press it again to undo.
- **`noctalia-greeter` and `noctalia` are both young**, from a codebase family whose open upstream
  bugs cluster on multi-output DRM teardown — which is this machine's exact shape. The greeter
  keeps `tuigreet` behind it; the shell keeps nothing.
- If gamescope crashes with `vkImportSemaphoreFdKHR failed`, set `ENABLE_GAMESCOPE_WSI=0`
  ([gamescope#1662][gs]).
- If the cursor misbehaves, add `WLR_NO_HARDWARE_CURSORS=1` to `/etc/sway/environment`.
- Lost with Plasma: Sunshine virtual monitors / KWin screencast, `kscreen-doctor` custom
  resolutions, `bazzite-powersave`'s qdbus path (`tuned-ppd` still works).
- Don't use `ujust toggle-nvk` or the `40-nvidia.just` toggles — they do naive string substitution
  on the image URI and break on a custom ref. `ujust verify-image` is safe; it no-ops here.

## Prior art

- [wayblueorg/wayblue](https://github.com/wayblueorg/wayblue) — sway/hyprland/river on Fedora
  Atomic; source of the NVIDIA environment settings.
- [gabeklavans/bazzite-niri](https://github.com/gabeklavans/bazzite-niri) — Bazzite-derived,
  Plasma removed, wlroots-family compositor.
- [ublue-os/image-template](https://github.com/ublue-os/image-template) — the Containerfile and
  Justfile shape.

[sway]: https://swaywm.org
[swayfx]: https://github.com/WillPower3309/swayfx
[noctalia]: https://docs.noctalia.dev/noctalia/
[rhbz]: https://bugzilla.redhat.com/show_bug.cgi?id=2481764
[diffid]: https://github.com/ublue-os/bazzite/issues/1892
[gs]: https://github.com/ValveSoftware/gamescope/issues/1662
