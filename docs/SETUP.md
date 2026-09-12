# Automatic CrossOver setup

Install and activate CrossOver, finish syncing the game in Resilio, then open the game in macETI-LAN.

- **Set up game** in Overview or Runtime prepares a supported package and saves all launch settings. GoldSrc calls this **Set up Counter-Strike 1.6** to identify the game selected from its multi-game package. Use **Launch** when the runtime is configured.
- If you already used **Create bottle only**, the full setup action reuses that macETI-created bottle. You do not need to locate an executable or enter paths yourself.
- For packages without automatic installation, **Create bottle only** prepares an empty Windows 10 environment. It does not extract or install the game, and the page explains that manual installation is still required. The CLI retains `--bottle-only` for advanced use on any Windows game.
- An existing configured game is preserved. Setup does not upgrade it when Resilio receives a newer package.

| Game | Exact ETI package | Automatic steps |
| --- | --- | --- |
| Among Us | `20250308` | Create bottle; extract `amongus.eti` into `C:\AmongUs`; select `Among Us.exe`, its containing folder and no arguments. |
| Rocket League | `20260410` | Create bottle; extract `rocket.eti` into `C:\RocketLeague`; select the supplied `SmartSteamLoader.exe`, its containing folder and no arguments, matching the Windows package's launch entry point. |
| Counter-Strike 1.6 / GoldSrc | `20240623` | Create or reuse bottle; extract `goldsrc.eti` into `C:\GoldSrc`; copy the supplied root launcher configuration into `hl-cs16`; select `hl-cs16\SmartSteamLoader.exe`, its containing directory and `-game cstrike`. |
| Other Windows games | Any | Create and save a bottle. Game extraction, prerequisites and game-specific settings remain manual. |

These recipes reproduce the tested clean-bottle baseline on CrossOver 26.3.0, Apple M2 Pro and macOS 15.7.9. They use CrossOver's default graphics settings, with no extra dependency installer, registry change or display override. Full package extraction currently requires Apple Silicon. CrossOver must be in `/Applications` or `~/Applications`, using its default per-user bottle location.

GoldSrc setup was tested by continuing a bottle the user had already created. The 1,026,965,875-byte archive expands to 2,300,436,864 bytes and contains CS 1.6, CS 1.5 and Half-Life. The automatic recipe selects CS 1.6 and reached its full-screen menu; the other variants, gameplay and LAN joining remain untested. See [the GoldSrc notes](GOLDSRC.md).

Warcraft III still needs its supplied key/profile helpers, Windows Bonjour and the documented OpenGL/window settings. FlatOut 2 needs its DirectX and resolution steps. Their existing working installations continue to launch normally. See [compatibility results](COMPATIBILITY.md) and the [Warcraft runbook](WARCRAFT-III.md).

## Downloads, storage and progress

First package setup downloads [RARLAB's macOS ARM 7.23 archive](https://www.rarlab.com/download.htm), about 654 KB. Both the download and extracted UnRAR executable must match pinned SHA-256 hashes. Only UnRAR, its license and readme are retained in the private setup cache; the full RAR application is not installed. Subsequent setups can use the cached tool offline. CrossOver or a game may have separate activation/network requirements.

Setup reads `<game-id>.eti` and `version.ini` from the game's Resilio folder. It checks the exact package revision and inspected archive size, validates archive paths/types, measures expanded size against the recipe limit and checks free disk space. UnRAR extraction checks CRCs. The expected game executable and companion files must exist before installation is accepted. These checks detect incomplete/changed archives; they are not publisher authentication for game files.

Extraction first uses private staging storage, then moves the result into the new bottle's `drive_c`. The synced package is never modified. Keep enough space for both the synced archive and the extracted game: Rocket League's tested package alone expands to about 6.9 GiB. CrossOver may map Windows Documents into the Mac's Documents folder, so a separate bottle does not guarantee that every game's saves stay inside it.

The page displays setup stages and a **Cancel setup** button. Downloads and extraction can be cancelled; an in-progress CrossOver bottle creation finishes before cancellation takes effect. Setup does not launch the game. Only one setup runs at a time, including across app/CLI instances.

## Existing installations and recovery

- Setup assigns a unique bottle name such as `macETI-amongus-XXXXXXXX`; names and paths are saved automatically. It never replaces an existing configured game or installs into an unrelated manually selected bottle.
- Cancelled or failed extraction removes its staging directory. A successfully created bottle is kept and reused on retry. An incomplete bottle creation is reported by name: inspect or remove that specific bottle in CrossOver before retrying.
- Receipts let setup recover a completed installation if saving runtime settings was interrupted. If files already occupy an unexpected destination, setup preserves them and reports the path.
- Runtime preferences use a locked compare-and-update. If another window or CLI changed the runtime during setup, those newer settings are kept and the prepared bottle remains available for manual selection.
- **Show setup logs** opens `~/Library/Application Support/macETI-LAN/Setup`. Receipts and logs remain private. After an app crash or forced quit, an unreferenced `.staging-…` directory may remain there; remove it only when setup is no longer running. Do not upload this directory to a public issue.
- To remove game files, open **Remove game…** on the game page. Review saves before moving an installed copy or disconnected download to Trash. CrossOver bottles and setup receipts are retained for reuse; see [removal and recovery](REMOVING-GAMES.md).

## CLI and contributions

```sh
maceti setup amongus
maceti setup rocket
maceti setup goldsrc
maceti setup factorio --bottle-only
```

The CLI uses the same worker and preferences as the app. It prints progress and the resulting runtime configuration. A configured installation is returned without reinstalling it.

Executable recipes live in `Sources/MacETICore/CrossOverSetup.swift`, with process/download handling in `SetupProcess.swift`. Compatibility JSON remains plain guidance; changing prose or recording a successful test cannot enable execution. Adding a recipe requires an inspected revision, bounded archive layout, reproducible launch settings, failure/retry tests and a real isolated setup trial. Tests use synthetic sparse placeholders and mocked extraction, with no commercial game data or downloads.
