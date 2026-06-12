# Scene Switcher

Save the apps you have open into a numbered slot, then bring that exact set
back any time with a hotkey. Loading a slot opens the apps it remembers and
**closes** the apps from your *other* saved slots that aren't part of it.

Apps you've never saved into any slot are never touched — it only ever closes
apps it knows about.

Everything lives on the **CapsLock layer** — hold `CapsLock`, then press a key.
This is built for a 60% keyboard and is safe while gaming: nothing fires unless
CapsLock is held, and CapsLock no longer toggles caps (it's a pure modifier).

## Scene hotkeys (slots 1–9)

| Do this | Hotkey |
|---|---|
| **Load** slot *n* (open its apps, close the others) | `CapsLock` + *n* |
| **Save** the apps open right now into slot *n* | `CapsLock` + `Shift` + *n* |
| **Delete** slot *n* (asks to confirm) | `CapsLock` + `Alt` + *n* |

Example: open Steam, Discord and Spotify, press `CapsLock+Shift+2` to save them
as slot 2. Later, press `CapsLock+2` and it'll reopen those three and close the
apps that belong to your other slots. You can also delete a slot from the tray
icon → **Delete a slot**.

## Move the active window

Hold `CapsLock` and use the **right-hand letters as a mini numpad**:

```
 U  I  O      top-left   |  top half   | top-right
 J  K  L      left half  | MAXIMIZE    | right half
 M  ,  .      bot-left   | bottom half | bot-right
   Space      centered
```

| Do this | Hotkey |
|---|---|
| Snap window to a zone | `CapsLock` + `U I O / J L / M , .` |
| Maximize / fullscreen | `CapsLock` + `K` |
| Center the window | `CapsLock` + `Space` |
| Send window to the next monitor | `CapsLock` + `Enter` |

> Want a different layer key than CapsLock (e.g. right Alt)? It's one line near
> the top of `layout.ahk` — just ask.

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
