# Components

The parts of the image, each in its own note.

| Note | Owns |
| --- | --- |
| [[Compositor]] | Drawing windows: SwayFX, wlroots, the NVIDIA environment, blur and rounding. |
| [[Shell]] | Everything that is not drawing windows: bar, launcher, notifications, lock, polkit. |
| [[Login screen]] | Getting you to a session: greetd, noctalia-greeter, the fallback. |
| [[Theming]] | What it all looks like: the greyscale palette, GTK, icons, fonts. |
| [[Workspaces]] | Per-screen blocks of ten, and the helper that works them out. |
| [[Applications]] | Flatpaks, the terminal, and what Plasma's removal took with it. |

## The one-paragraph version

A Bazzite bootc image with Plasma removed. [[Compositor|SwayFX]] draws the windows;
[[Shell|noctalia]] is every other part of the desktop, from one package and one TOML
directory; [[Login screen|noctalia-greeter]] is the login screen and brings its own
compositor. Bazzite's gaming and hardware stack — ogc kernel, patched mesa and Xwayland,
Steam, gamescope, MangoHud — is untouched underneath.

## Two packages that share a name

`noctalia` and `noctalia-greeter` are separate products. They share a name, a palette and
an upstream, and nothing else: different repos (Fedora and Terra), different wlroots
versions, different config files, no overlapping files at all. The build asserts that last
one, because two packages claiming the same path would break the login screen.

See [[Shell]] and [[Login screen]].
