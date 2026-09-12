import XCTest
import Foundation
import CSQLite
@testable import MacETICore

final class CatalogTests: XCTestCase {
    private var temporary: URL!
    private let key = "B" + String(repeating: "A", count: 32)

    override func setUpWithError() throws {
        temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: temporary)
    }

    private func database(_ sql: String, name: String = "source.db", schema: Bool = true) throws -> URL {
        let url = temporary.appendingPathComponent(name)
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &handle), SQLITE_OK)
        defer { sqlite3_close(handle) }
        if schema {
            XCTAssertEqual(sqlite3_exec(handle, "CREATE TABLE games (db_id INTEGER PRIMARY KEY, game_id TEXT, game_title TEXT, game_version TEXT, game_size NUMERIC, game_key TEXT)", nil, nil, nil), SQLITE_OK)
        }
        XCTAssertEqual(sqlite3_exec(handle, sql, nil, nil, nil), SQLITE_OK)
        return url
    }

    private func insert(_ id: String, title: String = "Test game", accessKey: String? = nil) -> String {
        "INSERT INTO games (game_id, game_title, game_version, game_size, game_key) VALUES ('\(id)', '\(title)', '20250308', 0.3, '\(accessKey ?? key)');"
    }

    func testReadsRealETISchemaAndPreservesPackageRevision() throws {
        let source = try database(insert("amongus", title: "Among Us"))
        let catalog = try CatalogReader.read(source)
        XCTAssertEqual(catalog.game(id: "amongus")?.packageRevision, "20250308")
        XCTAssertEqual(catalog.games.first?.reportedSizeGB, 0.3)
        XCTAssertNotNil(catalog.games.first?.readOnlyKey)
    }

    func testRejectsWriteKeysAndRedactsReadKeys() throws {
        let source = try database(insert("quake3", accessKey: "A" + String(repeating: "A", count: 32)) + insert("amongus"))
        let catalog = try CatalogReader.read(source)
        XCTAssertNil(catalog.game(id: "quake3")?.readOnlyKey)
        XCTAssertFalse(String(describing: catalog.games).contains(key))
        let output = String(decoding: try JSONEncoder().encode(catalog.games.map(\.summary)), as: UTF8.self)
        XCTAssertFalse(output.contains(key))
        XCTAssertFalse(output.contains("game_key"))
    }

    func testSkipsTraversalAndControlCharacters() throws {
        let source = try database(insert("../escape") + insert("quake3", title: "bad\nname") + insert("amongus"))
        let catalog = try CatalogReader.read(source)
        XCTAssertEqual(catalog.games.map(\.id), ["amongus"])
        XCTAssertEqual(catalog.skippedRows, 2)
    }

    func testDuplicateIDsFailImport() throws {
        let source = try database(insert("quake3") + insert("quake3"))
        XCTAssertThrowsError(try CatalogReader.read(source))
    }

    func testViewCannotReplaceCatalogTable() throws {
        let source = try database("CREATE VIEW games AS SELECT 'quake3' AS game_id;", schema: false)
        XCTAssertThrowsError(try CatalogReader.read(source))
    }

    func testMissingColumnsAreRejected() throws {
        let source = try database("CREATE TABLE games (id TEXT);", schema: false)
        XCTAssertThrowsError(try CatalogReader.read(source))
    }

    func testInvalidSizeDoesNotBecomeZero() throws {
        let source = try database(insert("quake3") + "UPDATE games SET game_size='unknown';")
        XCTAssertNil(try CatalogReader.read(source).games.first?.reportedSizeGB)
    }

    func testFailedImportPreservesSavedCatalog() throws {
        let store = LibraryStore(paths: LibraryPaths(home: temporary))
        let source = try database(insert("quake3"))
        let firstReceipt = try store.importCatalog(from: source)
        let broken = temporary.appendingPathComponent("broken.db")
        try Data("not a database".utf8).write(to: broken)
        XCTAssertThrowsError(try store.importCatalog(from: broken))
        let (catalog, receipt) = try store.load()
        XCTAssertEqual(catalog.games.map(\.id), ["quake3"])
        XCTAssertEqual(receipt?.sha256, firstReceipt.sha256)
        let permissions = try FileManager.default.attributesOfItem(atPath: store.paths.snapshot.path)[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o600)
    }

    func testActiveJournalIsNotImported() throws {
        let source = try database(insert("quake3"))
        try Data().write(to: URL(fileURLWithPath: source.path + "-wal"))
        XCTAssertThrowsError(try LibraryStore(paths: LibraryPaths(home: temporary)).importCatalog(from: source))
    }

    func testPlanIncludesAnyCatalogGameAndDoesNotCreateGameFolders() throws {
        let paths = LibraryPaths(home: temporary)
        let store = LibraryStore(paths: paths)
        let source = try database(insert("quake3") + insert("factorio"))
        let plan = try store.plan(CatalogReader.read(source))
        XCTAssertEqual(plan.count, 2)
        XCTAssertEqual(plan.first(where: { $0.id == "factorio" })?.canConnect, true)
        XCTAssertEqual(plan.first(where: { $0.id == "factorio" })?.runtime, "CrossOver")
        XCTAssertThrowsError(try store.plan(CatalogReader.read(source), gameIDs: ["missing"]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.syncRoot.path))
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(plan), as: UTF8.self).contains(key))
    }

    func testGamePathsRejectTraversalAndEscapingSymlink() throws {
        let paths = LibraryPaths(home: temporary)
        try paths.createDirectories()
        XCTAssertThrowsError(try paths.gameDirectory("../outside"))
        XCTAssertThrowsError(try paths.gameDirectory("eti_launcher"))
        XCTAssertEqual(try paths.gameDirectory("quake3").lastPathComponent, "quake3")
        let outside = temporary.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: paths.syncRoot.appendingPathComponent("quake3"), withDestinationURL: outside)
        XCTAssertThrowsError(try paths.gameDirectory("quake3"))
    }

    func testMismatchedReceiptIsNotPresentedAsProvenance() throws {
        let store = LibraryStore(paths: LibraryPaths(home: temporary))
        let first = try database(insert("quake3"))
        try store.importCatalog(from: first)
        let second = try database(insert("amongus"), name: "second.db")
        try Data(contentsOf: second).write(to: store.paths.snapshot, options: .atomic)
        let (catalog, receipt) = try store.load()
        XCTAssertEqual(catalog.games.map(\.id), ["amongus"])
        XCTAssertNil(receipt)
    }
}
