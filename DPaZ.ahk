#Requires AutoHotkey v2.0
#SingleInstance Force

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Move and resize windows by holding the Windows key and
;; dragging with the mouse.
;;
;;    Win + Left mouse:  Move the window under the cursor
;;    Win + Right mouse: Resize the window under the cursor
;;    Win + Middle mouse: Close the window under the cursor (a normal close, like the X button)
;;
;; - Snapping: push the mouse against the left or right side of a monitor for half the screen, or
;;   into a corner for a quarter. Push the top of a window against the top of a monitor to maximize it.
;;   Hold it there for a moment and a see-through preview shows where it will go - let go to snap.
;; - Grabbing a maximized window restores it first
;; - The mouse cursor changes while you drag (move arrows, or a diagonal
;;   resize arrow that matches the corner you grabbed)
;; - Dragging updates once per screen refresh, so it's as smooth as your monitor (100 Hz = 100 updates/sec)
;; - Windows can't be shrunk below a minimum size, or grown beyond the screen
;; - Windows can't be dragged completely off-screen
;; - Fixed-size windows, fullscreen apps, the desktop and the taskbar are left alone
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

DetectHiddenWindows false
SetWinDelay -1
CoordMode "Mouse", "Screen"
A_MaxHotkeysPerInterval := 1000

;; make sure coordinates are real pixels on every monitor, even when the monitors use different display scaling
try DllCall("SetThreadDpiAwarenessContext", "Ptr", -4, "Ptr")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; SETTINGS

