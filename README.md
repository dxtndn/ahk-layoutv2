# Scene Switcher

Save the apps you have open into a numbered slot, then bring that exact set
back any time with a hotkey. Loading a slot opens the apps it remembers and
**closes** the apps from your *other* saved slots that aren't part of it.

Apps you've never saved into any slot are never touched — it only ever closes
apps it knows about.

## Hotkeys (slots 1–9)

| Do this | Hotkey |
|---|---|
| **Save** the apps open right now into slot *n* | `Ctrl` + `Alt` + `Shift` + *n* |
| **Load** slot *n* (open its apps, close the others) | `Ctrl` + `Alt` + *n* |

Example: open Steam, Discord and Spotify, press `Ctrl+Alt+Shift+2` to save them
as slot 2. Later, press `Ctrl+Alt+2` and it'll reopen those three and close the
apps that belong to your other slots.

## How to run it

1. Install [AutoHotkey **v2**](https://www.autohotkey.com/).
2. Double-click `layout.ahk`. A green **H** icon appears in your system tray —
   that means it's running.
3. Right-click the tray icon for **Open scenes folder** or **Exit**.

To have it start automatically with Windows, put a shortcut to `layout.ahk` in
your Startup folder (`Win+R` → `shell:startup`).

## Where saves live

Each slot is a file in the `scenes/` folder (`scenes/1.txt`, `scenes/2.txt`, …).
These are personal to your machine and are **not** uploaded to GitHub.

## Tweaks

- **Force-close timeout** — if an app won't close on its own, it's force-closed
  after 4 seconds. Change `ForceCloseMs` near the top of `layout.ahk`
  (set it to `0` to only ever close politely).
- **Different keys** — the hotkeys are defined in the `Loop 9 { … }` block near
  the top of `layout.ahk` (`^` = Ctrl, `!` = Alt, `+` = Shift, `#` = Win).
