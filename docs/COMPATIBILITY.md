# Compatibility guidance — 12 September 2026

Version 0.3 implements the first stage: sourced guidance on every game page, versioned profiles for the five priority games, and private recording of manual test results. It does not install prerequisites, change bottle settings, execute CrossTies or claim a working game recipe.

## User flow

Open a game and select **Compatibility** (also linked from Overview). The page shows whether guidance is game-specific or general, its review date, the recommended runtime route, and any difference from the user's saved runtime. It includes suggested setup, expandable troubleshooting, a Windows LAN checklist and source links with platform/date context.

**Record a test…** captures gameplay and LAN outcomes separately. Reaching a menu does not imply gameplay works; joining a host does not imply completing a session. A completed LAN session requires a successful gameplay observation and both client/host game versions. Notes hold graphics backend, MSync, bottle Windows version, dependencies and symptoms. Saving a test launches nothing and changes no runtime configuration.

The latest recorded result displays its environment and date. If the catalog package or saved runtime configuration differs, the page marks it as historical for those settings. Runtime upgrades, graphics toggles and dependencies inside CrossOver are not automatically tracked: the recorded version and notes describe that particular trial, never certification of the current machine. Full history remains visible; append a correction or new trial instead of replacing prior observations.

## Profile content

`Sources/MacETICore/Resources/compatibility.json` has schema version 1 and content revision `2026-09-12.1`. It contains shared setup notes, source metadata and five profiles:

| ETI ID | Route | Catalog package at research time |
| --- | --- | --- |
| `amongus` | CrossOver | `20250308` |
| `l4d2` | CrossOver | `20201021` |
| `flat2` | CrossOver | `20160922` |
| `cod2` | CrossOver, experimental | `20160922` |
| `quake3` | Native ioquake3 experiment | `20160922` |

These package revisions came from the live catalog. The packages themselves were not downloaded or inspected. The page warns when a catalog revision changes. A curated route never overrides the user's saved runtime. Other games get shared guidance for their chosen runtime and an explicit unresearched status.

The sources include [CrossOver 26 advanced settings](https://support.codeweavers.com/en_US/advanced-settings-in-crossover-mac-26), [CrossTie profile documentation](https://support.codeweavers.com/en_US/an-intermediate-guide-on-what-the-crosstie-editor-options-mean), CodeWeavers game-specific tips, [Innersloth](https://www.innersloth.com/games/among-us/) and [ioquake3](https://ioquake3.org/get-it/). Game-specific URLs and historical dates are retained in the JSON. Dynamic ratings are linked rather than presented as continuously current data.

Graphics Auto is a trial baseline for CrossOver 26+, not a measured recommendation for each ETI game. Historical tips are labeled by age/platform; no arbitrary DLL downloads, registry fixes or old performance arguments are applied. Project-authored trial steps are described as recommendations or experiments, not attributed tests.

## Data and packaging

- The bundled resource loads offline. The packaged app and CLI read it from `Contents/Resources/macETI-LAN_MacETICore.bundle`. SwiftPM CLI/tests discover their adjacent resource bundle; no compiled-in developer build path is used.
- Profile decoding rejects unknown schema versions, duplicate game/source IDs, invalid game IDs, non-HTTPS source URLs and missing source references. Guidance is plain text; it has no executable action format.
- `compatibility-tests.json` uses its own versioned document in the private application-support directory. Writes are locked, atomic and mode `0600`; corrupt or future-version logs are preserved and reported. This log includes local executable paths and user-entered observations and is not uploaded.
- Browsing guidance creates no test log. Saving an observation does not modify `library.json`, create individual game folders or start a sync.
- `maceti compatibility GAME_ID [--json]` uses the same guide resolver and requires an existing catalog game. It does not expose sync keys or change settings.

## Validation

- `swift test`: 26 tests pass, including 8 new compatibility tests for curated/fallback routes, resource loading, invalid profiles, private history persistence, invalid-log preservation, historical-result matching and LAN outcome validation.
- ARM64 production build and ad-hoc signature verification pass. A standalone Foundation check resolves and reads the JSON resource inside the `.app`.
- Release CLI reads all five priority profiles plus general guidance for Factorio. The catalog remains at 214 games and unknown IDs are rejected.
- No live test log or individual game folders were created during these checks. Synthetic test records exist only in temporary test directories and are removed afterwards.
- Native visual verification completed after unlocking and restarting the rebuilt app. Checked Among Us's game-specific guidance, all expandable troubleshooting/LAN/source sections, Factorio's general fallback, the Runtime shortcut and Quake III's native ioquake3 guidance. Layouts and scrolling render correctly in the native sheets. See the [compatibility page preview](compatibility-preview.jpg).
- Inspected the test-recording form, including automatic M2 Pro/macOS environment details and disabled Save for an empty result. A synthetic menu-only observation combined with a completed LAN session was rejected with an actionable validation error. Cancelled the form and confirmed no live test log was created. Successful persistence remains covered by the isolated core tests; no real game result was entered during UI verification.

CrossOver game startup and Windows LAN play remain untested. Automatic setup and rollback will be implemented with the first reproducible, package-matched recipe; recording a local result alone never promotes a profile to executable automation.
