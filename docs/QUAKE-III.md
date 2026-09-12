# Quake III Arena: native Apple Silicon setup

Tested on 12 September 2026 with Apple M2 Pro and macOS 15.7.9. The native client joined an existing Windows LAN match; CrossOver was not needed for this package.

| Component | Observed version |
| --- | --- |
| ETI game/package | `quake3`, revision `20160922`; archive 447,772,292 bytes |
| Synced Windows executable | `Q3 1.32` |
| Native engine | `ioq3 1.36_GIT_96db7a06-2021-07-19 macosx-arm64`, built 12 September 2021 |
| Windows LAN server | `Q3 1.32 win-x86 Oct 7 2002`, protocol 68 |
| Graphics | OpenGL2 renderer, OpenGL 4.1, Apple M2 Pro |
| Verified display | 1280×800 window; 1512×982 full-screen desktop mode |

The [official download page](https://ioquake3.org/get-it/) links the [notarized Universal 2 archive](https://files.ioquake3.org/ioquake3_notarized.zip). The tested archive was 7,688,113 bytes with SHA-256 `31346892f3b98a45727d51576c4b14926ef66e540a4286e3edecd26e1dcd03e0`. Its executable contains both ARM64 and x86_64; the launch log confirmed ARM64 execution. `codesign --verify --deep --strict` passed and `spctl --assess --type execute` reported Notarized Developer ID. A future download may contain a different build.

## Prepare the files

1. Finish syncing Quake III in Resilio with Selective Sync off.
2. Create a separate writable runtime folder, for example `~/Library/Application Support/macETI-LAN/Runtimes/quake3`.
3. Extract `ioquake3.app` from the official archive into that folder. Keep its signed bundle intact.
4. Extract the synced `quake3.eti` and copy only `baseq3/pak0.pk3` through `baseq3/pak8.pk3` into the runtime folder's `baseq3` subfolder. This package already contains all eight patches; do not add a second set of patch files without checking versions.
5. Create a separate `UserData` folder inside the runtime folder. Start with fresh native settings instead of copying the synced Windows `q3config.cfg` or old logs.

UnRAR 7.23 extracted the inspected files successfully, and all nine PK3 archives passed their internal ZIP CRC checks. The game data remains separate from the signed engine app, following the [ioquake3 player's guide](https://ioquake3.org/help/players-guide/). The trial used the base game only; Team Arena and additional mods were not tested.

## Configure macETI-LAN

Select **Native / Mac app** in Runtime:

- Executable: `<runtime-root>/ioquake3.app/Contents/MacOS/ioquake3`
- Working folder: `<runtime-root>`
- Arguments, one per line:

```text
+set
fs_basepath
<runtime-root>
+set
fs_homepath
<runtime-root>/UserData
```

Replace `<runtime-root>` with the absolute path to your runtime folder. The launcher passes arguments separately, so paths containing spaces need no extra quote characters in the form. This selects the native executable inside the bundle; selecting the `.app` itself uses a different launch mode without an explicit working folder.

Click **Save runtime**, then use **Overview → Launch**. If the configuration was saved externally while the launcher was open, close the game details sheet, click **Refresh** in the library, and reopen the game page. A details sheet left open can still show the old configuration and a disabled Launch button.

The tested full-screen settings are `r_fullscreen 1` and `r_mode -2`, which selected the Mac's 1512×982 desktop mode. Settings persist in `UserData/baseq3/q3config.cfg`; they are not forced in the saved launcher arguments. Exit using the game's own Exit menu. Stopping the test process with SIGTERM produced an Abnormal Exit / safe-video prompt on the next start, even though the previous game had rendered successfully.

## What was tested

- Main menu and local `q3dm1` match: world, HUD and keyboard movement observed with the native ARM64 engine.
- LAN discovery: a server answered the standard UDP query on the wired LAN interface. The server reported protocol 68 and five players.
- Native direct joining: the client loaded the Windows-hosted `Q3DM12` map in full-screen mode, with world and HUD rendered. A server status query then reported six players. The server had `sv_pure=1` and PunkBuster off.
- Runtime paths and the test result were saved in macETI-LAN's private library/history. The server address was used only for the one-time connection test and is not stored in the launch arguments.

This establishes local rendering/movement and joining that Windows host. It does not certify a completed LAN round, reconnecting, map transitions, other mods, Mac hosting or operation without WAN. PunkBuster is unsupported by ioquake3 according to its player's guide; other server requirements need separate checks. CrossOver remains a fallback if a particular Windows package/mod is incompatible with the native engine.

Game files, engine binaries, private settings/keys, server addresses and screenshots with player identities are not included in the repository.
