import Foundation

/// Executable recipes are reviewed Swift code, never commands supplied by the catalog.
public struct CrossOverRecipe: Sendable {
    public let gameID: String
    public let packageRevision: String
    public let folder: String
    public let executable: String
    let archiveBytes: Int64
    let maximumExpandedBytes: Int64
    let requiredFiles: [String]

    public static func recipe(for gameID: String, revision: String) -> Self? {
        recipes.first { $0.gameID == gameID && $0.packageRevision == revision }
    }
    public static let recipes: [Self] = [
        .init(gameID: "amongus", packageRevision: "20250308", folder: "AmongUs", executable: "Among Us.exe",
              archiveBytes: 445_998_660, maximumExpandedBytes: 2_000_000_000,
              requiredFiles: ["Among Us.exe", "UnityPlayer.dll", "GameAssembly.dll"]),
        .init(gameID: "rocket", packageRevision: "20260410", folder: "RocketLeague", executable: "SmartSteamLoader.exe",
              archiveBytes: 7_122_959_252, maximumExpandedBytes: 10_000_000_000,
              requiredFiles: ["SmartSteamLoader.exe", "SmartSteamEmu.ini", "Binaries/Win32/RocketLeague.exe"])
    ]
}

public enum CrossOverSetupMode: Sendable { case bottleOnly, installPackage }

struct SetupReceipt: Codable {
    var version = 1
    let gameID: String
    let token: UUID
    var bottleCreated = false
    var installedRevision: String?
    var bottle: String { "macETI-\(gameID)-\(token.uuidString.prefix(8))" }
}

/// Blocking worker. The app runs it off the main thread. A filesystem lock also covers other app instances.
public struct CrossOverSetup: Sendable {
    public let paths: LibraryPaths
    let bottles: URL
    let crossOver: URL?
    // Injectable process/tool boundaries allow failure tests without CrossOver or game downloads.
    var run: @Sendable (URL, [String], URL, Bool) throws -> Void
    var archiveTool: @Sendable (URL, URL, @Sendable (String) -> Void) throws -> URL
    public let cancellation: SetupCancellation

    public init(paths: LibraryPaths = .init(), home: URL = FileManager.default.homeDirectoryForCurrentUser,
                crossOver: URL? = GameLauncher.crossOverApp(), cancellation: SetupCancellation = .init()) {
        self.paths = paths
        self.bottles = home.appendingPathComponent("Library/Application Support/CrossOver/Bottles", isDirectory: true)
        self.crossOver = crossOver
        self.cancellation = cancellation
        let runner = SetupProcess(cancellation: cancellation)
        self.run = { exe, args, log, cancellable in
            try runner.run(exe, args, log: log, timeout: cancellable ? 1800 : 180, cancellable: cancellable)
        }
        self.archiveTool = { root, log, progress in
            try SetupArchiveTool.prepare(at: root, runner: runner, log: log, progress: progress)
        }
    }

    public var logs: URL { paths.support.appendingPathComponent("Setup", isDirectory: true) }

