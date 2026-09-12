import Foundation
import Darwin

public enum GameplayResult: String, Codable, CaseIterable, Sendable {
    case notTested, menu, played, failed
    public var title: String {
        switch self {
        case .notTested: "Not tested"
        case .menu: "Reached the menu"
        case .played: "Gameplay worked"
        case .failed: "Failed"
        }
    }
}

public enum LANResult: String, Codable, CaseIterable, Sendable {
    case notTested, joined, completed, failed
    public var title: String {
        switch self {
        case .notTested: "Not tested"
        case .joined: "Joined Windows host"
        case .completed: "Completed a Windows LAN session"
        case .failed: "Failed"
        }
    }
}

public struct CompatibilityTest: Codable, Identifiable, Sendable {
    public let id: UUID
    public let recordedAt: Date
    public let gameID: String
    public let packageRevision: String
    public let guidanceRevision: String
    public let runtime: RuntimeConfiguration
    public var runtimeVersion: String
    public let macOSVersion: String
    public let hardware: String
    public var gameVersion: String
    public var windowsGameVersion: String
    public var gameplay: GameplayResult
    public var lan: LANResult
    public var notes: String

    public init(game: Game, guidanceRevision: String, runtime: RuntimeConfiguration,
                runtimeVersion: String, macOSVersion: String = ProcessInfo.processInfo.operatingSystemVersionString,
                hardware: String = CompatibilityEnvironment.hardware,
                gameVersion: String = "", windowsGameVersion: String = "",
                gameplay: GameplayResult = .notTested, lan: LANResult = .notTested, notes: String = "") {
        id = UUID(); recordedAt = Date(); gameID = game.id; packageRevision = game.packageRevision
        self.guidanceRevision = guidanceRevision; self.runtime = runtime; self.runtimeVersion = runtimeVersion
        self.macOSVersion = macOSVersion; self.hardware = hardware; self.gameVersion = gameVersion
        self.windowsGameVersion = windowsGameVersion; self.gameplay = gameplay; self.lan = lan; self.notes = notes
    }

    public func matchesPackageAndSettings(game: Game, runtime: RuntimeConfiguration) -> Bool {
        gameID == game.id && packageRevision == game.packageRevision && self.runtime == runtime
    }

    public func validate() throws {
        guard CatalogReader.validID(gameID), !runtimeVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !macOSVersion.isEmpty, !hardware.isEmpty, !packageRevision.isEmpty else {
            throw ETIError("Record the runtime version and test environment before saving.")
        }
        guard gameplay != .notTested || lan != .notTested else { throw ETIError("Choose an observed gameplay or LAN result.") }
        guard lan != .completed || gameplay == .played,
              lan != .joined || gameplay == .menu || gameplay == .played else {
            throw ETIError("A successful LAN result also needs a matching gameplay result.")
        }
        if lan == .joined || lan == .completed {
            guard !gameVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !windowsGameVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ETIError("Record both game versions for a successful Windows LAN test.")
            }
        }
        let strings = [runtimeVersion, macOSVersion, hardware, gameVersion, windowsGameVersion, notes,
                       packageRevision, guidanceRevision, runtime.bottle, runtime.executablePath, runtime.workingDirectory] + runtime.arguments
        guard runtime.arguments.count <= 128, strings.allSatisfy({ $0.utf8.count < 16_384 && !$0.contains("\0") }) else {
            throw ETIError("Test details contain an invalid or oversized value.")
        }
    }
}

public enum CompatibilityEnvironment {
    public static var hardware: String {
        func value(_ name: String) -> String? {
            var size = 0
            guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 1 else { return nil }
            var bytes = [CChar](repeating: 0, count: size)
            guard sysctlbyname(name, &bytes, &size, nil, 0) == 0 else { return nil }
            return String(bytes: bytes.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, encoding: .utf8)
        }
        return [value("machdep.cpu.brand_string"), value("hw.model")].compactMap { $0 }.joined(separator: " · ")
    }

    public static var crossOverVersion: String? {
        guard let app = GameLauncher.crossOverApp() else { return nil }
        return Bundle(url: app)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }
}

public struct CompatibilityTestStore: Sendable {
    public let paths: LibraryPaths
    public init(paths: LibraryPaths = .init()) { self.paths = paths }
    public var file: URL { paths.support.appendingPathComponent("compatibility-tests.json") }
    private struct Document: Codable {
        var schemaVersion = 1
        var tests: [CompatibilityTest] = []
    }

    public func load() throws -> [CompatibilityTest] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        let data = try Data(contentsOf: file)
        guard data.count <= 8_000_000 else { throw ETIError("The local test log is too large.") }
        let document = try JSONDecoder().decode(Document.self, from: data)
        guard document.schemaVersion == 1, document.tests.count <= 1000,
              Set(document.tests.map(\.id)).count == document.tests.count else {
            throw ETIError("Unsupported or invalid local compatibility test log.")
        }
        try document.tests.forEach { try $0.validate() }
        return document.tests.sorted { $0.recordedAt > $1.recordedAt }
    }

    @discardableResult
    public func append(_ test: CompatibilityTest) throws -> [CompatibilityTest] {
        try test.validate()
        try paths.createDirectories()
        let fd = Darwin.open(paths.support.appendingPathComponent("compatibility-tests.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw ETIError("Cannot lock the local test log.") }
        defer { Darwin.close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw ETIError("Cannot lock the local test log.") }
        defer { flock(fd, LOCK_UN) }
        let tests = try load()
        guard tests.count < 1000, !tests.contains(where: { $0.id == test.id }) else { throw ETIError("Test log is full or this result has already been saved.") }
        let updated = [test] + tests
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(Document(tests: updated))
        guard data.count <= 8_000_000 else { throw ETIError("The local test log is too large.") }
        try data.write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        return updated
    }
}
