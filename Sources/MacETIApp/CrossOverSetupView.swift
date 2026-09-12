import AppKit
import SwiftUI
import MacETICore

struct CrossOverSetupView: View {
    @ObservedObject var library: LibraryModel
    let game: Game
    var formHasChanges = false
    private var config: RuntimeConfiguration { library.preference(game).runtime }
    private var recipe: CrossOverRecipe? { .recipe(for: game.id, revision: game.packageRevision) }
    private var executablePresent: Bool { FileManager.default.fileExists(atPath: config.executablePath) }
    private var busy: Bool { library.setupGameID == game.id }

    var body: some View {
        if config.kind == .crossOver {
            VStack(alignment: .leading, spacing: 12) {
                Label("CrossOver setup", systemImage: "shippingbox").font(.headline)
                if !config.executablePath.isEmpty {
                    Label(executablePresent ? "Runtime configured · \(config.bottle)" : "Saved executable is missing · check Runtime settings",
                          systemImage: executablePresent ? "checkmark.circle" : "exclamationmark.triangle")
                    Text(executablePresent ? "Your existing installation is kept. Use Launch to play." : "Select the correct executable in Runtime. Your saved bottle is preserved.").font(.callout).foregroundStyle(.secondary)
                } else {
                    if recipe != nil {
                        Text("Create a Windows 10 bottle, extract the synced package and save the launch settings. Finish the Resilio transfer first.")
                        Text("First setup downloads the checked UnRAR 7.23 tool from RARLAB (about 654 KB). Game files come from your synced folder.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Create and save a dedicated Windows 10 bottle. Then follow Compatibility for this game's installation and select its executable in Runtime.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    if GameLauncher.crossOverApp() == nil {
                        Link("Install and activate CrossOver first", destination: URL(string: "https://www.codeweavers.com/crossover")!)
                    }
                    HStack {
                        if recipe != nil {
                            Button("Set up game", systemImage: "wand.and.stars") { library.setUp(game, mode: .installPackage) }
                                .buttonStyle(.borderedProminent)
                        }
                        if config.bottle.isEmpty {
                            Button("Create bottle only", systemImage: "plus") { library.setUp(game, mode: .bottleOnly) }
                        } else { Text("Bottle: \(config.bottle)").font(.callout) }
                    }.disabled(library.setupGameID != nil || library.removingGameID != nil || !library.preferencesAvailable || formHasChanges ||
                               library.launchingIDs.contains(game.id) || GameLauncher.crossOverApp() == nil)
                    if formHasChanges { Text("Save your edited runtime settings before starting setup.").font(.caption).foregroundStyle(Theme.gold) }
                    if let other = library.setupGameID, other != game.id { Text("Another game's setup is running.").font(.caption) }
                }
                if busy {
                    HStack {
                        ProgressView().controlSize(.small)
                        Button("Cancel setup") { library.cancelSetup() }
                    }
                }
                if let message = library.setupMessages[game.id] {
                    Text(message).font(.callout).foregroundStyle(Theme.gold).textSelection(.enabled)
                    Button("Show setup logs") { NSWorkspace.shared.open(CrossOverSetup(paths: library.store.paths).logs) }
                        .font(.caption)
                }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
