# Focus Banner

A scrolling "do not disturb" marquee pinned to the top of your Mac's screen,
just below the menu bar. It floats above all windows, appears on every Space
and every connected display, and is click-through — it never steals your mouse
or keyboard.

## Install (for users)

1. Download `FocusBanner-x.y.z.zip` from the
   [Releases page](../../releases), unzip it, and drag `FocusBanner.app`
   into `/Applications` (or anywhere you like).
2. First launch: the app is not notarized, so macOS will block a plain
   double-click. **Right-click the app → Open → Open** (needed only once).
   Alternatively: `xattr -d com.apple.quarantine FocusBanner.app`
3. The banner appears at the top of the screen, and a text-input icon shows
   up in the menu bar — use it to customize everything.

Requires macOS 13 or later.

## Build from source

```sh
./build.sh        # produces FocusBanner.app
open FocusBanner.app
```

The only requirement is the Xcode Command Line Tools (`xcode-select --install`).
`make-icon.swift` regenerates `AppIcon.icns` if you want a different icon.

## Run from the terminal (optional)

The raw binary inside the bundle accepts a message and flags:

```sh
FocusBanner.app/Contents/MacOS/focusbanner "🎧 Deep work — please don't interrupt" &
```

## Modes

The banner has two modes, switchable from the menu bar icon (or ⌘1 / ⌘2
while the menu is open):

- **Focus — Do Not Disturb** — the classic "headphones on" banner
- **Available — Interruptions Welcome** — a friendly green banner telling
  people it's fine to come talk to you

Each mode has its own message and its own text/background colors, so the
banner reads differently at a glance from across the room.

## Menu bar item

While the banner is running, a text-input icon (a small box with a text
cursor) appears in the menu bar. Click it for:

- The two **mode** entries (checkmark shows the active one)
- **Settings…** — opens the settings window (see below)
- **Pause Scrolling** / **Resume Scrolling** — freeze the marquee in place
- **Quit Focus Banner** — remove the banner and the menu bar icon

## Settings window

Everything is customized in one place (menu bar icon → **Settings…**).
All changes apply live and are saved immediately:

- **Current mode** — same switch as the menu
- **Focus / Available message** — the banner updates as you type
- **Focus / Available colors** — text and background color wells (alpha
  supported, so the background can be more or less translucent)
- **Font** — opens the macOS font panel (any family, style, size); the bar
  grows automatically if the font gets too tall for it
- **Font size** — slider from 10 pt to 48 pt
- **Bar height** — slider from 20 px to 80 px
- **Scroll speed** — slider from 30 px/s to 300 px/s
- **Screen** — all displays (default) or a single one by name; the banner
  also repositions automatically when displays are plugged in or removed
- **Glow** — neon halo around the text, tinted to match the text color
- **CRT effect** — horizontal scanlines over the banner (no flicker)
- **Keep other windows below the banner** — pushes any window overlapping
  the banner down below it (checked every half second). Requires the
  Accessibility permission: the first time you enable it, macOS shows a
  dialog pointing to System Settings → Privacy & Security → Accessibility.
  Full-screen apps are left alone. Note: because the binary is re-signed on
  every rebuild, you may need to re-grant (or toggle off/on) the permission
  after recompiling.

## Settings persistence

Every change made in the settings window (and the mode switch) is saved
immediately to `~/.config/focusbanner.json` and restored automatically on
the next launch. Configs from older single-mode versions are migrated into
the Focus mode automatically.

Precedence at startup: built-in defaults < saved settings < command-line
flags. Flags affect the Focus mode (the positional message argument sets the
Focus message). Delete the JSON file to reset to factory defaults.

The screen choice is saved by display name (e.g. "DELL U2723QE"); if that
display isn't connected at launch, the banner shows on all displays until
it reappears.

## Stop

Use **Quit Focus Banner** in the menu bar item, or:

```sh
pkill focusbanner
```

(or Ctrl+C in the terminal that launched it)

## Options

| Flag          | Default  | Meaning                    |
|---------------|----------|----------------------------|
| `--speed`     | `100`    | Scroll speed in px/second  |
| `--height`    | `30`     | Bar height in px           |
| `--font-size` | `16`     | Text size in points        |
| `--bg`        | `1E1E2E` | Background color (hex)     |
| `--fg`        | `FFD866` | Text color (hex)           |

Example — a taller red-on-white banner that scrolls slowly:

```sh
./focusbanner "In a call until 3pm" --height 40 --font-size 20 --bg FFFFFF --fg CC0000 --speed 60
```

## Rebuild after editing banner.swift

```sh
./build.sh
```

## Releasing a new version

1. Bump `VERSION` in `build.sh`, run `./build.sh`.
2. Zip the app: `ditto -c -k --keepParent FocusBanner.app FocusBanner-x.y.z.zip`
3. Attach the zip to a GitHub release.

The app is ad-hoc signed (no Apple Developer account), so downloaders will
see the Gatekeeper warning described in the install section.
