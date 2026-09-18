# Login screen

greetd running `noctalia-greeter`, which brings **its own wlroots 0.20 compositor**.

## Why not a console greeter

A text console cannot scale per monitor: its font is a fixed pixel bitmap, so the same
8×16 cell is physically twice the size on the 81 PPI screen as on the 160 PPI one. A
graphical greeter with its own compositor derives each output's scale from that output's
geometry and renders through fractional scaling.

The cost is real and worth stating: a GPU stack is now in the login path. A driver or
greeter regression takes the login screen down along with the session, and the way back is
`Ctrl+Alt+F2` rather than simply logging in. `tuigreet` stays installed, unbound, as the
rung below — it needs no compositor and no GPU. See [[Recovery]].

## Why greetd

`sddm-wayland-sway` runs its greeter as a real Sway instance and gives you no way to pass
flags to it, so it walks straight into sway's own NVIDIA guard. greetd lets the greeter's
command line be written by hand, which is the whole reason it is here.

## The wrapper

`/etc/greetd/config.toml` points `command =` at
`/usr/libexec/noctalia-greeter-nvidia` rather than at the greeter.

The greeter's compositor is a separate wlroots instance started by greetd, so it inherits
**none** of `/etc/sway/environment`. It cannot be a `greetd.service` drop-in either:
greetd builds the session's environment itself, and env assignments inside greetd's own
TOML are not valid. A wrapper on the `command =` line is what is left.

The wrapper sets `WLR_RENDERER` with `:=`, not `=`, so an inherited value wins — which is
what lets `just greeter-preview` run that exact file nested inside a live session.
`gles2` here is for a different reason than in the [[Compositor|session]]: it is the only
renderer proven on nvidia-open, and the upstream fallback for NVIDIA swapchain errors
has "nothing is displayed" as its symptom.

`--unsupported-gpu` and `-D noscanout` are deliberately *not* set: those are sway's own
guards, and this compositor does not have them.

## greeter.toml takes a detour

The greeter reads `/var/lib/noctalia-greeter/greeter.toml`, and has no `/etc` path in its
search order. But `/var` content in a bootc image is only applied on **initial
provisioning** — switching an already-installed system is an upgrade, so a new
`greeter.toml` would silently not appear.

So the image ships it at `/usr/share/factory/...` and
`/usr/lib/tmpfiles.d/bazzite-sway.conf` copies it into place on every boot:

```
r  /var/lib/noctalia-greeter/greeter.toml
C  /var/lib/noctalia-greeter/greeter.toml   0640 greetd greetd - -
```

`r` then `C`, and specifically **not** `C+`. Over an existing *file*, `C` and `C+` behave
identically and both skip silently; the `+` only lifts the refusal to descend into a
non-empty destination *directory*. `systemd-tmpfiles-setup` runs the remove pass before
the create pass in one invocation, so the pair together is an unconditional refresh from
the image every boot. All three facts are asserted by the build and by CI.

**The greeter rewrites that file when it starts**, into its own canonical form with
comments stripped and keys sorted. A shorter file in `/var` is not a failed copy — check
the values, which is what `verify.sh` does.

## SELinux

Without a `file_contexts` alias the state directory lands as `var_lib_t`, which `xdm_t`
cannot write, and the login screen comes up blank. `build_files/17-noctalia-greeter.sh`
appends one line borrowing greetd's existing rule, so no policy module is needed. It is
edited by hand because the proper command writes into `/var`, which a bootc image does not
keep.

This is the failure in this component most likely to be silent, so it is asserted twice:
at build time via `matchpathcon`, and after boot via `ls -Zd`.

## The avatar

The greeter cannot read your home directory, so the image ships an SVG at
`/usr/share/bazzite-sway/greeter-avatar.svg` and `just greeter-avatar` binds it to your
account through AccountsService. That second half is per-user state under `/var` and
cannot be in the image. Without it you get the stock line-art person, which looks
deliberate rather than broken — so `verify.sh` reports whether it has been run.

## What cannot be checked before boot

The greeter has no validate mode, and a misspelled key is ignored in silence. The build
checks what it can — the palette is 16 valid hex roles, all within the greyscale set,
`scheme_selector_position` is hidden, there is no `[output]` block — but it cannot ask the
greeter whether those are its keys.

`just greeter-preview` runs the real greeter nested in the current session against a fake
greetd. Log in as `user` / `password`; the sum it asks is 9. It uses software rendering,
so judge layout there and not exact colours, and it exercises no DRM at all — whether the
login screen works on this GPU is still a reboot away.

Related: [[Theming]], [[Recovery]], [[Build and release]].
