#Requires AutoHotkey v2.0
#SingleInstance Force

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Based on DPaZ by sebmaynard
;; Modified by HardBucks (with Claude): Win-only hotkeys, removed pan/zoom, snap-to-maximize, multi-monitor fixes, etc.
;; Move and resize windows by holding the Windows key and
;; dragging with the mouse.
;;
;;    Win + Left mouse:  Move the window under the cursor
;;    Win + Right mouse: Resize the window under the cursor
;;
;; - Drag a window to the top edge of a monitor and let go to maximize it
;;   (a blue preview shows what will happen)
;; - Grabbing a maximized window restores it first
;; - Windows can't be shrunk below a minimum size, or grown beyond the screen
;; - Windows can't be dragged completely off-screen
;; - Fixed-size windows, fullscreen apps, the desktop and the taskbar are left alone
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

DetectHiddenWindows false
SetWinDelay -1
CoordMode "Mouse", "Screen"
A_MaxHotkeysPerInterval := 1000

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; SETTINGS

;; smallest size (pixels) a window can be shrunk to
;; (a window that is already smaller than this can't shrink further, but can still grow)
global MinWidth := 200
global MinHeight := 120

;; how many pixels of a window must stay on screen when you drag it towards an edge
global KeepVisible := 100

;; how close (pixels) the cursor has to be to the top of a monitor to maximize
global SnapMargin := 3

;; how far (pixels) you have to drag before a click turns into a drag
;; (so a plain Win+click on a maximized window doesn't un-maximize it)
global DragThreshold := 6

;; how often (ms) the drag is updated
global delay := 10

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

;; the window we "grabbed" - so we don't accidentally grab another one during move/resize
global GrabbedWindow := ""
;; which half of the window we grabbed when resizing - "left"/"right"/"" and "top"/"bottom"/""
global GrabbedHalfX := ""
global GrabbedHalfY := ""

;; the window (and monitor number) that will be maximized if the mouse is released now
global SnapWindow := ""
global SnapMonitor := 0

;; the blue "this will be maximized" rectangle - click-through, never takes focus
global PreviewGui := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale +E0x80000 +E0x20 +E0x80 +E0x8000000", "DPaZ snap preview")
PreviewGui.BackColor := "3B82F6"
DllCall("SetLayeredWindowAttributes", "Ptr", PreviewGui.Hwnd, "UInt", 0, "UChar", 90, "UInt", 2)
global PreviewRect := ""

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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; STARTING / ENDING A DRAG

StartDrag(what) {
    global StartX, StartY, PressX, PressY
    global DragActive, DragType, DragMoved
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

    SetTimer(what == "move" ? MoveWindow : ResizeWindow, -delay)
}

EndDrag(what, cancel := false) {
    global DragActive, DragType, SnapWindow, SnapMonitor

    if (not DragActive || DragType != what)
        return

    DragActive := false
    SetTimer MoveWindow, 0
    SetTimer ResizeWindow, 0
    HideSnapPreview()

    TargetWindow := SnapWindow
    TargetMonitor := SnapMonitor
    SnapWindow := ""
    SnapMonitor := 0
    ResetGrab()

    if (what == "move" && TargetWindow && not cancel)
        SnapMaximize(TargetWindow, TargetMonitor)
}

ResetGrab() {
    global GrabbedWindow := ""
    global GrabbedHalfX := ""
    global GrabbedHalfY := ""
}

MoveWindow() {
    DoStuffToWindows("move")
}

ResizeWindow() {
    DoStuffToWindows("resize")
}

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; MAGIC

DoStuffToWindows(what) {
    ;; don't let the mouse-up hotkey butt in half way through an update
    Critical

    global StartX, StartY, PressX, PressY, Busy
    global DragActive, DragType, DragMoved
    global GrabbedWindow, GrabbedHalfX, GrabbedHalfY
    global SnapWindow, SnapMonitor
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

                if (Style & WS_MAXIMIZE) {
                    ;; a maximized window: once the mouse really moves, restore it and put it under
                    ;; the cursor so the cursor stays at the same relative spot on the window
                    if (DragMoved) {
                        FracX := Min(Max((MouseX - X) / W, 0), 1)
                        FracY := Min(Max((MouseY - Y) / H, 0), 1)
                        WinRestore(Window)
                        WinGetPos(&X, &Y, &W, &H, Window)
                        MoveAndResize(Round(MouseX - FracX * W), Round(MouseY - FracY * H), , , Window)
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

                        ;; at the top edge of a monitor? then letting go will maximize
                        Mon := GetSnapMonitor(MouseX, MouseY)
                        if (Mon && DragMoved && (Style & WS_MAXIMIZEBOX)) {
                            SnapWindow := Window
                            SnapMonitor := Mon
                            ShowSnapPreview(Mon)
                        }
                        else {
                            SnapWindow := ""
                            SnapMonitor := 0
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

                        ;; keep the opposite corner fixed
                        NewX := (GrabbedHalfX == "left") ? X + W - NewW : X
                        NewY := (GrabbedHalfY == "top") ? Y + H - NewH : Y
                        MoveAndResize(NewX, NewY, NewW, NewH, Window)

                        ;; the app may have refused the size we asked for (its own min/max size) - see what we got
                        WinGetPos(, , &ActualW, &ActualH, Window)
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

                SetTimer(ResumeRedraw.Bind(Window), -delay)
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

    if (DragActive)
        SetTimer(what == "move" ? MoveWindow : ResizeWindow, -delay)
}

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; SNAP TO TOP (MAXIMIZE)

;; Returns the number of the monitor whose top edge the cursor is pushing against, or 0.
;; If another monitor sits directly above that spot, the cursor can just carry on up
;; onto it, so that's not an "edge" and we return 0.
GetSnapMonitor(MouseX, MouseY) {
    global SnapMargin
    Loop MonitorGetCount() {
        MonitorGet(A_Index, &ML, &MT, &MR, &MB)
        if (MouseX >= ML && MouseX < MR && MouseY >= MT && MouseY < MB) {
            if (MouseY > MT + SnapMargin)
                return 0
            if (PointOnAnyMonitor(MouseX, MT - 1))
                return 0
            return A_Index
        }
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

ShowSnapPreview(MonitorNumber) {
    global PreviewGui, PreviewRect
    MonitorGetWorkArea(MonitorNumber, &L, &T, &R, &B)
    Rect := L "," T "," R "," B
    if (Rect == PreviewRect)
        return
    PreviewRect := Rect
    PreviewGui.Show(Format("NA x{} y{} w{} h{}", L, T, R - L, B - T))
}

HideSnapPreview() {
    global PreviewGui, PreviewRect
    if (PreviewRect == "")
        return
    PreviewRect := ""
    PreviewGui.Hide()
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
;; HELPERS

ResumeRedraw(window) {
    try {
        SendMessage(0xB, 1, 0, , window) ; wParam 1 enables redraw
        ; force a redraw
        DllCall("RedrawWindow", "Ptr", WinExist(window), "Ptr", 0, "Ptr", 0, "UInt", 0x85)
    }
    catch {
        ;; window closed in the meantime
    }
}

IsGoodWindow(window, X, Y, W, H) {
    try {
        ;; Skip tiny windows
        if (W < 2 || H < 2)
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
    ;; Note: SWP_NOSENDCHANGING is deliberately NOT used, so that windows get to apply
    ;; their own minimum/maximum size limits instead of being forced to any size.
    SWP_NOREDRAW := 0x0008
    SWP_DEFERERASE := 0x2000
    SWP_NOCOPYBITS := 0x0100
    SWP_NOZORDER := 0x0004
    Flags := SWP_NOREDRAW | SWP_DEFERERASE | SWP_NOCOPYBITS | SWP_NOZORDER
    try {
        if (WindowWidth && WindowHeight) {
            DllCall("SetWindowPos", "Ptr", Window, "Ptr", 0, "Int", Round(WindowX), "Int", Round(WindowY), "Int", Round(WindowWidth), "Int", Round(WindowHeight), "UInt", Flags)
        }
        else {
            SWP_NOSIZE := 0x0001
            Flags |= SWP_NOSIZE
            DllCall("SetWindowPos", "Ptr", Window, "Ptr", 0, "Int", Round(WindowX), "Int", Round(WindowY), "Int", 0, "Int", 0, "UInt", Flags)
        }
    }
    catch {
        ;; not a lot we can do here...
    }
}
