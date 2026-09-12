# Changelog

## Unreleased

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

Game installation and Mac–Windows LAN compatibility remain experimental. See the compatibility notes for individual observations; automatic setup recipes are not implemented.
