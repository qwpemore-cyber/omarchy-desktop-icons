# Omarchy Desktop Icons

A small Omarchy shell plugin that draws the contents of `~/Desktop` as icons on
the desktop, above the wallpaper and under normal windows.

The icons appear **only in the floating workspace layout** — the same mode in
which Omarchy shows the dock. Tiled (`dwindle`) and `scrolling` workspaces stay
completely clean. Cycle modes with:

```bash
omarchy hyprland workspace layout toggle
```

## Features

- Top level of the Desktop folder as a grid of icons (folders first).
- Image files show thumbnails; everything else gets a themed file-type icon.
- Single click selects, double click opens, right click opens a small menu.
- File menu: open, open in terminal (folders), copy path, move to trash, refresh.
- Empty-desktop menu: open Desktop folder, open it in a terminal, change
  wallpaper, refresh.
- Live refresh through `inotifywait` plus a slow safety poll.
- Arabic and English UI strings under `i18n/`.

## Layout

| File | Purpose |
|------|---------|
| `manifest.json` | Omarchy plugin manifest (`service` kind). |
| `DesktopIcons.qml` | The desktop surface, grid, menus, and layout detection. |
| `list-desktop.py` | Bounded JSON listing of the Desktop folder. |
| `i18n/*.json` | UI strings. |
| `reload.sh` | Ask the running shell to rescan plugins after an edit. |
| `install.sh` | Symlink this folder into `~/.config/omarchy/plugins/`. |

## Development

The canonical project lives here. It is linked into the shell's plugin folder:

```text
~/.config/omarchy/plugins/bog.desktop-icons -> ~/Work/omarchy-desktop-icons
```

The shell's own file watcher does not follow that symlink, so after editing run:

```bash
./reload.sh
```

`reload.sh` restarts the shell, which is the reliable way to drop Quickshell's
cached QML for this plugin. A lighter `omarchy-shell shell rescanPlugins` may
keep serving the previous code through the symlink.

Then move to a floating workspace to see the icons:

```bash
omarchy hyprland workspace layout toggle
```

Install on another machine with:

```bash
./install.sh
omarchy plugin enable bog.desktop-icons
```

## Notes

- Desktop folder resolution uses XDG, but ignores a Desktop entry that points at
  `$HOME` and falls back to `~/Desktop`, creating it when missing.
- The listing is capped at 500 entries, hidden files are skipped, and every
  displayed string is rendered with `Text.PlainText`.
