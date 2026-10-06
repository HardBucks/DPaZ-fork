# This is vibecoded slop, I have no idea what am doing‼️‼️

# HardBucks' Fork DPaZ

I really like how linux lets you drag windows around with a hotkey. I tried AltDrag but it has alot of bugs, and I didn't like PowerToys' Move and Grab because of the white foreground overlay.
So I took sebmaynard's [DPaZ](https://github.com/sebmaynard/DPaZ) ahk script and i modify with it using Claude (vibecoding maxxing) and try to make a better version for myself.
Also this script is very basic and it uses ahk. there is probably better alternatives out there, I'm just doing this for personal use
forgive me if I'm making a repository wrong because I've never used GitHub lol.

(rest of this text are ai now)
## Demo

https://github.com/user-attachments/assets/a724f132-2bff-4300-9d6d-e888f9dd340a

## Mappings

| Binding             | Action          |
| ------------------- | --------------- |
| `Win`+`left mouse`  | move a window   |
| `Win`+`right mouse` | resize a window |
| `Win`+`middle mouse` | close a window (normal close, same as clicking the X) |

## What's different from the original

- it's just `Win` now, not `Ctrl`+`Win`
- I took out the pan and zoom stuff. I only wanted move and resize
- snapping like windows has, but it goes by the window and not the cursor. push a window against the top and let go to maximize it, against the left or right for half the screen, or into a corner for a quarter. a see-through preview grows out of the window first so you know where it's going
- drag a snapped window away and it gets its old size back
- dragging updates once per screen refresh, so on a 100Hz or 144Hz monitor it follows your refresh rate instead of a fixed timer
- the cursor changes while you drag. you get the move arrows when moving, and when resizing you get the diagonal arrow that matches the corner you grabbed
- dragging a maximized window un-maximizes it. it only does it once you actually drag, so a plain click won't mess with it
- windows can't get shrunk to nothing anymore, and you can't drag one all the way off the screen
- dialogs and other windows that aren't meant to be resized won't get resized, and windows with no maximize button won't snap
- middle click closes the window under the mouse. it's a normal close like the X button, so apps can still ask you to save
- it leaves the desktop, the taskbar and fullscreen stuff (games, videos) alone
- works with more than one monitor
- holding left and right click at the same time used to fight over the same window. now whichever one you press first wins
- if you lock your pc in the middle of a drag it cancels the drag

## Installation

It's a short [AutoHotkey](https://www.autohotkey.com/) (v2) script, so install that, then run `DPaZ.ahk` and you should be good to go.

If you want it to start when you log in:

1. put `DPaZ.ahk` somewhere it can stay (I use `%localappdata%\AutoHotkey`)
2. press `Win`+`R`, type `shell:startup` and hit enter
3. make a shortcut to `DPaZ.ahk` and put it in that folder
## Settings

- `MinWidth` / `MinHeight`: smallest a window can be resized to
- `KeepVisible`: how much of a window has to stay on screen
- `SnapMargin`: how close the edge of a window has to get to the edge of the screen to snap
- `PreviewColor` / `PreviewOpacity` / `PreviewRadius`: how the snap preview looks
- `DragThreshold`: how far you have to drag before a click counts as a drag
- `SyncToRefresh`: `true` updates the window once per screen refresh, `false` goes back to a plain 10ms timer if the sync ever acts up
- `FocusOnDrag`: `true` brings the window to the front and focuses it when you start dragging, `false` leaves focus alone

## Stuff that doesn't work

- windows running as admin (like Task Manager) can't be moved unless the script runs as admin too
- if a UAC prompt pops up while you're dragging, the script can get stuck dragging. just click again and it goes away
- some apps draw their own window frame and might act weird. no promises it works on everything

## Credits

Original script by [sebmaynard](https://github.com/sebmaynard/DPaZ).
