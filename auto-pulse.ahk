#Requires AutoHotkey v2.0
#SingleInstance Force

; ============================================================
;  Auto-Pulse  -  AutoHotkey v2
;  Start/Stop hotkey is configurable (default F6)   F8 = Capture cursor position
;  Action mode switches between mouse clicks and key presses.
;  Dark mode is toggleable via the checkbox.
;  A small on-screen HUD shows on/off status; drag its body to move it,
;  grab an edge/corner to resize it (starts in the top-right corner).
;  Checks GitHub on launch and reports if a newer version exists.
; ============================================================

CoordMode("Mouse", "Screen")   ; use absolute screen coordinates

App := { clicking: false, count: 0, dark: true, picking: false, onTop: false,
         positions: [], posIndex: 0, toggleKey: "F6", capturing: false,
         hud: true, clickTimes: [],
         version: "1.2.3", updateAvailable: false, latestVersion: "",
         updateChecked: false }

; Where the update checker looks for the latest published version.
UPDATE_VERSION_URL := "https://raw.githubusercontent.com/brageat/auto-pulse/main/VERSION"
UPDATE_PAGE_URL    := "https://github.com/brageat/auto-pulse"

BuildGui()
if App.hud                            ; HUD is shown by default
    ShowHud()

; ---- Global hotkeys ---------------------------------------
SetToggleHotkey(App.toggleKey)        ; start/stop (user-configurable via "Set...")
Hotkey("F8", CaptureCursorPos)        ; F8 grabs the cursor's position instantly

; Check GitHub for a newer version shortly after launch (off the UI thread's
; critical path; -1 => run once). Silent so a failed check stays quiet.
SetTimer(() => CheckForUpdate(true), -1500)

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

    g := Gui("", "Auto-Pulse")
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
    ; Fixed mode uses a list of one or more points; clicks cycle through them.
    mouseCtrls.Push(g.Add("GroupBox", "x10 y244 w310 h170", "Click Location"))
    App.posCurrent := g.Add("Radio", "x22 y266", "Current cursor position")
    mouseCtrls.Push(App.posCurrent)
    App.posFixed := g.Add("Radio", "x22 y290", "Fixed position(s)")
    mouseCtrls.Push(App.posFixed)

    mouseCtrls.Push(g.Add("Text", "x40 y319 w14", "X:"))
    App.x := g.Add("Edit", "x56 y316 w48 Number Background" ctrlBg)
    mouseCtrls.Push(App.x)
    mouseCtrls.Push(g.Add("Text", "x110 y319 w14", "Y:"))
    App.y := g.Add("Edit", "x126 y316 w48 Number Background" ctrlBg)
    mouseCtrls.Push(App.y)
    addBtn := g.Add("Button", "x182 y315 w58 h23", "Add")
    addBtn.SetFont("c" btnText)
    addBtn.OnEvent("Click", AddTypedPosition)
    mouseCtrls.Push(addBtn)
    pick := g.Add("Button", "x246 y315 w64 h23", "Pick (F8)")
    pick.SetFont("c" btnText)
    pick.OnEvent("Click", ArmPicker)
    mouseCtrls.Push(pick)

    App.posList := g.Add("ListBox", "x40 y346 w170 h60 Background" ctrlBg)
    mouseCtrls.Push(App.posList)
    removeBtn := g.Add("Button", "x218 y346 w92 h23", "Remove")
    removeBtn.SetFont("c" btnText)
    removeBtn.OnEvent("Click", RemoveSelectedPosition)
    mouseCtrls.Push(removeBtn)
    clearBtn := g.Add("Button", "x218 y373 w92 h23", "Clear")
    clearBtn.SetFont("c" btnText)
    clearBtn.OnEvent("Click", (*) => ClearPositions())
    mouseCtrls.Push(clearBtn)

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
    g.Add("GroupBox", "x10 y422 w310 h70", "Repeat")
    App.repeatForever := g.Add("Radio", "x22 y444", "Until stopped")
    App.repeatCount   := g.Add("Radio", "x22 y468", "Stop after")
    App.countEdit := g.Add("Edit", "x115 y465 w55 Number Background" ctrlBg)
    g.Add("Text", "x178 y468 w50", "times")

    ; Hotkey -- the global start/stop key (configurable)
    g.Add("GroupBox", "x10 y500 w310 h48", "Start/Stop Hotkey")
    g.Add("Text", "x22 y523 w52", "Hotkey:")
    App.hotkeyDisplay := g.Add("Text", "x80 y521 w150 Center Border", App.toggleKey)
    setHk := g.Add("Button", "x238 y518 w72 h23", "Set...")
    setHk.SetFont("c" btnText)
    setHk.OnEvent("Click", CaptureToggleHotkey)

    ; Controls
    App.startBtn := g.Add("Button", "x10 y558 w150 h36", "Start (" App.toggleKey ")")
    App.startBtn.SetFont("c" btnText)
    App.startBtn.OnEvent("Click", (*) => StartClicking())
    App.stopBtn := g.Add("Button", "x170 y558 w150 h36", "Stop (" App.toggleKey ")")
    App.stopBtn.SetFont("c" btnText)
    App.stopBtn.OnEvent("Click", (*) => StopClicking())

    App.status := g.Add("Text", "x10 y604 w310 Center", "Idle")

    App.darkCheck := g.Add("Checkbox", "x10 y632 w90 " (App.dark ? "Checked" : ""), "Dark mode")
    App.darkCheck.OnEvent("Click", ToggleDark)

    App.topCheck := g.Add("Checkbox", "x110 y632 w120 " (App.onTop ? "Checked" : ""), "Always on top")
    App.topCheck.OnEvent("Click", ToggleOnTop)

    App.hudCheck := g.Add("Checkbox", "x240 y632 w85 " (App.hud ? "Checked" : ""), "Show HUD")
    App.hudCheck.OnEvent("Click", ToggleHud)

    ; Update status / link (click to re-check, or to open the download page)
    App.updateLink := g.Add("Text", "x10 y660 w310 Center", "Auto-Pulse v" App.version)
    App.updateLink.OnEvent("Click", OnUpdateClick)

    App.mouseCtrls := mouseCtrls
    App.keyCtrls   := keyCtrls

    g.Show("w330 h688")

    RestoreSettings(s)
    RefreshPosList()                  ; rebuild the list view from App.positions
    ApplyActionMode()                 ; show the controls for the current mode
    RefreshUpdateText()               ; keep any update notice across re-themes
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

