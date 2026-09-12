# Counter-Strike 1.6 from the GoldSrc package

In macETI-LAN 0.6.0 or later, open **Half-Life / Counter-Strike (Goldsrc)** after syncing and choose **Set up Counter-Strike 1.6**. This extracts the package and fills in every launch field. If you previously created a bottle through macETI, setup reuses it. Use **Launch** once the runtime is configured.

Older versions offered only **Create bottle only**. That created an empty Windows environment; there was no installed executable to find. The automatic recipe removes that manual step for ETI revision `20240623`.

## Inspected layout and launch settings

The archive is 1,026,965,875 bytes and expands to 2,300,436,864 bytes across 11,238 file/directory entries. Setup validates its layout and extracts with CRC checks into `C:\GoldSrc` in the dedicated bottle. It includes `hl-cs16`, `hl-cs15` and shared launcher settings; extraction retains the package layout.

The supplied Windows launcher selects CS 1.6 by copying the root `SmartSteamEmu.ini` into `hl-cs16`, then starting `SmartSteamLoader.exe -game cstrike` there. macETI performs the configuration copy only inside fresh staging and saves:

| Field | Value inside the bottle |
| --- | --- |
| Executable | `C:\GoldSrc\hl-cs16\SmartSteamLoader.exe` |
| Working directory | `C:\GoldSrc\hl-cs16` |
| Arguments | `-game` and `cstrike`, as separate arguments |

Actual Mac paths are filled in by setup. The synced package is unchanged, and existing configured installations are preserved. CS 1.5 and Half-Life have separate entry points and have not been validated in this recipe. The supplied CS 1.5 setup script is not needed for the tested CS 1.6 menu launch.

## Observed startup and argument fix

On 13 September 2026, the automatic worker continued an existing macETI-created Windows 10 64-bit bottle on Apple M2 Pro, macOS 15.7.9 and CrossOver 26.3.0. It extracted successfully and saved the runtime. Graphics remained Auto, High Resolution Mode off, with no additional prerequisite installers or DLL replacements.

The first launch hit a GoldSrc filesystem assertion. Inspection showed CrossOver had changed `-game cstrike` into `-game C:\GoldSrc\hl-cs16\cstrike`. GoldSrc rejects the colon in that game-directory argument. CrossOver's installed `bin/wine` wrapper exposes `--no-convert`; macETI now uses it to preserve game arguments literally while continuing to accept Mac executable and working-folder paths. The process then received `-game cstrike` unchanged and reached the full-screen Counter-Strike main menu.

The menu was rendered with the package's German labels. Gameplay, input during a match, sound, Windows LAN joining and the exact engine build were not recorded. Match the Windows host's CS **1.6** variant and engine version before testing a server; the same archive also contains CS 1.5. If a failed test left another instance open, close its game/error window before relaunching.

For setup/recovery behavior and supported revisions, see [automatic setup](SETUP.md). Private configuration files, logs and game content are excluded from the repository.
