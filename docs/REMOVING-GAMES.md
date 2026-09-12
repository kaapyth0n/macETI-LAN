# Removing games

Open a game in macETI-LAN and click **Remove game…** at the bottom of its page. This opens a review dialog; opening it does not change any files.

1. Close the game and any of its installers, including copies opened directly from CrossOver or Finder.
2. Select **Installed copy**, **Synced download**, or both. The dialog shows the exact directories and estimated allocated size. Size is an estimate, not a guarantee of reclaimed space on APFS.
3. If removing the download, open Resilio and **Disconnect** that game's folder on this Mac. Return to macETI and confirm the folder is disconnected. Pausing or quitting Resilio is insufficient. macETI cannot verify its connection state.
4. Check for saves inside the selected folders, acknowledge that the game is closed, then click **Move to Trash**.
5. To reclaim space, review the moved items in Finder's Trash and empty those items when ready. macETI never empties Trash.

Resilio's **Disconnect** affects this device and leaves downloaded files on disk. Its separate **Remove** action can affect the folder listing on devices linked to your identity, so use Disconnect when available. Older Sync Free versions expose Remove instead. See [Resilio's disconnect guide](https://help.resilio.com/hc/en-us/articles/205457785-Disconnecting-and-Removing-Folders) and [Sync Free guidance](https://help.resilio.com/hc/en-us/articles/205504569-I-m-using-Sync-Free-and-there-is-no-Disconnect-button-in-the-folder-menu). Do not reconnect the share to a folder in Trash.

## What moves and what stays

| Choice | What moves to Trash | What stays |
| --- | --- | --- |
| Installed copy | The reviewed game directory, including its local saves/settings | Synced package, CrossOver bottle, saves outside that directory |
| Synced download | The reviewed per-game Resilio folder, including its hidden files | Separate installed copy and its launch settings |
| Both | Both directories above | CrossOver bottle and files outside those directories |

If removal includes the configured executable or working directory, macETI clears its executable, working directory and launch arguments. The runtime type and bottle name remain saved. My games, compatibility history, catalog data, setup receipts and logs are retained. Use the star to remove a game from My games; the full catalog still lists it.

For the native Quake III layout, the installed directory includes `UserData`, so its settings and saves move to Trash too. For CrossOver games, saves may live either inside the game directory or elsewhere in the bottle. Review them before emptying Trash.

## Supported folders and safeguards

Downloads can be removed from the default `~/Resilio Sync/macETI-LAN/<game-id>` location for any catalog game. Installed copies are offered only for these dedicated layouts:

- A native runtime inside `~/Library/Application Support/macETI-LAN/Runtimes/<game-id>`.
- A configured CrossOver game in its own top-level directory under a bottle's `drive_c`, such as `drive_c/AmongUs` or `drive_c/Left4Dead2`.

The executable and any configured working directory must belong to that installation. Whole bottles, Windows/users/shared Program Files directories, linked directories and folders referenced by another saved game are excluded. Unrecognized locations have a Finder shortcut for manual management. Unconfigured legacy copies are not inferred or removed.

Setup and removal share a process-wide filesystem lock across app instances. The worker also locks preferences, checks the reviewed directory identities and current settings, and attempts to put moved folders back if a later move or preference save fails. If a restore fails, the error identifies the remaining Trash locations. Game processes launched outside macETI are not reliably tracked; the closed-game acknowledgement is required.

## Restore or reinstall

You can restore files from Trash before emptying it. Move each directory back to its displayed original path and select the executable again in **Runtime** if its settings were cleared. Reconnect a download in Resilio to the restored original path only after it is back in place.

For an automatically created Among Us, Rocket League or CS 1.6 installation, keep or resync its package and use its **Set up game** or **Set up Counter-Strike 1.6** action to extract again into the retained bottle. An existing manually chosen bottle still uses manual installation; alternatively, clear its saved runtime configuration to create a new managed bottle. Other games follow their Compatibility instructions. Restored files and new installations do not automatically recover saves that have already been emptied from Trash.
