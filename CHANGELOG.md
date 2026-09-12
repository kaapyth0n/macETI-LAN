# Changelog

## Unreleased

- Record Left 4 Dead 2's supplied-overlay startup fix, local gameplay test, full-screen settings and observed LAN peer discovery.

- Document native ARM64 Quake III setup, verified local rendering/movement and joining a Windows 1.32 LAN server in full-screen mode.
- Exclude Quake game-data archives, keys, configuration and demos from source publication.

## 0.4.0 — Automatic CrossOver setup

- Create and save a dedicated Windows 10 64-bit bottle from any Windows game page.
- Set up the tested Among Us and Rocket League packages automatically: validate the synced archive, extract into a fresh bottle and save the executable, working folder and arguments.
- Preserve existing installations, provide progress/cancellation and keep private recovery receipts and logs.
- Add Rocket League’s tested older-build guidance and the `maceti setup` command.

- Fix CrossOver launches when the executable and working directory use macOS paths.
- Document the verified FlatOut 2 resolution setup and classic Warcraft III Frozen Throne setup, including OpenGL rendering, edition selection and Bonjour discovery.
- Add Warcraft III's package-specific compatibility page and distinguish local gameplay, observed lobbies and user-reported LAN joining.
- Exclude Warcraft license files, maps, saves and replays from source publication checks.
- Record Among Us's clean-bottle startup, Skeld practice test and subsequent user-confirmed LAN play with Windows, including its actual game version and the distinction between Steam account errors and Local play.

## 0.3.1 — Dock icon fix

- Set the running application's Dock icon explicitly at startup, including when macOS retains an older placeholder icon for an app rebuilt in place.
- Use the complete icon filename in bundle metadata and increment the bundle version.

## 0.3.0 — Initial public preview

- Native SwiftUI catalog browser with artwork, search, filters, saved games and grid/list views.
- Guided per-game Resilio connection and existing-runtime launch configuration.
- Versioned compatibility guidance for five priority games and a general fallback.
- Private manual test history with separate gameplay and Windows LAN outcomes.
- Original app icon, packaged CLI, setup helpers and release checksums.
- Public build/contribution documentation and macOS CI.

Game installation and Mac–Windows LAN compatibility remain experimental. See the compatibility notes for individual observations; automatic package recipes currently cover Among Us and Rocket League only.
