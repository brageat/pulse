#Requires AutoHotkey v2.0
#SingleInstance Force

; ============================================================
;  AutoClicker  -  AutoHotkey v2
;  F6 = Start/Stop (global)   F8 = Capture cursor position
;  Dark mode is toggleable via the checkbox.
; ============================================================

CoordMode("Mouse", "Screen")   ; use absolute screen coordinates

App := { clicking: false, count: 0, dark: true }

BuildGui()

; ---- Global hotkeys ---------------------------------------
Hotkey("F6", (*) => ToggleClicking())
Hotkey("F8", CapturePosition)

; ---- GUI builder (re-run to re-theme) ---------------------
BuildGui() {
    global App

    SetTimer(DoClick, 0)              ; pause any active loop during rebuild
    s := SnapshotSettings()           ; keep current values across the rebuild
    if App.HasOwnProp("gui")
        App.gui.Destroy()

    ; palette
    if App.dark {
        bg := "1F1F1F", ctrlBg := "2D2D2D", text := "E0E0E0"
    } else {
        bg := "F0F0F0", ctrlBg := "FFFFFF", text := "101010"
    }
    btnText := "101010"               ; readable on the system button face

    g := Gui("+AlwaysOnTop", "AutoClicker")
    App.gui := g
    g.OnEvent("Close", (*) => ExitApp())
    g.BackColor := bg
    g.SetFont("s9 c" text, "Segoe UI")
    ApplyDarkTitleBar(g.Hwnd, App.dark)

    ; Interval
    g.Add("GroupBox", "x10 y8 w310 h80", "Click Interval")
    g.Add("Text", "x22 y32 w90", "Interval (ms):")
    App.interval := g.Add("Edit", "x115 y29 w80 Number Background" ctrlBg)
    g.Add("Text", "x22 y60 w90", "Random +/- (ms):")
    App.random := g.Add("Edit", "x115 y57 w80 Number Background" ctrlBg)

    ; Click options
    g.Add("GroupBox", "x10 y96 w310 h80", "Click Options")
    g.Add("Text", "x22 y120 w60", "Button:")
    App.button := g.Add("DropDownList", "x115 y117 w90 Background" ctrlBg, ["Left", "Right", "Middle"])
    g.Add("Text", "x22 y148 w60", "Type:")
    App.type := g.Add("DropDownList", "x115 y145 w90 Background" ctrlBg, ["Single", "Double"])

    ; Location
    g.Add("GroupBox", "x10 y184 w310 h100", "Click Location")
    App.posCurrent := g.Add("Radio", "x22 y206", "Current cursor position")
    App.posFixed   := g.Add("Radio", "x22 y230", "Fixed position")
    g.Add("Text", "x40 y256 w20", "X:")
    App.x := g.Add("Edit", "x60 y253 w55 Number Background" ctrlBg)
    g.Add("Text", "x125 y256 w20", "Y:")
    App.y := g.Add("Edit", "x145 y253 w55 Number Background" ctrlBg)
    pick := g.Add("Button", "x215 y252 w95 h24", "Pick (F8)")
    pick.SetFont("c" btnText)
    pick.OnEvent("Click", CapturePosition)

    ; Repeat
    g.Add("GroupBox", "x10 y292 w310 h70", "Repeat")
    App.repeatForever := g.Add("Radio", "x22 y314", "Until stopped")
    App.repeatCount   := g.Add("Radio", "x22 y338", "Stop after")
    App.countEdit := g.Add("Edit", "x115 y335 w55 Number Background" ctrlBg)
    g.Add("Text", "x178 y338 w50", "clicks")

    ; Controls
    start := g.Add("Button", "x10 y372 w150 h36", "Start (F6)")
    start.SetFont("c" btnText)
    start.OnEvent("Click", (*) => StartClicking())
    stop := g.Add("Button", "x170 y372 w150 h36", "Stop (F6)")
    stop.SetFont("c" btnText)
    stop.OnEvent("Click", (*) => StopClicking())

    App.status := g.Add("Text", "x10 y418 w310 Center", "Idle")

    App.darkCheck := g.Add("Checkbox", "x10 y446 " (App.dark ? "Checked" : ""), "Dark mode")
    App.darkCheck.OnEvent("Click", ToggleDark)

    g.Show("w330 h474")

    RestoreSettings(s)
    UpdateStatus()
    if App.clicking                   ; resume loop if we were clicking
        SetTimer(DoClick, -NextInterval())
}

