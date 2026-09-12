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
                        Text(config.bottle.isEmpty ? "Install the synced game and fill in its launch settings automatically. A Windows 10 bottle will be created for you. Finish the Resilio transfer first." : "Install the synced game into the bottle you already created and fill in its launch settings automatically. Finish the Resilio transfer first.")
                        if let name = recipe?.launchName { Text("This package will launch \(name).").font(.callout).foregroundStyle(Theme.gold) }
                        Text("First setup downloads the checked UnRAR 7.23 tool from RARLAB (about 654 KB). Game files come from your synced folder.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Automatic installation is not supported for this package yet. Creating a bottle only prepares the Windows environment; the game still needs to be installed manually.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    if GameLauncher.crossOverApp() == nil {
                        Link("Install and activate CrossOver first", destination: URL(string: "https://www.codeweavers.com/crossover")!)
                    }
                    HStack {
                        if let recipe {
                            Button("Set up \(recipe.launchName ?? "game")", systemImage: "wand.and.stars") { library.setUp(game, mode: .installPackage) }
                                .buttonStyle(.borderedProminent)
                        }
                        if config.bottle.isEmpty && recipe == nil {
                            Button("Create bottle only", systemImage: "plus") { library.setUp(game, mode: .bottleOnly) }
                        } else if !config.bottle.isEmpty { Text("Bottle: \(config.bottle)").font(.callout) }
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
                if let message = library.setupMessages[game.id], busy || config.executablePath.isEmpty {
                    Text(message).font(.callout).foregroundStyle(Theme.gold).textSelection(.enabled)
                    Button("Show setup logs") { NSWorkspace.shared.open(CrossOverSetup(paths: library.store.paths).logs) }
                        .font(.caption)
                }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
