import Foundation
import CryptoKit

public struct LibraryPaths: Sendable {
    public let support: URL
    public let syncRoot: URL
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, syncRoot: URL? = nil) {
        support = home.appendingPathComponent("Library/Application Support/macETI-LAN", isDirectory: true)
        self.syncRoot = syncRoot ?? home.appendingPathComponent("Resilio Sync/macETI-LAN", isDirectory: true)
    }
    public var liveCatalog: URL { syncRoot.appendingPathComponent("eti_launcher/update/game.db") }
    public var snapshot: URL { support.appendingPathComponent("catalog.sqlite") }
    public var receipt: URL { support.appendingPathComponent("catalog-receipt.json") }
    public var launcherKey: URL { support.appendingPathComponent("launcher.key") }
    public var runtimeRoot: URL { support.appendingPathComponent("Runtimes", isDirectory: true) }

    public func gameDirectory(_ id: String) throws -> URL {
        guard CatalogReader.validID(id), id != "eti_launcher" else { throw ETIError("Invalid or reserved game identifier.") }
        let root = syncRoot.resolvingSymlinksInPath().standardizedFileURL
        let result = root.appendingPathComponent(id, isDirectory: true)
        guard result.resolvingSymlinksInPath().deletingLastPathComponent().path == root.path else {
            throw ETIError("The game folder points outside the library. Choose a dedicated folder.")
        }
        return result
    }

    public func createDirectories() throws {
        let fm = FileManager.default
        for folder in [support, runtimeRoot] {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        try fm.createDirectory(at: syncRoot.appendingPathComponent("eti_launcher"), withIntermediateDirectories: true)
    }
}

public struct LibraryStore: Sendable {
    public let paths: LibraryPaths
    public init(paths: LibraryPaths = LibraryPaths()) { self.paths = paths }

    /// Import a bounded, validated snapshot. The live Resilio file is never changed.
    /// ETI distributes a standalone SQLite file; active SQLite WAL databases are not supported.
    @discardableResult
    public func importCatalog(from source: URL) throws -> CatalogReceipt {
        try paths.createDirectories()
        let fm = FileManager.default
        for suffix in ["-wal", "-journal"] where fm.fileExists(atPath: source.path + suffix) {
            throw ETIError("Import a completed standalone game.db, without an active SQLite journal.")
        }
        let attrs = try fm.attributesOfItem(atPath: source.path)
        guard attrs[.type] as? FileAttributeType == .typeRegular,
              let size = attrs[.size] as? Int, size > 0, size <= CatalogReader.maximumBytes else {
            throw ETIError("The catalog must be a regular SQLite file smaller than 50 MB.")
        }
        let data = try Data(contentsOf: source)
        guard data.count <= CatalogReader.maximumBytes else { throw ETIError("Catalog is too large.") }
        let staging = paths.support.appendingPathComponent(".catalog-\(UUID().uuidString).sqlite")
        defer { try? fm.removeItem(at: staging) }
        try data.write(to: staging, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: staging.path)
        let catalog = try CatalogReader.read(staging)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let receipt = CatalogReceipt(sourcePath: source.path, sourceModifiedAt: attrs[.modificationDate] as? Date,
                                     importedAt: Date(), sha256: hash, gameCount: catalog.games.count,
                                     skippedRows: catalog.skippedRows)
        // Each file replacement is atomic. A receipt is accepted only when its hash matches the snapshot.
        try data.write(to: paths.snapshot, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: paths.snapshot.path)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(receipt).write(to: paths.receipt, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: paths.receipt.path)
        return receipt
    }

    public func load() throws -> (Catalog, CatalogReceipt?) {
        let catalog = try CatalogReader.read(paths.snapshot)
        let receipt = try? JSONDecoder().decode(CatalogReceipt.self, from: Data(contentsOf: paths.receipt))
        let digest = try SHA256.hash(data: Data(contentsOf: paths.snapshot)).map { String(format: "%02x", $0) }.joined()
        return (catalog, receipt?.sha256 == digest ? receipt : nil)
    }

    public func plan(_ catalog: Catalog, gameIDs: [String]? = nil, library: UserLibrary = .init()) throws -> [SyncPlanItem] {
        let ids = gameIDs ?? CatalogFilter.games(in: catalog, library: library).map(\.id)
        return try ids.map { id in
            guard let game = catalog.game(id: id) else { throw ETIError("Game \(id) is not in this catalog.") }
            let destination = try paths.gameDirectory(id)
            return SyncPlanItem(id: id, title: game.title,
                                catalogAvailable: true, packageRevision: game.packageRevision,
                                reportedSizeGB: game.reportedSizeGB, destination: destination.path,
                                runtime: library.preferences(for: id).runtime.kind.title, canConnect: game.readOnlyKey != nil,
                                status: "Runtime and multiplayer untested")
        }
    }
}