ToggleDark(*) {
    global App
    App.dark := App.darkCheck.Value
    BuildGui()
}

; ---- Settings persistence across rebuilds -----------------
SnapshotSettings() {
    global App
    if !App.HasOwnProp("interval")    ; first build -> defaults
        return { interval: 100, random: 0, button: 1, type: 1,
                 fixed: false, x: "", y: "", repeatCount: false, count: 100 }
    return { interval: App.interval.Value,   random: App.random.Value,
             button: App.button.Value,       type: App.type.Value,
             fixed: App.posFixed.Value,       x: App.x.Value, y: App.y.Value,
             repeatCount: App.repeatCount.Value, count: App.countEdit.Value }
}

RestoreSettings(s) {
    global App
    App.interval.Value := s.interval
    App.random.Value   := s.random
    App.button.Choose(s.button)
    App.type.Choose(s.type)
    (s.fixed ? App.posFixed : App.posCurrent).Value := 1
    App.x.Value := s.x
    App.y.Value := s.y
    (s.repeatCount ? App.repeatCount : App.repeatForever).Value := 1
    App.countEdit.Value := s.count
}

; ---- Logic ------------------------------------------------
ToggleClicking() {
    global App
    if App.clicking
        StopClicking()
    else
        StartClicking()
}

StartClicking() {
    global App
    if App.clicking
        return
    App.clicking := true
    App.count := 0
    UpdateStatus()
    SetTimer(DoClick, -NextInterval())
}

StopClicking() {
    global App
    if !App.clicking
        return
    App.clicking := false
    SetTimer(DoClick, 0)
    UpdateStatus()
}

DoClick() {
    global App
    if !App.clicking
        return
    PerformClick()
    App.count += 1
    UpdateStatus()
    if (App.repeatCount.Value && App.count >= Integer(App.countEdit.Value)) {
        StopClicking()
        return
    }
    SetTimer(DoClick, -NextInterval())   ; re-arm with fresh (possibly random) delay
}

PerformClick() {
    global App
    opt := App.button.Text
    if (App.type.Text = "Double")
        opt .= " 2"
    if App.posFixed.Value {
        x := App.x.Value = "" ? 0 : App.x.Value
        y := App.y.Value = "" ? 0 : App.y.Value
        Click(x " " y " " opt)
    } else {
        Click(opt)
    }
}

NextInterval() {
    global App
    base := App.interval.Value = "" ? 1 : Integer(App.interval.Value)
    rnd  := App.random.Value   = "" ? 0 : Integer(App.random.Value)
    if (rnd > 0)
        base += Random(-rnd, rnd)
    return base < 1 ? 1 : base
}

UpdateStatus() {
    global App
    if App.clicking
        App.status.Value := "Running... (" App.count " clicks)"
    else
        App.status.Value := App.count > 0 ? "Stopped (" App.count " clicks)" : "Idle"
}

CapturePosition(*) {
    global App
    MouseGetPos(&mx, &my)
    App.x.Value := mx
    App.y.Value := my
    App.posFixed.Value := 1
    App.status.Value := "Captured position " mx ", " my
}

; Paint the window title bar to match the theme (Win10 2004+/Win11).
; Tries the modern attribute (20), falls back to the older one (19).
ApplyDarkTitleBar(hwnd, dark) {
    val := dark ? 1 : 0
    for attr in [20, 19] {
        if !DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", hwnd,
            "Int", attr, "Int*", val, "Int", 4, "Int")
            return            ; HRESULT 0 = success
    }
}
