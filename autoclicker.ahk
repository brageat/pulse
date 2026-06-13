#Requires AutoHotkey v2.0
#SingleInstance Force

; ============================================================
;  AutoClicker  -  AutoHotkey v2
;  F6 = Start/Stop (global)   F8 = Capture cursor position
;  Action mode switches between mouse clicks and key presses.
;  Dark mode is toggleable via the checkbox.
; ============================================================

CoordMode("Mouse", "Screen")   ; use absolute screen coordinates

App := { clicking: false, count: 0, dark: true, picking: false, onTop: true }

BuildGui()

; ---- Global hotkeys ---------------------------------------
Hotkey("F6", (*) => ToggleClicking())
Hotkey("F8", ArmPicker)

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

    g := Gui("", "AutoClicker")
    App.gui := g
    g.OnEvent("Close", (*) => ExitApp())
    g.Opt(App.onTop ? "+AlwaysOnTop" : "-AlwaysOnTop")
    g.BackColor := bg
    g.SetFont("s9 c" text, "Segoe UI")
    ApplyDarkTitleBar(g.Hwnd, App.dark)

    mouseCtrls := []                  ; controls shown only in mouse-click mode
    keyCtrls   := []                  ; controls shown only in key-press mode

    ; Action mode
    g.Add("GroupBox", "x10 y8 w310 h52", "Action")
    g.Add("Text", "x22 y31 w60", "Action:")
    App.action := g.Add("DropDownList", "x115 y28 w150 Background" ctrlBg, ["Mouse click", "Key press"])
    App.action.OnEvent("Change", ApplyActionMode)

    ; Interval
    g.Add("GroupBox", "x10 y68 w310 h80", "Click Interval")
    g.Add("Text", "x22 y92 w90", "Interval (ms):")
    App.interval := g.Add("Edit", "x115 y89 w80 Number Background" ctrlBg)
    g.Add("Text", "x22 y120 w90", "Random +/- (ms):")
    App.random := g.Add("Edit", "x115 y117 w80 Number Background" ctrlBg)

    ; Mouse: click options (same vertical slot as the Keystroke group)
    mouseCtrls.Push(g.Add("GroupBox", "x10 y156 w310 h80", "Click Options"))
    mouseCtrls.Push(g.Add("Text", "x22 y180 w60", "Button:"))
    App.button := g.Add("DropDownList", "x115 y177 w90 Background" ctrlBg, ["Left", "Right", "Middle"])
    mouseCtrls.Push(App.button)
    mouseCtrls.Push(g.Add("Text", "x22 y208 w60", "Type:"))
    App.type := g.Add("DropDownList", "x115 y205 w90 Background" ctrlBg, ["Single", "Double"])
    mouseCtrls.Push(App.type)

    ; Mouse: location (hidden in key mode -- keys go to the focused window)
    mouseCtrls.Push(g.Add("GroupBox", "x10 y244 w310 h100", "Click Location"))
    App.posCurrent := g.Add("Radio", "x22 y266", "Current cursor position")
    mouseCtrls.Push(App.posCurrent)
    App.posFixed := g.Add("Radio", "x22 y290", "Fixed position")
    mouseCtrls.Push(App.posFixed)
    mouseCtrls.Push(g.Add("Text", "x40 y316 w20", "X:"))
    App.x := g.Add("Edit", "x60 y313 w55 Number Background" ctrlBg)
    mouseCtrls.Push(App.x)
    mouseCtrls.Push(g.Add("Text", "x125 y316 w20", "Y:"))
    App.y := g.Add("Edit", "x145 y313 w55 Number Background" ctrlBg)
    mouseCtrls.Push(App.y)
    pick := g.Add("Button", "x215 y312 w95 h24", "Pick (F8)")
    pick.SetFont("c" btnText)
    pick.OnEvent("Click", ArmPicker)
    mouseCtrls.Push(pick)

    ; Key: keystroke (occupies the same slot as the two mouse groups)
    keyCtrls.Push(g.Add("GroupBox", "x10 y156 w310 h188", "Keystroke"))
    keyCtrls.Push(g.Add("Text", "x22 y182 w55", "Key(s):"))
    App.keysEdit := g.Add("Edit", "x115 y179 w195 Background" ctrlBg)
    keyCtrls.Push(App.keysEdit)
    hint := "Sent to the focused window using AutoHotkey send syntax.`n`n"
          . "Examples:`n"
          . "    {Space}   {Enter}   {Tab}   {F5}`n"
          . "    a    ^c = Ctrl+C    !{Tab} = Alt+Tab`n`n"
          . "Tip: in key mode press F6 to start after`n"
          . "focusing the target window."
    keyCtrls.Push(g.Add("Text", "x22 y214 w295 h120", hint))

    ; Repeat
    g.Add("GroupBox", "x10 y352 w310 h70", "Repeat")
    App.repeatForever := g.Add("Radio", "x22 y374", "Until stopped")
    App.repeatCount   := g.Add("Radio", "x22 y398", "Stop after")
    App.countEdit := g.Add("Edit", "x115 y395 w55 Number Background" ctrlBg)
    g.Add("Text", "x178 y398 w50", "times")

    ; Controls
    start := g.Add("Button", "x10 y432 w150 h36", "Start (F6)")
    start.SetFont("c" btnText)
    start.OnEvent("Click", (*) => StartClicking())
    stop := g.Add("Button", "x170 y432 w150 h36", "Stop (F6)")
    stop.SetFont("c" btnText)
    stop.OnEvent("Click", (*) => StopClicking())

    App.status := g.Add("Text", "x10 y478 w310 Center", "Idle")

    App.darkCheck := g.Add("Checkbox", "x10 y506 w90 " (App.dark ? "Checked" : ""), "Dark mode")
    App.darkCheck.OnEvent("Click", ToggleDark)

    App.topCheck := g.Add("Checkbox", "x110 y506 w120 " (App.onTop ? "Checked" : ""), "Always on top")
    App.topCheck.OnEvent("Click", ToggleOnTop)

    App.mouseCtrls := mouseCtrls
    App.keyCtrls   := keyCtrls

    g.Show("w330 h534")

    RestoreSettings(s)
    ApplyActionMode()                 ; show the controls for the current mode
    UpdateStatus()
    if App.clicking                   ; resume loop if we were clicking
        SetTimer(DoClick, -NextInterval())
}

