import Foundation

public struct LaunchCommand: Codable, Equatable, Sendable {
    public let executable: URL
    public let arguments: [String]
    public let workingDirectory: URL?
}

public enum GameLauncher {
    public static func crossOverApp(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        [URL(fileURLWithPath: "/Applications/CrossOver.app"), home.appendingPathComponent("Applications/CrossOver.app")]
            .first { FileManager.default.isExecutableFile(atPath: $0.appendingPathComponent("Contents/SharedSupport/CrossOver/bin/wine").path) }
    }

    public static func command(for config: RuntimeConfiguration, crossOver: URL? = crossOverApp()) throws -> LaunchCommand {
        let fm = FileManager.default
        guard config.executablePath.hasPrefix("/"), !config.executablePath.contains("\0") else {
            throw ETIError("Choose the game's local executable or Mac app in Runtime settings.")
        }
        let executable = URL(fileURLWithPath: config.executablePath).standardizedFileURL
        guard fm.fileExists(atPath: executable.path) else { throw ETIError("The configured executable is missing. Finish installation and check Runtime settings.") }
        var workingDirectory: URL?
        if !config.workingDirectory.isEmpty {
            var isDirectory: ObjCBool = false
            guard config.workingDirectory.hasPrefix("/"),
                  fm.fileExists(atPath: config.workingDirectory, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw ETIError("The configured working folder does not exist.")
            }
            workingDirectory = URL(fileURLWithPath: config.workingDirectory, isDirectory: true)
        }
        guard config.arguments.count <= 128, config.arguments.allSatisfy({ !$0.contains("\0") }) else {
            throw ETIError("Invalid launch arguments.")
        }
        switch config.kind {
        case .crossOver:
            guard let crossOver else { throw ETIError("CrossOver is not installed. Install it and create a bottle, then configure this game.") }
            guard !config.bottle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !config.bottle.contains("/"), !config.bottle.contains("\0") else {
                throw ETIError("Create a bottle in Runtime settings or enter an existing bottle name.")
            }
            guard executable.pathExtension.lowercased() == "exe" else { throw ETIError("Choose a Windows .exe for CrossOver.") }
            let wine = crossOver.appendingPathComponent("Contents/SharedSupport/CrossOver/bin/wine")
            guard fm.isExecutableFile(atPath: wine.path) else { throw ETIError("The selected CrossOver installation is missing its Wine executable.") }
            let gameDirectory = workingDirectory ?? executable.deletingLastPathComponent()
            // --cx-app searches bottle application names; a Mac path must be positional.
            // Pass the folder explicitly so CrossOver converts it to the Windows working directory.
            return LaunchCommand(executable: wine,
                                 arguments: ["--bottle", config.bottle, "--workdir", gameDirectory.path, "--", executable.path] + config.arguments,
                                 workingDirectory: gameDirectory)
        case .native:
            if executable.pathExtension.lowercased() == "app" {
                guard Bundle(url: executable)?.executableURL != nil else { throw ETIError("Choose a valid Mac app bundle.") }
                guard workingDirectory == nil else { throw ETIError("A working folder is supported for a native executable, not a Mac app bundle.") }
                return LaunchCommand(executable: URL(fileURLWithPath: "/usr/bin/open"),
                                     arguments: ["-a", executable.path] + (config.arguments.isEmpty ? [] : ["--args"] + config.arguments), workingDirectory: nil)
            }
            guard fm.isExecutableFile(atPath: executable.path), executable.pathExtension.lowercased() != "exe" else {
                throw ETIError("Choose an executable Mac engine or a Mac app.")
            }
            return LaunchCommand(executable: executable, arguments: config.arguments,
                                 workingDirectory: workingDirectory ?? executable.deletingLastPathComponent())
        }
    }

    /// Only a user-configured local executable reaches this path. Catalog strings never become commands.
    @discardableResult
    public static func launch(_ command: LaunchCommand) throws -> Process {
        let process = Process()
        process.executableURL = command.executable
        process.arguments = command.arguments
        process.currentDirectoryURL = command.workingDirectory
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process
    }
}
