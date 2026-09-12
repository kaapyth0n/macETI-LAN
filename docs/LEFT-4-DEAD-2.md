# Left 4 Dead 2 on Apple Silicon

Tested on 12 September 2026 with Apple M2 Pro, macOS 15.7.9 and CrossOver 26.3.0 (26.3.0.39832). Local gameplay worked after disabling the supplied optional overlay. Windows LAN joining has not yet been verified.

| Component | Tested value |
| --- | --- |
| ETI package | `l4d2`, revision `20201021` |
| Game | `2.2.0.3`, build `8011`; 32-bit Windows executable |
| Archive | 9,987,347,585 bytes |
| Expanded files | 18,250,177,979 bytes; 72,401 archive entries |
| Bottle | Dedicated Windows 10 64-bit; Graphics Auto; High Resolution Mode off |
| Saved launch | `left4dead2.exe`, game root as working folder, `-novid` |
| Display | Local gameplay in a 1280×800 window; full-screen menu at 1280×800 |

## Installation and startup fix

1. Finish syncing in Resilio. Create a dedicated bottle from the game's Runtime page. Automatic package installation is not implemented for this revision.
2. Extract `l4d2.eti` into a separate writable folder, such as the bottle's `C:\Left4Dead2`. The trial validated archive paths/types and completed both UnRAR's integrity test and extraction successfully. Keep extra space beyond the expanded size for the bottle, caches and saves.
3. Create an empty file named `disable_overlay.txt` inside `bin/steam_settings` in that extracted game folder. Create the settings folder if absent. Leave the supplied DLLs intact.
4. In macETI Runtime, select `left4dead2.exe`, use its containing directory as the working folder, add `-novid` as one argument and save. If settings were saved externally, close the details sheet, Refresh the library, then reopen the game page.
5. In the game, select **Options → Video → Display Mode → Full screen**. The tested resolution is 1280×800, widescreen 16:10. Remove temporary `-windowed`, `-w`, `-h` and `-condebug` launch arguments after testing so saved preferences control display mode.

The original launch exited with code 9 before displaying a window. CrossOver diagnostics placed the unhandled exception inside the package's `steam_api.dll`, identified as Goldberg, while initializing its overlay. Disabling that overlay allowed the menu and local map to load. The [component's original README](https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/blob/master/Readme_release.txt) documents `steam_settings/disable_overlay.txt`; the same filename is present in the supplied DLL. No replacement DLLs or extra prerequisite installers were used.

The package initially contained a 2560×1440 video configuration with 8× antialiasing. The first trial used a smaller window. After the game's video configuration completed, the saved file reported full-screen 1280×800, 4× antialiasing, 4× anisotropic filtering and VSync on. These are recorded observations, not a performance benchmark or requirements for every Mac.

## Observed behavior

- Dead Center, chapter 1 (`c1m1_hotel`): terrain/buildings, sky, weapon and HUD rendered. Holding W moved the player to the fence; one mouse click fired a shot and changed ammunition from 15 to 14.
- The full-screen menu rendered after changing display mode through Options.
- Six peers appeared in the menu's friends list. Discovery does not establish a successful Windows join. Select the desired mode and **Play With Friends**, or a peer in the menu, for the next LAN test.
- The package displayed an insecure/VAC warning. Public VAC-secured servers were not tested. Steam Cloud was disabled in the first-run dialog.
- Sound, a completed chapter/match, reconnecting, hosting, other campaigns/mods and operation without WAN remain unverified.

Game data, local identity/settings, server addresses, screenshots with player names and diagnostic logs stay outside the repository. The launch configuration and local gameplay observation are saved only in the user's private macETI library.

## macOS disk-space observation

Raw filesystem free space initially understated the Mac's available capacity because Time Machine snapshots retained deleted cache blocks. The native `volumeAvailableCapacityForImportantUsage` value reported additional reclaimable capacity. During this installation, macOS reclaimed space automatically and extraction completed; no Time Machine snapshots were manually removed. [Apple explains that local snapshots are deleted as storage is needed.](https://support.apple.com/en-ie/102154) A capacity estimate is not a guarantee: monitor actual space during a large extraction and preserve headroom.
