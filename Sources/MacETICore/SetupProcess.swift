import Foundation
import CryptoKit

/// Shared between the background setup worker and the main-thread Cancel button.
public final class SetupCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    public init() {}
    public func cancel() { lock.withLock { cancelled = true } }
    public func check() throws {
        if lock.withLock({ cancelled }) { throw CancellationError() }
    }
}

struct SetupProcess: Sendable {
    let cancellation: SetupCancellation

    /// Output goes to private files, so verbose subprocesses cannot block on a full pipe.
    func run(_ executable: URL, _ arguments: [String], log: URL,
             timeout: TimeInterval = 300, cancellable: Bool = true) throws {
        if cancellable { try cancellation.check() }
        let fm = FileManager.default
        guard fm.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw ETIError("Cannot create the setup log.")
        }
        let output = try FileHandle(forWritingTo: log)
        defer { try? output.close() }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = output
        // Do not inherit a developer's Wine bottle override or RAR configuration.
        var environment = ProcessInfo.processInfo.environment
        for key in ["WINEPREFIX", "CX_BOTTLE", "CX_BOTTLE_PATH", "RAR"] { environment.removeValue(forKey: key) }
        environment["LC_ALL"] = "C"
        process.environment = environment
        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        do {
            while process.isRunning {
                if cancellable { try cancellation.check() }
                guard Date() < deadline else { throw ETIError("Setup timed out. See the private setup log.") }
                Thread.sleep(forTimeInterval: 0.1)
            }
        } catch {
            if process.isRunning { process.terminate() }
            let stopDeadline = Date().addingTimeInterval(3)
            while process.isRunning && Date() < stopDeadline { Thread.sleep(forTimeInterval: 0.1) }
            if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            throw error
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ETIError("\(executable.lastPathComponent) exited with code \(process.terminationStatus). See the private setup log.")
        }
    }
}

enum SetupArchiveTool {
    // Publisher download, pinned to the ARM build used for the verified game trials.
    static let download = "https://www.rarlab.com/rar/rarmacos-arm-723.tar.gz"
    static let archiveHash = "68b393c000758d477fde43c955ff7542f12f76f3f5e87cdda923152fc791bd4d"
    static let executableHash = "99720d63484b8db77db43477db095f198d52b34515938d4ee7b165c59fa1cbe9"

    static func prepare(at root: URL, runner: SetupProcess, log: URL,
                        progress: @Sendable (String) -> Void) throws -> URL {
        #if !arch(arm64)
        throw ETIError("Package extraction currently requires Apple Silicon. Bottle creation and manual setup remain available.")
        #else
        let fm = FileManager.default
        let destination = root.appendingPathComponent("unrar-7.23-arm64", isDirectory: true)
        let tool = destination.appendingPathComponent("rar/unrar")
        if fm.fileExists(atPath: tool.path) {
            guard try hash(tool) == executableHash, fm.isExecutableFile(atPath: tool.path) else {
                throw ETIError("The cached archive tool failed validation. Remove \(destination.path) and retry.")
            }
            return tool
        }
        progress("Downloading UnRAR 7.23 from RARLAB…")
        let staging = root.appendingPathComponent(".tool-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: staging) }
        let archive = staging.appendingPathComponent("download.tar.gz")
        try runner.run(URL(fileURLWithPath: "/usr/bin/curl"),
                       ["--fail", "--location", "--silent", "--show-error", "--proto", "=https", "--proto-redir", "=https",
                        "--max-time", "120", "--max-filesize", "2000000", "--output", archive.path, download], log: log, timeout: 130)
        guard try hash(archive) == archiveHash else { throw ETIError("The archive tool download failed its SHA-256 check.") }
        // The complete tarball is pinned before extracting these three fixed members.
        try runner.run(URL(fileURLWithPath: "/usr/bin/tar"),
                       ["-xzf", archive.path, "-C", staging.path, "rar/unrar", "rar/license.txt", "rar/readme.txt"], log: log)
        guard try hash(staging.appendingPathComponent("rar/unrar")) == executableHash else {
            throw ETIError("The downloaded archive executable failed validation.")
        }
        try fm.removeItem(at: archive)
        try fm.moveItem(at: staging, to: destination)
        return tool
        #endif
    }

    static func hash(_ file: URL) throws -> String {
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? Int, size <= 2_000_000 else { throw ETIError("Invalid archive tool file.") }
        return SHA256.hash(data: try Data(contentsOf: file)).map { String(format: "%02x", $0) }.joined()
    }
}
