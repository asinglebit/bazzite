# Build and release

## The Containerfile

Two stages. The first is `FROM scratch AS ctx` and exists only to hold `build_files/`,
`system_files/` and `cosign.pub`, so editing a build script does not invalidate the 5 GiB
base layer. The second is `FROM ghcr.io/ublue-os/bazzite-nvidia-open:stable` and runs
`build_files/build.sh` in a single `RUN`, followed by `bootc container lint`.

`CTX_DIGEST` is a hash of the build scripts, passed as a build arg for one reason: without
it podman says "Using cache" and quietly re-tags the previous image even though a script
changed.

## The numbered steps, and why the order

`build_files/build.sh` runs them in sequence. Four of the orderings are load-bearing and
are commented as such in the file:

| Step | Does | Ordering constraint |
| --- | --- | --- |
| `10-sway-install` | Desktop packages, NVIDIA env, fonts, icons, theme | |
| `15-swayfx` | Swap sway for SwayFX | **Before 17**, whose checks would otherwise inspect the Fedora sway this replaces |
| `17-noctalia-greeter` | The login screen | |
| `18-noctalia-shell` | Wire the shell to the session | **After 17** so it can compare palettes; **before 20** which picks the session |
| `20-display-manager` | greetd as the display manager | **Before 30**, so the image never points `display-manager.service` at a package that is gone |
| `30-kde-remove` | Remove Plasma and KDE apps | |
| `35-devel-install` | `-devel` headers for an unrelated project | |
| `40-branding` | os-release, image-info, GRUB label, disable uupd | |
| `45-bazzite-user-setup` | Patch upstream's broken login script | **After 40**, which must leave `base-image-name` as `kinoite` |
| `50-signing` | cosign trust files | |

Two of those deserve expanding.

**`40-branding`** must keep `base-image-name` as `"kinoite"`. It is the runtime oracle
Bazzite's own scripts and `ujust` recipes read to work out which desktop this is; any
other value sends them down a worse branch. The build and CI both assert it.

**`45-bazzite-user-setup`** patches a script in stock Bazzite that has an empty `then`
branch and therefore does not parse. It is patched rather than masked because the script
never reaches the part that would stop it re-running, so it would fail at every login
forever.

## Rechunking

`rpm-ostree compose build-chunked-oci` re-splits the image into per-package layers that
stay byte-identical across rebuilds. That is the difference between a nightly update
pulling hundreds of MB and pulling several GB.

It must happen **before** the push, because it rewrites the manifest and the signature is
over the pushed digest. It also drops every label, so `just rechunk-ci` reads them off the
source image and re-applies them — except the `ostree.*` ones, which are regenerated, and
re-applying stale ones causes the very `Missing ostree.final-diffid` bug the recipe exists
to fix.

## Signing

Key-based cosign, not keyless — so the workflow needs no OIDC token. Three files go into
the image, and missing the middle one is the interesting failure:

1. `/etc/pki/containers/<ns>.pub` — the public key.
2. `/etc/containers/registries.d/<ns>.yaml` with `use-sigstore-attachments: true` — where
   to look for the signature. **Without this, verification passes without ever looking.**
3. `/etc/containers/policy.json` with a `sigstoreSigned` rule for the registry.

The `""` catch-all in `policy.json` must survive as `insecureAcceptAnything`, or the first
bootstrap switch onto this image — on a machine that does not yet trust it — would be
impossible. CI asserts all four conditions.

`cosign sign` is called with `--new-bundle-format=false --use-signing-config=false`.
Without them, cosign v3 writes a bundle format podman, skopeo and bootc cannot read as a
sigstore attachment, and verification then fails at pull time on the machine rather than
in CI.

A **local build passes no registry**, so `50-signing.sh` skips the trust setup entirely
and the image stays unsigned and says so. This matters more than it sounds — see the
bootstrap trap in [[Cadence]].

## CI

`.github/workflows/build.yml`. Order: check the secret → free disk → build → rechunk →
run the in-image checks → push → sign → verify.

The secret check is first on purpose. A run that built, rechunked and pushed successfully
and only then failed to sign would leave an **unsigned** image on GHCR that the policy
baked into it refuses on every later upgrade. Failing in seconds beats failing after forty
minutes with a broken artifact published.

Disk is the other practical constraint: the base image extracts to ~13 GB and the rechunk
writes two more full copies, so peak demand is around 40 GB against a runner that starts
with about 20 GB free.

The in-image checks run **after** the rechunk precisely so they also prove the rechunk
preserved `/etc` and the enablement symlinks.

Triggers: nightly cron at 12:00 UTC, pushes to `main` that can change the image
(`**.md`, `dotfiles/**`, `verify.sh` and `.gitignore` are ignored), pull requests, and
`workflow_dispatch`. **Pull requests build and check but do not push or sign.**

Related: [[Cadence]], [[Architecture]], [[Operations]].
