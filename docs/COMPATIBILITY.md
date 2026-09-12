# Compatibility guidance — 12 September 2026

The launcher provides sourced guidance on every game page, versioned profiles for six games, and private recording of manual test results. The source includes manual setup notes from actual FlatOut 2, Warcraft III and Among Us trials. It does not install prerequisites, change bottle settings or execute CrossTies. Changes under Unreleased in the changelog require a source build until a new binary is published.

## User flow

Open a game and select **Compatibility** (also linked from Overview). The page shows whether guidance is game-specific or general, its review date, the recommended runtime route, and any difference from the user's saved runtime. It includes suggested setup, expandable troubleshooting, a Windows LAN checklist and source links with platform/date context.

**Record a test…** captures gameplay and LAN outcomes separately. Reaching a menu does not imply gameplay works; joining a host does not imply completing a session. A completed LAN session requires a successful gameplay observation and both client/host game versions. Notes hold graphics backend, MSync, bottle Windows version, dependencies and symptoms. Saving a test launches nothing and changes no runtime configuration.

The latest recorded result displays its environment and date. If the catalog package or saved runtime configuration differs, the page marks it as historical for those settings. Runtime upgrades, graphics toggles and dependencies inside CrossOver are not automatically tracked: the recorded version and notes describe that particular trial, never certification of the current machine. Full history remains visible; append a correction or new trial instead of replacing prior observations.

## Profile content

`Sources/MacETICore/Resources/compatibility.json` has schema version 1 and content revision `2026-09-12.5`. It contains shared setup notes, source metadata and six profiles:

| ETI ID | Route | Catalog package at research time |
| --- | --- | --- |
| `amongus` | CrossOver | `20250308` |
| `l4d2` | CrossOver | `20201021` |
| `flat2` | CrossOver | `20160922` |
| `cod2` | CrossOver, experimental | `20160922` |
| `quake3` | Native ioquake3 experiment | `20160922` |
| `wc3` | CrossOver, built-in OpenGL renderer | `20260308` |

These package revisions came from the live catalog. FlatOut 2, Warcraft III and Among Us packages were subsequently synced, inspected and tested as described below. The other entries remain research profiles. The page warns when a catalog revision changes. A curated route never overrides the user's saved runtime. Other games get shared guidance for their chosen runtime and an explicit unresearched status.

