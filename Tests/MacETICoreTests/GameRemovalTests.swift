import Foundation
import XCTest
@testable import MacETICore

final class GameRemovalTests: XCTestCase {
    private var home: URL!
    private var paths: LibraryPaths { .init(home: home) }
    private var preferences: PreferencesStore { .init(paths: paths) }
    private var fm: FileManager { .default }
    private var install: URL { home.appendingPathComponent("Library/Application Support/CrossOver/Bottles/TestBottle/drive_c/AmongUs") }
    private var download: URL { paths.syncRoot.appendingPathComponent("amongus") }

    override func setUpWithError() throws {
        home = fm.temporaryDirectory.appendingPathComponent("maceti-removal-\(UUID().uuidString)").resolvingSymlinksInPath()
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try fm.removeItem(at: home) }

    private func file(_ url: URL, text: String = "synthetic fixture") throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }
    private func fixture() throws -> RuntimeConfiguration {
        var config = RuntimeConfiguration()
        config.bottle = "TestBottle"
        config.executablePath = install.appendingPathComponent("Among Us.exe").path
        config.workingDirectory = install.path
        config.arguments = ["-example"]
        try file(URL(fileURLWithPath: config.executablePath))
        try file(install.appendingPathComponent("save.dat"), text: "save inside game")
        try file(download.appendingPathComponent("game.eti"))
        try file(install.deletingLastPathComponent().appendingPathComponent("users/player/save.dat"), text: "save outside game")
        try file(install.deletingLastPathComponent().appendingPathComponent("AnotherGame/game.exe"))
        try preferences.update("amongus") { $0.runtime = config; $0.saved = true }
        return config
    }
    private func worker() throws -> GameRemoval {
        let trash = home.appendingPathComponent("FixtureTrash")
        try fm.createDirectory(at: trash, withIntermediateDirectories: true)
        var worker = GameRemoval(paths: paths, home: home)
        worker.trash = { source in
            var destination = trash.appendingPathComponent(source.lastPathComponent)
            if FileManager.default.fileExists(atPath: destination.path) { destination = trash.appendingPathComponent(source.lastPathComponent + "-2") }
            try FileManager.default.moveItem(at: source, to: destination)
            return destination
        }
        return worker
    }
    private func remove(_ worker: GameRemoval, plan: GameRemovalPlan? = nil, kinds: Set<GameRemovalKind>) throws -> UserLibrary {
        try worker.perform(plan ?? worker.plan(gameID: "amongus"), kinds: kinds, gameClosed: true, downloadDisconnected: true)
    }

    func testInstallOnlyKeepsDownloadBottleOtherGameAndExternalSaves() throws {
        let config = try fixture()
        let result = try remove(worker(), kinds: [.installation]).preferences(for: "amongus")
        XCTAssertTrue(result.runtime.executablePath.isEmpty)
        XCTAssertTrue(result.runtime.workingDirectory.isEmpty)
        XCTAssertEqual(result.runtime.arguments, [])
        XCTAssertEqual(result.runtime.bottle, config.bottle)
        XCTAssertTrue(result.saved)
        XCTAssertFalse(fm.fileExists(atPath: install.path))
        XCTAssertTrue(fm.fileExists(atPath: download.path))
        XCTAssertTrue(fm.fileExists(atPath: install.deletingLastPathComponent().appendingPathComponent("users/player/save.dat").path))
        XCTAssertTrue(fm.fileExists(atPath: install.deletingLastPathComponent().appendingPathComponent("AnotherGame/game.exe").path))
        XCTAssertEqual(try String(contentsOf: home.appendingPathComponent("FixtureTrash/AmongUs/save.dat"), encoding: .utf8), "save inside game")
    }

    func testDownloadOnlyRetainsLaunchSettingsAndInstallation() throws {
        let config = try fixture()
        let result = try remove(worker(), kinds: [.download])
        XCTAssertEqual(result.preferences(for: "amongus").runtime, config)
        XCTAssertTrue(fm.fileExists(atPath: install.path))
        XCTAssertFalse(fm.fileExists(atPath: download.path))
    }

    func testBothFoldersMoveAndCatalogIsPreserved() throws {
        _ = try fixture()
        try file(paths.snapshot, text: "catalog fixture")
        let worker = try worker()
        _ = try remove(worker, kinds: [.installation, .download])
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: home.appendingPathComponent("FixtureTrash").path).count, 2)
        XCTAssertEqual(try String(contentsOf: paths.snapshot, encoding: .utf8), "catalog fixture")
        XCTAssertTrue(try worker.plan(gameID: "amongus").folders.isEmpty)
    }

    func testRequiresClosedGameAndDisconnectedDownloadBeforeAnyMove() throws {
        _ = try fixture()
        var worker = try worker()
        worker.trash = { _ in XCTFail("Acknowledgements must precede file operations"); throw ETIError("Unexpected move") }
        let plan = try worker.plan(gameID: "amongus")
        XCTAssertThrowsError(try worker.perform(plan, kinds: [.download], gameClosed: true, downloadDisconnected: false))
        XCTAssertThrowsError(try worker.perform(plan, kinds: [.installation], gameClosed: false, downloadDisconnected: true))
        XCTAssertThrowsError(try worker.perform(plan, kinds: [], gameClosed: true, downloadDisconnected: true))
    }

    func testSecondMoveFailureRestoresFirstAndPreservesPreferences() throws {
        let config = try fixture()
        var worker = try worker()
        let move = worker.trash
        let failing = download
        worker.trash = { source in
            if source.path == failing.path { throw ETIError("Simulated download move failure") }
            return try move(source)
        }
        XCTAssertThrowsError(try remove(worker, kinds: [.installation, .download])) { error in
            XCTAssertTrue(error.localizedDescription.contains("Simulated download move failure"))
        }
        XCTAssertTrue(fm.fileExists(atPath: install.path))
        XCTAssertTrue(fm.fileExists(atPath: download.path))
        XCTAssertEqual(try preferences.load().preferences(for: "amongus").runtime, config)
        XCTAssertTrue(try fm.contentsOfDirectory(atPath: home.appendingPathComponent("FixtureTrash").path).isEmpty)
    }

    func testFailedPreferenceWriteRestoresMovedFolder() throws {
        _ = try fixture()
        var worker = try worker()
        let move = worker.trash
        let prefFile = preferences.file
        worker.trash = { source in
            let result = try move(source)
            // Simulate a preferences write failure after the move.
            try FileManager.default.moveItem(at: prefFile, to: prefFile.appendingPathExtension("backup"))
            try FileManager.default.createDirectory(at: prefFile, withIntermediateDirectories: false)
            return result
        }
        XCTAssertThrowsError(try remove(worker, kinds: [.installation]))
        XCTAssertTrue(fm.fileExists(atPath: install.path))
        XCTAssertTrue(try fm.contentsOfDirectory(atPath: home.appendingPathComponent("FixtureTrash").path).isEmpty)
    }

    func testRuntimeEditAndNewSharedReferenceInvalidateReviewedPlan() throws {
        let config = try fixture()
        let worker = try worker()
        let reviewed = try worker.plan(gameID: "amongus")
        try preferences.update("amongus") { $0.runtime.arguments = ["changed"] }
        XCTAssertThrowsError(try remove(worker, plan: reviewed, kinds: [.installation]))
        try preferences.update("amongus") { $0.runtime = config }
        try preferences.update("another") { $0.runtime = config }
        XCTAssertThrowsError(try remove(worker, plan: reviewed, kinds: [.installation]))
        XCTAssertTrue(fm.fileExists(atPath: install.path))
    }

    func testReplacingReviewedFolderOrSymlinkCannotDeleteReplacement() throws {
        _ = try fixture()
        let worker = try worker()
        let reviewed = try worker.plan(gameID: "amongus")
        let moved = home.appendingPathComponent("OriginalDownload")
        try fm.moveItem(at: download, to: moved)
        try file(download.appendingPathComponent("replacement.txt"))
        XCTAssertThrowsError(try remove(worker, plan: reviewed, kinds: [.download]))
        try fm.removeItem(at: download)
        try fm.createSymbolicLink(at: download, withDestinationURL: moved)
        XCTAssertThrowsError(try remove(worker, plan: reviewed, kinds: [.download]))
        XCTAssertTrue(fm.fileExists(atPath: moved.appendingPathComponent("game.eti").path))
    }

    func testUnmanagedPathsAndWindowsSharedDirectoriesAreNotOffered() throws {
        var config = try fixture()
        let worker = try worker()
        for path in [home.appendingPathComponent("Documents"), install.deletingLastPathComponent(),
                     install.deletingLastPathComponent().appendingPathComponent("Program Files"),
                     install.deletingLastPathComponent().appendingPathComponent("users")] {
            config.executablePath = path.appendingPathComponent("game.exe").path
            config.workingDirectory = path.path
            try file(URL(fileURLWithPath: config.executablePath))
            try preferences.update("amongus") { $0.runtime = config }
            XCTAssertFalse(try worker.plan(gameID: "amongus").folders.contains { $0.kind == .installation })
        }
    }

    func testNativeRemovalIncludesItsUserDataButPreservesOtherRuntime() throws {
        let root = paths.runtimeRoot.appendingPathComponent("quake3")
        try file(root.appendingPathComponent("ioquake3.app/Contents/MacOS/ioquake3"))
        try file(root.appendingPathComponent("UserData/config.cfg"))
        try file(paths.runtimeRoot.appendingPathComponent("other/engine"))
        var config = RuntimeConfiguration(kind: .native)
        config.executablePath = root.appendingPathComponent("ioquake3.app/Contents/MacOS/ioquake3").path
        config.workingDirectory = root.path
        try preferences.update("quake3") { $0.runtime = config }
        let worker = try worker()
        let plan = try worker.plan(gameID: "quake3")
        XCTAssertEqual(plan.folders.map { $0.url.path }, [root.path])
        let result = try worker.perform(plan, kinds: [.installation], gameClosed: true, downloadDisconnected: false)
        XCTAssertEqual(result.preferences(for: "quake3").runtime.kind, .native)
        XCTAssertTrue(fm.fileExists(atPath: home.appendingPathComponent("FixtureTrash/quake3/UserData/config.cfg").path))
        XCTAssertTrue(fm.fileExists(atPath: paths.runtimeRoot.appendingPathComponent("other/engine").path))
    }

    func testDownloadUsedAsRuntimeClearsLaunchSettingsOnRemoval() throws {
        _ = try fixture()
        try preferences.update("amongus") { $0.runtime.executablePath = download.appendingPathComponent("game.exe").path; $0.runtime.workingDirectory = download.path }
        XCTAssertTrue(try remove(worker(), kinds: [.download]).preferences(for: "amongus").runtime.executablePath.isEmpty)
    }

    func testExistingSetupLockPreventsRemoval() throws {
        _ = try fixture()
        let worker = try worker()
        let setup = paths.support.appendingPathComponent("Setup")
        try fm.createDirectory(at: setup, withIntermediateDirectories: true)
        let fd = Darwin.open(setup.appendingPathComponent("setup.lock").path, O_CREAT | O_RDWR, 0o600)
        XCTAssertGreaterThanOrEqual(fd, 0)
        defer { flock(fd, LOCK_UN); Darwin.close(fd) }
        XCTAssertEqual(flock(fd, LOCK_EX | LOCK_NB), 0)
        XCTAssertThrowsError(try remove(worker, kinds: [.installation]))
        XCTAssertTrue(fm.fileExists(atPath: install.path))
    }

    func testInvalidGameIDsAndSharedSymlinkReferencesAreRejected() throws {
        _ = try fixture()
        let worker = try worker()
        for id in ["eti_launcher", "..", "../amongus", ""] { XCTAssertThrowsError(try worker.plan(gameID: id)) }
        let alias = home.appendingPathComponent("Alias")
        try fm.createSymbolicLink(at: alias, withDestinationURL: install)
        try preferences.update("another") { $0.runtime.executablePath = alias.appendingPathComponent("game.exe").path }
        let plan = try worker.plan(gameID: "amongus")
        XCTAssertEqual(plan.folders.map(\.kind), [.download])
        XCTAssertTrue(plan.notes.contains { $0.contains("another") })
    }

    func testCaseVariantsOfSharedExistingPathAreProtected() throws {
        let config = try fixture()
        let lower = config.executablePath.lowercased()
        // This assertion is relevant on the default case-insensitive macOS volume.
        guard fm.fileExists(atPath: lower) else { throw XCTSkip("Case-sensitive volume") }
        try preferences.update("another") { $0.runtime.executablePath = lower }
        XCTAssertFalse(try worker().plan(gameID: "amongus").folders.contains { $0.kind == .installation })
    }

    func testLinkedInstallationIsExcludedAndSizeDoesNotFollowInnerLinks() throws {
        _ = try fixture()
        let before = GameRemoval.allocatedBytes(at: install)
        XCTAssertNotNil(before)
        let external = home.appendingPathComponent("External")
        try file(external.appendingPathComponent("data"), text: String(repeating: "x", count: 100_000))
        try fm.createSymbolicLink(at: install.appendingPathComponent("ExternalLink"), withDestinationURL: external)
        XCTAssertEqual(GameRemoval.allocatedBytes(at: install), before)
        let moved = home.appendingPathComponent("MovedGame")
        try fm.moveItem(at: install, to: moved)
        try fm.createSymbolicLink(at: install, withDestinationURL: moved)
        XCTAssertFalse(try worker().plan(gameID: "amongus").folders.contains { $0.kind == .installation })
    }
}