    public func perform(gameID: String, revision: String, mode: CrossOverSetupMode,
                        expectedRuntime: RuntimeConfiguration,
                        progress: @Sendable (String) -> Void) throws -> RuntimeConfiguration {
        guard CatalogReader.validID(gameID), gameID != "eti_launcher" else { throw ETIError("Invalid game identifier.") }
        guard expectedRuntime.kind == .crossOver else { throw ETIError("Choose CrossOver in Runtime first.") }
        guard let crossOver else { throw ETIError("Install and activate CrossOver, then retry setup.") }
        let manager = crossOver.appendingPathComponent("Contents/SharedSupport/CrossOver/bin/cxbottle")
        guard FileManager.default.isExecutableFile(atPath: manager.path) else { throw ETIError("CrossOver's bottle tool is missing.") }
        let fm = FileManager.default
        try paths.createDirectories()
        try fm.createDirectory(at: logs, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let fd = Darwin.open(logs.appendingPathComponent("setup.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw ETIError("Cannot lock setup.") }
        defer { Darwin.close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw ETIError("Another setup is running. Wait for it to finish.") }
        defer { flock(fd, LOCK_UN) }
        try cancellation.check()
        let preferences = PreferencesStore(paths: paths)
        guard try preferences.load().preferences(for: gameID).runtime == expectedRuntime else {
            throw ETIError("Runtime settings changed. Refresh the game page before setup.")
        }
        // A configured installation is never replaced, even if its package revision has changed.
        if !expectedRuntime.executablePath.isEmpty {
            _ = try GameLauncher.command(for: expectedRuntime, crossOver: crossOver)
            try validateBottle(expectedRuntime.bottle)
            progress("The saved runtime is already configured. Use Launch.")
            return expectedRuntime
        }
        let receiptURL = logs.appendingPathComponent("\(gameID).json")
        var receipt: SetupReceipt
        if fm.fileExists(atPath: receiptURL.path) {
            let data = try Data(contentsOf: receiptURL)
            guard data.count < 16_384 else { throw ETIError("Invalid setup receipt; the original was preserved.") }
            receipt = try JSONDecoder().decode(SetupReceipt.self, from: data)
            guard receipt.version == 1, receipt.gameID == gameID else { throw ETIError("Unsupported setup receipt; the original was preserved.") }
        } else { receipt = SetupReceipt(gameID: gameID, token: UUID()) }
        if !expectedRuntime.bottle.isEmpty && expectedRuntime.bottle != receipt.bottle {
            try validateBottle(expectedRuntime.bottle)
            if mode == .bottleOnly { return expectedRuntime }
            throw ETIError("This game already uses a manually selected bottle. Keep using manual setup, or clear the saved bottle to create a separate installation.")
        }
        let bottle = bottles.appendingPathComponent(receipt.bottle, isDirectory: true)
        if fm.fileExists(atPath: bottle.path), !receipt.bottleCreated {
            throw ETIError("An incomplete setup bottle exists: \(receipt.bottle). Inspect or remove that bottle in CrossOver, then retry. Other bottles were left intact.")
        }
        if receipt.bottleCreated && !fm.fileExists(atPath: bottle.path) {
            receipt.bottleCreated = false
            receipt.installedRevision = nil
        }
        if receipt.bottleCreated { try validateBottle(receipt.bottle) }
        let log = logs.appendingPathComponent("\(gameID)-setup.log")
        let recipe = CrossOverRecipe.recipe(for: gameID, revision: revision)
        if mode == .installPackage && recipe == nil { throw ETIError("This package revision has no automatic install recipe. Create a bottle and follow Compatibility for manual setup.") }

        var stage: URL?
        defer { if let stage { try? fm.removeItem(at: stage) } }
        if mode == .installPackage, let recipe {
            let destination = bottle.appendingPathComponent("drive_c/\(recipe.folder)", isDirectory: true)
            if fm.fileExists(atPath: destination.path) {
                // Recover a completed extraction if the app stopped before saving runtime settings.
                guard receipt.bottleCreated, receipt.installedRevision == revision else {
                    throw ETIError("The destination already contains files. They were preserved; inspect \(destination.path) before retrying.")
                }
                try validateInstalled(recipe, at: destination)
            } else {
                progress("Checking the synced package…")
                let archive = try package(for: recipe)
                let before = try fm.attributesOfItem(atPath: archive.path)
                let unrar = try archiveTool(logs, log, progress)
                try cancellation.check()
                progress("Checking archive contents and available space…")
                let listing = logs.appendingPathComponent("\(gameID)-archive.log")
                try run(unrar, ["lt", "-c-", "-cfg-", "-p-", "--", archive.path], listing, true)
                let size = try ArchiveContents.validate(try boundedText(listing), recipe: recipe)
                let free = try fm.attributesOfFileSystem(forPath: paths.support.path)[.systemFreeSize] as? NSNumber
                guard let free, free.int64Value > size + 512_000_000 else {
                    throw ETIError("Setup needs \(ByteCountFormatter.string(fromByteCount: size + 512_000_000, countStyle: .file)) of free space for the extracted game and bottle.")
                }
                let staging = logs.appendingPathComponent(".staging-\(gameID)-\(UUID().uuidString)", isDirectory: true)
                try fm.createDirectory(at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                stage = staging
                progress("Extracting game files and checking CRCs… This can take several minutes.")
                try run(unrar, ["x", "-c-", "-cfg-", "-p-", "-o-", "-idq", "--", archive.path, staging.path + "/"], log, true)
                let after = try fm.attributesOfItem(atPath: archive.path)
                guard before[.size] as? NSNumber == after[.size] as? NSNumber,
                      before[.modificationDate] as? Date == after[.modificationDate] as? Date,
                      before[.systemFileNumber] as? NSNumber == after[.systemFileNumber] as? NSNumber else {
                    throw ETIError("The package changed during extraction. Let Resilio finish, then retry.")
                }
                try validateInstalled(recipe, at: staging)
            }
        }

        try cancellation.check()
        if !receipt.bottleCreated {
            // Persist the randomly named, owned bottle before asking CrossOver to create it.
            try save(receipt, at: receiptURL)
            progress("Creating a Windows 10 64-bit bottle… Cancel takes effect after this step.")
            do {
                try run(manager, ["--bottle", receipt.bottle, "--create", "--template", "win10_64"], log, false)
                try validateBottle(receipt.bottle)
                receipt.bottleCreated = true
                try save(receipt, at: receiptURL)
            } catch {
                throw ETIError("\(error.localizedDescription) If CrossOver created a partial bottle named \(receipt.bottle), inspect or remove it there before retrying.")
            }
        }
        try cancellation.check()
        var config = expectedRuntime
        config.bottle = receipt.bottle
        if mode == .installPackage, let recipe {
            let destination = bottle.appendingPathComponent("drive_c/\(recipe.folder)", isDirectory: true)
            if let stage {
                // Record the intended revision before the atomic move; retry verifies files before reuse.
                receipt.installedRevision = revision
                try save(receipt, at: receiptURL)
                try fm.moveItem(at: stage, to: destination)
            }
            config.workingDirectory = destination.path
            config.executablePath = destination.appendingPathComponent(recipe.executable).path
            config.arguments = []
        }
        progress("Saving launch settings…")
        try preferences.update(gameID) {
            guard $0.runtime == expectedRuntime else {
                throw ETIError("Runtime settings changed during setup. The prepared bottle \(receipt.bottle) was kept; your newer settings were preserved.")
            }
            $0.runtime = config
        }
        progress(mode == .installPackage ? "Ready to launch." : "Bottle created and saved. Select the installed executable below; see Compatibility for any extra setup.")
        return config
    }

    private func package(for recipe: CrossOverRecipe) throws -> URL {
        let folder = try paths.gameDirectory(recipe.gameID)
        let archive = folder.appendingPathComponent("\(recipe.gameID).eti")
        let version = folder.appendingPathComponent("version.ini")
        let fm = FileManager.default
        guard let attr = try? fm.attributesOfItem(atPath: archive.path),
              attr[.type] as? FileAttributeType == .typeRegular,
              (attr[.size] as? NSNumber)?.int64Value == recipe.archiveBytes,
              let versionAttr = try? fm.attributesOfItem(atPath: version.path),
              versionAttr[.type] as? FileAttributeType == .typeRegular,
              (versionAttr[.size] as? NSNumber)?.intValue ?? Int.max <= 64,
              let data = try? String(contentsOf: version, encoding: .utf8),
              data.trimmingCharacters(in: .whitespacesAndNewlines) == recipe.packageRevision else {
            throw ETIError("The expected package is missing or incomplete. Finish syncing \(recipe.gameID) in Resilio with Selective Sync off, then retry (package \(recipe.packageRevision)).")
        }
        return archive
    }

    private func validateBottle(_ name: String) throws {
        guard !name.isEmpty, !name.contains("/"), name != ".", name != "..", !name.contains("\0") else { throw ETIError("Invalid bottle name.") }
        let folder = bottles.appendingPathComponent(name, isDirectory: true)
        let drive = folder.appendingPathComponent("drive_c", isDirectory: true)
        guard folder.resolvingSymlinksInPath().path == folder.standardizedFileURL.path,
              drive.resolvingSymlinksInPath().path == drive.standardizedFileURL.path,
              FileManager.default.fileExists(atPath: folder.appendingPathComponent("cxbottle.conf").path),
              FileManager.default.fileExists(atPath: drive.path) else {
            throw ETIError("The bottle \(name) is missing or incomplete. Check it in CrossOver.")
        }
    }

    private func validateInstalled(_ recipe: CrossOverRecipe, at folder: URL) throws {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]) else {
            throw ETIError("Cannot inspect the extracted game.")
        }
        for case let file as URL in enumerator {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true, values.isRegularFile == true || values.isDirectory == true else {
                throw ETIError("The archive contains unsupported links or special files.")
            }
        }
        for name in recipe.requiredFiles {
            let attr = try fm.attributesOfItem(atPath: folder.appendingPathComponent(name).path)
            guard attr[.type] as? FileAttributeType == .typeRegular, (attr[.size] as? NSNumber)?.int64Value ?? 0 > 0 else {
                throw ETIError("The extracted game is missing \(name).")
            }
        }
    }

    private func save(_ receipt: SetupReceipt, at file: URL) throws {
        try JSONEncoder().encode(receipt).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    private func boundedText(_ file: URL) throws -> String {
        let size = try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber
        guard let size, size.intValue <= 8_000_000 else { throw ETIError("Archive listing is too large.") }
        return try String(contentsOf: file, encoding: .utf8)
    }
}

enum ArchiveContents {
    /// UnRAR's English technical listing includes redirection type, unlike a filenames-only listing.
    static func validate(_ listing: String, recipe: CrossOverRecipe) throws -> Int64 {
        var names: Set<String> = []
        var total: Int64 = 0
        for block in listing.components(separatedBy: "\n\n") {
            let lines = block.components(separatedBy: .newlines).map { String($0.drop(while: { $0 == " " || $0 == "\t" })) }
            let nameFields = lines.filter { $0.hasPrefix("Name: ") }
            guard !nameFields.isEmpty else { continue }
            let types = lines.filter { $0.hasPrefix("Type: ") }
            let sizes = lines.filter { $0.hasPrefix("Size: ") }
            guard nameFields.count == 1, types.count == 1,
                  ["Type: File", "Type: Directory"].contains(types[0]),
                  !lines.contains(where: { $0.localizedCaseInsensitiveContains("target:") || $0.localizedCaseInsensitiveContains("link:") }) else {
                throw ETIError("The archive contains an unsupported entry.")
            }
            let size: Int64
            if types[0] == "Type: Directory", sizes.isEmpty { size = 0 }
            else if sizes.count == 1, let bytes = Int64(sizes[0].dropFirst(6)), bytes >= 0 { size = bytes }
            else { throw ETIError("The archive contains an invalid entry size.") }
            let name = String(nameFields[0].dropFirst(6)).replacingOccurrences(of: "\\", with: "/")
            let components = name.components(separatedBy: "/")
            guard !name.isEmpty, !name.contains(":"), !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                  components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.hasSuffix(".") && !$0.hasSuffix(" ") }),
                  names.insert(name.lowercased()).inserted else { throw ETIError("The archive contains unsafe or duplicate paths.") }
            guard size <= recipe.maximumExpandedBytes - total else { throw ETIError("The archive exceeds this recipe's size limit.") }
            total += size
        }
        guard total > 0, names.count < 50_000,
              recipe.requiredFiles.allSatisfy({ names.contains($0.lowercased()) }) else { throw ETIError("The archive does not match the expected game layout.") }
        return total
    }
}
