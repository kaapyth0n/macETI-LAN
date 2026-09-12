import Foundation

public enum GameRemovalKind: String, CaseIterable, Hashable, Sendable {
    case installation, download
    public var title: String { self == .installation ? "Installed copy" : "Synced download" }
}

public struct GameRemovalFolder: Equatable, Sendable {
    public let kind: GameRemovalKind
    public let url: URL
    fileprivate let device: UInt64
    fileprivate let inode: UInt64
}

public struct GameRemovalPlan: Sendable {
    public let gameID: String
    public let runtime: RuntimeConfiguration
    public let folders: [GameRemovalFolder]
    public let notes: [String]
}

/// Only dedicated game directories can be removed. Bottles, saves outside those
/// directories, the catalog and setup receipts are retained.
public struct GameRemoval: Sendable {
    public let paths: LibraryPaths
    let bottles: URL
    // Tests move synthetic fixtures into a private trash directory.
    var trash: @Sendable (URL) throws -> URL

    public init(paths: LibraryPaths = .init(), home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.paths = paths
        bottles = home.appendingPathComponent("Library/Application Support/CrossOver/Bottles")
        trash = { source in
            var result: NSURL?
            try FileManager.default.trashItem(at: source, resultingItemURL: &result)
            guard let result else { throw ETIError("The folder was moved to Trash, but macOS did not return its location. Check Trash before retrying.") }
            return result as URL
        }
    }

    public func plan(gameID: String) throws -> GameRemovalPlan {
        try plan(gameID: gameID, library: PreferencesStore(paths: paths).load())
    }

    private func plan(gameID: String, library: UserLibrary) throws -> GameRemovalPlan {
        guard CatalogReader.validID(gameID), gameID != "eti_launcher" else { throw ETIError("Invalid game identifier.") }
        let runtime = library.preferences(for: gameID).runtime
        var folders: [GameRemovalFolder] = []
        var notes: [String] = []
        if !runtime.executablePath.isEmpty {
            do {
                let url = try installation(gameID: gameID, runtime: runtime)
                if let folder = try folder(.installation, at: url, gameID: gameID, library: library) { folders.append(folder) }
                else { notes.append("The configured installation is already missing. Correct or reset it in Runtime settings.") }
            } catch { notes.append("Installed copy: \(error.localizedDescription)") }
        }
        do {
            let url = paths.syncRoot.resolvingSymlinksInPath().appendingPathComponent(gameID, isDirectory: true)
            if let folder = try folder(.download, at: url, gameID: gameID, library: library) { folders.append(folder) }
        } catch { notes.append("Synced download: \(error.localizedDescription)") }
        return .init(gameID: gameID, runtime: runtime, folders: folders, notes: notes)
    }

    private func installation(gameID: String, runtime: RuntimeConfiguration) throws -> URL {
        let native = paths.runtimeRoot.resolvingSymlinksInPath().appendingPathComponent(gameID, isDirectory: true)
        if runtime.kind == .native, Self.contains(native, runtime.executablePath),
           runtime.workingDirectory.isEmpty || Self.contains(native, runtime.workingDirectory) { return native }
        if runtime.kind == .crossOver, !runtime.bottle.isEmpty, runtime.bottle != ".", runtime.bottle != "..",
           !runtime.bottle.contains("/"), runtime.executablePath.hasPrefix("/") {
            let bottle = bottles.resolvingSymlinksInPath().appendingPathComponent(runtime.bottle)
            let drive = bottle.appendingPathComponent("drive_c")
            // Never follow a bottle or drive symlink into an unrelated installation.
            guard bottle.standardizedFileURL.path == bottle.resolvingSymlinksInPath().path,
                  drive.standardizedFileURL.path == drive.resolvingSymlinksInPath().path else {
                throw ETIError("This bottle uses a linked folder. Manage its files in Finder or CrossOver.")
            }
            let exe = URL(fileURLWithPath: runtime.executablePath).standardizedFileURL
            if Self.contains(drive, exe.path) {
                let relative = Array(exe.pathComponents.dropFirst(drive.pathComponents.count))
                let protected = ["windows", "users", "program files", "program files (x86)", "programdata", "documents and settings"]
                if relative.count >= 2, let name = relative.first, !protected.contains(name.lowercased()) {
                    let folder = drive.appendingPathComponent(name, isDirectory: true)
                    if Self.contains(folder, exe.resolvingSymlinksInPath().path),
                       runtime.workingDirectory.isEmpty || Self.contains(folder, runtime.workingDirectory) { return folder }
                }
            }
        }
        throw ETIError("This location cannot be removed automatically. Reveal the executable and manage its dedicated game folder in Finder or CrossOver.")
    }

