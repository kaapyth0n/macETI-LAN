import AppKit
import SwiftUI
import MacETICore

struct GameDetailView: View {
    @ObservedObject var library: LibraryModel
    let game: Game
    @Environment(\.dismiss) private var dismiss
    @State private var section = "overview"
    @State private var showRemoval = false
    private var config: RuntimeConfiguration { library.preference(game).runtime }
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 20) {
                GameArtwork(game: game, paths: library.store.paths).frame(width: 235, height: 137).clipShape(RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 10) {
                    Text(game.title).font(.title.bold())
                    Text([game.metadata.year, game.metadata.genre].filter { !$0.isEmpty }.joined(separator: " · ")).foregroundStyle(.secondary)
                    Text(config.kind.title).font(.callout.weight(.medium)).foregroundStyle(Theme.gold)
                    Button(library.preference(game).saved ? "Saved to My games" : "Add to My games",
                           systemImage: library.preference(game).saved ? "star.fill" : "star") { library.toggleSaved(game) }
                        .disabled(!library.preferencesAvailable)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.secondary) }
                    .buttonStyle(.plain).accessibilityLabel("Close game")
            }.padding(24)
            Picker("Game details", selection: $section) {
                Text("Overview").tag("overview")
                Text("Compatibility").tag("compatibility")
                Text("Sync").tag("sync")
                Text("Runtime").tag("runtime")
            }.pickerStyle(.segmented).padding(.horizontal, 24).padding(.bottom, 18)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let message = library.message {
                        Text(message).font(.callout).foregroundStyle(Theme.gold).textSelection(.enabled)
                    }
                    switch section {
                    case "compatibility": CompatibilityView(library: library, game: game) { section = "runtime" }
                    case "sync": SyncSetupView(library: library, game: game)
                    case "runtime": RuntimeSettingsView(library: library, game: game, initial: config).id(game.id)
                    default: overview
                    }
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                Button("Remove game…", systemImage: "trash", role: .destructive) { showRemoval = true }
                    .disabled(!library.preferencesAvailable || library.setupGameID != nil || library.removingGameID != nil || library.launchingIDs.contains(game.id))
                    .help("Close the game and finish any setup before removing files.")
                Spacer()
            }.padding(.horizontal, 24).padding(.vertical, 12)
        }.frame(width: 770, height: 710).background(Theme.background).preferredColorScheme(.dark).tint(Theme.gold)
            .sheet(isPresented: $showRemoval) { GameRemovalView(library: library, game: game) }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 30) {
                stat("PACKAGE SIZE", sizeText(game))
                stat("PLAYERS", game.metadata.maximumPlayers.map(String.init) ?? "—")
                stat("PACKAGE REVISION", game.packageRevision)
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Theme.panel, in: RoundedRectangle(cornerRadius: 8))
            if !game.metadata.publisher.isEmpty { Text(game.metadata.publisher).foregroundStyle(.secondary) }
            HStack {
                Button("Sync this game…", systemImage: "arrow.down.circle") { section = "sync" }
                    .buttonStyle(.borderedProminent).disabled(game.readOnlyKey == nil)
                Button("Runtime settings…", systemImage: "slider.horizontal.3") { section = "runtime" }
                Button(library.launchingIDs.contains(game.id) ? "Launching…" : "Launch", systemImage: "play.fill") { library.launch(game) }
                    .disabled(config.executablePath.isEmpty || !library.preferencesAvailable || library.launchingIDs.contains(game.id) || library.setupGameID == game.id || library.removingGameID != nil)
            }
            CrossOverSetupView(library: library, game: game)
            Button("Compatibility & setup", systemImage: "checkmark.seal") { section = "compatibility" }
            Text("CrossOver is the default for Windows packages. Choose Native / Mac app when using a port, and select its installed executable.")
                .foregroundStyle(.secondary)
            if let note = GameProfile.selected.first(where: { $0.id == game.id })?.note {
                Label(note, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
            }
            Divider()
            Text("Sync availability does not establish Mac compatibility. Package revisions and sizes come from ETI; the actual game version and LAN compatibility still need testing.")
                .font(.caption).foregroundStyle(.secondary)
            if let folder = try? library.store.paths.gameDirectory(game.id), FileManager.default.fileExists(atPath: folder.path) {
                Button("Show local game folder") { NSWorkspace.shared.open(folder) }
                Text("A folder is present. Check Resilio for transfer completion.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.medium))
        }
    }
}

