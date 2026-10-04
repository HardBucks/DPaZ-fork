# HardBucks' Fork DPaZ

I really like how linux lets you drag windows around with a hotkey. I tried AltDrag but it has alot of bugs, and I didn't like PowerToys' Move and Grab because of the white foreground overlay.

So I took sebmaynard's [DPaZ](https://github.com/sebmaynard/DPaZ) script and messed with it using Claude (vibecoding maxxing) and try to make a better version for myself.

Also this script is very basic there is probably better alternatives out there, I'm just doing this for personal use

## Demo

https://github.com/user-attachments/assets/96829a9c-c76e-44e4-998c-08fb9ca14285

## Mappings

|Binding|Action|
|---|---|
|`Win`+`left mouse`|move a window|
|`Win`+`right mouse`|resize a window|

## Stuff I added

- I chnaged the hotkey into `Win` now, not `Ctrl`+`Win`
- I took out the pan and zoom stuff. I only wanted move and resize
- dragging a window to the top of the screen maximizes a window and a blue box shows up
- dragging a maximized window un-maximizes it
- windows can't get shrunk to nothing anymore, and you can't drag one all the way off the screen
- dialogs and other windows that aren't meant to be resized won't get resized
- it excluded apps like games with fullscreen and other apps that is fullscreen
- holding left and right click at the same time used to fight over the same window. now fixed
- if you lock your pc in the middle of a drag it cancels the drag
- cursor changed when you dragging
- window focuses when you dragging

## Installation

It's a short [AutoHotkey](https://www.autohotkey.com/) (v2) script, so install that, then run `DPaZ.ahk` and you should be good to go.

If you want it to start when you log in:

1. put `DPaZ.ahk` somewhere it can stay (I use `%localappdata%\AutoHotkey`)
2. press `Win`+`R`, type `shell:startup` and hit enter
3. make a shortcut to `DPaZ.ahk` and put it in that folder
## Settings

- `MinWidth` / `MinHeight`: smallest a window can be resized to
- `KeepVisible`: how much of a window has to stay on screen
- `SnapMargin`: how close to the top of the screen you need to be to maximize
- `DragThreshold`: how far you have to drag before a click counts as a drag
- `FocusOnDrag`: focuses window when you're dragging

## Stuff that doesn't work

- windows running as admin (like Task Manager) can't be moved unless the script runs as admin too
- if a UAC prompt pops up while you're dragging, the script can get stuck dragging. just click again and it goes away
- some apps draw their own window frame and might act weird. so no promises it works on everything

## Credits

Original script by [sebmaynard](https://github.com/sebmaynard/DPaZ). I just changed stuff

forgive me if I'm making a repository wrong because I've never used GitHub lol.
I will probably never update this so don't ask me for suggestions