    private func folder(_ kind: GameRemovalKind, at url: URL, gameID: String, library: UserLibrary) throws -> GameRemovalFolder? {
        var info = stat()
        if lstat(url.path, &info) != 0 {
            if errno == ENOENT { return nil }
            throw ETIError("Cannot inspect \(url.path).")
        }
        guard (info.st_mode & S_IFMT) == S_IFDIR,
              url.standardizedFileURL.path == url.resolvingSymlinksInPath().path else {
            throw ETIError("Linked folders and non-directory paths must be managed in Finder.")
        }
        for (otherID, preference) in library.games where otherID != gameID {
            let config = preference.runtime
            let references = [config.executablePath, config.workingDirectory] + config.arguments.filter { $0.hasPrefix("/") }
            if references.contains(where: { path in
                guard path.hasPrefix("/") else { return false }
                let resolved = Self.resolveReference(path)
                return Self.contains(url, resolved.path) || Self.contains(resolved, url.path)
            }) { throw ETIError("This folder is also referenced by \(otherID). Separate the installations before removing it.") }
        }
        return .init(kind: kind, url: url, device: UInt64(info.st_dev), inode: UInt64(info.st_ino))
    }

    /// Run off the main thread. Recheck the reviewed folders under the same lock
    /// used by setup, and hold the preferences lock through the move and save.
    @discardableResult
    public func perform(_ reviewed: GameRemovalPlan, kinds: Set<GameRemovalKind>,
                        gameClosed: Bool, downloadDisconnected: Bool) throws -> UserLibrary {
        guard !kinds.isEmpty, gameClosed else { throw ETIError("Select a folder and close the game before removing its files.") }
        guard !kinds.contains(.download) || downloadDisconnected else {
            throw ETIError("Disconnect this game's folder in Resilio on this Mac first. Pausing sync is not enough.")
        }
        try paths.createDirectories()
        let setup = paths.support.appendingPathComponent("Setup")
        try FileManager.default.createDirectory(at: setup, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let fd = Darwin.open(setup.appendingPathComponent("setup.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw ETIError("Cannot lock game files.") }
        defer { Darwin.close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw ETIError("Another setup or removal is running. Wait for it to finish.") }
        defer { flock(fd, LOCK_UN) }
        let preferences = PreferencesStore(paths: paths)
        var moved: [(source: URL, destination: URL)] = []
        do {
            return try preferences.update(reviewed.gameID) { preference in
                guard preference.runtime == reviewed.runtime else { throw ETIError("Runtime settings changed. Close and reopen Remove game to review the current folders.") }
                let current = try plan(gameID: reviewed.gameID, library: preferences.load())
                let selected = reviewed.folders.filter { kinds.contains($0.kind) }
                guard selected.count == kinds.count, selected.allSatisfy({ current.folders.contains($0) }) else {
                    throw ETIError("The game folders changed or are shared with another game. Close and reopen Remove game to review them again.")
                }
                for item in selected {
                    // Recheck immediately before each move as the other move may take time.
                    guard try folder(item.kind, at: item.url, gameID: reviewed.gameID, library: preferences.load()) == item else {
                        throw ETIError("A game folder changed during removal. Review it again.")
                    }
                    moved.append((item.url, try trash(item.url)))
                }
                if selected.contains(where: { Self.contains($0.url, preference.runtime.executablePath) ||
                    Self.contains($0.url, preference.runtime.workingDirectory) }) {
                    // Retain the bottle for saves, dependencies and a later reinstall.
                    preference.runtime.executablePath = ""
                    preference.runtime.workingDirectory = ""
                    preference.runtime.arguments = []
                }
            }
        } catch {
            var unrestored: [String] = []
            for item in moved.reversed() {
                do { try FileManager.default.moveItem(at: item.destination, to: item.source) }
                catch { unrestored.append(item.destination.path) }
            }
            if !unrestored.isEmpty {
                throw ETIError("Removal did not finish. Some folders could not be restored and remain at: \(unrestored.joined(separator: ", ")). Check Trash and Runtime settings. \(error.localizedDescription)")
            }
            throw error
        }
    }

    /// Allocated size estimate, including hidden files but without following links.
    public static func allocatedBytes(at folder: URL) -> Int64? {
        let keys: Set<URLResourceKey> = [.isSymbolicLinkKey, .isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        var failed = false
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: Array(keys),
                                                              errorHandler: { _, _ in failed = true; return false }) else { return nil }
        var bytes: Int64 = 0
        for case let file as URL in enumerator {
            guard !Task.isCancelled else { return nil }
            guard let values = try? file.resourceValues(forKeys: keys) else { return nil }
            if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            if values.isRegularFile == true { bytes += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0) }
        }
        return failed ? nil : bytes
    }

    private static func contains(_ root: URL, _ path: String) -> Bool {
        guard path.hasPrefix("/") else { return false }
        let path = URL(fileURLWithPath: path).standardizedFileURL.path
        let root = root.standardizedFileURL.path
        return path == root || path.hasPrefix(root + "/")
    }

    private static func resolveReference(_ path: String) -> URL {
        // Foundation does not resolve a symlink ancestor when the final file is
        // missing. Still protect a game's saved reference to that directory.
        var existing = URL(fileURLWithPath: path).standardizedFileURL
        var suffix: [String] = []
        while !FileManager.default.fileExists(atPath: existing.path), existing.path != "/" {
            suffix.append(existing.lastPathComponent)
            existing.deleteLastPathComponent()
        }
        return suffix.reversed().reduce(existing.resolvingSymlinksInPath()) { $0.appendingPathComponent($1) }
    }
}
