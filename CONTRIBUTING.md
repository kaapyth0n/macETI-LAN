# Contributing

Small, focused pull requests are easiest to review. For a larger integration or engine port, open an issue describing the intended behavior first.

## Development

Use macOS 14+ and Swift 6. Clone the repository, run `swift test`, then `bash scripts/build-app.sh`. Open `dist/macETI-LAN.app` to exercise the UI. There are no external Swift dependencies.

- `Sources/MacETICore`: validated catalog access, private preferences, compatibility guidance/test history and launch command construction.
- `Sources/MacETIApp`: native SwiftUI catalog, sync handoff, runtime forms and compatibility pages.
- `Sources/MacETICLI`: local command-line interface.
- `Tests/MacETICoreTests`: synthetic fixtures and behavior checks.
- `scripts`: metadata/artwork helpers, icon generation, packaging and publication checks.

Before opening a PR:

```sh
swift test
bash scripts/build-app.sh
git add <the-files-you-intend-to-contribute>
python3 scripts/check-publication.py
```

Exercise changed UI flows and describe the result. Tests never need an ETI download, a real sync key or a CrossOver license. Test runtime command construction independently of launching games. Keep settings reversible and prevent one game's changes from affecting another bottle.

## Game guidance and reports

Guidance lives in `Sources/MacETICore/Resources/compatibility.json`; see [the profile documentation](docs/COMPATIBILITY.md).

1. Use the exact game ID from your imported catalog. Do not assume similarly named editions are interchangeable.
2. Cite primary sources with platform/date context. Mark old Linux/Intel advice as historical; do not present it as a tested M-series preset.
3. Increment the profile revision and content revision when changing guidance. `reviewedPackageRevision` is the catalog revision at review time, not a game version or test certificate.
4. Record the actual ETI package, game build, CrossOver/engine version, macOS version, chip, bottle Windows version, graphics settings and dependencies for a real trial.
5. Report gameplay and Windows-host LAN results separately. Include both game versions, reconnect/map-change behavior, and whether WAN was disconnected after setup. Record Mac hosting separately.

Prose or a successful observation does not enable automatic setup. A future recipe needs reproducible package-matched steps, constrained actions and rollback before it can be offered as an apply button.

Do not upload game archives, executables, cover collections, catalog databases, license files, sync keys or private logs. Summarize/redact reports instead of attaching an application-support directory. Screenshots should show only the relevant app UI.

## Pull requests

Explain the concrete problem, resulting behavior and verification. Note remaining game/version/platform limitations. Keep unrelated refactors separate. Changes are accepted under the repository's MIT license; third-party material needs appropriate attribution and redistribution rights.

## Releases

Update the version in `scripts/build-app.sh` and `CHANGELOG.md`, run tests, then `bash scripts/package-release.sh`. Verify the relocated app and bundled CLI, run the publication check, and attach the ZIP and `.sha256` file to a GitHub release for the tested commit. Build output belongs in release assets, not Git history. Describe ad-hoc signatures accurately; they are not Apple notarization.
