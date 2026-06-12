#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

; =========================================================
;  Scene Switcher
;
;  Save the apps you currently have open into a numbered slot,
;  then recall that slot later with a hotkey. Loading a slot
;  opens the apps it had open and closes the apps from your
;  OTHER saved slots that aren't part of it. Apps you've never
;  saved into any slot are never touched.
;
;  HOTKEYS  (slots 1-9):
;    Ctrl + Alt + Shift + <n>   =  SAVE  the apps open right now into slot n
;    Ctrl + Alt + <n>           =  LOAD  slot n (open its apps, close the others)
; =========================================================

SlotsDir := A_ScriptDir "\scenes"
ForceCloseMs := 4000          ; if an app won't close politely within this many ms, force it (0 = never force)

if !DirExist(SlotsDir)
    DirCreate(SlotsDir)

; ---- bind slots 1-9 ----
Loop 9 {
    n := A_Index
    Hotkey("^!+" n, SaveSlot.Bind(n))   ; Ctrl+Alt+Shift+n  -> save
    Hotkey("^!" n,  LoadSlot.Bind(n))   ; Ctrl+Alt+n        -> load
}

; ---- tray ----
A_TrayMenu.Delete()
A_TrayMenu.Add("Open scenes folder", (*) => Run(SlotsDir))
A_TrayMenu.Add("Exit", (*) => ExitApp())
A_IconTip := "Scene Switcher`nCtrl+Alt+Shift+# = save`nCtrl+Alt+# = load"

return

; =========================================================
;  SAVE / LOAD
; =========================================================

SaveSlot(n, *) {
    global SlotsDir
    lines := []
    for hwnd in WinGetList() {
        if !IsAppWindow(hwnd)
            continue
        try {
            proc := WinGetProcessName("ahk_id " hwnd)
            path := WinGetProcessPath("ahk_id " hwnd)
            WinGetPos(&x, &y, &w, &h, "ahk_id " hwnd)
            lines.Push(proc "`t" path "`t" x "`t" y "`t" w "`t" h)
        }
    }
    if !lines.Length {
        Flash("Slot " n ": nothing open to save")
        return
    }
    file := SlotsDir "\" n ".txt"
    if FileExist(file)
        FileDelete(file)
    FileAppend("; Scene slot " n "  (per line: proc, path, x, y, w, h)`n", file)
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

    want    := ProcsInFile(file)      ; processes this slot should have open
    managed := AllManagedProcs()      ; processes across every saved slot
    launch  := LaunchMapFromFile(file)

    ; close managed apps that aren't part of this slot
    for proc in managed
        if !want.Has(proc)
            CloseProc(proc, ForceCloseMs)

    ; open this slot's apps that aren't already running
    for proc, path in launch
        if !ProcessExist(proc)
            try Run(path)

    Flash("Loaded slot " n)
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

ProcsInFile(file) {
    set := Map()
    for line in DataLines(file)
        set[StrLower(StrSplit(line, "`t")[1])] := true
    return set
}

LaunchMapFromFile(file) {
    m := Map()                          ; proc(lower) -> exe path (first one seen)
    for line in DataLines(file) {
        f := StrSplit(line, "`t")
        proc := StrLower(f[1])
        if (!m.Has(proc) && f.Length >= 2 && f[2] != "")
            m[proc] := f[2]
    }
    return m
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

CloseProc(proc, forceMs) {
    if !ProcessExist(proc)
        return
    ; ask each window of this process to close politely
    for hwnd in WinGetList() {
        try {
            if (StrLower(WinGetProcessName("ahk_id " hwnd)) = proc)
                WinClose("ahk_id " hwnd)
        }
    }
    ; if it's still alive after the grace period, force it
    if (forceMs > 0 && ProcessWaitClose(proc, forceMs / 1000))
        try ProcessClose(proc)
}

Flash(text) {
    ToolTip(text)
    SetTimer(() => ToolTip(), -1200)
}
