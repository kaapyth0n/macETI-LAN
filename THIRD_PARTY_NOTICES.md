# Third-party notices

macETI-LAN is an independent companion project. ETI-LAN, Resilio Sync, CrossOver, Apple/macOS and the referenced games belong to their respective owners. No affiliation or endorsement is implied.

The repository and releases contain no commercial game packages, catalog database, Resilio access keys, cover archive, CrossOver runtime or native game engine. Users obtain those separately. The optional bootstrap helper reads metadata from ETI-LAN's public bootstrap archive; it does not execute the archive's scripts.

Game covers visible in documentation screenshots are shown to illustrate the launcher. They remain the property of their respective owners and are excluded from the project's MIT license. Do not treat screenshots as a licensed game-art collection. Cover art used by the running app is imported locally from the user's synced archive and is not bundled in the app.

Compatibility notes are project-authored summaries and trial recommendations. Their original sources are linked in the guidance resource; third-party source content retains its own terms.

`assets/AppIcon.png` is an original image generated for this project using OpenAI's built-in image-generation tool. Its prompt and packaging notes are in the source repository's `assets/README.md`. The project's MIT grant applies to this asset to the extent the contributors hold rights in it.

Automatic package setup downloads RARLAB's macOS ARM 7.23 archive from its official HTTPS site and checks pinned SHA-256 hashes before using its UnRAR executable. The downloaded license and readme remain alongside the private cached tool. RAR/UnRAR belong to Alexander Roshal and their respective contributors and retain their own license terms; they are not covered by this project's MIT license or bundled in the repository/release. See [RARLAB downloads](https://www.rarlab.com/download.htm).

The app links Apple's system frameworks and system SQLite. No third-party Swift packages are vendored.
