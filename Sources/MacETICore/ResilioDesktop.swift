import AppKit

public struct SystemStatus: Codable, Sendable {
    public let architecture: String
    public let resilioInstalled: Bool
    public let resilioVersion: String?
    public let resilioRunning: Bool
    public let liveCatalogPresent: Bool
    public let savedCatalogPresent: Bool
    public let syncRoot: String
    public let integration: String
}

@MainActor
public enum ResilioDesktop {
    public static var appURL: URL? {
        let candidates = [URL(fileURLWithPath: "/Applications/Resilio Sync.app"),
                          FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Resilio Sync.app")]
        return candidates.first { Bundle(url: $0)?.executableURL != nil }
    }

    public static func status(paths: LibraryPaths) -> SystemStatus {
        let bundle = appURL.flatMap(Bundle.init(url:))
        let running = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundle?.bundleIdentifier && $0.bundleIdentifier != nil }
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x86_64"
        #endif
        return SystemStatus(architecture: architecture, resilioInstalled: appURL != nil,
                            resilioVersion: bundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                            resilioRunning: running,
                            liveCatalogPresent: FileManager.default.fileExists(atPath: paths.liveCatalog.path),
                            savedCatalogPresent: FileManager.default.fileExists(atPath: paths.snapshot.path),
                            syncRoot: paths.syncRoot.path, integration: "Desktop handoff; no private API or transfer telemetry")
    }

    public static func open() throws {
        guard let appURL else { throw ETIError("Install and activate Resilio Sync first.") }
        NSWorkspace.shared.openApplication(at: appURL, configuration: .init())
    }

    public static func copyKey(_ key: ReadOnlyKey) {
        let clipboard = NSPasteboard.general
        clipboard.clearContents()
        clipboard.setString(key.forResilioConnection(), forType: .string)
        clipboard.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
    }
}
