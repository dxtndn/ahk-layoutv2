#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

; Work in real (physical) pixels on every monitor, so window placement is
; pixel-accurate even on displays with different DPI scaling (e.g. a 150% main
; monitor next to a 100% one). -4 = DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2.
try DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")

; =========================================================
;  Scene Switcher   —   everything lives on the CapsLock "layer"
;  (hold CapsLock, then press the key). Designed for a 60% board
;  and safe while gaming: nothing fires unless CapsLock is held.
; =========================================================
;  SCENES (save/recall sets of apps) — slots 1-9:
;    CapsLock + <n>            =  LOAD slot n (open its apps, close the others)
;    CapsLock + Shift + <n>    =  SAVE the apps open right now into slot n
;    CapsLock + Alt + <n>      =  DELETE slot n (asks to confirm)
;
;  MOVE THE ACTIVE WINDOW — CapsLock + right-hand letters (a mini numpad):
;    U I O   ->  top-left quarter / top half / top-right quarter
;    J K L   ->  left half       / MAXIMIZE  / right half
;    M , .   ->  bottom-left     / bottom half / bottom-right
;    Space   ->  centered
;    Enter   ->  send the window to the next monitor
;
;  OTHER:
;    CapsLock + ;   =  reload this script (after editing it)
; =========================================================

SlotsDir := A_ScriptDir "\scenes"
ForceCloseMs := 4000          ; if an app won't close politely within this many ms, force it (0 = never force)

; Apps whose visible window belongs to a DIFFERENT process than the one you
; actually start/stop (so launching the window's own .exe won't open it, and
; closing the window only hides it to the system tray). Keyed by the process
; name the window reports.
;   Steam: the window is steamwebhelper.exe, but Steam is started/stopped via
;   steam.exe. The steam:// links below open it, and fully QUIT it (instead of
;   dropping it to the tray) without needing to know where Steam is installed.
SpecialApps := Map(
    "steamwebhelper.exe", { launch: "steam://open/main", quit: "steam://exit" }
)

if !DirExist(SlotsDir)
    DirCreate(SlotsDir)

SetCapsLockState "AlwaysOff"  ; CapsLock becomes a pure modifier — it never toggles caps

; ---- scene slots 1-9 (CapsLock + number; Shift = save, Alt = delete) ----
Loop 9
    Hotkey("CapsLock & " A_Index, SceneKey.Bind(A_Index))

; ---- window zones (CapsLock + letter, laid out like a numpad) ----
;     key            x     y     w     h   (fractions of the monitor)
Zone("u",  0,    0,    0.5,  0.5)   ; top-left quarter
Zone("i",  0,    0,    1,    0.5)   ; top half
Zone("o",  0.5,  0,    0.5,  0.5)   ; top-right quarter
Zone("j",  0,    0,    0.5,  1)     ; left half
Zone("l",  0.5,  0,    0.5,  1)     ; right half
Zone("m",  0,    0.5,  0.5,  0.5)   ; bottom-left quarter
Zone(",",  0,    0.5,  1,    0.5)   ; bottom half
Zone(".",  0.5,  0.5,  0.5,  0.5)   ; bottom-right quarter

; ---- maximize (K), center (Space), next monitor (Enter) ----
Hotkey("CapsLock & k",     (*) => Maximize())
Hotkey("CapsLock & Space", (*) => CenterWindow())
Hotkey("CapsLock & Enter", (*) => SendToNextMonitor())

; ---- reload the script ( ;/: key ) ----
Hotkey("CapsLock & SC027", (*) => Reload())

; ---- tray ----
delMenu := Menu()
Loop 9
    delMenu.Add("Slot " A_Index, DeleteSlot.Bind(A_Index))
A_TrayMenu.Delete()
A_TrayMenu.Add("Open scenes folder", (*) => Run(SlotsDir))
A_TrayMenu.Add("Delete a slot", delMenu)
A_TrayMenu.Add("Reload script", (*) => Reload())
A_TrayMenu.Add("Exit", (*) => ExitApp())
A_IconTip := "Scene Switcher`nHold CapsLock + # = scenes`nHold CapsLock + U/I/O J/K/L M/,/. = move window"

