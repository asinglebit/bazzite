# Compositor

[SwayFX](https://github.com/WillPower3309/swayfx) — Sway with blur, rounded corners,
shadows and inactive dimming.

## A drop-in, not a fork

`build_files/15-swayfx.sh` does `dnf5 swap sway swayfx`. SwayFX reports the same version,
installs to the same `/usr/bin/sway`, and provides `sway`, so `start-sway`, greetd,
`swaymsg` and the session desktop entry all keep working without knowing. Fedora's
`sway-config-fedora` is deliberately kept, because SwayFX needs it — which is also what
drags in the packages [[Architecture|retired rather than removed]].

Because `swayfx` carries `Conflicts: sway`, there is no package called `sway` any more.
Anything checking for it uses `rpm -q --whatprovides sway`.

## wlroots

SwayFX links the wlroots Fedora itself ships, the same one the [[Login screen]] uses.
The two drifting apart — Fedora moving on while SwayFX stays behind — is still the image's
most likely future breakage, so it is a deliberate tripwire: the build reads the library
name out of Fedora's `wlroots` package and asserts `ldd /usr/bin/sway` contains it, and CI
and `verify.sh` repeat it. Read rather than written down, so a wlroots bump both sides
take needs no edit, and one only Fedora takes fails the nightly instead of publishing a
desktop that cannot start.

## NVIDIA

From `/etc/sway/environment`, written by `build_files/10-sway-install.sh`:

| Variable | Why |
| --- | --- |
| `SWAY_EXTRA_ARGS=--unsupported-gpu` | sway refuses to start on this driver without it. |
| `WLR_SCENE_DISABLE_DIRECT_SCANOUT=1` | Turns off direct scanout, the standard fix for flicker and black frames on NVIDIA. Sway's own `-D noscanout` is gone since 1.12, and only logs an error if passed. |
| `WLR_RENDERER=gles2` | SwayFX's `fx_renderer` is GLES2-only. |
| `LIBVA_DRIVER_NAME=nvidia`, `NVD_BACKEND=direct` | Hardware video decode. |
| `ELECTRON_OZONE_PLATFORM_HINT=auto` | Electron apps get Wayland rather than XWayland. |

`WLR_RENDERER=gles2` is the one with a silent failure mode: on Vulkan, SwayFX starts
perfectly and simply draws **none** of its effects. Both the build and `verify.sh` check
the value rather than trusting it.

Two consequences fall out of the GLES2 pin: no Vulkan renderer, and no HDR — SwayFX is
built on sway 1.12, which has it, but `fx_renderer` cannot do the output colour transforms
HDR needs. VRR does work.

## Effects

`dotfiles/sway/config.d/25-effects.conf`. These apply to the chrome — bar, panels,
gaps — not to application windows, which stay opaque.

Two settings are load-bearing rather than decorative:

- **`default_dim_inactive`.** With `default_border none` there is no border to mark focus,
  so dimming is the only thing that shows which window is active.
- **`blur_ignore_transparent`** on every `noctalia-*` layer. Each panel claims a surface
  far larger than it paints; without this, an open panel frosts the whole screen for as
  long as it is up.

The `layer_effects` lines name noctalia's layer-shell namespaces, which were read out of
the binary. A rename upstream would stop blurring one surface and say nothing, so
`build_files/18-noctalia-shell.sh` asserts each string still exists in `/usr/bin/noctalia`,
and `verify.sh` asks the compositor which surfaces it actually blurred.

Full-screen surfaces and the lock screen are left out on purpose: rounding a full-screen
surface would round the screen itself, and noctalia blurs its own lock snapshot.

## Why the config is not validated at build time

`build_files/15-swayfx.sh` says so explicitly and tells you not to add it back. Inside a
container, `sway -C` cannot run at all — first a file capability, then a libseat seat that
does not exist — and a good config fails identically to a broken one. A check there would
prove nothing while looking like it proved something.

`verify.sh` does it after boot instead, from a real session. Note that `sway --validate`
needs `--unsupported-gpu` on this driver, or it exits on the NVIDIA guard before parsing
anything.

Related: [[Shell]], [[Theming]], [[Workspaces]].
