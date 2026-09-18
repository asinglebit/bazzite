# Theming

Flat greyscale. Seven greys, no hue anywhere the config can reach.

| Grey | Role |
| --- | --- |
| `#1a1a1a` | Content views, floating panels, popovers |
| `#242424` | Window bodies and chrome, the desktop grey |
| `#2e2e2e` | Hairline, selection fill |
| `#5a5a5a` | Disabled text |
| `#9a9a9a` | Secondary text |
| `#d8d8d8` | Primary text, and the accent |
| `#ffffff` | Alert |

Greyscale has no red and no green, so state is signalled with **brightness** instead. The
accent has to be the bright end, or a state change looks like nothing happened. A failed
login is white. The cost, stated plainly: a failed copy in a file manager loses its red,
and an error is one step of brightness from a warning.

## The palette exists twice

Once as TOML for the [[Login screen]]
(`system_files/.../greeter.toml`, sixteen roles) and once as JSON for the [[Shell]]
(`dotfiles/noctalia/palettes/bazzite-grey.json`).

Nothing at runtime notices if they drift — the login screen just stops matching the
desktop, which reads as a rendering quirk rather than a bug. So both `just
check-shell-config` and `verify.sh` compare the two and fail on disagreement.

They cannot be merged: one is in the image and one is a dotfile, and the login screen must
not depend on `just link-dotfiles` having been run.

## GTK, and the trap underneath it

GTK is themed by `adw-gtk3-dark` plus two stylesheets, `dotfiles/gtk-3.0/gtk.css` and
`dotfiles/gtk-4.0/gtk.css`, which redefine the palette by name. GTK loads user CSS above
the theme's own level, so the redefinition wins and a theme update cannot undo it — which
a forked theme under `~/.themes` would not survive.

**But installing a theme is not choosing one.** On Wayland, GTK ignores `settings.ini` for
theme, icon theme, cursor theme and UI font, and asks the XDG portal, which answers out of
`org.gnome.desktop.interface` in dconf. Before this was handled, `settings.ini` asked for
adw-gtk3-dark / Papirus-Dark / Adwaita / Inter and GTK reported Adwaita / breeze-dark /
breeze_cursors / Noto Sans — Plasma's values, left in dconf where removing Plasma could
not follow them.

The fix is `system_files/usr/share/glib-2.0/schemas/90-bazzite-sway.gschema.override`, in
the image so the desktop is correct before any dotfiles repo is cloned. It sets the
**default**, so a key a user has explicitly written still wins until `dconf reset`.
`verify.sh` distinguishes the three outcomes: wrong is a failure, right-but-from-dconf is
a warning, right-from-the-image passes.

`color-scheme` is the single signal libadwaita, Qt (via
`QT_QPA_PLATFORMTHEME=xdgdesktopportal`), Firefox, Chromium and Electron all follow.

The two stylesheets restate the palette rather than sharing one file by `@import`: GTK
resolves a relative import against the file it is reading, and these paths are symlinks
into the repo, so the import would make the desktop depend on the repo being checked out.

## Icons and fonts

**Papirus-Dark**, with the folders recoloured black by `papirus-folders` at build time —
it has to run during the build because `/usr/share/icons` is read-only afterwards. It
recolours `Papirus`, not `Papirus-Dark`: only the light package ships the colour variants
and the dark one inherits them. About 400 symlinks are made; the build checks one folder
icon and one user icon, because only the full variant set gives Home and Desktop black
icons.

**Inter** for UI, **Hack Nerd Font Mono** for the terminal and the bar. The Hack font is
one of only two artifacts in the whole build not from a signed repo — it is downloaded
from a GitHub release, pinned by version and SHA256. `papirus-folders` is the other. Both
would fail *soft* if they vanished, falling back to something that looks almost right, so
both are hard-asserted in the build and in CI.

## What the palette cannot reach

- **The greeter's caret and submit button.** noctalia-greeter treats the palette as seed
  colours and tone-adjusts them a few units, and the caret uses a hardcoded accent that
  tracks no role at all. Everything stays neutral; it is just not the same grey.
- **Firefox, Chromium and Electron.** They follow the portal's colour-scheme and their own
  internal palettes past that.

Related: [[Compositor]], [[Shell]], [[Login screen]].
