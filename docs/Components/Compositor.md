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

## The wlroots pin

SwayFX links `libwlroots-0.19`, which Fedora 44 still ships as a compat package. The
upstream COPR build is old and nobody has rebuilt it against 0.20.

This is the image's most likely future breakage, so it is a deliberate tripwire: the build
asserts `ldd /usr/bin/sway` contains `libwlroots-0.19.so`, and CI repeats it. The day
Fedora retires that compat package, the nightly fails instead of publishing a desktop that
cannot start.

The [[Login screen]] runs wlroots **0.20** at the same time. The two coexist on purpose,
and the build asserts each is on its own.

## NVIDIA

From `/etc/sway/environment`, written by `build_files/10-sway-install.sh`:

| Variable | Why |
| --- | --- |
| `SWAY_EXTRA_ARGS=--unsupported-gpu` | sway refuses to start on this driver without it. |
| `-D noscanout` | The standard fix for flicker and black frames on NVIDIA. |
| `WLR_RENDERER=gles2` | SwayFX's `fx_renderer` is GLES2-only. |
| `LIBVA_DRIVER_NAME=nvidia`, `NVD_BACKEND=direct` | Hardware video decode. |
| `ELECTRON_OZONE_PLATFORM_HINT=auto` | Electron apps get Wayland rather than XWayland. |

`WLR_RENDERER=gles2` is the one with a silent failure mode: on Vulkan, SwayFX starts
perfectly and simply draws **none** of its effects. Both the build and `verify.sh` check
the value rather than trusting it.

Two consequences fall out of the GLES2 pin: no Vulkan renderer, and no HDR
(`color-management-v1` landed in sway 1.12; F44 has 1.11). VRR does work.

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