struct SyncSetupView: View {
    @ObservedObject var library: LibraryModel
    let game: Game
    @State private var feedback = ""
    private var destination: URL? { try? library.store.paths.gameDirectory(game.id) }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Sync \(game.title)").font(.title3.bold())
            Text("Connect this one read-only package in Resilio. Listed size: \(sizeText(game)).").foregroundStyle(.secondary)
            Text("1. Copy the key. In Resilio, choose + → Enter a key or link, then paste.")
            HStack {
                Button("Copy key & open Resilio") {
                    if let key = game.readOnlyKey {
                        ResilioDesktop.copyKey(key)
                        library.openResilio()
                        feedback = "Key copied. Paste it into Resilio before copying the folder path."
                    }
                }.buttonStyle(.borderedProminent).disabled(game.readOnlyKey == nil || destination == nil)
            }
            Text("2. Set Selective Sync to Off for the full game package. Choose this folder:")
            Text(destination?.path ?? "Folder unavailable: check for a symlink outside the library.")
                .font(.callout.monospaced()).textSelection(.enabled).padding(12)
                .frame(maxWidth: .infinity, alignment: .leading).background(Theme.panel, in: RoundedRectangle(cornerRadius: 8))
            Button("Prepare & copy folder path") {
                do {
                    let folder = try library.store.paths.gameDirectory(game.id)
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(folder.path, forType: .string)
                    feedback = "Folder prepared; path copied. This replaces the key on the clipboard."
                } catch { feedback = error.localizedDescription }
            }.disabled(destination == nil)
            Text("3. Complete the connection in Resilio. Use its transfer status to check progress and pause or stop syncing.")
            Text("My games is a saved list. Adding or removing a game there does not connect or disconnect a Resilio share.")
                .font(.caption).foregroundStyle(.secondary)
            Text(feedback).font(.callout).foregroundStyle(Theme.gold)
        }
    }
}

struct RuntimeSettingsView: View {
    @ObservedObject var library: LibraryModel
    let game: Game
    @State private var config: RuntimeConfiguration
    @State private var argumentLines: String
    @State private var feedback = ""

    init(library: LibraryModel, game: Game, initial: RuntimeConfiguration) {
        self.library = library
        self.game = game
        _config = State(initialValue: initial)
        _argumentLines = State(initialValue: initial.arguments.joined(separator: "\n"))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            CrossOverSetupView(library: library, game: game,
                              formHasChanges: config != library.preference(game).runtime || argumentLines != config.arguments.joined(separator: "\n"))
            Group {
                Text("How should this game run?").font(.title3.bold())
                Picker("Runtime", selection: $config.kind) {
                    ForEach(RuntimeKind.allCases, id: \.self) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                if config.kind == .crossOver {
                    TextField("CrossOver bottle name", text: $config.bottle).textFieldStyle(.roundedBorder)
                    Text(GameLauncher.crossOverApp() == nil ? "Install and activate CrossOver to enable bottle creation." : "Setup fills this in automatically. You can also use an existing bottle.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Choose a native engine executable or a Mac .app. This overrides the default Windows runtime for this game only.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    TextField(config.kind == .crossOver ? "Windows game executable (.exe)" : "Native executable or Mac app", text: $config.executablePath)
                        .textFieldStyle(.roundedBorder)
                    Button("Choose…") { choose(directory: false) }
                }
                HStack {
                    TextField("Working folder (optional)", text: $config.workingDirectory).textFieldStyle(.roundedBorder)
                    Button("Choose…") { choose(directory: true) }
                }
                Text("Launch arguments · one argument per line").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $argumentLines).font(.callout.monospaced()).frame(height: 65)
                    .border(.white.opacity(0.1))
                Text("Use an installed copy for play. Keep extracted games, runtime settings and saves separate from the synced distribution package.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Save runtime") {
                        do {
                            config.arguments = argumentLines.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
                            try library.saveRuntime(config, for: game)
                            feedback = "Runtime saved for \(game.title)."
                        } catch { feedback = error.localizedDescription }
                    }.buttonStyle(.borderedProminent).disabled(!library.preferencesAvailable)
                    Button("Reset to default") {
                        config = .defaultFor(game.id)
                        argumentLines = ""
                        feedback = "Default restored in this form. Save to apply."
                    }
                    Spacer()
                    Text("See Compatibility for test results").font(.caption).foregroundStyle(.secondary)
                }
                Text(feedback).font(.callout).foregroundStyle(Theme.gold)
            }.disabled(library.setupGameID == game.id || library.removingGameID != nil)
        }
        .onChange(of: library.preference(game).runtime) { _, updated in
            config = updated
            argumentLines = updated.arguments.joined(separator: "\n")
        }
    }

    private func choose(directory: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = directory
        panel.canChooseFiles = !directory
        panel.treatsFilePackagesAsDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let selected = panel.url {
            if directory { config.workingDirectory = selected.path } else { config.executablePath = selected.path }
        }
    }
}
