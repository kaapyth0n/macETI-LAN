import AppKit
import Foundation
import MacETICore

@main
struct MacETICLI {
    @MainActor
    static func main() {
        do { try run() }
        catch {
            FileHandle.standardError.write(Data("maceti: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    @MainActor
    static func run() throws {
        var args = Array(CommandLine.arguments.dropFirst())
        var root: URL?
        if let index = args.firstIndex(of: "--sync-root") {
            guard args.indices.contains(index + 1) else { throw ETIError("--sync-root requires a path.") }
            root = URL(fileURLWithPath: NSString(string: args[index + 1]).expandingTildeInPath)
            args.removeSubrange(index...(index + 1))
        }
        let paths = LibraryPaths(syncRoot: root)
        let store = LibraryStore(paths: paths)
        let command = args.first ?? "help"
        let rest = Array(args.dropFirst())
        switch command {
        case "help", "--help", "-h":
            print("""
            maceti — native ETI catalog companion

            doctor [--json]       Inspect this Mac and the Resilio installation
            init                  Create dedicated library and private runtime folders
            import [game.db]       Validate and save the live catalog (or the supplied file)
            catalog [--saved] [--json]  Show all games, or the saved My games selection
            plan [GAME_ID ...] [--saved] [--json]  Plan sync for any catalog games
            save GAME_ID         Add a game to My games (does not start sync)
            unsave GAME_ID       Remove from My games (does not disconnect Resilio)
            runtime GAME_ID [crossover|native]  Show settings or change runtime choice
            launch GAME_ID [--dry-run]  Launch the configured local game executable
            compatibility GAME_ID [--json]  Read setup guidance and dated sources
            copy-key GAME_ID      Copy any catalog game's read-only key to the clipboard
            copy-key launcher     Copy the privately stored launcher key
            resilio               Open the installed Resilio desktop app

            Add --sync-root PATH to use a different Resilio library root for this command.
            Package revisions and catalog sizes are ETI metadata, not game versions or measured downloads.
            """)
        case "init":
            try require(rest.isEmpty)
            try paths.createDirectories()
            print("Library: \(paths.syncRoot.path)\nCatalog: \(paths.liveCatalog.path)\nRuntime data: \(paths.runtimeRoot.path)")
        case "doctor":
            try require(rest.allSatisfy { $0 == "--json" })
            let status = ResilioDesktop.status(paths: paths)
            if rest.contains("--json") { try json(status) }
            else {
                print("Architecture: \(status.architecture)\nResilio: \(status.resilioVersion ?? "not found") — \(status.resilioRunning ? "running" : "not running")")
                print("Live catalog: \(status.liveCatalogPresent ? "present" : "missing")\nSaved catalog: \(status.savedCatalogPresent ? "present" : "missing")")
                print("Library: \(status.syncRoot)\nIntegration: \(status.integration)")
            }
        case "import":
            try require(rest.count <= 1 && !(rest.first?.hasPrefix("--") ?? false))
            let source = rest.first.map { URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath) } ?? paths.liveCatalog
            let receipt = try store.importCatalog(from: source)
            print("Imported \(receipt.gameCount) games; skipped \(receipt.skippedRows) invalid rows.\nSHA-256: \(receipt.sha256)")
        case "catalog":
            try require(rest.allSatisfy { ["--all", "--saved", "--json"].contains($0) })
            let (catalog, _) = try store.load()
            let library = try PreferencesStore(paths: paths).load()
            let games = CatalogFilter.games(in: catalog, library: library, scope: rest.contains("--saved") ? .saved : .all).map(\.summary)
            if rest.contains("--json") { try json(games) }
            else {
                for game in games {
                    print("\(game.id)\t\(game.title)\tpackage \(game.packageRevision)\t\(game.canConnect ? "read-only sync available" : "no usable key")")
                }
            }
        case "plan":
            try require(rest.allSatisfy { !$0.hasPrefix("--") || ["--json", "--saved"].contains($0) })
            let (catalog, _) = try store.load()
            let library = try PreferencesStore(paths: paths).load()
            var ids = rest.filter { !$0.hasPrefix("--") }
            try require(!rest.contains("--saved") || ids.isEmpty)
            if rest.contains("--saved") { ids = CatalogFilter.games(in: catalog, library: library, scope: .saved).map(\.id) }
            let plan = try store.plan(catalog, gameIDs: ids.isEmpty && !rest.contains("--saved") ? nil : ids, library: library)
            if rest.contains("--json") { try json(plan) }
            else { for item in plan { print("\(item.title)\n  \(item.destination)\n  \(item.runtime) · \(item.status)") } }
        case "compatibility":
            try require(rest.count == 1 || (rest.count == 2 && rest[1] == "--json"))
            let (catalog, _) = try store.load()
            guard let game = catalog.game(id: rest[0]) else { throw ETIError("Game is not in this catalog.") }
            let runtime = try PreferencesStore(paths: paths).load().preferences(for: game.id).runtime.kind
            let guide = try CompatibilityCatalog.bundled().guide(for: game.id, runtime: runtime)
            if rest.contains("--json") { try json(guide) }
            else {
                print("\(game.title) · \(guide.route.title) · reviewed \(guide.reviewedAt)")
                print(guide.profile?.summary ?? "General guidance only; no game-specific profile has been researched.")
                print("Automatic setup is not available. Guidance is not a test result.")
                for note in guide.setup + guide.troubleshooting { print("\n\(note.title)\n\(note.detail)") }
                print("\nWindows LAN checklist:")
                for item in guide.lanChecklist { print("- \(item)") }
                for source in guide.sources { print("\n\(source.title)\n\(source.url.absoluteString)\n\(source.context)") }
            }
        case "copy-key":
            try require(rest.count == 1)
            let key: ReadOnlyKey
            if rest[0] == "launcher" {
                guard let launcher = ReadOnlyKey(try String(contentsOf: paths.launcherKey, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)) else {
                    throw ETIError("No usable launcher key. Run scripts/bootstrap-catalog.py first.")
                }
                key = launcher
            } else {
                let (catalog, _) = try store.load()
                guard let gameKey = catalog.game(id: rest[0])?.readOnlyKey else { throw ETIError("No read-only key is available in this catalog.") }
                key = gameKey
            }
            ResilioDesktop.copyKey(key)
            print("Read-only key copied. In Resilio, choose + → Enter a key or link. No transfer has been started by maceti.")
        case "save", "unsave", "runtime", "launch":
            try require(!rest.isEmpty)
            let (catalog, _) = try store.load()
            guard catalog.game(id: rest[0]) != nil else { throw ETIError("Game is not in this catalog.") }
            let preferences = PreferencesStore(paths: paths)
            switch command {
            case "save", "unsave":
                try require(rest.count == 1)
                try preferences.update(rest[0]) { $0.saved = command == "save" }
                print("My games updated. Resilio subscriptions are unchanged.")
            case "runtime":
                try require(rest.count <= 2)
                if rest.count == 2 {
                    guard ["crossover", "native"].contains(rest[1]) else { throw ETIError("Runtime must be crossover or native.") }
                    try preferences.update(rest[0]) { $0.runtime.kind = rest[1] == "native" ? .native : .crossOver }
                }
                try json(preferences.load().preferences(for: rest[0]).runtime)
            default:
                try require(rest.count == 1 || (rest.count == 2 && rest[1] == "--dry-run"))
                let config = try preferences.load().preferences(for: rest[0]).runtime
                let launch = try GameLauncher.command(for: config)
                if rest.contains("--dry-run") {
                    try json(launch)
                } else {
                    let process = try GameLauncher.launch(launch)
                    process.waitUntilExit()
                    if process.terminationStatus != 0 { throw ETIError("Launch process exited with code \(process.terminationStatus).") }
                }
            }
        case "resilio":
            try require(rest.isEmpty)
            try ResilioDesktop.open()
        default: throw ETIError("Unknown command. Run maceti help.")
        }
    }

    static func require(_ condition: Bool) throws {
        if !condition { throw ETIError("Invalid arguments. Run maceti help.") }
    }

    static func json<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(decoding: try encoder.encode(value), as: UTF8.self))
    }
}
