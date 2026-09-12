import Foundation

public enum RuntimeKind: String, Codable, CaseIterable, Sendable {
    case crossOver
    case native
    public var title: String { self == .crossOver ? "CrossOver" : "Native / Mac app" }
}

public struct RuntimeConfiguration: Codable, Equatable, Sendable {
    public var kind: RuntimeKind
    public var bottle = ""
    public var executablePath = ""
    public var arguments: [String] = []
    public var workingDirectory = ""

    public init(kind: RuntimeKind = .crossOver) { self.kind = kind }
    public static func defaultFor(_ gameID: String) -> Self {
        // An explicit port experiment; every other catalog entry defaults to CrossOver.
        .init(kind: gameID == "quake3" ? .native : .crossOver)
    }
}

public struct GamePreferences: Codable, Equatable, Sendable {
    public var saved: Bool
    public var runtime: RuntimeConfiguration
    public init(gameID: String) {
        saved = GameProfile.selected.contains { $0.id == gameID }
        runtime = .defaultFor(gameID)
    }
}

public struct UserLibrary: Codable, Sendable {
    public var version = 1
    public var games: [String: GamePreferences] = [:]
    public init() {}
    public func preferences(for gameID: String) -> GamePreferences {
        games[gameID] ?? GamePreferences(gameID: gameID)
    }
}

public struct PreferencesStore: Sendable {
    public let paths: LibraryPaths
    public init(paths: LibraryPaths = .init()) { self.paths = paths }
    public var file: URL { paths.support.appendingPathComponent("library.json") }

    public func load() throws -> UserLibrary {
        guard FileManager.default.fileExists(atPath: file.path) else { return UserLibrary() }
        let data = try Data(contentsOf: file)
        guard data.count <= 2_000_000 else { throw ETIError("Library preferences are too large.") }
        let library = try JSONDecoder().decode(UserLibrary.self, from: data)
        guard library.version == 1 else { throw ETIError("This version of library preferences is not supported.") }
        for (id, preferences) in library.games {
            guard CatalogReader.validID(id) else { throw ETIError("Library preferences contain an invalid game ID.") }
            try Self.validate(preferences.runtime)
        }
        return library
    }

    @discardableResult
    public func update(_ gameID: String, _ change: (inout GamePreferences) -> Void) throws -> UserLibrary {
        guard CatalogReader.validID(gameID) else { throw ETIError("Invalid game identifier.") }
        try paths.createDirectories()
        // Serialize the complete read/modify/write, including CLI and other app windows.
        let lock = paths.support.appendingPathComponent("library.lock")
        let fd = Darwin.open(lock.path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw ETIError("Cannot lock library preferences.") }
        defer { Darwin.close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw ETIError("Cannot lock library preferences.") }
        defer { flock(fd, LOCK_UN) }
        var library = try load()
        var preference = library.preferences(for: gameID)
        change(&preference)
        try Self.validate(preference.runtime)
        library.games[gameID] = preference
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(library).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        return library
    }

    private static func validate(_ config: RuntimeConfiguration) throws {
        let strings = [config.bottle, config.executablePath, config.workingDirectory] + config.arguments
        guard config.arguments.count <= 128, strings.allSatisfy({ $0.utf8.count < 16_384 && !$0.contains("\0") }) else {
            throw ETIError("Runtime settings contain an invalid value.")
        }
    }
}

public enum CatalogScope: String, CaseIterable, Sendable {
    case all = "All games"
    case saved = "My games"
    case native = "Native ports"
    case crossOver = "CrossOver"
}

public enum CatalogSort: String, CaseIterable, Sendable {
    case title = "Name"
    case size = "Size"
    case players = "Players"
}

public enum CatalogFilter {
    public static func games(in catalog: Catalog, library: UserLibrary, search: String = "",
                             genre: String = "", scope: CatalogScope = .all, sort: CatalogSort = .title) -> [Game] {
        let terms = search.split(whereSeparator: \.isWhitespace).map(String.init)
        return catalog.games.filter { game in
            let prefs = library.preferences(for: game.id)
            let matchesScope = switch scope {
            case .all: true
            case .saved: prefs.saved
            case .native: prefs.runtime.kind == .native
            case .crossOver: prefs.runtime.kind == .crossOver
            }
            let searchable = [game.title, game.id, game.metadata.genre, game.metadata.publisher].joined(separator: " ")
            return matchesScope && (genre.isEmpty || game.metadata.genre == genre)
                && terms.allSatisfy { searchable.localizedStandardContains($0) }
        }.sorted { left, right in
            switch sort {
            case .size:
                if left.reportedSizeGB != right.reportedSizeGB { return (left.reportedSizeGB ?? -1) > (right.reportedSizeGB ?? -1) }
            case .players:
                if left.metadata.maximumPlayers != right.metadata.maximumPlayers { return (left.metadata.maximumPlayers ?? -1) > (right.metadata.maximumPlayers ?? -1) }
            case .title: break
            }
            let comparison = left.title.localizedStandardCompare(right.title)
            return comparison == .orderedSame ? left.id < right.id : comparison == .orderedAscending
        }
    }
}