return

; =========================================================
;  SCENES: save / load / delete
; =========================================================

SaveSlot(n, *) {
    global SlotsDir
    lines := []
    for hwnd in WinGetList() {
        if !IsAppWindow(hwnd)
            continue
        try {
            id    := "ahk_id " hwnd
            proc  := WinGetProcessName(id)
            path  := WinGetProcessPath(id)
            mm    := WinGetMinMax(id)
            state := (mm = 1) ? "max" : (mm = -1) ? "min" : "normal"
            title := StrReplace(StrReplace(WinGetTitle(id), "`t", " "), "`n", " ")
            WinGetPos(&x, &y, &w, &h, id)
            lines.Push(proc "`t" path "`t" x "`t" y "`t" w "`t" h "`t" state "`t" title)
        }
    }
    if !lines.Length {
        Flash("Slot " n ": nothing open to save")
        return
    }
    file := SlotsDir "\" n ".txt"
    if FileExist(file)
        FileDelete(file)
    FileAppend("; Scene slot " n "  (per line: proc, path, x, y, w, h, state, title)`n", file)
    for line in lines
        FileAppend(line "`n", file)
    Flash("Saved slot " n "  (" CountProcs(lines) " apps)")
}

LoadSlot(n, *) {
    global SlotsDir, ForceCloseMs
    file := SlotsDir "\" n ".txt"
    if !FileExist(file) {
        Flash("Slot " n " is empty - nothing saved yet")
        return
    }

    records := ReadRecords(file)      ; one entry per saved window
    want    := Map()                  ; processes this slot should have open
    for r in records
        want[r.proc] := true
    managed := AllManagedProcs()      ; processes across every saved slot

    ; close managed apps that aren't part of this slot — all at once, so we wait
    ; out the close grace period ONCE for the whole batch, not per app
    toClose := []
    for proc in managed
        if !want.Has(proc)
            toClose.Push(proc)
    CloseProcs(toClose, ForceCloseMs)

    ; open this slot's apps that aren't already running (launch each app once)
    launched := Map()
    for r in records {
        if launched.Has(r.proc)
            continue
        launched[r.proc] := true
        if ProcessExist(r.proc)
            continue
        LaunchApp(r)
    }

    Flash("Loading slot " n " ...")
    RestorePositions(records)         ; move each window back to where it was
    Flash("Loaded slot " n)
}

