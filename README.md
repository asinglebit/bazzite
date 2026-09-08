# Bazzite noctalia swayfx image

<img width="1536" height="864" alt="image (1)" src="https://github.com/user-attachments/assets/ddd9ff47-8579-4152-9553-3b005620f3a0" />

A [Bazzite](https://bazzite.gg)-derived bootc image running [SwayFX][swayfx] — [Sway][sway] with
blur, rounded corners and shadows — instead of KDE Plasma, with Bazzite's gaming and hardware stack
intact: ogc kernel, patched mesa/Xwayland/bluez/wireplumber, Steam, gamescope, MangoHud, sched_ext,
`ujust`.


Everything that is not the compositor is [noctalia][noctalia]: bar, launcher, notifications and
control centre, session menu, lock screen, OSD, clipboard, screenshots and the polkit agent, from
one TOML directory and one palette. `noctalia-greeter` is the login screen. The look is flat
greyscale — the desktop's half lives in `dotfiles/`, the login screen's in the image.

Built for `ghcr.io/ublue-os/bazzite-nvidia-open:stable` on an RTX 4070 Ti (nvidia-open 610.x),
Fedora 44. Sway is the only session offered.

## What is in here

| Path | What it is |
| --- | --- |
| `Containerfile` | `FROM ghcr.io/ublue-os/bazzite-nvidia-open:stable`, then one `RUN` of `build_files/build.sh` |
| `Justfile` | Every command below. `build-image` is the single build path, so CI and a local build produce the same image |
| `build_files/` | The build, in order: `10` desktop packages + NVIDIA env + fonts + icons, `15` swap sway for swayfx, `17` the greeter, `18` the shell, `20` greetd as DM, `30` remove Plasma, `35` `-devel` headers for an unrelated project, `40` branding, `45` patch upstream's broken `bazzite-user-setup`, `50` cosign trust |
| `system_files/` | Copied verbatim into the image: greetd config, the greeter's wrapper and `greeter.toml`, the shell's systemd unit, tmpfiles rules, the gschema override, and the comment-only `/etc/sway/config.d/` files that retire Fedora's drop-ins |
| `dotfiles/` | Per-user **desktop** config — outputs, input, appearance, effects, wallpaper, GTK theming, `noctalia/`. Symlinked into `~/.config`; never enters the image |
| `verify.sh` | Post-boot checks: the assertions needing a running session, a GPU and a seat, which the build cannot make |
| `.github/workflows/build.yml` | Nightly rebuild → rechunk → in-image checks → push → cosign sign → verify |
| `cosign.pub` | Public half of the CI signing key. `cosign.key` lives only in the `SIGNING_SECRET` Actions secret |

Shell, toolchains, tmux and Ghostty's own config are a separate, portable repo:
[asinglebit/dotfiles](https://github.com/asinglebit/dotfiles). The two are independent — exactly
one owns any given path under `~/.config` — so nothing here needs it.

## Install the published image

CI publishes `ghcr.io/asinglebit/bazzite-sway:sway` plus a dated tag (`sway-20260906`), both the
same manifest and one signature. There is deliberately **no `:latest`**: deployments track the
`:sway` ref, and a bare `bootc switch ghcr.io/asinglebit/bazzite-sway` resolving elsewhere would
silently change what the machine follows.

```bash
just switch-remote sway     # verifies the cosign signature
sudo systemctl reboot
```

The GHCR package has to be public first, or the pull gets a 401 — new packages are private even on
a public repo. That first pull is trust-on-first-use, because the trust ships *inside* the image
being installed; everything after it is verified, since bootc stores the whole
`ostree-image-signed:` ref and reuses it verbatim. If the switch is refused,
`just bootstrap-remote sway` does the same pull unverified — move to `switch-remote` afterwards.
Don't reach for `bootc switch --enforce-container-sigpolicy`: it demands the *default* policy
require signatures, which Bazzite's does not.

### Updating

Nothing fetches on its own — no timer, no update agent. Because the nightly tracks upstream, this
is also how kernel, mesa and NVIDIA driver updates arrive.

```bash
just update-check   # metadata only, no layers
just update         # stage; applies at the next reboot
just update-now     # stage and reboot straight into it
```

### Updating without this repo

The update recipes are one-line wrappers, and bootc stores the image ref *inside the deployment*,
so a machine that already follows the published tag needs no checkout to keep current:

| | |
| --- | --- |
| `just update-check` | `sudo bootc upgrade --check` |
| `just update` | `sudo bootc upgrade` |
| `just update-now` | `sudo bootc upgrade --apply` |
| `just rollback` | `sudo bootc rollback --apply` |
| `just status` | `bootc status` |
| `just switch-remote sway` | `sudo bootc switch ostree-image-signed:docker://ghcr.io/asinglebit/bazzite-sway:sway` |
| `just bootstrap-remote sway` | `sudo bootc switch ghcr.io/asinglebit/bazzite-sway:sway` |

The catch is that `bootc upgrade` re-resolves whichever ref the deployment already carries, so it
is not enough on a machine that got here through `just switch`. That one follows
`ostree-unverified-image:containers-storage:localhost/bazzite-sway:sway` — its own podman
storage — and will never see a CI build however many times the workflow runs. `bootc status` says
which; if the ref reads `containers-storage`, the move onto GHCR is a one-time `bootc switch`,
after which plain `bootc upgrade` is enough forever.

Take that first switch **unverified**, and deliberately so. A locally built machine has no
`asinglebit` rule in `policy.json` and no `/etc/pki/containers/asinglebit.pub`, because a local
build passes no registry and `50-signing.sh` skips the trust setup — so the `ostree-image-signed:`
ref matches nothing and falls through to the `""` catch-all, which is `insecureAcceptAnything`. It
would pull unverified while *looking* verified, the same trap the next section is about. Use
`bootstrap-remote`, reboot, confirm the pubkey landed, then move to `switch-remote`.

Both prerequisites above still apply — a published image to upgrade to ([Running the CI
yourself](#running-the-ci-yourself)) and a readable package. To keep that package private rather
than public, put a pull secret at `/etc/ostree/auth.json`: bootc reads that, not a user's `podman
login`.

### Confirming verification is actually on

The first two checks can both pass while verification silently falls through to the catch-all. The
third is the one that proves it.

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

## Build and apply locally

```bash
just insurance          # pin the running deployment, disable uupd — do this once
just build              # ~40 min cold; the base image alone is ~13 GB extracted
just switch             # point the system at localhost/bazzite-sway:sway
sudo systemctl reboot
```

A local build passes no registry, so `40-branding.sh` keeps the `containers-storage` ref and
`50-signing.sh` skips the trust setup entirely — the image stays unsigned and says so.

| | |
| --- | --- |
| `just stage` | Download and stage without committing to a reboot |
| `just build-image tag registry pull` | The parameterised form. `just build` is `build-image sway`; CI passes a registry and `newer` |
| `just rechunk` | Only if `switch` fails with `Missing ostree.final-diffid` ([bazzite#1892][diffid]) |
| `just clean` | Drop local build layers. Does not touch the OS or its deployments |
| `just status` | `bootc`, `rpm-ostree` and `ostree` status together |

Two things about the build that are easy to get wrong: it must run as **root** (the recipe uses
`sudo podman`, because bootc reads root's containers-storage), and never `--squash` — it rewrites
layer diffids, which is the `Missing ostree.final-diffid` bug above.

Rebuilding the *same* tag then needs `bootc upgrade`, not `switch`: `switch` compares the image
reference rather than its content and would leave the previous build staged. `just switch` detects
that and falls through automatically.

## Per-user setup

The image carries the desktop and no per-user config.

```bash
just link-dotfiles && swaymsg reload   # this repo's desktop config
just greeter-avatar                    # bind the login-screen avatar to this account
just check-shell-config                # optional: validate the config as committed
```

`link-dotfiles` is idempotent, backs up anything in the way, and prunes symlinks this repo no
longer ships. The desktop works without it — the image retires Fedora's sway drop-ins in `/etc`, so
a first login gets a working bar and launcher on stock defaults. What it adds is the palette, the
monitor layout and the plugins.

`greeter-avatar` cannot be part of the image: the greeter reads the user's `IconFile` from
AccountsService, which is per-user state under `/var`. Without it the login screen draws its stock
line-art person. Re-run after a reinstall; `verify.sh` reports whether it has been.

## Checking and recovering

```bash
./verify.sh              # post-boot checks against the running session
just greeter-preview     # the real login screen, nested, against a fake greetd
just rollback            # previous deployment
just restore             # all the way back to stock upstream Bazzite
```

Or hold **Shift** at boot and pick the older entry — `40-branding.sh` labels them `Bazzite Sway`
so they are distinguishable under pressure.

**If the login screen is black:** `Ctrl+Alt+F2`, point `command =` in `/etc/greetd/config.toml` at
the `tuigreet` line written in its comments, `systemctl restart greetd`. greetd is
`Restart=always` with `StartLimitBurst=5` and `Conflicts=getty@tty1.service`, so five failures in
thirty seconds leaves VT 1 dead — logind's other five VTs still work.

**If the shell is dead,** the session is a compositor and a wallpaper and the only symptom is
silence: no bar, no notifications, no lock, and `pkexec` hangs rather than failing. `$mod+Return`
still opens a terminal — that binding is in `/etc/sway/config` and does not go through the shell.
`sudo rm /etc/sway/config.d/90-bar.conf` and log out gives stock waybar back; `90-swayidle.conf`
restores swayidle and swaylock. bootc 3-way merges `/etc`, so those deletions persist.

## Running the CI yourself

The workflow needs one secret and one permission:

```bash
COSIGN_PASSWORD="" cosign generate-key-pair    # produces cosign.key + cosign.pub
```

Commit `cosign.pub`; put the contents of `cosign.key` in the repo secret `SIGNING_SECRET`
(Settings → Secrets and variables → Actions). `cosign.key` is gitignored and must stay that way.
The job checks the secret exists before spending forty minutes on a build, because a run that
built, pushed and *then* failed to sign would leave an unsigned image on GHCR that the policy baked
into it refuses on every later `bootc upgrade`.

It triggers on a nightly cron (12:00 UTC), on pushes to `main` that touch something able to change
the image (`**.md`, `dotfiles/**` and `verify.sh` are ignored), on pull requests, and manually via
`workflow_dispatch`. Pull requests build and run the in-image checks but do not push or sign.

## Known limitations

- **The settings GUI outranks this repo.** noctalia merges its defaults, then
  `~/.config/noctalia/*.toml`, then `~/.local/state/noctalia/settings.toml` — and the last is
  written by clicking in the settings window and wins. `verify.sh` reports that file if it exists;
  deleting it hands control back.
- **A rollback restores the image, not `dotfiles/`.** The two roll back separately and neither
  knows about the other.
- **No HDR** (`color-management-v1` is sway 1.12; F44 has 1.11) and **no Vulkan renderer**
  (SwayFX's `fx_renderer` is GLES2-only). VRR does work.
- **No screen recording** — noctalia's capture is stills. **Screen sharing is whole-output only**;
  `xdg-desktop-portal-wlr` has no window picker, which is why the bar has a `privacy` widget.
- **The login screen does not match the desktop exactly.** noctalia-greeter treats
  `[appearance.palette]` as seed colours and tone-adjusts them, and its caret ignores the palette
  outright. Everything stays neutral grey; it just is not the same grey.
- **Five of six noctalia plugins are fetched from GitHub** at first use and cached outside the
  image, untracked and unpinned. Only `asinglebit/bazzite-sway` is in this repo. `auto_update` is
  `"none"`, so nothing re-fetches on its own.
- Don't use `ujust toggle-nvk` or the `40-nvidia.just` toggles — they do naive string substitution
  on the image URI and break on a custom ref. `ujust verify-image` is safe; it no-ops here.
- Lost with Plasma: Sunshine virtual monitors / KWin screencast, `kscreen-doctor` custom
  resolutions, `bazzite-powersave`'s qdbus path (`tuned-ppd` still works).

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
[diffid]: https://github.com/ublue-os/bazzite/issues/1892
