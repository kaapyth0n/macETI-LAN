import XCTest
import Foundation
@testable import MacETICore

final class SetupTests: XCTestCase {
    private var home: URL!
    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("maceti-setup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: home) }
    private var paths: LibraryPaths { .init(home: home) }
    private var recipe: CrossOverRecipe { CrossOverRecipe.recipe(for: "amongus", revision: "20250308")! }

    private static func listing(_ recipe: CrossOverRecipe) -> String {
        recipe.requiredFiles.map { "        Name: \($0)\n        Type: File\n        Size: 16\n" }.joined(separator: "\n")
        + "\n        Name: Game_Data\n        Type: Directory\n"
    }

    private func setup() throws -> CrossOverSetup {
        let app = home.appendingPathComponent("Cross Over.app")
        let bin = app.appendingPathComponent("Contents/SharedSupport/CrossOver/bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        for name in ["cxbottle", "wine"] {
            let exe = bin.appendingPathComponent(name)
            try Data("fixture".utf8).write(to: exe)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: exe.path)
        }
        var setup = CrossOverSetup(paths: paths, home: home, crossOver: app)
        let bottles = setup.bottles
        let recipe = self.recipe
        setup.archiveTool = { _, _, _ in URL(fileURLWithPath: "/synthetic/unrar") }
        setup.run = { exe, args, log, _ in
            if exe.lastPathComponent == "cxbottle" {
                XCTAssertEqual(Array(args.suffix(3)), ["--create", "--template", "win10_64"])
                let bottle = bottles.appendingPathComponent(args[1])
                try FileManager.default.createDirectory(at: bottle.appendingPathComponent("drive_c"), withIntermediateDirectories: true)
                try Data("fixture".utf8).write(to: bottle.appendingPathComponent("cxbottle.conf"))
            } else if args.first == "lt" {
                try Data(Self.listing(recipe).utf8).write(to: log)
            } else if args.first == "x" {
                let destination = URL(fileURLWithPath: args.last!)
                for file in recipe.requiredFiles { try Data("synthetic fixture".utf8).write(to: destination.appendingPathComponent(file)) }
            } else { XCTFail("Unexpected setup command") }
        }
        return setup
    }

    private func package() throws {
        let folder = try paths.gameDirectory(recipe.gameID)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("amongus.eti")
        FileManager.default.createFile(atPath: file.path, contents: nil)
        let handle = try FileHandle(forWritingTo: file)
        // Sparse placeholder; extraction is mocked. No commercial game data in tests.
        try handle.truncate(atOffset: UInt64(recipe.archiveBytes))
        try handle.close()
        try Data(recipe.packageRevision.utf8).write(to: folder.appendingPathComponent("version.ini"))
    }

