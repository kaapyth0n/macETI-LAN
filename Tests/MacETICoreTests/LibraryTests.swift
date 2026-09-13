import XCTest
import Foundation
@testable import MacETICore

final class LibraryTests: XCTestCase {
    private var temporary: URL!
    override func setUpWithError() throws {
        temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: temporary) }

    private func game(_ id: String, _ title: String, size: Double? = nil, genre: String = "", players: Int? = nil) -> Game {
        var game = Game(id: id, title: title, packageRevision: "20260101", reportedSizeGB: size, readOnlyKey: nil)
        game.metadata.genre = genre
        game.metadata.maximumPlayers = players
        return game
    }

    func testCrossOverDefaultAndExplicitPortOverride() throws {
        let store = PreferencesStore(paths: LibraryPaths(home: temporary))
        XCTAssertEqual(try store.load().preferences(for: "factorio").runtime.kind, .crossOver)
        XCTAssertEqual(try store.load().preferences(for: "amongus").runtime.kind, .crossOver)
        XCTAssertEqual(try store.load().preferences(for: "quake3").runtime.kind, .native)
        try store.update("quake3") { $0.runtime.kind = .crossOver }
        try store.update("factorio") { $0.runtime.kind = .native }
        let reloaded = try PreferencesStore(paths: LibraryPaths(home: temporary)).load()
        XCTAssertEqual(reloaded.preferences(for: "quake3").runtime.kind, .crossOver)
        XCTAssertEqual(reloaded.preferences(for: "factorio").runtime.kind, .native)
        XCTAssertEqual(reloaded.preferences(for: "flat2").runtime.kind, .crossOver)
    }

    func testSavedSelectionPersistsWithoutCreatingSyncSubscriptions() throws {
        let paths = LibraryPaths(home: temporary)
        let store = PreferencesStore(paths: paths)
        try store.update("factorio") { $0.saved = true }
        try store.update("amongus") { $0.saved = false }
        XCTAssertTrue(try store.load().preferences(for: "factorio").saved)
        XCTAssertFalse(try store.load().preferences(for: "amongus").saved)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.syncRoot.appendingPathComponent("factorio").path))
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: store.file.path)[.posixPermissions] as? Int, 0o600)
    }

    func testInvalidPreferencesArePreservedInsteadOfOverwritten() throws {
        let store = PreferencesStore(paths: LibraryPaths(home: temporary))
        try store.update("factorio") { $0.saved = true }
        let data = Data("{\"version\":99,\"games\":{}}".utf8)
        try data.write(to: store.file)
        XCTAssertThrowsError(try store.update("factorio") { $0.saved = false })
        XCTAssertEqual(try Data(contentsOf: store.file), data)
        XCTAssertThrowsError(try store.update("../escape") { $0.saved = false })
    }

    func testSearchGenreScopeAndSortAcrossCatalog() {
        let catalog = Catalog(games: [game("quake3", "Quake III", size: 0.9, genre: "FPS", players: 32),
                                      game("factorio", "Factorio", size: 2, genre: "Strategy", players: 64),
                                      game("flat2", "FlatOut 2", size: 5, genre: "Racing", players: 8)], skippedRows: 0)
        let library = UserLibrary()
        XCTAssertEqual(CatalogFilter.games(in: catalog, library: library).count, 3)
        XCTAssertEqual(CatalogFilter.games(in: catalog, library: library, search: "FACTORIO strategy").map(\.id), ["factorio"])
        XCTAssertEqual(CatalogFilter.games(in: catalog, library: library, genre: "Racing").map(\.id), ["flat2"])
        XCTAssertEqual(CatalogFilter.games(in: catalog, library: library, scope: .native).map(\.id), ["quake3"])
        XCTAssertEqual(CatalogFilter.games(in: catalog, library: library, scope: .saved).count, 2)
        XCTAssertEqual(CatalogFilter.games(in: catalog, library: library, sort: .players).map(\.id), ["factorio", "quake3", "flat2"])
        XCTAssertEqual(CatalogFilter.games(in: catalog, library: library, sort: .size).map(\.id), ["flat2", "factorio", "quake3"])
        XCTAssertTrue(CatalogFilter.games(in: catalog, library: library, search: "nonexistent").isEmpty)
    }

    func testCrossOverArgumentsRemainSeparateAndLiteral() throws {
        let app = temporary.appendingPathComponent("Cross Over.app")
        let wine = app.appendingPathComponent("Contents/SharedSupport/CrossOver/bin/wine")
        try FileManager.default.createDirectory(at: wine.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("test".utf8).write(to: wine)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: wine.path)
        let exe = temporary.appendingPathComponent("Game Name.exe")
        try Data().write(to: exe)
        var config = RuntimeConfiguration()
        config.bottle = "LAN Games"
        config.executablePath = exe.path
        config.arguments = ["+connect", "192.0.2.1", "$(touch /tmp/never-run-this)"]
        let command = try GameLauncher.command(for: config, crossOver: app)
        XCTAssertEqual(command.executable, wine)
        XCTAssertEqual(command.arguments, ["--bottle", "LAN Games", "--workdir", exe.deletingLastPathComponent().path, "--", exe.path] + config.arguments)
        XCTAssertEqual(command.workingDirectory, exe.deletingLastPathComponent())
        let gameDirectory = temporary.appendingPathComponent("Game Data", isDirectory: true)
        try FileManager.default.createDirectory(at: gameDirectory, withIntermediateDirectories: true)
        config.workingDirectory = gameDirectory.path
        let customDirectoryCommand = try GameLauncher.command(for: config, crossOver: app)
        XCTAssertEqual(customDirectoryCommand.arguments, ["--bottle", "LAN Games", "--workdir", gameDirectory.path, "--", exe.path] + config.arguments)
        XCTAssertEqual(customDirectoryCommand.workingDirectory, gameDirectory)
        // Warcraft must retain its previously tested conversion and renderer flags.
        config.arguments = ["-window", "-opengl"]
        let warcraftCommand = try GameLauncher.command(for: config, crossOver: app)
        XCTAssertFalse(warcraftCommand.arguments.contains("--no-convert"))
        XCTAssertEqual(Array(warcraftCommand.arguments.suffix(2)), ["-window", "-opengl"])
        let goldSrc = gameDirectory.appendingPathComponent("hl-cs16/SmartSteamLoader.exe")
        try FileManager.default.createDirectory(at: goldSrc.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: goldSrc)
        config.executablePath = goldSrc.path
        config.arguments = ["-game", "cstrike"]
        let goldSrcCommand = try GameLauncher.command(for: config, crossOver: app)
        XCTAssertTrue(goldSrcCommand.arguments.contains("--no-convert"))
        XCTAssertEqual(Array(goldSrcCommand.arguments.suffix(2)), ["-game", "cstrike"])
        XCTAssertThrowsError(try GameLauncher.command(for: config, crossOver: nil))
        config.bottle = ""
        XCTAssertThrowsError(try GameLauncher.command(for: config, crossOver: app))
    }

    func testNativeDispatchAndMissingExecutable() throws {
        var config = RuntimeConfiguration(kind: .native)
        config.executablePath = "/usr/bin/true"
        let command = try GameLauncher.command(for: config)
        XCTAssertEqual(command.executable.path, "/usr/bin/true")
        let process = try GameLauncher.launch(command)
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        config.executablePath = temporary.appendingPathComponent("missing").path
        XCTAssertThrowsError(try GameLauncher.command(for: config))
        config.executablePath = "relative-path"
        XCTAssertThrowsError(try GameLauncher.command(for: config))
    }
}