; ---- Status HUD -------------------------------------------
; A small always-on-top overlay in the top-right corner that shows
; whether the clicker is running and the running count. It's a
; separate, click-through window so it never steals focus or blocks
; clicks on whatever is underneath it.
ToggleHud(*) {
    global App
    App.hud := App.hudCheck.Value
    if App.hud
        ShowHud()
    else if App.HasOwnProp("hudGui")
        App.hudGui.Hide()
}

ShowHud() {
    global App
    if !App.HasOwnProp("hudGui")
        BuildHud()
    h := App.hudGui
    if !App.hudPlaced {
        h.Show("Hide AutoSize")             ; size to the text in real pixels (DPI-correct)
        WinGetPos(, , &w, , h.Hwnd)         ; actual window width incl. resize frame
        MonitorGetWorkArea(MonitorGetPrimary(), , &top, &right)
        h.Show(Format("x{} y{} NoActivate", right - w, top))   ; into the top-right corner...
        SnapHudToCorner(h.Hwnd, right, top) ; ...then trim the invisible resize border
        App.hudPlaced := true
    } else {
        h.Show("NoActivate")                ; reuse wherever the user last moved/sized it
    }
    WinSetTransparent(225, h.Hwnd)          ; slightly see-through
    UpdateHud()
}

; A +Resize window's frame includes an invisible DWM "grab" border (9px here,
; wider at higher DPI) that GetWindowRect counts but you can't see -- so snapping
; the window rect to the screen edge leaves the *visible* edge a few px short.
; Measure that border (window rect vs DWM's extended frame bounds) and nudge the
; window so the visible top-right corner is genuinely flush.
SnapHudToCorner(hwnd, right, top) {
    WinGetPos(&wx, &wy, &ww, , hwnd)
    rc := Buffer(16, 0)
    ; DWMWA_EXTENDED_FRAME_BOUNDS = 9 -> the *visible* window bounds
    if (DllCall("dwmapi\DwmGetWindowAttribute", "ptr", hwnd, "uint", 9, "ptr", rc, "uint", 16) != 0)
        return                              ; no DWM -> keep the naive position
    borderR := (wx + ww) - NumGet(rc, 8, "int")   ; invisible border on the right
    borderT := NumGet(rc, 4, "int") - wy          ; invisible border on top (usually 0)
    if (borderR < 0 || borderR > 40)              ; ignore anything implausible
        borderR := 0
    if (borderT < 0 || borderT > 40)
        borderT := 0
    if (borderR || borderT)
        WinMove(right - ww + borderR, top - borderT, , , "ahk_id " hwnd)
}

BuildHud() {
    global App
    ; -DPIScale so positions/sizes are real pixels (matches MonitorGetWorkArea),
    ; which keeps the window fully on-screen at any display scaling.
    ; +Resize gives it a sizing border; HudHitTest() (below) lets you drag the
    ; body to move it and grab any edge/corner to resize it. (Dropping the old
    ; WS_EX_TRANSPARENT click-through is what makes those grabs possible.)
    h := Gui("+AlwaysOnTop -Caption +ToolWindow +Resize -DPIScale", "Auto-Pulse HUD")
    App.hudGui := h
    App.hudPlaced := false           ; first ShowHud() snaps it to the corner
    h.MarginX := 14, h.MarginY := 8
    h.BackColor := "161616"

    ; A Text control's height is fixed at Add() time from the *current* font,
    ; so set each line's font BEFORE adding it -- enlarging it afterward would
    ; leave the control too short and clip the text. LayoutHud() re-applies the
    ; font and the box size together on resize, which keeps text from clipping.
    h.SetFont("s15 bold cDDDDDD", "Segoe UI")
    App.hudStatus := h.Add("Text", "w180 Center", "OFF")
    h.SetFont("s8 norm cAAAAAA")
    App.hudCount  := h.Add("Text", "w180 Center", "Idle")
    h.SetFont("s9 cCCCCCC")
    App.hudCps    := h.Add("Text", "w180 Center", "0.0 cps")

    h.OnEvent("Size", HudSize)       ; rescale the text as the window is resized
    OnMessage(0x84, HudHitTest)      ; WM_NCHITTEST -> drag-to-move + edge resize
}

; Re-flow the three HUD lines for the current client size: scale the fonts with
; the window and keep the block vertically centred. Font and box are set together
; (see BuildHud) so the larger text never clips. Colours are left alone here --
; the status colour is owned by UpdateHud().
LayoutHud(w, h) {
    global App
    if !App.HasOwnProp("hudStatus") || !App.HasOwnProp("hudW")
        return
    ; Scale to the *smaller* of the width/height ratios so the whole block always
    ; fits -- scaling by width alone let a short window clip the bottom line.
    scale := Min(w / App.hudW, h / App.hudH)
    scale := Max(0.5, Min(scale, 6.0))
    m   := Round(14 * scale)         ; side margin
    cw  := Max(10, w - 2 * m)
    s1  := Round(15 * scale), s2 := Round(8 * scale), s3 := Round(9 * scale)
    h1  := Round(s1 * 1.9),   h2 := Round(s2 * 1.9),   h3 := Round(s3 * 1.9)
    gap := Round(2 * scale)
    y   := Max(0, (h - (h1 + h2 + h3 + 2 * gap)) // 2)   ; centre the block vertically

    App.hudStatus.SetFont("s" s1 " bold", "Segoe UI"), App.hudStatus.Move(m, y, cw, h1)
    y += h1 + gap
    App.hudCount.SetFont("s" s2 " norm"),              App.hudCount.Move(m, y, cw, h2)
    y += h2 + gap
    App.hudCps.SetFont("s" s3),                        App.hudCps.Move(m, y, cw, h3)
}

; Relayout as the window is dragged-resized. The first event after the
; (auto-sized) window appears captures that DPI-correct size as the scaling
; baseline and leaves the natural layout untouched; only genuine user resizes
; re-flow through LayoutHud, so the default HUD stays pixel-perfect.
HudSize(thisGui, minMax, w, h) {
    global App
    if (minMax = -1 || w < 1 || h < 1)
        return
    if !App.HasOwnProp("hudW") {     ; first real size = the auto-sized baseline
        App.hudW := w, App.hudH := h
        return
    }
    if (w = App.hudW && h = App.hudH)   ; unchanged from baseline -> keep natural layout
        return
    LayoutHud(w, h)
    UpdateHud()                      ; re-apply the live status colour
}

; A borderless window has no title bar to grab, so we hit-test it ourselves:
; the outer EDGE pixels report as resize handles and everything inside reports
; as the caption, which turns the whole body into a move handle. Only our HUD
; is touched; every other window falls through to default handling.
HudHitTest(wParam, lParam, msg, hwnd) {
    global App
    if !App.HasOwnProp("hudGui") || hwnd != App.hudGui.Hwnd
        return
    x := lParam & 0xFFFF, y := (lParam >> 16) & 0xFFFF
    if (x > 0x7FFF)
        x -= 0x10000                 ; sign-extend (coords go negative across monitors)
    if (y > 0x7FFF)
        y -= 0x10000
    WinGetPos(&wx, &wy, &ww, &wh, hwnd)
    EDGE := 6
    ; Map cursor to a column/row band, then pick the matching hit-test code.
    col := (x < wx + EDGE) ? "L" : (x >= wx + ww - EDGE) ? "R" : "M"
    row := (y < wy + EDGE) ? "T" : (y >= wy + wh - EDGE) ? "B" : "M"
    switch row . col {
        case "TL": return 13         ; HTTOPLEFT
        case "TR": return 14         ; HTTOPRIGHT
        case "BL": return 16         ; HTBOTTOMLEFT
        case "BR": return 17         ; HTBOTTOMRIGHT
        case "TM": return 12         ; HTTOP
        case "BM": return 15         ; HTBOTTOM
        case "ML": return 10         ; HTLEFT
        case "MR": return 11         ; HTRIGHT
    }
    return 2                         ; HTCAPTION -> drag the body to move
}

UpdateHud() {
    global App
    if !App.hud || !App.HasOwnProp("hudStatus")
        return
    noun := App.action.Value = 2 ? "presses" : "clicks"
    unit := App.action.Value = 2 ? "kps" : "cps"
    if App.clicking {
        App.hudStatus.SetFont("c33DD55")          ; green = running
        App.hudStatus.Text := "ON"
        cps := CurrentCps()
    } else {
        App.hudStatus.SetFont("c888888")          ; gray = stopped
        App.hudStatus.Text := "OFF"
        cps := 0.0
    }
    App.hudCount.Text := (App.clicking || App.count > 0) ? App.count " " noun : "Idle"
    App.hudCps.Text := Format("{:.1f} {}", cps, unit)
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
                 action: 1, keys: "", hotkey: App.toggleKey }
    return { interval: App.interval.Value,   random: App.random.Value,
             button: App.button.Value,       type: App.type.Value,
             fixed: App.posFixed.Value,       x: App.x.Value, y: App.y.Value,
             repeatCount: App.repeatCount.Value, count: App.countEdit.Value,
             action: App.action.Value,       keys: App.keysEdit.Value,
             hotkey: App.toggleKey }
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
    App.hotkeyDisplay.Text := s.hotkey
}

; ---- Configurable start/stop hotkey -----------------------
; The handler is named (not a closure) so Hotkey() can re-target the
; same callback when the binding changes.
ToggleHotkeyHandler(*) {
    ToggleClicking()
}

; Register/replace the global start/stop hotkey. Returns false (and
; leaves the old binding in place) if the key string is invalid.
SetToggleHotkey(newKey) {
    global App
    old := App.HasOwnProp("toggleKey") ? App.toggleKey : ""
    try {
        Hotkey(newKey, ToggleHotkeyHandler, "On")
    } catch {
        if App.HasOwnProp("status")
            App.status.Value := "Invalid hotkey: " newKey
        return false
    }
    if (old != "" && old != newKey)
        try Hotkey(old, "Off")        ; disable the previous binding
    App.toggleKey := newKey
    UpdateHotkeyLabels()
    return true
}

; Keep the on-screen labels in sync with the active hotkey.
UpdateHotkeyLabels() {
    global App
    if App.HasOwnProp("hotkeyDisplay")
        App.hotkeyDisplay.Text := App.toggleKey
    if App.HasOwnProp("startBtn")
        App.startBtn.Text := "Start (" App.toggleKey ")"
    if App.HasOwnProp("stopBtn")
        App.stopBtn.Text := "Stop (" App.toggleKey ")"
}

; "Set..." arms a one-shot capture: the next key you press (with any
; modifiers) becomes the global start/stop hotkey. Esc cancels.
CaptureToggleHotkey(*) {
    global App
    if App.capturing
        return
    App.capturing := true
    old := App.toggleKey
    if (old != "")                    ; don't let the old key fire mid-capture
        try Hotkey(old, "Off")
    App.status.Value := "Press the new start/stop hotkey (Esc to cancel)..."

    ih := InputHook("T10")            ; 10s timeout so we never hang
    ih.KeyOpt("{All}", "E")           ; any key ends the capture
    ih.Start()
    ih.Wait()
    App.capturing := false

    key := ih.EndKey
    if (key = "" || key = "Escape" || IsModifierKey(key)) {
        if (old != "")
            try Hotkey(old, "On")     ; restore the previous binding
        App.status.Value := "Hotkey unchanged (" old ")"
        return
    }

    mods := ""
    em := ih.EndMods                  ; e.g. "<^>!" -> collapse to "^!"
    if InStr(em, "^")
        mods .= "^"
    if InStr(em, "!")
        mods .= "!"
    if InStr(em, "+")
        mods .= "+"
    if InStr(em, "#")
        mods .= "#"
    newKey := mods . key

    if SetToggleHotkey(newKey)
        App.status.Value := "Start/stop hotkey set to " newKey
    else if (old != "")
        try Hotkey(old, "On")         ; registration failed -> keep the old one
}

IsModifierKey(k) {
    static mods := Map("Control",1, "LControl",1, "RControl",1,
                       "Alt",1, "LAlt",1, "RAlt",1,
                       "Shift",1, "LShift",1, "RShift",1,
                       "LWin",1, "RWin",1)
    return mods.Has(k)
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
    App.clickTimes := []              ; reset the CPS measurement window
    App.posIndex := 0                 ; restart the fixed-position cycle
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
    RecordClick()
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
        if (App.positions.Length > 0) {        ; cycle through the saved points
            App.posIndex += 1
            if (App.posIndex > App.positions.Length)
                App.posIndex := 1
            p := App.positions[App.posIndex]
            Click(p.x " " p.y " " opt)
        } else if (App.x.Value != "" && App.y.Value != "") {
            Click(App.x.Value " " App.y.Value " " opt)   ; typed-but-not-added point
        } else {
            Click(opt)
        }
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

; ---- Clicks-per-second measurement ------------------------
; Keep a timestamp per action within a 1-second window; the live
; rate is the average over that window (stable across fast/slow rates).
RecordClick() {
    global App
    now := A_TickCount
    App.clickTimes.Push(now)
    while (App.clickTimes.Length > 0 && now - App.clickTimes[1] > 1000)
        App.clickTimes.RemoveAt(1)
}

CurrentCps() {
    global App
    t := App.clickTimes
    n := t.Length
    if (n < 2)
        return 0.0
    span := t[n] - t[1]
    return span > 0 ? Round((n - 1) * 1000.0 / span, 1) : 0.0
}

UpdateStatus() {
    global App
    noun := App.action.Value = 2 ? "presses" : "clicks"
    if App.clicking
        App.status.Value := "Running... (" App.count " " noun ")"
    else
        App.status.Value := App.count > 0 ? "Stopped (" App.count " " noun ")" : "Idle"
    UpdateHud()
}

; ---- Picking the fixed position ---------------------------
; F8 captures the cursor's current position instantly. The Pick button
; instead arms click-to-pick -- clicking the button can't grab a position
; directly, since at that moment the cursor is on the button itself.

; F8: snapshot wherever the cursor is right now, no second click needed.
CaptureCursorPos(*) {
    global App
    if App.action.Value = 2           ; key mode -> no screen position to pick
        return
    if App.picking                    ; mid click-to-pick? drop it and grab now
        EndPick()
    MouseGetPos(&mx, &my)             ; screen coords (CoordMode set at startup)
    App.x.Value := mx
    App.y.Value := my
    AddPosition(mx, my)
    App.status.Value := "Added position " mx ", " my
}

; The Pick button arms click-to-pick: the next click (off this window)
; becomes the fixed position. Esc cancels.
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
    AddPosition(mx, my)
    App.status.Value := "Added position " mx ", " my
}

; ---- Fixed-position list ----------------------------------
AddTypedPosition(*) {
    global App
    if (App.x.Value = "" || App.y.Value = "") {
        App.status.Value := "Enter X and Y first"
        return
    }
    AddPosition(App.x.Value, App.y.Value)
    App.status.Value := "Added position " App.x.Value ", " App.y.Value
}

AddPosition(x, y) {
    global App
    App.positions.Push({ x: x, y: y })
    App.posFixed.Value := 1
    RefreshPosList()
    App.posList.Choose(App.positions.Length)
}

RemoveSelectedPosition(*) {
    global App
    idx := App.posList.Value
    if (idx < 1)
        return
    App.positions.RemoveAt(idx)
    if (App.posIndex > App.positions.Length)
        App.posIndex := App.positions.Length
    RefreshPosList()
    App.status.Value := "Removed position " idx
}

ClearPositions() {
    global App
    App.positions := []
    App.posIndex := 0
    RefreshPosList()
    App.status.Value := "Cleared positions"
}

; Rebuild the ListBox view from App.positions (the source of truth).
RefreshPosList() {
    global App
    if !App.HasOwnProp("posList")
        return
    App.posList.Delete()
    items := []
    for p in App.positions
        items.Push(A_Index ":  " p.x ", " p.y)
    if (items.Length > 0)
        App.posList.Add(items)
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

; ---- Update check -----------------------------------------
; Compares this build's version (App.version) against the VERSION file
; published on the repo's main branch. The bottom label shows the result
; and, when an update exists, links to the download page.
CheckForUpdate(silent := false) {
    global App
    SetUpdateText("Checking for updates...", "999999")
    remote := FetchRemoteVersion()
    if (remote = "") {                         ; offline / blocked / not found
        App.updateAvailable := false
        SetUpdateText(silent ? "Auto-Pulse v" App.version : "Update check failed - click to retry",
            "999999")
        return
    }
    if (CompareVersions(remote, App.version) > 0) {
        App.updateAvailable := true
        App.latestVersion := remote
    } else {
        App.updateAvailable := false
    }
    App.updateChecked := true
    RefreshUpdateText()
    if App.updateAvailable
        NotifyUpdate()
}

; Pop up a notice with the download link whenever a newer version is found.
NotifyUpdate() {
    global App, UPDATE_PAGE_URL
    msg := "A new version of Auto-Pulse is available.`n`n"
         . "You have:`tv" App.version "`n"
         . "Latest:`tv" App.latestVersion "`n`n"
         . "Get the new version here:`n" UPDATE_PAGE_URL "`n`n"
         . "Open the download page now?"
    if (MsgBox(msg, "Auto-Pulse - update available", "YesNo Iconi 0x40000") = "Yes")
        Run(UPDATE_PAGE_URL)
}

; Fetch the published version string. Returns "" on any failure.
FetchRemoteVersion() {
    global UPDATE_VERSION_URL
    try {
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.Open("GET", UPDATE_VERSION_URL "?_=" A_TickCount, true)   ; bust caches
        req.SetTimeouts(3000, 3000, 3000, 4000)
        req.Send()
        req.WaitForResponse(6)
        if (req.Status != 200)
            return ""
        v := LTrim(Trim(req.ResponseText, " `t`r`n"), "vV")
        return RegExMatch(v, "^\d+(\.\d+)*$") ? v : ""
    } catch {
        return ""
    }
}

; Numeric, dot-separated comparison. 1 if a>b, -1 if a<b, 0 if equal.
CompareVersions(a, b) {
    pa := StrSplit(a, "."), pb := StrSplit(b, ".")
    loop Max(pa.Length, pb.Length) {
        x := A_Index <= pa.Length ? Integer(pa[A_Index]) : 0
        y := A_Index <= pb.Length ? Integer(pb[A_Index]) : 0
        if (x != y)
            return x > y ? 1 : -1
    }
    return 0
}

; Render the current update state onto the bottom label.
RefreshUpdateText() {
    global App
    if !App.HasOwnProp("updateLink")
        return
    if App.updateAvailable
        SetUpdateText("Update available: v" App.latestVersion " - click to download", "FFD24D")
    else if App.updateChecked
        SetUpdateText("Auto-Pulse v" App.version " (up to date)", "6FBF73")
    else
        SetUpdateText("Auto-Pulse v" App.version, "999999")
}

SetUpdateText(txt, color) {
    global App
    if !App.HasOwnProp("updateLink")
        return
    App.updateLink.Text := txt
    App.updateLink.SetFont("c" color)
}

; Clicking the label opens the download page if an update is waiting,
; otherwise it re-runs the check.
OnUpdateClick(*) {
    global App, UPDATE_PAGE_URL
    if App.updateAvailable
        Run(UPDATE_PAGE_URL)
    else
        CheckForUpdate(false)
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