ToggleDark(*) {
    global App
    App.dark := App.darkCheck.Value
    BuildGui()
}

ToggleOnTop(*) {
    global App
    App.onTop := App.topCheck.Value
    App.gui.Opt(App.onTop ? "+AlwaysOnTop" : "-AlwaysOnTop")
}

; Show only the controls relevant to the selected Action (mouse vs key).
ApplyActionMode(*) {
    global App
    isKey := App.action.Value = 2
    for c in App.mouseCtrls
        c.Visible := !isKey
    for c in App.keyCtrls
        c.Visible := isKey
}

; ---- Settings persistence across rebuilds -----------------
SnapshotSettings() {
    global App
    if !App.HasOwnProp("interval")    ; first build -> defaults
        return { interval: 100, random: 0, button: 1, type: 1,
                 fixed: false, x: "", y: "", repeatCount: false, count: 100,
                 action: 1, keys: "" }
    return { interval: App.interval.Value,   random: App.random.Value,
             button: App.button.Value,       type: App.type.Value,
             fixed: App.posFixed.Value,       x: App.x.Value, y: App.y.Value,
             repeatCount: App.repeatCount.Value, count: App.countEdit.Value,
             action: App.action.Value,       keys: App.keysEdit.Value }
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
    App.action.Choose(s.action)
    App.keysEdit.Value := s.keys
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
    PerformAction()
    App.count += 1
    UpdateStatus()
    if (App.repeatCount.Value && App.count >= Integer(App.countEdit.Value)) {
        StopClicking()
        return
    }
    SetTimer(DoClick, -NextInterval())   ; re-arm with fresh (possibly random) delay
}

PerformAction() {
    global App
    if (App.action.Value = 2) {       ; Key press
        keys := App.keysEdit.Value
        if (keys != "")
            Send(keys)
        return
    }
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
    noun := App.action.Value = 2 ? "presses" : "clicks"
    if App.clicking
        App.status.Value := "Running... (" App.count " " noun ")"
    else
        App.status.Value := App.count > 0 ? "Stopped (" App.count " " noun ")" : "Idle"
}

; ---- Click-to-pick for the fixed position -----------------
; Arm via the Pick button or F8, then click the target location;
; that click's coordinates become the fixed position. Esc cancels.
ArmPicker(*) {
    global App
    if App.action.Value = 2           ; key mode -> no screen position to pick
        return
    if App.picking
        return
    App.picking := true
    App.status.Value := "Click the target location (Esc to cancel)..."
    Hotkey("~LButton", PickClick, "On")
    Hotkey("Escape", CancelPick, "On")
}

PickClick(*) {
    global App
    MouseGetPos(&mx, &my, &win)
    if (win = App.gui.Hwnd)        ; clicked on this window -> ignore, keep waiting
        return
    EndPick()
    App.x.Value := mx
    App.y.Value := my
    App.posFixed.Value := 1
    App.status.Value := "Captured position " mx ", " my
}

CancelPick(*) {
    global App
    EndPick()
    App.status.Value := "Pick cancelled"
}

EndPick() {
    global App
    App.picking := false
    Hotkey("~LButton", "Off")
    Hotkey("Escape", "Off")
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
