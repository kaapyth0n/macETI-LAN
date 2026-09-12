import Foundation

public struct ETIError: LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// Access keys deliberately cannot participate in Codable output or debug descriptions.
public struct ReadOnlyKey: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    private let value: String
    public init?(_ value: String) {
        guard value.range(of: "^B[A-Z2-7]{32}$", options: .regularExpression) != nil else { return nil }
        self.value = value
    }
    public var description: String { "<read-only key>" }
    public var debugDescription: String { description }
    public func forResilioConnection() -> String { value }
}

public struct Game: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let packageRevision: String
    public let reportedSizeGB: Double?
    public let readOnlyKey: ReadOnlyKey?
    public var metadata: GameMetadata = .init()
    public var summary: GameSummary {
        GameSummary(id: id, title: title, packageRevision: packageRevision,
                    reportedSizeGB: reportedSizeGB, canConnect: readOnlyKey != nil, metadata: metadata)
    }
}

public struct GameSummary: Identifiable, Codable, Sendable {
    public let id: String
    public let title: String
    public let packageRevision: String
    public let reportedSizeGB: Double?
    public let canConnect: Bool
    public let metadata: GameMetadata
}

public struct GameMetadata: Codable, Sendable, Equatable {
    public var year = ""
    public var publisher = ""
    public var genre = ""
    public var maximumPlayers: Int?
    public init() {}
}

public struct GameProfile: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let runtime: String
    public let note: String
    public static let selected: [GameProfile] = [
        .init(id: "quake3", title: "Quake III Arena", runtime: "Native · ioquake3",
              note: "First native target. Verify the Windows server protocol, maps and mods."),
        .init(id: "amongus", title: "Among Us", runtime: "CrossOver",
              note: "Match the Windows version before testing a local lobby."),
        .init(id: "l4d2", title: "Left 4 Dead 2", runtime: "CrossOver",
              note: "ETI's catalog entry is Left 4 Dead 2. Test Windows-hosted co-op and level transitions."),
        .init(id: "flat2", title: "FlatOut 2", runtime: "CrossOver",
              note: "Test the same Windows build first. The Mac release's LAN compatibility is unverified."),
        .init(id: "cod2", title: "Call of Duty 2", runtime: "CrossOver · untested",
              note: "Published Mac compatibility is poor. A working runtime has not been established.")
    ]
}

public struct CatalogReceipt: Codable, Sendable {
    public let sourcePath: String
    public let sourceModifiedAt: Date?
    public let importedAt: Date
    public let sha256: String
    public let gameCount: Int
    public let skippedRows: Int
}

public struct Catalog: Sendable {
    public let games: [Game]
    public let skippedRows: Int
    public func game(id: String) -> Game? { games.first { $0.id == id } }
}

public struct SyncPlanItem: Codable, Sendable {
    public let id: String
    public let title: String
    public let catalogAvailable: Bool
    public let packageRevision: String?
    public let reportedSizeGB: Double?
    public let destination: String
    public let runtime: String
    public let canConnect: Bool
    public let status: String
}