; Move every saved window back to its position. Waits (up to a few seconds)
; for freshly-launched apps to open their windows, then places them.
RestorePositions(records) {
    deadline     := A_TickCount + 6000
    match        := Map()    ; record index -> hwnd it was matched to (kept stable)
    used         := Map()    ; hwnd -> true (already claimed by some record)
    lastProgress := A_TickCount
    loop {
        before := match.Count
        idx := 0
        for r in records {
            idx++
            if !match.Has(idx) {
                hwnd := FindWindowFor(r, used)
                if hwnd {
                    match[idx] := hwnd
                    used[hwnd] := true
                }
            }
            if match.Has(idx)
                ApplyPlacement(match[idx], r)   ; re-apply so late self-moves get corrected
        }
        if (match.Count = records.Length)       ; everything placed -> done immediately
            break
        if (match.Count > before)               ; a new window just showed up
            lastProgress := A_TickCount
        ; stop early once no new window has appeared for a bit (an app that won't
        ; launch shouldn't make every load sit here for the full 6 seconds)
        if (A_TickCount - lastProgress > 1500 || A_TickCount > deadline)
            break
        Sleep 200
    }
}

; Find an unclaimed live window for this record: same process, preferring an
; exact title match, otherwise the first available window of that process.
FindWindowFor(r, used) {
    fallback := 0
    for hwnd in WinGetList() {
        if (used.Has(hwnd) || !IsAppWindow(hwnd))
            continue
        try {
            if (StrLower(WinGetProcessName("ahk_id " hwnd)) != r.proc)
                continue
            if (r.title != "" && WinGetTitle("ahk_id " hwnd) = r.title)
                return hwnd
        } catch
            continue
        if !fallback
            fallback := hwnd
    }
    return fallback
}

ApplyPlacement(hwnd, r) {
    id := "ahk_id " hwnd
    try {
        if (r.state = "max") {
            WinMaximize(id)
        } else if (r.state = "min") {
            WinMinimize(id)
        } else {
            if WinGetMinMax(id)
                WinRestore(id)
            WinMove(r.x, r.y, r.w, r.h, id)
        }
    }
}

DeleteSlot(n, *) {
    global SlotsDir
    file := SlotsDir "\" n ".txt"
    if !FileExist(file) {
        Flash("Slot " n " is already empty")
        return
    }
    if (MsgBox("Delete saved slot " n "?", "Scene Switcher", "YesNo Icon!") = "Yes") {
        FileDelete(file)
        Flash("Deleted slot " n)
    }
}

; =========================================================
;  WINDOW MOVING
; =========================================================

; bind one CapsLock-layer zone hotkey
Zone(key, fx, fy, fw, fh) {
    Hotkey("CapsLock & " key, SnapZone.Bind(fx, fy, fw, fh))
}

; CapsLock + number: plain = load, +Shift = save, +Alt = delete
SceneKey(n, *) {
    if GetKeyState("Shift", "P")
        SaveSlot(n)
    else if GetKeyState("Alt", "P")
        DeleteSlot(n)
    else
        LoadSlot(n)
}

SnapZone(fx, fy, fw, fh, *) {
    hwnd := WinExist("A")
    if !hwnd
        return
    id := "ahk_id " hwnd
    if WinGetMinMax(id)               ; if maximized/minimized, restore before moving
        WinRestore(id)
    mon := GetWindowMonitor(hwnd)
    MonitorGetWorkArea(mon, &l, &t, &r, &b)
    w := r - l, h := b - t
    ; target rectangle for the window's VISIBLE edges, then move + verify + retry
    PlaceWithRetry(id, hwnd, Round(l + fx * w), Round(t + fy * h), Round(fw * w), Round(fh * h), l, t, r, b)
    EnsureUsable(id, hwnd, l, t, r, b)   ; bail oversized windows out to the main monitor
}

; Move the window, check it actually landed in the right spot/size, and retry up
; to 3 times with exponential backoff (50ms, 100ms) for apps that apply the move
; lazily or shove themselves around afterward. Returns true once verified.
PlaceWithRetry(id, hwnd, tx, ty, tw, th, wl, wt, wr, wb) {
    delay := 50
    Loop 3 {
        MoveVisible(id, hwnd, tx, ty, tw, th)
        ClampOnScreen(id, hwnd, wl, wt, wr, wb)   ; pull back apps that refused to shrink
        if VerifyPlacement(hwnd, tx, ty, tw, th, wl, wt, wr, wb)
            return true
        if (A_Index < 3) {
            Sleep delay
            delay *= 2
        }
    }
    return false
}

; Is the window where we wanted it? Allowed slack of a couple pixels. A window
; that's LARGER than the target (an app enforcing its minimum size) counts as
; correct as long as it's fully on screen and pushed as far toward the target
; as its size allows.
VerifyPlacement(hwnd, tx, ty, tw, th, wl, wt, wr, wb, tol := 2) {
    v := GetVisibleRect(hwnd)
    ; must be fully on screen
    if (v.x < wl - tol || v.y < wt - tol || v.x + v.w > wr + tol || v.y + v.h > wb + tol)
        return false
    ; never smaller than asked (larger is fine — minimum-size apps)
    if (v.w < tw - tol || v.h < th - tol)
        return false
    ; expected position given the window's actual size (same clamp math)
    ex := tx, ey := ty
    if (ex + v.w > wr)
        ex := wr - v.w
    if (ey + v.h > wb)
        ey := wb - v.h
    if (ex < wl)
        ex := wl
    if (ey < wt)
        ey := wt
    return (Abs(v.x - ex) <= tol && Abs(v.y - ey) <= tol)
}

; Move a window so its *visible* edges land exactly on (x, y, w, h), cancelling
; out the invisible DWM border that otherwise leaves gaps between windows and
; against the screen edges.
MoveVisible(id, hwnd, x, y, w, h) {
    bd := GetInvisibleBorder(hwnd)
    WinMove(x - bd.l, y - bd.t, w + bd.l + bd.r, h + bd.t + bd.b, id)
}

; If the window is too big to actually fit on the monitor it was placed on — so
; its controls hang off the edge, or it spills across into the next monitor —
; relocate it to the very top-left of the main monitor where it's usable.
EnsureUsable(id, hwnd, wl, wt, wr, wb) {
    v := GetVisibleRect(hwnd)
    if (v.w <= (wr - wl) + 4 && v.h <= (wb - wt) + 4)
        return                                   ; it fits here, nothing to do
    MonitorGetWorkArea(MonitorGetPrimary(), &pl, &pt, &pr, &pb)
    MoveVisible(id, hwnd, pl, pt, v.w, v.h)
    Flash("Too big for that display - moved to main monitor")
}

; If the window ended up hanging off the work area (because it has a minimum
; size larger than the zone), slide it back so it's fully on screen. If it's
; simply bigger than the monitor, align it to the top-left so its controls stay
; reachable.
ClampOnScreen(id, hwnd, wl, wt, wr, wb) {
    v := GetVisibleRect(hwnd)
    nx := v.x, ny := v.y
    if (nx + v.w > wr)
        nx := wr - v.w
    if (ny + v.h > wb)
        ny := wb - v.h
    if (nx < wl)
        nx := wl
    if (ny < wt)
        ny := wt
    if (nx != v.x || ny != v.y)
        MoveVisible(id, hwnd, nx, ny, v.w, v.h)
}

; The window's actual *visible* rectangle (what DWM reports), as {x, y, w, h}.
GetVisibleRect(hwnd) {
    frame := Buffer(16, 0)
    if (DllCall("dwmapi\DwmGetWindowAttribute", "ptr", hwnd, "uint", 9, "ptr", frame, "uint", 16) != 0) {
        WinGetPos(&x, &y, &w, &h, "ahk_id " hwnd)
        return { x: x, y: y, w: w, h: h }
    }
    fl := NumGet(frame, 0, "int"), ft := NumGet(frame, 4, "int")
    fr := NumGet(frame, 8, "int"), fb := NumGet(frame, 12, "int")
    return { x: fl, y: ft, w: fr - fl, h: fb - ft }
}

; Thickness of the invisible drop-shadow border on each side of a window:
; (full window rect) minus (the visible frame DWM reports). Usually ~7px on
; left/right/bottom, 0 on top. Returns zeros if DWM can't tell us.
GetInvisibleBorder(hwnd) {
    rect := Buffer(16, 0)
    if !DllCall("GetWindowRect", "ptr", hwnd, "ptr", rect)
        return { l: 0, t: 0, r: 0, b: 0 }
    wl := NumGet(rect, 0, "int"), wt := NumGet(rect, 4, "int")
    wr := NumGet(rect, 8, "int"), wb := NumGet(rect, 12, "int")
    frame := Buffer(16, 0)
    if (DllCall("dwmapi\DwmGetWindowAttribute", "ptr", hwnd, "uint", 9, "ptr", frame, "uint", 16) != 0)
        return { l: 0, t: 0, r: 0, b: 0 }
    fl := NumGet(frame, 0, "int"), ft := NumGet(frame, 4, "int")
    fr := NumGet(frame, 8, "int"), fb := NumGet(frame, 12, "int")
    return { l: fl - wl, t: ft - wt, r: wr - fr, b: wb - fb }
}

Maximize(*) {
    hwnd := WinExist("A")
    if hwnd
        WinMaximize("ahk_id " hwnd)
}

; Center the active window on its monitor. Tries to size it to 60% x 70%, but if
; the app refuses to shrink that far (e.g. Spotify), it re-centers using the
; window's ACTUAL size so its true center lands on the monitor's center.
CenterWindow(*) {
    hwnd := WinExist("A")
    if !hwnd
        return
    id := "ahk_id " hwnd
    if WinGetMinMax(id)
        WinRestore(id)
    mon := GetWindowMonitor(hwnd)
    MonitorGetWorkArea(mon, &l, &t, &r, &b)
    w := r - l, h := b - t
    tw := Round(w * 0.6), th := Round(h * 0.7)   ; desired size for apps that can resize

    delay := 50
    Loop 3 {
        ; resize toward the target (centered), then re-center using the real size
        g := CenteredPos(l, t, w, h, tw, th)
        MoveVisible(id, hwnd, g.x, g.y, tw, th)
        v := GetVisibleRect(hwnd)
        p := CenteredPos(l, t, w, h, v.w, v.h)
        MoveVisible(id, hwnd, p.x, p.y, v.w, v.h)

        ; verify it's truly centered (or as centered as an oversized window can be)
        v2 := GetVisibleRect(hwnd)
        want := CenteredPos(l, t, w, h, v2.w, v2.h)
        if (Abs(v2.x - want.x) <= 2 && Abs(v2.y - want.y) <= 2)
            break
        if (A_Index < 3) {
            Sleep delay
            delay *= 2
        }
    }
    EnsureUsable(id, hwnd, l, t, r, b)   ; bail oversized windows out to the main monitor
}

; Top-left position that centers a (winW x winH) window in the work area. If the
; window is bigger than the work area in a dimension, it pins to the top/left so
; its controls stay reachable.
CenteredPos(wl, wt, ww, wh, winW, winH) {
    nx := wl + Round((ww - winW) / 2)
    ny := wt + Round((wh - winH) / 2)
    if (nx < wl)
        nx := wl
    if (ny < wt)
        ny := wt
    return { x: nx, y: ny }
}

SendToNextMonitor(*) {
    hwnd := WinExist("A")
    if !hwnd
        return
    count := MonitorGetCount()
    if (count < 2)
        return
    id := "ahk_id " hwnd
    wasMax := WinGetMinMax(id) = 1
    if wasMax
        WinRestore(id)

    cur := GetWindowMonitor(hwnd)
    next := Mod(cur, count) + 1        ; cycle to the next monitor

    ; current position as fractions of the current monitor's work area
    MonitorGetWorkArea(cur, &cl, &ct, &cr, &cb)
    WinGetPos(&x, &y, &w, &h, id)
    fx := (x - cl) / (cr - cl), fy := (y - ct) / (cb - ct)
    fw := w / (cr - cl),        fh := h / (cb - ct)

    ; apply the same fractions on the next monitor
    MonitorGetWorkArea(next, &nl, &nt, &nr, &nb)
    nw := nr - nl, nh := nb - nt
    WinMove(Round(nl + fx * nw), Round(nt + fy * nh), Round(fw * nw), Round(fh * nh), id)
    if wasMax {
        WinMaximize(id)
    } else {
        ClampOnScreen(id, hwnd, nl, nt, nr, nb)   ; keep oversized apps fully on screen
        EnsureUsable(id, hwnd, nl, nt, nr, nb)    ; or bail out to main monitor if it can't fit
    }
}

GetWindowMonitor(hwnd) {
    WinGetPos(&x, &y, &w, &h, "ahk_id " hwnd)
    cx := x + w / 2, cy := y + h / 2
    Loop MonitorGetCount() {
        MonitorGet(A_Index, &l, &t, &r, &b)
        if (cx >= l && cx < r && cy >= t && cy < b)
            return A_Index
    }
    return MonitorGetPrimary()
}

; =========================================================
;  HELPERS
; =========================================================

; True only for real, switchable application windows.
IsAppWindow(hwnd) {
    id := "ahk_id " hwnd
    if (WinGetTitle(id) = "")
        return false
    if !(WinGetStyle(id) & 0x10000000)          ; WS_VISIBLE
        return false
    if (WinGetExStyle(id) & 0x80)               ; WS_EX_TOOLWINDOW -> not a real app window
        return false
    if DllCall("GetWindow", "ptr", hwnd, "uint", 4, "ptr")   ; GW_OWNER -> it's a dialog/popup
        return false
    cls := WinGetClass(id)
    if (cls = "Shell_TrayWnd" || cls = "Progman" || cls = "WorkerW" || cls = "Windows.UI.Core.CoreWindow")
        return false
    return true
}

; Parse a slot file into window records. Format per line (tab-separated):
;   proc  path  x  y  w  h  [state]  [title]
; (state/title are optional so older save files still load.)
ReadRecords(file) {
    out := []
    for line in DataLines(file) {
        f := StrSplit(line, "`t")
        if (f.Length < 6)
            continue
        out.Push({
            proc:  StrLower(Trim(f[1])),
            path:  Trim(f[2]),
            x: Integer(f[3]), y: Integer(f[4]), w: Integer(f[5]), h: Integer(f[6]),
            state: (f.Length >= 7) ? Trim(f[7]) : "normal",
            title: (f.Length >= 8) ? Trim(f[8]) : ""
        })
    }
    return out
}

AllManagedProcs() {
    global SlotsDir
    set := Map()
    Loop Files, SlotsDir "\*.txt" {
        for line in DataLines(A_LoopFilePath)
            set[StrLower(StrSplit(line, "`t")[1])] := true
    }
    return set
}

DataLines(file) {
    out := []
    for line in StrSplit(FileRead(file), "`n", "`r") {
        t := Trim(line)
        if (t != "" && SubStr(t, 1, 1) != ";")
            out.Push(t)
    }
    return out
}

CountProcs(lines) {
    set := Map()
    for line in lines
        set[StrLower(StrSplit(line, "`t")[1])] := true
    return set.Count
}

; Launch one saved app. Special apps (e.g. Steam) use their dedicated start
; command; everything else just runs its saved path.
LaunchApp(r) {
    global SpecialApps
    if SpecialApps.Has(r.proc) {
        try Run(SpecialApps[r.proc].launch)
        return
    }
    if (r.path != "")
        try Run(r.path)
}

; Close a whole batch of processes at once. Every app is asked to quit up front,
; THEN we wait a single shared grace period for the group to exit — so closing
; five apps costs one wait, not five. Anything still alive after that is forced.
; Special apps (e.g. Steam) are quit via their dedicated command and never
; force-killed (so Steam shuts down cleanly instead of just hiding in the tray).
CloseProcs(procs, forceMs) {
    global SpecialApps
    closeSet := Map()
    for proc in procs {
        if SpecialApps.Has(proc)
            try Run(SpecialApps[proc].quit)        ; e.g. steam://exit
        else if ProcessExist(proc)
            closeSet[proc] := true
    }
    ; politely close every window of those apps in one sweep
    for hwnd in WinGetList() {
        try {
            if closeSet.Has(StrLower(WinGetProcessName("ahk_id " hwnd)))
                WinClose("ahk_id " hwnd)
        }
    }
    if (forceMs <= 0)
        return
    ; one shared wait for the whole batch to exit
    deadline := A_TickCount + forceMs
    loop {
        alive := false
        for proc in closeSet {
            if ProcessExist(proc) {
                alive := true
                break
            }
        }
        if (!alive || A_TickCount > deadline)
            break
        Sleep 100
    }
    ; force anything that's still standing
    for proc in closeSet
        if ProcessExist(proc)
            try ProcessClose(proc)
}

Flash(text) {
    ToolTip(text)
    SetTimer(() => ToolTip(), -1200)
}