The sources include [CrossOver 26 advanced settings](https://support.codeweavers.com/en_US/advanced-settings-in-crossover-mac-26), [CrossTie profile documentation](https://support.codeweavers.com/en_US/an-intermediate-guide-on-what-the-crosstie-editor-options-mean), CodeWeavers game-specific tips, [Innersloth](https://www.innersloth.com/games/among-us/) and [ioquake3](https://ioquake3.org/get-it/). Game-specific URLs and historical dates are retained in the JSON. Dynamic ratings are linked rather than presented as continuously current data.

Graphics Auto is a trial baseline for CrossOver 26+, with the tested game-specific settings recorded separately. Historical tips are labeled by age/platform. Nothing in a guide executes automatically; project observations are distinguished from external reports.

## Observed game results

Trials on 12 September 2026 used Apple M2 Pro, macOS 15.7.9 and CrossOver 26.3.0 (26.3.0.39832), with dedicated Windows 10 64-bit bottles, Graphics Auto and High Resolution Mode off.

| Game/build | Observed result | Still to verify |
| --- | --- | --- |
| FlatOut 2 v1.2, package `20160922` | User confirmed gameplay. Agent verified the full-screen profile menu at 1512×945, 32-bit colour, 16:10 after configuring with temporary `-setup` and removing the forced Wine virtual desktop. Microsoft's official June 2010 DirectX runtime was installed in this bottle. | Windows LAN race/derby, track change and reconnect. |
| Warcraft III 1.30.4.11274, package `20260308` | User confirmed joining a Windows LAN match, but its 3D world was black. After adding `-opengl`, the agent verified terrain, models, portrait and movement in a short local run of the same custom map, both windowed and using macOS full-screen. The LAN browser showed waiting lobbies after the fix. | Joining and completing a LAN round with the final OpenGL configuration, map changes, reconnect, Mac hosting and operation without WAN. |
| Among Us v2024.11.26s (build 4936), package `20250308` | **User confirmed working LAN play with the Windows group.** The agent separately verified Skeld practice rendering and keyboard movement. Launched without extra dependencies or arguments; Local was accessible after dismissing `SteamworksAuthFail`. | Reconnecting, Mac hosting and operation without WAN. Tasks, discussion, voting and completed-round coverage were not individually recorded in the user's report. |
| Left 4 Dead 2, Call of Duty 2, Quake III | Research guidance only at this revision. | Package-specific gameplay and Windows interoperability. |

The [Warcraft III runbook](WARCRAFT-III.md) records extraction, supplied setup helpers, expansion selection, resolution and Bonjour details. Private logs, screenshots with player identities, license material and test history stay outside the repository. No complete LAN round is certified by these observations.

For Among Us, the tested dedicated bottle used a writable `C:\AmongUs` installation, `Among Us.exe`, its containing directory as the working folder, and no arguments. The archive was 445,998,660 bytes; UnRAR 7.23 extracted 110 files with successful CRC checks. The 32-bit Unity 2020.3.45f1 player reported Direct3D 11.0, feature level 11.1, on Apple M2 Pro. Mouse+Keyboard was already selected. No graphics override or additional runtime installer was needed for the short practice test.

The direct Among Us launch could not sign into a Steam account. [Innersloth documents this error when launching outside Steam](https://innersloth.zendesk.com/hc/en-us/articles/7094045780500--SteamworksAuthFail-bug). Closing the error allowed Local and Practice in this particular build; online authentication was not repaired or tested. Native ports, account linking and a current store build are separate experiments.

After the initial empty-browser check, the user confirmed that Among Us worked with the Windows LAN group. Record this as a **user-reported successful LAN test**, alongside the agent-observed local practice test. The user had arranged a matching Windows lobby; the exact Windows version was not independently captured. The earlier empty list occurred while the other players were already in a round and did not establish a discovery defect. Keep the initial observation in private history and append this confirmation.

## Data and packaging

- The bundled resource loads offline. The packaged app and CLI read it from `Contents/Resources/macETI-LAN_MacETICore.bundle`. SwiftPM CLI/tests discover their adjacent resource bundle; no compiled-in developer build path is used.
- Profile decoding rejects unknown schema versions, duplicate game/source IDs, invalid game IDs, non-HTTPS source URLs and missing source references. Guidance is plain text; it has no executable action format.
- `compatibility-tests.json` uses its own versioned document in the private application-support directory. Writes are locked, atomic and mode `0600`; corrupt or future-version logs are preserved and reported. This log includes local executable paths and user-entered observations and is not uploaded.
- Browsing guidance creates no test log. Saving an observation does not modify `library.json`, create individual game folders or start a sync.
- `maceti compatibility GAME_ID [--json]` uses the same guide resolver and requires an existing catalog game. It does not expose sync keys or change settings.

## Initial launcher validation

- `swift test`: 26 tests pass, including 8 new compatibility tests for curated/fallback routes, resource loading, invalid profiles, private history persistence, invalid-log preservation, historical-result matching and LAN outcome validation.
- ARM64 production build and ad-hoc signature verification pass. A standalone Foundation check resolves and reads the JSON resource inside the `.app`.
- Release CLI reads all five priority profiles plus general guidance for Factorio. The catalog remains at 214 games and unknown IDs are rejected.
- No live test log or individual game folders were created during these checks. Synthetic test records exist only in temporary test directories and are removed afterwards.
- Native visual verification completed after unlocking and restarting the rebuilt app. Checked Among Us's game-specific guidance, all expandable troubleshooting/LAN/source sections, Factorio's general fallback, the Runtime shortcut and Quake III's native ioquake3 guidance. Layouts and scrolling render correctly in the native sheets. See the [compatibility page preview](compatibility-preview.jpg).
- Inspected the test-recording form, including automatic M2 Pro/macOS environment details and disabled Save for an empty result. A synthetic menu-only observation combined with a completed LAN session was rejected with an actionable validation error. Cancelled the form and confirmed no live test log was created. Successful persistence remains covered by the isolated core tests; no real game result was entered during UI verification.

Those initial UI checks preceded the real game trials above. Automatic setup and rollback remain future work; recording a local result alone never promotes a profile to executable automation.
