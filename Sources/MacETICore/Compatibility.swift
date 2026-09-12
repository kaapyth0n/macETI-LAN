import Foundation

private final class CompatibilityBundleAnchor: NSObject {}

public struct CompatibilitySource: Codable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let url: URL
    public let context: String
}

public struct CompatibilityNote: Codable, Sendable {
    public let title: String
    public let detail: String
    public let sourceIDs: [String]
}

/// Authored guidance, not executable instructions or a claim of successful testing.
public struct CompatibilityProfile: Codable, Sendable {
    public let gameID: String
    public let revision: Int
    public let reviewedPackageRevision: String
    public let route: RuntimeKind
    public let summary: String
    public let setup: [CompatibilityNote]
    public let troubleshooting: [CompatibilityNote]
    public let lanChecklist: [String]
    public let sourceIDs: [String]
}

public struct CompatibilityGuide: Codable, Sendable {
    public let gameID: String
    public let contentRevision: String
    public let reviewedAt: String
    public let profile: CompatibilityProfile?
    public let route: RuntimeKind
    public let setup: [CompatibilityNote]
    public let troubleshooting: [CompatibilityNote]
    public let lanChecklist: [String]
    public let sources: [CompatibilitySource]
    // Derived from reviewed Swift recipes for the exact package; prose never enables actions.
    public let automaticSetupAvailable: Bool
}

public struct CompatibilityCatalog: Codable, Sendable {
    public let schemaVersion: Int
    public let contentRevision: String
    public let reviewedAt: String
    public let sources: [CompatibilitySource]
    public let crossOverSetup: [CompatibilityNote]
    public let nativeSetup: [CompatibilityNote]
    public let troubleshooting: [CompatibilityNote]
    public let lanChecklist: [String]
    public let profiles: [CompatibilityProfile]

    public static func bundled() throws -> Self {
        // A shipped .app must use its own resources, never a developer's build-directory fallback.
        let roots: [URL]
        if Bundle.main.bundleURL.pathExtension == "app" {
            roots = [Bundle.main.resourceURL].compactMap { $0 }
        } else {
            let executableFolder = Bundle.main.executableURL?.deletingLastPathComponent()
            roots = [Bundle.main.resourceURL, Bundle.main.bundleURL, executableFolder,
                     executableFolder?.deletingLastPathComponent().appendingPathComponent("Resources"),
                     Bundle(for: CompatibilityBundleAnchor.self).bundleURL.deletingLastPathComponent()].compactMap { $0 }
        }
        let resourceBundle = roots.compactMap {
            Bundle(url: $0.appendingPathComponent("macETI-LAN_MacETICore.bundle"))
        }.first
        guard let url = resourceBundle?.url(forResource: "compatibility", withExtension: "json") else {
            throw ETIError("Compatibility guidance is missing from the app bundle.")
        }
        return try decode(Data(contentsOf: url))
    }

    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= 1_000_000 else { throw ETIError("Compatibility guidance is too large.") }
        let catalog = try JSONDecoder().decode(Self.self, from: data)
        guard catalog.schemaVersion == 1 else { throw ETIError("Unsupported compatibility guidance version.") }
        let sourceIDs = Set(catalog.sources.map(\.id))
        guard sourceIDs.count == catalog.sources.count,
              Set(catalog.profiles.map(\.gameID)).count == catalog.profiles.count,
              catalog.sources.allSatisfy({ $0.url.scheme == "https" && $0.url.host != nil && $0.url.user == nil && $0.url.password == nil }),
              catalog.profiles.allSatisfy({ CatalogReader.validID($0.gameID) && $0.revision > 0 }) else {
            throw ETIError("Compatibility guidance contains invalid or duplicate entries.")
        }
        let notes = catalog.crossOverSetup + catalog.nativeSetup + catalog.troubleshooting
            + catalog.profiles.flatMap { $0.setup + $0.troubleshooting }
        let references = notes.flatMap(\.sourceIDs) + catalog.profiles.flatMap(\.sourceIDs)
        guard references.allSatisfy(sourceIDs.contains) else { throw ETIError("Compatibility guidance references a missing source.") }
        return catalog
    }

    public func guide(for gameID: String, runtime: RuntimeKind, packageRevision: String? = nil) -> CompatibilityGuide {
        let profile = profiles.first { $0.gameID == gameID }
        let route = profile?.route ?? runtime
        let setup = (route == .crossOver ? crossOverSetup : nativeSetup) + (profile?.setup ?? [])
        let issues = (profile?.troubleshooting ?? []) + troubleshooting
        let refs = Set((setup + issues).flatMap(\.sourceIDs) + (profile?.sourceIDs ?? []) + ["compatibility-center"])
        return CompatibilityGuide(gameID: gameID, contentRevision: contentRevision, reviewedAt: reviewedAt,
                                  profile: profile, route: route, setup: setup, troubleshooting: issues,
                                  lanChecklist: profile?.lanChecklist ?? lanChecklist,
                                  sources: sources.filter { refs.contains($0.id) },
                                  automaticSetupAvailable: runtime == .crossOver && packageRevision.map {
                                      CrossOverRecipe.recipe(for: gameID, revision: $0) != nil
                                  } == true)
    }
}
