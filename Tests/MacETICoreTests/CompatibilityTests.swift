import XCTest
import Foundation
@testable import MacETICore

final class CompatibilityTests: XCTestCase {
    private var temporary: URL!
    override func setUpWithError() throws {
        temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: temporary) }

    private func game(revision: String = "20160922") -> Game {
        Game(id: "flat2", title: "FlatOut 2", packageRevision: revision, reportedSizeGB: 5.3, readOnlyKey: nil)
    }
    private func trial() -> CompatibilityTest {
        CompatibilityTest(game: game(), guidanceRevision: "2026-09-12.1", runtime: .init(),
                          runtimeVersion: "26.0", macOSVersion: "15.7", hardware: "Apple M2",
                          gameVersion: "test-build", gameplay: .menu, notes: "Synthetic test fixture")
    }

    func testBundledProfilesCoverTargetsAndRequirePackageForAutomation() throws {
        let catalog = try CompatibilityCatalog.bundled()
        // Curated guidance can grow without changing which games are initially saved.
        XCTAssertTrue(Set(GameProfile.selected.map(\.id)).isSubset(of: Set(catalog.profiles.map(\.gameID))))
        for profile in catalog.profiles {
            let guide = catalog.guide(for: profile.gameID, runtime: .crossOver)
            XCTAssertFalse(guide.automaticSetupAvailable)
            XCTAssertFalse(guide.sources.isEmpty)
            XCTAssertFalse(guide.setup.isEmpty)
            XCTAssertFalse(guide.lanChecklist.isEmpty)
            XCTAssertFalse(profile.reviewedPackageRevision.isEmpty)
        }
        let encoded = String(decoding: try JSONEncoder().encode(catalog.guide(for: "flat2", runtime: .crossOver)), as: UTF8.self)
        XCTAssertTrue(encoded.contains("\"automaticSetupAvailable\":false"))
    }

    func testUnresearchedGamesUseGeneralGuidanceAndRespectRuntimeChoice() throws {
        let catalog = try CompatibilityCatalog.bundled()
        let windows = catalog.guide(for: "factorio", runtime: .crossOver)
        XCTAssertNil(windows.profile)
        XCTAssertEqual(windows.route, .crossOver)
        XCTAssertTrue(windows.sources.contains { $0.id == "cx26" })
        let native = catalog.guide(for: "factorio", runtime: .native)
        XCTAssertNil(native.profile)
        XCTAssertEqual(native.route, .native)
        XCTAssertFalse(native.sources.contains { $0.id == "cx26" })
        // Native recommendations are still labeled native when the saved choice is different.
        XCTAssertEqual(catalog.guide(for: "quake3", runtime: .crossOver).route, .native)
    }

    func testGuideRejectsUnsupportedVersionsInvalidLinksAndBrokenReferences() throws {
        let catalog = try CompatibilityCatalog.bundled()
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(catalog)) as? [String: Any])
        func rejected(_ change: (inout [String: Any]) -> Void) throws {
            var value = original
            change(&value)
            XCTAssertThrowsError(try CompatibilityCatalog.decode(JSONSerialization.data(withJSONObject: value)))
        }
        try rejected { $0["schemaVersion"] = 99 }
        try rejected { value in
            var sources = value["sources"] as! [[String: Any]]
            sources[0]["url"] = "file:///tmp/do-not-open"
            value["sources"] = sources
        }
        try rejected { value in
            var profiles = value["profiles"] as! [[String: Any]]
            profiles[0]["sourceIDs"] = ["missing-source"]
            value["profiles"] = profiles
        }
        try rejected { value in
            var profiles = value["profiles"] as! [[String: Any]]
            profiles.append(profiles[0])
            value["profiles"] = profiles
        }
    }

    func testReadingGuidanceDoesNotWriteLibraryOrStartSync() throws {
        let paths = LibraryPaths(home: temporary)
        let before = try FileManager.default.contentsOfDirectory(atPath: temporary.path)
        let catalog = try CompatibilityCatalog.bundled()
        _ = catalog.guide(for: "flat2", runtime: .crossOver)
        XCTAssertTrue(try CompatibilityTestStore(paths: paths).load().isEmpty)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: temporary.path), before)
    }

    func testLocalResultsPersistIndependentlyOfRuntimeSettingsAndSync() throws {
        let paths = LibraryPaths(home: temporary)
        let preferences = PreferencesStore(paths: paths)
        try preferences.update("flat2") { $0.runtime.bottle = "Existing bottle" }
        let before = try Data(contentsOf: preferences.file)
        let store = CompatibilityTestStore(paths: paths)
        let first = trial()
        try store.append(first)
        var second = trial()
        second.gameplay = .failed
        try store.append(second)
        let loaded = try CompatibilityTestStore(paths: paths).load()
        XCTAssertEqual(loaded.map(\.id), [second.id, first.id])
        XCTAssertEqual(loaded[1].runtimeVersion, "26.0")
        XCTAssertEqual(loaded[1].macOSVersion, "15.7")
        XCTAssertEqual(loaded[1].hardware, "Apple M2")
        XCTAssertEqual(try Data(contentsOf: preferences.file), before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try paths.gameDirectory("flat2").path))
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: store.file.path)[.posixPermissions] as? Int, 0o600)
        XCTAssertThrowsError(try store.append(first))
    }

    func testLANSuccessRequiresObservedGameplayAndBothVersions() throws {
        var test = trial()
        test.gameplay = .notTested
        XCTAssertThrowsError(try test.validate())
        test.gameplay = .menu
        test.lan = .completed
        XCTAssertThrowsError(try test.validate())
        test.gameplay = .played
        XCTAssertThrowsError(try test.validate())
        test.windowsGameVersion = "windows-test-build"
        XCTAssertNoThrow(try test.validate())
        test.runtimeVersion = " "
        XCTAssertThrowsError(try test.validate())
    }

    func testPackageAndConfigurationChangesDoNotInheritHistoricalResults() {
        let test = trial()
        XCTAssertTrue(test.matchesPackageAndSettings(game: game(), runtime: .init()))
        XCTAssertFalse(test.matchesPackageAndSettings(game: game(revision: "20260913"), runtime: .init()))
        var changed = RuntimeConfiguration()
        changed.arguments = ["-windowed"]
        XCTAssertFalse(test.matchesPackageAndSettings(game: game(), runtime: changed))
        changed = .init(kind: .native)
        XCTAssertFalse(test.matchesPackageAndSettings(game: game(), runtime: changed))
    }

    func testInvalidOrFutureLogIsPreservedOnAppend() throws {
        let store = CompatibilityTestStore(paths: LibraryPaths(home: temporary))
        try store.append(trial())
        for invalid in [Data("{\"schemaVersion\":99,\"tests\":[]}".utf8), Data("broken".utf8)] {
            try invalid.write(to: store.file)
            XCTAssertThrowsError(try store.append(trial()))
            XCTAssertEqual(try Data(contentsOf: store.file), invalid)
        }
    }
}