    func testBottleCreationSavesAndReusesWithoutSyncPackage() throws {
        var worker = try setup()
        let config = try worker.perform(gameID: "factorio", revision: "anything", mode: .bottleOnly, expectedRuntime: .init()) { _ in }
        XCTAssertTrue(config.bottle.hasPrefix("macETI-factorio-"))
        XCTAssertTrue(config.executablePath.isEmpty)
        XCTAssertEqual(try PreferencesStore(paths: paths).load().preferences(for: "factorio").runtime, config)
        worker.run = { _, _, _, _ in XCTFail("Existing bottle must not be created twice") }
        XCTAssertEqual(try worker.perform(gameID: "factorio", revision: "anything", mode: .bottleOnly, expectedRuntime: config) { _ in }, config)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.syncRoot.appendingPathComponent("factorio").path))
    }

    func testExactPackageInstallAndIdempotencePreserveExistingGame() throws {
        var worker = try setup()
        try package()
        let config = try worker.perform(gameID: recipe.gameID, revision: recipe.packageRevision, mode: .installPackage, expectedRuntime: .init()) { _ in }
        XCTAssertEqual(URL(fileURLWithPath: config.executablePath).lastPathComponent, "Among Us.exe")
        XCTAssertTrue(config.executablePath.hasPrefix(worker.bottles.path))
        XCTAssertEqual(config.arguments, [])
        XCTAssertEqual(config.workingDirectory, URL(fileURLWithPath: config.executablePath).deletingLastPathComponent().path)
        try Data("user save".utf8).write(to: URL(fileURLWithPath: config.workingDirectory).appendingPathComponent("save.dat"))
        worker.run = { _, _, _, _ in XCTFail("A configured game must not be reinstalled") }
        let again = try worker.perform(gameID: recipe.gameID, revision: "new-revision", mode: .installPackage, expectedRuntime: config) { _ in }
        XCTAssertEqual(config, again)
        XCTAssertEqual(try String(contentsOf: URL(fileURLWithPath: config.workingDirectory).appendingPathComponent("save.dat"), encoding: .utf8), "user save")
    }

    func testUnsupportedOrIncompletePackageCannotCreateBottle() throws {
        var worker = try setup()
        worker.run = { _, _, _, _ in XCTFail("Preflight must fail before any command") }
        XCTAssertThrowsError(try worker.perform(gameID: "amongus", revision: "future", mode: .installPackage, expectedRuntime: .init()) { _ in })
        XCTAssertThrowsError(try worker.perform(gameID: "amongus", revision: recipe.packageRevision, mode: .installPackage, expectedRuntime: .init()) { _ in })
        XCTAssertFalse(FileManager.default.fileExists(atPath: worker.bottles.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: PreferencesStore(paths: paths).file.path))
    }

    func testCancelledExtractionRemovesStageAndKeepsPreferences() throws {
        var worker = try setup()
        try package()
        let original = worker.run
        worker.run = { exe, args, log, cancellable in
            try original(exe, args, log, cancellable)
            if args.first == "x" { throw CancellationError() }
        }
        XCTAssertThrowsError(try worker.perform(gameID: "amongus", revision: recipe.packageRevision, mode: .installPackage, expectedRuntime: .init()) { _ in })
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: worker.logs.path).contains { $0.hasPrefix(".staging-") })
        XCTAssertFalse(FileManager.default.fileExists(atPath: worker.bottles.path))
        XCTAssertTrue(try PreferencesStore(paths: paths).load().preferences(for: "amongus").runtime.bottle.isEmpty)
    }

    func testFailedCreationKeepsOwnedPartialBottleAndRefusesBlindRetry() throws {
        var worker = try setup()
        let original = worker.run
        worker.run = { exe, args, log, cancellable in
            try original(exe, args, log, cancellable)
            throw ETIError("Simulated creation failure")
        }
        XCTAssertThrowsError(try worker.perform(gameID: "factorio", revision: "1", mode: .bottleOnly, expectedRuntime: .init()) { _ in })
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: worker.bottles.path).count, 1)
        worker.run = { _, _, _, _ in XCTFail("An incomplete bottle must be inspected before retry") }
        XCTAssertThrowsError(try worker.perform(gameID: "factorio", revision: "1", mode: .bottleOnly, expectedRuntime: .init()) { _ in })
        XCTAssertTrue(try PreferencesStore(paths: paths).load().preferences(for: "factorio").runtime.bottle.isEmpty)
    }

    func testConcurrentRuntimeEditIsPreservedButPreparedBottleCanBeRecovered() throws {
        var worker = try setup()
        let original = worker.run
        let preferences = PreferencesStore(paths: paths)
        worker.run = { exe, args, log, cancellable in
            try original(exe, args, log, cancellable)
            try preferences.update("factorio") { $0.runtime.arguments = ["user-edited"] }
        }
        XCTAssertThrowsError(try worker.perform(gameID: "factorio", revision: "1", mode: .bottleOnly, expectedRuntime: .init()) { _ in })
        let edited = try preferences.load().preferences(for: "factorio").runtime
        XCTAssertEqual(edited.arguments, ["user-edited"])
        worker.run = { _, _, _, _ in XCTFail("Completed bottle should be recovered without another creation") }
        let result = try worker.perform(gameID: "factorio", revision: "1", mode: .bottleOnly, expectedRuntime: edited) { _ in }
        XCTAssertEqual(result.arguments, ["user-edited"])
        XCTAssertFalse(result.bottle.isEmpty)
    }

    func testArchiveValidationRejectsTraversalLinksDuplicatesAndOversize() throws {
        let valid = Self.listing(recipe)
        XCTAssertEqual(try ArchiveContents.validate(valid, recipe: recipe), 48)
        for name in ["../outside", "/absolute", "C:\\escape", "folder/../../escape", "file:stream", "dir/", "dir/file.", "dir/file "] {
            XCTAssertThrowsError(try ArchiveContents.validate(valid + "\nName: \(name)\nType: File\nSize: 1\n", recipe: recipe))
        }
        XCTAssertThrowsError(try ArchiveContents.validate(valid + "\nName: alias\nType: Unix symbolic link\nSize: 1\n", recipe: recipe))
        XCTAssertThrowsError(try ArchiveContents.validate(valid + "\nName: alias\nType: File\nSize: 1\nTarget: /tmp/outside\n", recipe: recipe))
        XCTAssertThrowsError(try ArchiveContents.validate(valid + "\nName: among us.EXE\nType: File\nSize: 1\n", recipe: recipe))
        XCTAssertThrowsError(try ArchiveContents.validate(valid + "\nName: huge\nType: File\nSize: 9223372036854775807\n", recipe: recipe))
        XCTAssertThrowsError(try ArchiveContents.validate("Name: game.exe\nType: File\nSize: 1", recipe: recipe))
    }

    func testAutomaticAvailabilityRequiresExactRevisionAndCrossOver() throws {
        let catalog = try CompatibilityCatalog.bundled()
        XCTAssertTrue(catalog.guide(for: "amongus", runtime: .crossOver, packageRevision: "20250308").automaticSetupAvailable)
        XCTAssertTrue(catalog.guide(for: "rocket", runtime: .crossOver, packageRevision: "20260410").automaticSetupAvailable)
        XCTAssertFalse(catalog.guide(for: "amongus", runtime: .native, packageRevision: "20250308").automaticSetupAvailable)
        XCTAssertFalse(catalog.guide(for: "amongus", runtime: .crossOver, packageRevision: "future").automaticSetupAvailable)
        XCTAssertFalse(catalog.guide(for: "factorio", runtime: .crossOver, packageRevision: "20250308").automaticSetupAvailable)
    }
}
