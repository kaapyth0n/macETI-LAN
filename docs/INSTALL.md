# Install and set up macETI-LAN

The current download targets Apple Silicon and macOS 14+. It includes the app, a CLI inside the app bundle, and optional Python helpers under `tools/`. No game, catalog, artwork archive or third-party runtime is included.

## Open the app

Download the `macos-arm64.zip` and `.sha256` file from [GitHub Releases](https://github.com/kaapyth0n/macETI-LAN/releases/latest). In the folder containing both downloads, verify integrity with:

```sh
shasum -a 256 -c macETI-LAN-v0.3.0-macos-arm64.zip.sha256
```

Extract the ZIP, move `macETI-LAN.app` to Applications and open it. This preview is ad-hoc signed, not Developer ID signed or notarized. If macOS blocks it, use [Apple's per-app Open Anyway procedure](https://support.apple.com/en-gb/102445) after reviewing the download's source. Do not disable Gatekeeper globally.

The app opens without Xcode or Python. A fresh installation has an empty catalog until the steps below are completed.

## Connect the catalog

Install and activate [Resilio Sync](https://www.resilio.com/sync/). If you already have a current ETI `game.db`, use **Import** in the app. Otherwise, Python 3 and the optional bootstrap script can obtain only ETI's launcher metadata.

Open Terminal in the extracted release folder, then run:

```sh
python3 tools/bootstrap-catalog.py
"/Applications/macETI-LAN.app/Contents/MacOS/maceti" init
"/Applications/macETI-LAN.app/Contents/MacOS/maceti" copy-key launcher
```

For a source checkout, the same scripts are under `scripts/` and the CLI is `.build/debug/maceti` after `swift build`.

1. In Resilio, choose **+ → Enter a key or link** and paste the copied key.
2. Turn **Selective Sync on** for the launcher share. Choose `~/Resilio Sync/macETI-LAN/eti_launcher` as its folder.
3. In Finder, locate `update/game.db` and choose **Sync to this device** if it is a placeholder.
4. Click **Refresh** in macETI-LAN. It imports the completed live catalog and keeps a private offline snapshot.

The bootstrap also saves an old seed database for inspection, but does not import it. Use the newly synced live `game.db`. If the upstream archive's format changes, the helper reports an error instead of guessing a key.

## Optional cover art

Sync `update/assets.eti` to this device using Finder, then run from the extracted release folder:

```sh
python3 tools/import-artwork.py
```

Restart the app after importing covers. The helper extracts only matching catalog images into the local artwork cache. Missing covers use placeholders.

## Choose a game

Open a game's **Sync** tab, copy its individual key, and connect it in Resilio using the displayed game folder. For the complete package, turn Selective Sync off for that game's share. Check Resilio for transfer completion.

Prepare a separate writable game installation, then configure it in **Runtime**: an existing CrossOver bottle and Windows `.exe`, or an installed native engine/app. **Compatibility** supplies sourced trial guidance. No automatic installation, bottle setup or game fixes are applied by this release.

The launcher opening successfully does not establish that a game works on macOS or can join Windows players. Match game versions and test LAN play before an event.

## Help and contributions

[Project README](https://github.com/kaapyth0n/macETI-LAN#readme) · [Issues](https://github.com/kaapyth0n/macETI-LAN/issues) · [Contributing](https://github.com/kaapyth0n/macETI-LAN/blob/main/CONTRIBUTING.md)

Do not attach your catalog, Resilio keys or private application-support files to public reports.
