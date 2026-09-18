# Recovery

Ordered roughly by how bad it is.

## The bar is gone, everything else works

Almost always switched off rather than broken. `$mod+period` disables every bar through
noctalia's own `enabled` setting and turns them back on;
`~/.config/sway/noctalia-bar-toggle.sh print` says which state they are in.

If that setting got written by the settings window instead, deleting
`~/.local/state/noctalia/settings.toml` hands control back to `dotfiles/` — and re-enables
the bar, because the toggle writes `bar.<name>.enabled` into the same file.

See [[Workspaces|the bar switch]].

## The shell is dead

No bar, no notifications, no lock, and `pkexec` **hangs** rather than failing, so `ujust`
and `bazzite-user-setup` block forever. Nothing prints an error, because the thing that
would print it is what died.

`$mod+Return` still opens a terminal — that binding is in `/etc/sway/config` and does not
go through the shell.

```bash
systemctl --user status noctalia
journalctl --user -u noctalia -b -n 50
```

To get a working desktop back while you look at it, delete the retirement files and log
out: `sudo rm /etc/sway/config.d/90-bar.conf` gives stock waybar back, and
`90-swayidle.conf` restores swayidle and swaylock. bootc 3-way merges `/etc`, so those
deletions persist across updates — put them back when you are done.

See [[Shell]].

## The login screen is black

`Ctrl+Alt+F2`, then point `command =` in `/etc/greetd/config.toml` at the `tuigreet` line
written in that file's own comments, and `systemctl restart greetd`.

Be quick about the VT: greetd is `Restart=always` with `StartLimitBurst=5` and
`Conflicts=getty@tty1.service`, so five failures in thirty seconds leaves VT 1 dead.
logind's other five VTs still work.

The usual causes, in order of likelihood:

1. The state directory `/var/lib/noctalia-greeter` is missing, wrongly owned, or has the
   wrong SELinux label — `verify.sh` checks all three.
2. `greeter.toml` did not get copied by tmpfiles, so the greeter came up stock.
3. The GPU wrapper or the greeter binary is missing, so greetd's command line points at
   nothing.

See [[Login screen]].

## The desktop will not start at all

Hold **Shift** at boot and pick the older entry — `40-branding.sh` labels them
`Bazzite Sway`, so they are distinguishable under pressure.

```bash
just rollback    # previous deployment
just restore     # all the way back to stock upstream Bazzite
```

Remember that a rollback restores the **image only**. `dotfiles/` is a git checkout and
rolls back separately; so do flatpaks. See [[Cadence]].

## Updates stopped arriving

Check `bootc status`. If the ref reads `containers-storage`, the machine is following its
own local podman storage and will never see a CI build — that is the
[[Cadence|ref trap]], and the fix is a one-time `bootc switch`.

## Updates are arriving unverified

Two of the three obvious checks pass even when verification has silently fallen through to
the `insecureAcceptAnything` catch-all. Only the negative control in the repo README
proves it: point the same policy at the wrong key and confirm the pull is refused.

If it copies instead of failing, updates are going through unverified. See
[[Build and release]].

## Something is subtly wrong and you cannot name it

Run `./verify.sh` first. It exists for exactly this: 100-plus assertions about a running
session, most of which describe failures that look like a quirk rather than a bug — a
login screen that does not quite match, a bar that draws both screens' workspaces, a theme
key coming from the wrong place, a threshold that drifted between two files.

Related: [[Operations]], [[Components]].