;; smallest size (pixels) a window can be shrunk to
;; (a window that is already smaller than this can't shrink further, but can still grow)
global MinWidth := 200
global MinHeight := 120

;; how many pixels of a window must stay on screen when you drag it towards an edge
global KeepVisible := 100

;; Snapping to the sides and corners follows the MOUSE. Snapping to the top (maximize) follows the WINDOW.

;; how close (pixels) the mouse has to get to the side of a monitor to snap to it
global SideMargin := 3
;; ...and next to another monitor. The mouse just carries on over to the other screen there,
;; so it needs a wider spot to stop in.
global SharedSideMargin := 12
;; how close (pixels) to a corner the mouse has to be, along the edge, for a quarter-screen snap
global CornerSize := 100
;; how close (pixels) the top of a window has to get to the top of the monitor to maximize
global SnapMargin := 3
;; how long (ms) you have to stay in a snap spot before the preview shows up and letting go snaps
;; (so dragging a window past an edge doesn't snap it - set to 0 to snap straight away)
global SnapDelay := 150

;; the see-through preview shown while a window is about to snap
global PreviewColor := "BCCCE4"
global PreviewOpacity := 120   ; 0 (invisible) to 255 (solid)
global PreviewRadius := 8      ; how round the corners are, 0 = square

;; how far (pixels) you have to drag before a click turns into a drag
;; (so a plain Win+click on a maximized window doesn't un-maximize it)
global DragThreshold := 6

;; true  = bring the window to the front and give it focus when you start dragging it
;; false = leave focus and the window order alone while dragging
global FocusOnDrag := true

;; true  = update the window once per screen refresh (smoothest, follows your monitor's refresh rate)
;; false = update on a fixed 10 ms timer instead - use this if the sync ever causes trouble
global SyncToRefresh := true

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; STATE

global StartX := 0
global StartY := 0
global PressX := 0
global PressY := 0
global Busy := false

global DragActive := false
global DragType := ""
global DragMoved := false
;; goes up by one for every drag, so a loop left over from an old drag can tell it's out of date
global DragId := 0
;; have we already focused the window for this drag?
global DragFocused := false

;; the window we "grabbed" - so we don't accidentally grab another one during move/resize
global GrabbedWindow := ""
;; which half of the window we grabbed when resizing - "left"/"right"/"" and "top"/"bottom"/""
global GrabbedHalfX := ""
global GrabbedHalfY := ""
;; size limits the app has shown us during a resize (0 = none found yet)
global GrabMinW := 0
global GrabMaxW := 0
global GrabMinH := 0
global GrabMaxH := 0

;; the window (and monitor number) that will be maximized if the mouse is released now
global SnapWindow := ""
global SnapMonitor := 0
;; ...and where it will go: "top", "left", "right", "topleft", "topright", "bottomleft" or "bottomright"
global SnapZone := ""
;; the zone the window was in when the drag started. A window that starts out against an edge doesn't
;; snap until it has been somewhere else first (so sliding it along the edge doesn't snap it)
global SnapStartZone := ""
global SnapZoneInit := false
global SnapArmed := false
;; how many frames in a row the window has been outside every zone (see the snap check)
global SnapGrace := 0
;; the snap spot the window is waiting in, and since when (for SnapDelay)
global SnapCandidate := ""
global SnapSince := 0

;; windows we snapped to a half/quarter: window -> [old width, old height, snapped x, y, width, height]
;; so that dragging one away gives it its old size back
global SnappedWindows := Map()

;; The snap preview: two plain click-through windows that never take focus - a thin light ring
;; (the border) and the see-through fill inside it. Plain solid-colour windows don't flicker when they
;; are moved or resized, which a window with a control inside it does.
global PreviewBorder := 2
global PreviewGui := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale +E0x80000 +E0x20 +E0x80 +E0x8000000", "DPaZ snap preview")
PreviewGui.BackColor := "FFFFFF"
DllCall("SetLayeredWindowAttributes", "Ptr", PreviewGui.Hwnd, "UInt", 0, "UChar", PreviewOpacity, "UInt", 2)
global PreviewFillGui := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale +E0x80000 +E0x20 +E0x80 +E0x8000000", "DPaZ snap preview fill")
PreviewFillGui.BackColor := PreviewColor
DllCall("SetLayeredWindowAttributes", "Ptr", PreviewFillGui.Hwnd, "UInt", 0, "UChar", PreviewOpacity, "UInt", 2)
;; "" when hidden, otherwise which zone/monitor it is showing
global PreviewKey := ""
;; where the preview is now, and where it is growing towards: [x, y, width, height]
global PreviewCur := [0, 0, 0, 0]
global PreviewDst := [0, 0, 0, 0]
;; what was last applied to the windows, so we only touch them when something really changed
global PreviewShown := ""
global PreviewShownSize := ""

;; which cursor we're showing right now: "" (the normal ones), "move", "nwse" or "nesw"
global CursorState := ""

;; if an earlier run died in the middle of a drag it may have left a changed cursor behind
RestoreCursor(true)
;; make sure the cursor goes back to normal when the script quits or reloads
OnExit(ExitCleanup)

ExitCleanup(reason, code) {
    RestoreCursor()
}

;; cancel any drag if the PC gets locked (we'd never see the mouse button being released)
try {
    DllCall("wtsapi32\WTSRegisterSessionNotification", "Ptr", A_ScriptHwnd, "UInt", 0)
    OnMessage(0x2B1, OnSessionChange)
}

OnSessionChange(wParam, lParam, msg, hwnd) {
    global DragType
    if (wParam = 7) ; WTS_SESSION_LOCK
        EndDrag(DragType, true)
}

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; HOTKEYS

#LButton:: {
    StartDrag("move")
}
#LButton Up:: {
    EndDrag("move")
}

#RButton:: {
    StartDrag("resize")
}
#RButton Up:: {
    EndDrag("resize")
}

#MButton:: {
    CloseWindowUnderCursor()
}

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; STARTING / ENDING A DRAG

StartDrag(what) {
    global StartX, StartY, PressX, PressY
    global DragActive, DragType, DragMoved, DragId
    global SnapWindow, SnapMonitor

    ;; only one drag at a time (e.g. ignore the right button while moving with the left)
    if (DragActive) {
        ;; ...unless the old drag is clearly dead already
        if (GetKeyState(DragType == "move" ? "LButton" : "RButton", "P"))
            return
        EndDrag(DragType, true)
    }

    ResetGrab()
    MouseGetPos &StartX, &StartY
    PressX := StartX
    PressY := StartY
    DragActive := true
    DragType := what
    DragMoved := false
    SnapWindow := ""
    SnapMonitor := 0

    ;; the drag itself runs as a loop (started from a timer so this hotkey can finish straight away)
    DragId += 1
    SetTimer(DragLoop.Bind(what, DragId), -1)
}

EndDrag(what, cancel := false) {
    global DragActive, DragType, SnapWindow, SnapMonitor, SnapZone

    if (not DragActive || DragType != what)
        return

    DragActive := false
    HideSnapPreview()
    RestoreCursor()

    TargetWindow := SnapWindow
    TargetMonitor := SnapMonitor
    TargetZone := SnapZone
    SnapWindow := ""
    SnapMonitor := 0
    SnapZone := ""
    ResetGrab()

    if (what == "move" && TargetWindow && TargetZone != "" && not cancel)
        SnapWindowTo(TargetWindow, TargetZone, TargetMonitor)
}

ResetGrab() {
    global GrabbedWindow := ""
    global GrabbedHalfX := ""
    global GrabbedHalfY := ""
    global GrabMinW := 0
    global GrabMaxW := 0
    global GrabMinH := 0
    global GrabMaxH := 0
    global DragFocused := false
    global SnapArmed := false
    global SnapZoneInit := false
    global SnapStartZone := ""
    global SnapZone := ""
    global SnapGrace := 0
    global SnapCandidate := ""
}

;; The drag runs as one loop with one update per screen refresh, instead of a timer.
;; (Windows timers tick roughly every 15 ms and unevenly, which is what made it stutter on a 100 Hz monitor.)
DragLoop(what, Id) {
    global DragActive, DragType, DragId, PreviewKey

    while (DragActive && DragType == what && DragId == Id) {
        ;; an update can't be interrupted half way through...
        Critical "On"
        try {
            DoStuffToWindows(what)
            if (PreviewKey != "")
                PreviewAnimate()
        }
        catch {
            ;; never let one bad update kill the whole drag
        }
        Critical "Off"

        ;; ...but in between, other things (like the mouse-up hotkey) get their turn
        WaitForFrame()
    }
}

WaitForFrame() {
    global SyncToRefresh

    if (SyncToRefresh) {
        ;; DwmFlush waits for the next screen refresh. If it can't, fall back to a short sleep.
        if (DllCall("dwmapi\DwmFlush") != 0)
            Sleep 8
    }
    else {
        Sleep 10
    }
    ;; let any waiting hotkeys / messages run
    Sleep -1
}

CloseWindowUnderCursor() {
    global DragActive

    ;; not while a move/resize is going on - we'd close the window being dragged
    if (DragActive)
        return

    try {
        MouseGetPos(, , &Window)
        if (not Window || not WinExist(Window))
            return

        ;; same "is this a normal window" rules as dragging: never the desktop, taskbar,
        ;; Start menu, fullscreen games and so on
        WinGetPos(&X, &Y, &W, &H, Window)
        if (not IsGoodWindow(Window, X, Y, W, H))
            return

        ;; a normal close, exactly like clicking the X - the app can still ask to save first
        WinClose(Window)
    }
    catch {
        ;; window vanished, nothing to do
    }
}

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; MAGIC

DoStuffToWindows(what) {
    global StartX, StartY, PressX, PressY, Busy
    global DragActive, DragType, DragMoved
    global GrabbedWindow, GrabbedHalfX, GrabbedHalfY
    global SnapWindow, SnapMonitor
    global GrabMinW, GrabMaxW, GrabMinH, GrabMaxH
    global FocusOnDrag, DragFocused, SnapArmed, SnapMargin
    global SnapZone, SnapStartZone, SnapZoneInit, SnappedWindows, SnapGrace
    global SnapCandidate, SnapSince, SnapDelay
    global MinWidth, MinHeight, KeepVisible, DragThreshold

    ;; a stray timer from a drag that's already over
    if (not DragActive || DragType != what)
        return

    ;; mouse button isn't held any more - the drag is over
    Button := (what == "move") ? "LButton" : "RButton"
    if not GetKeyState(Button, "P") {
        EndDrag(what)
        return
    }

    ;; if we're already doing something to the window, don't try and clobber it
    if (Busy)
        return
    Busy := true

    NextStartX := StartX
    NextStartY := StartY

    WS_MAXIMIZE := 0x1000000
    WS_MAXIMIZEBOX := 0x10000
    WS_THICKFRAME := 0x40000

    try {
        MouseGetPos &MouseX, &MouseY, &WindowUnderCursor
        NextStartX := MouseX
        NextStartY := MouseY

        ;; has the mouse really been dragged, or is it just a click so far?
        if (not DragMoved && (Abs(MouseX - PressX) >= DragThreshold || Abs(MouseY - PressY) >= DragThreshold))
            DragMoved := true

        if (not GrabbedWindow)
            GrabbedWindow := WindowUnderCursor
        Window := GrabbedWindow

        if (Window && WinExist(Window)) {
            WinGetPos(&X, &Y, &W, &H, Window)

            if (IsGoodWindow(Window, X, Y, W, H)) {
                Style := WinGetStyle(Window)

                ;; move cursor - for a maximized window only once it's really being dragged
                if (what == "move" && (DragMoved || not (Style & WS_MAXIMIZE)))
                    SetDragCursor("move")

                ;; bring the window to the front, once, at the start of the drag
                if (FocusOnDrag && not DragFocused) {
                    DragFocused := true
                    FocusWindow(Window)
                }

                ;; did we snap this window, and is it still exactly where we left it?
                WasSnapped := false
                if (SnappedWindows.Has(Window)) {
                    SnapInfo := SnappedWindows[Window]
                    if (Abs(X - SnapInfo[3]) <= 2 && Abs(Y - SnapInfo[4]) <= 2 && Abs(W - SnapInfo[5]) <= 2 && Abs(H - SnapInfo[6]) <= 2)
                        WasSnapped := true
                    else
                        SnappedWindows.Delete(Window)
                }
                if (WasSnapped && what == "resize") {
                    ;; resizing a snapped window just makes it a normal window again
                    SnappedWindows.Delete(Window)
                    WasSnapped := false
                }

                if (Style & WS_MAXIMIZE) {
                    ;; a maximized window: once the mouse really moves, restore it and put it under
                    ;; the cursor so the cursor stays at the same relative spot on the window
                    if (DragMoved) {
                        FracX := Min(Max((MouseX - X) / W, 0), 1)
                        FracY := Min(Max((MouseY - Y) / H, 0), 1)
                        ;; Windows animates the un-maximize, which looks like a flash when we
                        ;; immediately move the window - so switch the animation off just for this
                        SetWindowAnimations(Window, false)
                        try {
                            WinRestore(Window)
                            WinGetPos(&X, &Y, &W, &H, Window)
                            MoveAndResize(Round(MouseX - FracX * W), Round(MouseY - FracY * H), , , Window)
                        }
                        finally {
                            SetWindowAnimations(Window, true)
                        }
                    }
                }
                else if (WasSnapped) {
                    ;; a snapped window being moved: once the mouse really moves, give it its old size back
                    ;; (the same way a maximized window gets restored)
                    if (DragMoved) {
                        FracX := Min(Max((MouseX - X) / W, 0), 1)
                        FracY := Min(Max((MouseY - Y) / H, 0), 1)
                        SnappedWindows.Delete(Window)
                        MoveAndResize(Round(MouseX - FracX * SnapInfo[1]), Round(MouseY - FracY * SnapInfo[2]), SnapInfo[1], SnapInfo[2], Window)
                    }
                }
                else {
                    ;; size of the whole desktop (all monitors)
                    VL := SysGet(76)
                    VT := SysGet(77)
                    VW := SysGet(78)
                    VH := SysGet(79)

                    if (what == "move") {
                        NewX := X + (MouseX - StartX)
                        NewY := Y + (MouseY - StartY)

                        ;; don't let the window get lost off-screen
                        KeepX := Min(KeepVisible, W)
                        KeepY := Min(KeepVisible, H)
                        NewX := Max(VL - W + KeepX, Min(NewX, VL + VW - KeepX))
                        NewY := Max(VT, Min(NewY, VT + VH - KeepY))

                        MoveAndResize(NewX, NewY, , , Window)

                        ;; only "use up" the movement that was actually applied, so the window
                        ;; doesn't jump when the cursor comes back from beyond a screen edge
                        NextStartX := StartX + (NewX - X)
                        NextStartY := StartY + (NewY - Y)

                        ;; is the mouse against a side or corner of a monitor, or the top of the window against
                        ;; the top of one? then letting go will snap it there
                        GetFrameInsets(Window, X, Y, W, H, &IL, &IT, &IR, &IB)
                        Zone := GetSnapZone(MouseX, MouseY, NewX + IL, NewY + IT, NewX + W - IR, NewY + H - IB, SnapZone, &Mon)

                        ;; a window that starts out in a snap spot has to leave it before it can snap
                        if (not SnapZoneInit) {
                            SnapZoneInit := true
                            SnapStartZone := Zone
                        }
                        if (Zone == "" || Zone != SnapStartZone)
                            SnapArmed := true

                        ;; top = maximize, which needs a maximize button. The rest need a resizable border.
                        CanSnap := (Zone == "top") ? (Style & WS_MAXIMIZEBOX) : (Style & WS_THICKFRAME)

                        if (Zone != "" && SnapArmed && DragMoved && CanSnap) {
                            ;; how long has it been waiting in this spot?
                            Candidate := Zone "|" Mon
                            if (Candidate != SnapCandidate) {
                                SnapCandidate := Candidate
                                SnapSince := A_TickCount
                            }

                            if (A_TickCount - SnapSince >= SnapDelay) {
                                SnapGrace := 0
                                SnapWindow := Window
                                SnapMonitor := Mon
                                SnapZone := Zone
                                ShowSnapPreview(Zone, Mon, Window)
                            }
                        }
                        else if (SnapWindow && SnapGrace < 4) {
                            ;; outside every spot for a frame or two - most likely a wobble right at the
                            ;; edge, so keep the preview up instead of hiding it and showing it again
                            SnapGrace += 1
                        }
                        else {
                            SnapGrace := 0
                            SnapCandidate := ""
                            SnapWindow := ""
                            SnapMonitor := 0
                            SnapZone := ""
                            HideSnapPreview()
                        }
                    }
                    else if (Style & WS_THICKFRAME) {
                        ;; resizing - only for windows that have a resizable border

                        ;; figure out which quarter of the window we're in so we can "drag" that corner
                        if (not GrabbedHalfX || not GrabbedHalfY) {
                            GrabbedHalfX := (MouseX < X + W / 2) ? "left" : "right"
                            GrabbedHalfY := (MouseY < Y + H / 2) ? "top" : "bottom"
                        }

                        ;; top-left / bottom-right corners get the \ arrow, the other two get the / arrow
                        SameDiagonal := ((GrabbedHalfX == "left") == (GrabbedHalfY == "top"))
                        SetDragCursor(SameDiagonal ? "nwse" : "nesw")

                        ;; how much the mouse moved, in the direction that grows the window
                        DeltaX := MouseX - StartX
                        DeltaY := MouseY - StartY
                        if (GrabbedHalfX == "left")
                            DeltaX *= -1
                        if (GrabbedHalfY == "top")
                            DeltaY *= -1

                        ;; new size: not smaller than the minimum, not bigger than the desktop
                        ;; (windows already outside those limits are never forced to change by the limit)
                        NewW := Min(Max(W + DeltaX, Min(MinWidth, W)), Max(VW, W))
                        NewH := Min(Max(H + DeltaY, Min(MinHeight, H)), Max(VH, H))

                        ;; limits this app already showed us earlier in the drag
                        if (GrabMinW)
                            NewW := Max(NewW, GrabMinW)
                        if (GrabMaxW)
                            NewW := Min(NewW, GrabMaxW)
                        if (GrabMinH)
                            NewH := Max(NewH, GrabMinH)
                        if (GrabMaxH)
                            NewH := Min(NewH, GrabMaxH)

                        ;; keep the opposite corner fixed
                        NewX := (GrabbedHalfX == "left") ? X + W - NewW : X
                        NewY := (GrabbedHalfY == "top") ? Y + H - NewH : Y
                        MoveAndResize(NewX, NewY, NewW, NewH, Window)

                        ;; the app may have refused the size we asked for (its own min/max size) - see what we got
                        WinGetPos(, , &ActualW, &ActualH, Window)

                        ;; if it refused, remember where its limit is so the next ticks ask for that
                        ;; straight away instead of asking for too much and correcting every time
                        if (ActualW > NewW)
                            GrabMinW := ActualW
                        else if (ActualW < NewW)
                            GrabMaxW := ActualW
                        if (ActualH > NewH)
                            GrabMinH := ActualH
                        else if (ActualH < NewH)
                            GrabMaxH := ActualH

                        if (ActualW != NewW || ActualH != NewH) {
                            NewX := (GrabbedHalfX == "left") ? X + W - ActualW : X
                            NewY := (GrabbedHalfY == "top") ? Y + H - ActualH : Y
                            MoveAndResize(NewX, NewY, , , Window)
                        }

                        ;; only "use up" the mouse movement that actually changed the window
                        AppliedX := ActualW - W
                        AppliedY := ActualH - H
                        if (GrabbedHalfX == "left")
                            AppliedX *= -1
                        if (GrabbedHalfY == "top")
                            AppliedY *= -1
                        NextStartX := StartX + AppliedX
                        NextStartY := StartY + AppliedY
                    }
                }
            }
        }
    }
    catch {
        ;; the window probably disappeared mid-drag, or it is not allowed to be touched
        ;; (e.g. an elevated window) - nothing sensible to do, just carry on
    }
    finally {
        ;; whatever happened, make sure the script can never get "stuck"
        StartX := NextStartX
        StartY := NextStartY
        Busy := false
    }
}

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; SNAP TO TOP (MAXIMIZE)

;; Returns the number of the monitor the point is on, or 0.
GetMonitorAt(PX, PY) {
    Loop MonitorGetCount() {
        MonitorGet(A_Index, &ML, &MT, &MR, &MB)
        if (PX >= ML && PX < MR && PY >= MT && PY < MB)
            return A_Index
    }
    return 0
}

PointOnAnyMonitor(PX, PY) {
    Loop MonitorGetCount() {
        MonitorGet(A_Index, &ML, &MT, &MR, &MB)
        if (PX >= ML && PX < MR && PY >= MT && PY < MB)
            return true
    }
    return false
}

;; Works out which snap zone the drag is in. Returns "top", "left", "right", "topleft", "topright",
;; "bottomleft", "bottomright" or "", and sets ZoneMon to the monitor it is on.
;;
;; Sides and corners go by the MOUSE (it gets pushed against the edge of its monitor).
;; The top (maximize) goes by the WINDOW: the top of the window reaching the top of the monitor it is on.
;; That way the top still works on a monitor that has another one above it, where the mouse
;; would just carry on up onto the other screen.
GetSnapZone(MouseX, MouseY, VisLeft, VisTop, VisRight, VisBottom, PrevZone, &ZoneMon) {
    global SideMargin, SharedSideMargin, CornerSize, SnapMargin

    ZoneMon := 0
    Mon := GetMonitorAt(MouseX, MouseY)
    if (not Mon)
        return ""
    MonitorGet(Mon, &ML, &MT, &MR, &MB)

    ;; once you're in a spot it takes a bit more to leave it again. Without that, sitting right on the
    ;; margin flips in and out every frame and the preview flickers.
    Extra := 8

    ;; how close the mouse has to be to each side - wider where another monitor is on the other side of it
    MarginL := (PointOnAnyMonitor(ML - 1, MouseY) ? SharedSideMargin : SideMargin) + (InStr(PrevZone, "left") ? Extra : 0)
    MarginR := (PointOnAnyMonitor(MR, MouseY) ? SharedSideMargin : SideMargin) + (InStr(PrevZone, "right") ? Extra : 0)
    MarginT := (PointOnAnyMonitor(MouseX, MT - 1) ? SharedSideMargin : SideMargin) + (InStr(PrevZone, "top") ? Extra : 0)
    MarginB := (PointOnAnyMonitor(MouseX, MB) ? SharedSideMargin : SideMargin) + (InStr(PrevZone, "bottom") ? Extra : 0)

    NearLeft := (MouseX <= ML + MarginL)
    NearRight := (MouseX >= MR - MarginR)
    NearTop := (MouseY <= MT + MarginT)
    NearBottom := (MouseY >= MB - MarginB)

    ;; the mouse is against the left or right side: a half, or a quarter if it's up in a corner
    if (NearLeft != NearRight) {
        Horizontal := NearLeft ? "left" : "right"
        Vertical := ""
        if (MouseY <= MT + CornerSize)
            Vertical := "top"
        else if (MouseY >= MB - CornerSize)
            Vertical := "bottom"
        ZoneMon := Mon
        return Vertical . Horizontal
    }

    ;; the mouse is against the top or bottom and has slid along it into a corner: a quarter
    if (NearTop != NearBottom) {
        Vertical := NearTop ? "top" : "bottom"
        Horizontal := ""
        if (MouseX <= ML + CornerSize)
            Horizontal := "left"
        else if (MouseX >= MR - CornerSize)
            Horizontal := "right"
        if (Horizontal != "") {
            ZoneMon := Mon
            return Vertical . Horizontal
        }
    }

    ;; the top of the window against the top of the monitor the window is mostly on: maximize
    WinMon := GetMonitorAt((VisLeft + VisRight) // 2, (VisTop + VisBottom) // 2)
    if (not WinMon)
        WinMon := Mon
    MonitorGet(WinMon, &WL, &WT, &WR, &WB)
    if (VisTop <= WT + SnapMargin + (InStr(PrevZone, "top") ? Extra : 0)) {
        ZoneMon := WinMon
        return "top"
    }

    return ""
}

;; The area (inside the taskbar) a window in this zone should fill.
GetZoneRect(Zone, MonitorNumber, &L, &T, &R, &B) {
    MonitorGetWorkArea(MonitorNumber, &L, &T, &R, &B)
    if (Zone == "top")
        return
    MidX := L + (R - L) // 2
    MidY := T + (B - T) // 2
    if (InStr(Zone, "left"))
        R := MidX
    if (InStr(Zone, "right"))
        L := MidX
    if (InStr(Zone, "top"))
        B := MidY
    if (InStr(Zone, "bottom"))
        T := MidY
}

;; The part of a window you can actually see. Windows 10/11 windows have an invisible border
;; around them, so this is a bit smaller than what WinGetPos says.
GetFrameRect(window, &FX, &FY, &FW, &FH) {
    WinGetPos(&FX, &FY, &FW, &FH, window)
    try {
        Rect := Buffer(16, 0)
        ;; DWMWA_EXTENDED_FRAME_BOUNDS = 9
        if (DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", window, "UInt", 9, "Ptr", Rect, "UInt", 16) == 0) {
            FX := NumGet(Rect, 0, "Int")
            FY := NumGet(Rect, 4, "Int")
            FW := NumGet(Rect, 8, "Int") - FX
            FH := NumGet(Rect, 12, "Int") - FY
        }
    }
}

;; How thick that invisible border is on each side (X, Y, W, H = the window's WinGetPos rectangle).
GetFrameInsets(window, X, Y, W, H, &IL, &IT, &IR, &IB) {
    GetFrameRect(window, &FX, &FY, &FW, &FH)
    IL := FX - X
    IT := FY - Y
    IR := (X + W) - (FX + FW)
    IB := (Y + H) - (FY + FH)
}

;; Shows the preview. It starts out where the dragged window is and grows into the snap area,
;; and slides from one area to the next if you move between zones.
ShowSnapPreview(Zone, MonitorNumber, window) {
    global PreviewKey, PreviewCur, PreviewDst, PreviewGui, PreviewFillGui, PreviewShown

    Key := Zone "|" MonitorNumber
    if (Key == PreviewKey)
        return

    GetZoneRect(Zone, MonitorNumber, &L, &T, &R, &B)
    PreviewDst := [L, T, R - L, B - T]

    if (PreviewKey == "") {
        GetFrameRect(window, &FX, &FY, &FW, &FH)
        PreviewCur := [FX, FY, FW, FH]

        ;; get the shape and position right while it's still hidden, so nothing old flashes up
        ApplyPreviewRect()
        PreviewGui.Show(Format("NA x{} y{} w{} h{}", PreviewShown[1], PreviewShown[2], PreviewShown[3], PreviewShown[4]))
        PreviewFillGui.Show(Format("NA x{} y{} w{} h{}", PreviewShown[1] + PreviewBorder, PreviewShown[2] + PreviewBorder, PreviewShown[3] - 2 * PreviewBorder, PreviewShown[4] - 2 * PreviewBorder))
    }

    PreviewKey := Key
}

;; one animation step, called once per frame by the drag loop
PreviewAnimate() {
    global PreviewCur, PreviewDst

    Changed := false
    Loop 4 {
        Diff := PreviewDst[A_Index] - PreviewCur[A_Index]
        if (Diff == 0)
            continue
        Changed := true
        if (Abs(Diff) < 1.5)
            PreviewCur[A_Index] := PreviewDst[A_Index]
        else
            PreviewCur[A_Index] += Diff * 0.3
    }
    if (Changed)
        ApplyPreviewRect()
}

ApplyPreviewRect() {
    global PreviewGui, PreviewFillGui, PreviewCur, PreviewRadius, PreviewBorder
    global PreviewShown, PreviewShownSize

    X := Round(PreviewCur[1])
    Y := Round(PreviewCur[2])
    W := Max(Round(PreviewCur[3]), 16)
    H := Max(Round(PreviewCur[4]), 16)

    ;; nothing moved by a whole pixel since last time? then leave the windows alone
    if (IsObject(PreviewShown) && PreviewShown[1] == X && PreviewShown[2] == Y && PreviewShown[3] == W && PreviewShown[4] == H)
        return
    PreviewShown := [X, Y, W, H]

    FillW := W - 2 * PreviewBorder
    FillH := H - 2 * PreviewBorder

    PreviewGui.Move(X, Y, W, H)
    PreviewFillGui.Move(X + PreviewBorder, Y + PreviewBorder, FillW, FillH)

    ;; the rounded corners only need rebuilding when the size changes, not when it just moves
    SizeKey := W "x" H
    if (SizeKey == PreviewShownSize)
        return
    PreviewShownSize := SizeKey

    Radius := PreviewRadius
    FillRadius := Max(Radius - PreviewBorder, 0)

    ;; the border window is only the ring between the outer and the inner rounded rectangle...
    Outer := DllCall("CreateRoundRectRgn", "Int", 0, "Int", 0, "Int", W + 1, "Int", H + 1, "Int", Radius * 2, "Int", Radius * 2, "Ptr")
    Inner := DllCall("CreateRoundRectRgn", "Int", PreviewBorder, "Int", PreviewBorder, "Int", W - PreviewBorder + 1, "Int", H - PreviewBorder + 1, "Int", FillRadius * 2, "Int", FillRadius * 2, "Ptr")
    DllCall("CombineRgn", "Ptr", Outer, "Ptr", Outer, "Ptr", Inner, "Int", 4) ; RGN_DIFF
    DllCall("DeleteObject", "Ptr", Inner)
    DllCall("SetWindowRgn", "Ptr", PreviewGui.Hwnd, "Ptr", Outer, "Int", true)

    ;; ...and the fill window is the inner one
    FillRegion := DllCall("CreateRoundRectRgn", "Int", 0, "Int", 0, "Int", FillW + 1, "Int", FillH + 1, "Int", FillRadius * 2, "Int", FillRadius * 2, "Ptr")
    DllCall("SetWindowRgn", "Ptr", PreviewFillGui.Hwnd, "Ptr", FillRegion, "Int", true)
}

HideSnapPreview() {
    global PreviewGui, PreviewFillGui, PreviewKey, PreviewShown, PreviewShownSize
    if (PreviewKey == "")
        return
    PreviewKey := ""
    PreviewShown := ""
    PreviewShownSize := ""
    PreviewGui.Hide()
    PreviewFillGui.Hide()
}

;; Snaps a window to a zone: the top maximizes it, everything else fills half or a quarter of the screen.
SnapWindowTo(window, Zone, MonitorNumber) {
    global SnappedWindows
    WS_MAXIMIZE := 0x1000000

    if (Zone == "top") {
        SnapMaximize(window, MonitorNumber)
        return
    }

    try {
        if (not WinExist(window))
            return
        if (WinGetStyle(window) & WS_MAXIMIZE)
            return

        WinGetPos(&X, &Y, &W, &H, window)
        GetZoneRect(Zone, MonitorNumber, &L, &T, &R, &B)
        GetFrameInsets(window, X, Y, W, H, &IL, &IT, &IR, &IB)

        ;; make the visible part of the window fill the area exactly (the invisible border hangs outside it)
        MoveAndResize(L - IL, T - IT, (R - L) + IL + IR, (B - T) + IT + IB, window)

        ;; remember the old size so dragging the window away puts it back
        WinGetPos(&AX, &AY, &AW, &AH, window)
        SnappedWindows[window] := [W, H, AX, AY, AW, AH]
    }
    catch {
        ;; window vanished, or we're not allowed to touch it
    }
}

SnapMaximize(window, MonitorNumber) {
    WS_MAXIMIZE := 0x1000000
    try {
        if (not WinExist(window))
            return
        if (WinGetStyle(window) & WS_MAXIMIZE)
            return

        ;; Windows maximizes a window onto whichever monitor it mostly sits on. Make sure that's the
        ;; monitor the cursor is on (matters when the window is wider than the monitor it's pushed up against).
        MonitorGet(MonitorNumber, &ML, &MT, &MR, &MB)
        WinGetPos(&X, &Y, &W, &H, window)
        NewX := Max(ML, Min(X, MR - W))
        NewY := Max(MT, Min(Y, MB - H))
        if (NewX != X || NewY != Y)
            MoveAndResize(NewX, NewY, , , window)

        WinMaximize(window)
    }
    catch {
        ;; window vanished, or we're not allowed to touch it
    }
}

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; CURSOR

;; Swaps every system cursor (arrow, text beam, hand, etc.) for the one we want, so it shows
;; no matter what is under the mouse. RestoreCursor puts the user's real cursors back.
SetDragCursor(kind) {
    global CursorState
    if (kind == CursorState)
        return

    ;; IDC_SIZEALL, IDC_SIZENWSE, IDC_SIZENESW
    IdcId := (kind == "move") ? 32646 : ((kind == "nwse") ? 32642 : 32643)

    ;; make our own copy first - Windows destroys whatever cursor we hand it, and the
    ;; one LoadCursor gives back is shared with the system
    Master := DllCall("CopyImage", "Ptr", DllCall("LoadCursor", "Ptr", 0, "Ptr", IdcId, "Ptr"), "UInt", 2, "Int", 0, "Int", 0, "UInt", 0, "Ptr")
    if (not Master)
        return

    for SlotId in [32512, 32513, 32514, 32515, 32516, 32642, 32643, 32644, 32645, 32646, 32648, 32649, 32650, 32651] {
        CursorCopy := DllCall("CopyImage", "Ptr", Master, "UInt", 2, "Int", 0, "Int", 0, "UInt", 0, "Ptr")
        if (CursorCopy)
            DllCall("SetSystemCursor", "Ptr", CursorCopy, "UInt", SlotId)
    }
    DllCall("DestroyCursor", "Ptr", Master)

    CursorState := kind
}

RestoreCursor(force := false) {
    global CursorState
    if (CursorState == "" && not force)
        return
    CursorState := ""
    ;; SPI_SETCURSORS - reload the user's cursors from their Windows settings
    DllCall("SystemParametersInfo", "UInt", 0x57, "UInt", 0, "Ptr", 0, "UInt", 0)
}

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; HELPERS

FocusWindow(window) {
    try {
        WinActivate(window)
    }
}

SetWindowAnimations(window, enable) {
    try {
        ;; DWMWA_TRANSITIONS_FORCEDISABLED = 3
        Disabled := Buffer(4, 0)
        NumPut("Int", enable ? 0 : 1, Disabled)
        DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", window, "UInt", 3, "Ptr", Disabled, "UInt", 4)
    }
}

IsGoodWindow(window, X, Y, W, H) {
    try {
        ;; Skip tiny windows
        if (W < 2 || H < 2)
            return false

        ;; Skip windows that aren't responding - moving one would hang this script as well
        if (DllCall("IsHungAppWindow", "Ptr", window))
            return false

        ;; Skip the desktop, taskbar, and other parts of the Windows shell
        WinClassName := WinGetClass(window)
        for shellClass in ["Progman", "WorkerW", "Shell_TrayWnd", "Shell_SecondaryTrayWnd"
                         , "Windows.UI.Core.CoreWindow", "NotifyIconOverflowWindow"
                         , "TopLevelWindowForOverflowXamlIsland"] {
            if (WinClassName = shellClass)
                return false
        }

        ;; Skip disabled or minimized windows
        Style := WinGetStyle(window)
        WS_DISABLED := 0x8000000
        WS_MINIMIZE := 0x20000000
        if (Style & WS_DISABLED || Style & WS_MINIMIZE)
            return false

        ;; Skip fullscreen apps (games, videos): no title bar and covering a whole monitor
        WS_CAPTION := 0xC00000
        WS_MAXIMIZE := 0x1000000
        if (not (Style & WS_CAPTION) && not (Style & WS_MAXIMIZE)) {
            Loop MonitorGetCount() {
                MonitorGet(A_Index, &ML, &MT, &MR, &MB)
                if (X <= ML && Y <= MT && X + W >= MR && Y + H >= MB)
                    return false
            }
        }

        ;; Skip fully transparent windows
        Trans := WinGetTransparent(window)
        if (Trans == 0)
            return false

        ;; Skip windows with no title
        Title := WinGetTitle(window)
        if (Title == "" || Title == "Transparent Window")
            return false

        return true
    }
    catch {
        ;; window vanished while we were looking at it
        return false
    }
}

MoveAndResize(WindowX, WindowY, WindowWidth := "", WindowHeight := "", Window := "") {
    ;; Plain SetWindowPos flags on purpose. Skipping the redraw / copy-bits steps and then repainting
    ;; by hand is what made windows flicker - Windows repaints them far better by itself.
    ;; SWP_NOSENDCHANGING is also left out, so windows get to apply their own min/max sizes.
    ;; SWP_NOACTIVATE: moving/resizing never changes focus by itself - that's the FocusOnDrag setting.
    SWP_NOSIZE := 0x0001
    SWP_NOZORDER := 0x0004
    SWP_NOACTIVATE := 0x0010
    Flags := SWP_NOZORDER | SWP_NOACTIVATE
    try {
        if (WindowWidth && WindowHeight) {
            DllCall("SetWindowPos", "Ptr", Window, "Ptr", 0, "Int", Round(WindowX), "Int", Round(WindowY), "Int", Round(WindowWidth), "Int", Round(WindowHeight), "UInt", Flags)
        }
        else {
            Flags |= SWP_NOSIZE
            DllCall("SetWindowPos", "Ptr", Window, "Ptr", 0, "Int", Round(WindowX), "Int", Round(WindowY), "Int", 0, "Int", 0, "UInt", Flags)
        }
    }
    catch {
        ;; not a lot we can do here...
    }
}
