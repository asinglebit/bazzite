# bazzite-sway

The reference vault for this image: what it is made of, why each piece was chosen, and
what moves on its own.

The repo's own `README.md` is the task-facing document — install it, update it, the exact
commands. This vault is the understanding-facing one. Where they overlap, the README is
the shorter answer and these notes are the reason behind it.

## Start here

| If you want to | Read |
| --- | --- |
| Understand the shape of the thing | [[Architecture]] |
| Know what a given part does | [[Components]] |
| Know *why* it is like this | [[Decisions]] |
| Know what changes on its own | [[Cadence]] |
| Drive it day to day | [[Operations]] |
| Fix it at 2am | [[Recovery]] |

## Contents

- **[[Architecture]]** — the three layers (image, `/etc`, `~/.config`) and the rule that
  decides which one a given file belongs in.
- **[[Components]]** — index of the parts:
  - [[Compositor]] — SwayFX, the wlroots pin, the NVIDIA flags, the effects.
  - [[Shell]] — noctalia, which is everything except the compositor.
  - [[Login screen]] — greetd, noctalia-greeter and its own compositor.
  - [[Theming]] — the greyscale palette and the four places it has to be repeated.
  - [[Workspaces]] — a block of ten per screen, derived at runtime.
  - [[Applications]] — flatpaks, the terminal, and what left with KDE.
- **[[Build and release]]** — Containerfile, the numbered build steps, rechunking, signing, CI.
- **[[Cadence]]** — what updates nightly, what updates when asked, and what never updates itself.
- **[[Decisions]]** — the choices, each with the alternative that was rejected.
- **[[Operations]]** — first run, per-user setup, the verification suite.
- **[[Recovery]]** — black login screen, dead shell, missing bar, rollback.

## Conventions in this vault

Notes describe the image **as committed**, not as running. When the two can disagree —
the settings GUI, dconf, a stale deployment — the note says so, and `verify.sh` is the
thing that tells you which you have.

Paths are given relative to the repo root. A claim about behaviour that the build or
`verify.sh` asserts is marked as such, because those are the claims that cannot quietly
rot.
