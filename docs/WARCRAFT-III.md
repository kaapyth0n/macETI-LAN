# Warcraft III: The Frozen Throne on Apple Silicon

This manual setup was tested on 12 September 2026 with the classic ETI `wc3` package revision `20260308`, game version **1.30.4.11274**, CrossOver **26.3.0**, macOS **15.7.9** and an **M2 Pro**. It does not cover the separate Reforged package.

The working launch arguments are **`-window` and `-opengl`**. They fixed the cropped display and black 3D world in this setup. Local rendering and movement were verified; a complete Windows LAN round with these final arguments remains to be tested.

## Prepare the local installation

1. Finish syncing the `wc3` share in Resilio. Keep its distribution files unchanged and prepare a writable local game installation.
2. Create a dedicated CrossOver Windows 10 64-bit bottle. Our bottle used Graphics **Auto**, High Resolution Mode **off** and no Wine virtual desktop.
3. Extract `wc3.eti` into the bottle, using `C:\WarcraftIII` in this trial. This is a RAR archive despite its extension. **Official UnRAR 7.23 for macOS ARM** successfully extracted and verified it. macOS `bsdtar` rejected the dictionary size; 7-Zip 26.03 could list the archive but could not correctly extract its newer compression method. Check extraction errors and file sizes before diagnosing the game. Obtain archive tools from [RARLAB](https://www.rarlab.com/download.htm).
4. Inspect the included setup script and helpers. In this package, `wc3_keys.exe` and `wc3_profile.exe` are self-extracting archives whose contents can be inspected without running their Windows executables. The key archive targets `C:\ProgramData\Blizzard Entertainment\Warcraft III`; it includes `roc.w3k`, `tft.w3k` and `user.w3k`. The profile archive targets the user's `Documents\Warcraft III` folder. Use only license material you are entitled to use; never publish these files or their contents.

The tested game read the expansion license files from **ProgramData**. An ownership prompt does not, by itself, establish that the synced package lacks setup material. Additional copies beside the executable were not established as necessary.

The supplied setup script also sets values in `HKCU\Software\Blizzard Entertainment\Warcraft III`:

| Value | Type | Local setup |
| --- | --- | --- |
| `Migration Complete` | DWORD | `1` |
| `User Game Save Folder` | String | `C:\WarcraftIII\UserData` in this trial |

The script references a `wc3path` variable supplied by its surrounding setup. Do not assume it exists when running the script alone. Reproduce the relevant setup deliberately instead of blindly running Windows firewall commands on the Mac.

**The save-folder value did not isolate all user data.** The game still wrote a replay under the Mac's `~/Documents/Warcraft III` through CrossOver's Documents mapping. Back up that directory as well as the local installation; respect existing Warcraft profiles when copying helper contents.

## Configure macETI-LAN

In Warcraft III → **Runtime**, select CrossOver and the dedicated bottle. Choose the local `Warcraft III.exe` and its containing folder as the working directory. For the layout above, these correspond to `C:\WarcraftIII\Warcraft III.exe` and `C:\WarcraftIII`; use the Mac file picker to select them inside the bottle.

Enter these arguments, one per line:

```text
-window
-opengl
```

Save and launch. Use the **macOS green window button** for full-screen play. The original `-nativefullscr` argument caused a display-mode change and upper-left cropping on this Mac. A windowed launch followed by macOS full-screen showed the complete image. The test used a 1512×945 logical desktop; choose a size appropriate for your own display.

If **Reign of Chaos** appears, click the small portrait button immediately to the **right of Single Player**. This switches to **The Frozen Throne** and restarts the game. The selection persisted after another clean restart; the game stored `Preferred Game Version` as DWORD `1` in its Warcraft III registry key. The package's `-frozenthrone` argument did not select the expansion in our test, so it is not part of the saved configuration.

## Black terrain, models or portraits

The default rendering path showed menus, the HUD and minimap correctly but left most of the actual world black. Merely reaching the menu was therefore a misleading startup check.

The game's built-in OpenGL renderer, selected by **`-opengl`**, restored terrain, scenery, buildings, the builder model, its portrait and visible movement on the same ETI custom map. No additional graphics DLL, DirectX installer or renderer registry override was needed for Warcraft in this trial. A [historical CodeWeavers OpenGL tip](https://www.codeweavers.com/compatibility/crossover/tips/warcraft-iii-the-frozen-throne/enabling-opengl) supplied background; its old registry workaround was not applied or independently validated here.

For a local reproduction, the test temporarily added `-loadfile` followed by the relative path of the affected map. Loading a map this way may require pressing a key after loading and selecting its difficulty before units appear. Remove the test-only arguments afterward. The saved launcher configuration contains only `-window` and `-opengl`.

## LAN discovery

- Match the actual game version, **expansion**, maps and mods on both computers. Sharing the package does not guarantee identical saved expansion preferences.
- Ask the Windows host to wait in a **Local Area Network → Create Game** lobby. A classic match that is already running is not a join target; an empty browser during that match alone does not prove a network failure.
- Accept Warcraft's **Bonjour** installation prompt if it appears. We verified **Bonjour Service** running inside the CrossOver bottle. macOS's own Bonjour service does not replace this check.
- Check the active LAN interface, local network permissions and relevant firewall rules if discovery fails. Firewall disabling or router port forwarding is not part of this setup.

An optional bottle-specific service check, after replacing the example bottle name:

```sh
"/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine" \
  --bottle "macETI-WarcraftIII" --debugmsg -all -- sc.exe query "Bonjour Service"
```

The expected service state is `RUNNING`. This proves that the service is running, not that a host is reachable.

## Evidence and remaining checks

The user successfully joined a Windows LAN match before the graphics fix. The subsequent OpenGL test verified a short **local** run of the affected map, including selection and movement, in windowed and macOS full-screen modes. The LAN browser displayed waiting lobbies afterward. These are separate observations: an entire LAN round with OpenGL, map changes, reconnecting, Mac hosting and offline operation remain unverified.

Keep license files, synced packages, maps, replays, private test records and identifiable LAN screenshots out of public reports. The repository ignores Warcraft data extensions and its publication check rejects them even if forcibly staged. Report versions, settings, symptoms and the exact extent of the test instead.
