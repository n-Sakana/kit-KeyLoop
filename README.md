# KeyLoop

A key sender for Windows. When the PC has had no keyboard or mouse input for a set time, KeyLoop sends the key you chose, and keeps sending it at that interval. It runs on Windows PowerShell 5.1 alone and needs no administrator rights.

## Install and start

Put the folder in a fixed place and run `install.bat`. It registers only under HKCU for the current user, shows the result, and waits for a key before closing. Right-click an empty area of an Explorer folder or of the desktop and choose `KeyLoop`. It is not added to the menu of selected files or folders.

The `KeyLoop` submenu has `Default` and `Custom...`.

- `Default`: idle time 120 seconds, no run time limit, key `0x07`.
- `Custom...`: choose the idle time, the run time and the key on screen.

From the right-click menu, KeyLoop opens in the classic console window (conhost), even where Windows Terminal is the default terminal, so the window fits the KeyLoop screen.

Choose the key from the list, or use `Enter a key code` to type a hex virtual-key code, or `Press a key` to press the key you want to send. A pressed key is recorded even if it is Shift or Ctrl alone, and nothing is decided until you choose `Use this key`.

While running, the screen shows the seconds until the next send, how many keys were sent, when the last one was sent, the running time and the time left. Press Ctrl+C to stop. Check what the key does in your applications, and your organization's rules for the PC, before using it.

If an error happens while starting, the window stays open with the reason until you press a key.

On Windows 11, if the menu is not visible, open "Show more options".

To start directly, run `KeyLoop.cmd`. The default start is `KeyLoop.cmd -Key 0x07 -Idle 120 -MaxRun 0`.

The first start, and the first start after an update, compiles the screens and saves them in `%LOCALAPPDATA%\KeyLoop`. Later starts load that file, which is faster. The folder can be deleted; it is rebuilt on the next start.

## Remove and move

`uninstall.bat` lists the right-click menu entries registered for the current user. Choose one with Up/Down and press Enter to remove it, or press Esc to cancel. Before removing, it saves a backup of the chosen entry in `output\context-menu-backups`, then shows what was removed and where the backup is. It does not delete the application files.

After moving the folder, run `install.bat` again in the new place.
