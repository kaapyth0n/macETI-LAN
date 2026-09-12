import AppKit
import SwiftUI
import MacETICore

struct GameRemovalView: View {
    @ObservedObject var library: LibraryModel
    let game: Game
    @Environment(\.dismiss) private var dismiss
    @State private var plan: GameRemovalPlan?
    @State private var selected: Set<GameRemovalKind> = []
    @State private var sizes: [GameRemovalKind: Int64] = [:]
    @State private var measured = false
    @State private var gameClosed = false
    @State private var disconnected = false
    @State private var error: String?

    private var busy: Bool { library.removingGameID != nil }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Remove \(game.title)").font(.title2.bold())
            Text("Choose which local files to move to Trash.").foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let plan {
                        ForEach(plan.folders, id: \.kind) { folder in
                            VStack(alignment: .leading, spacing: 8) {
                                Toggle(isOn: Binding(get: { selected.contains(folder.kind) }, set: { checked in
                                    if checked { selected.insert(folder.kind) } else { selected.remove(folder.kind) }
                                })) {
                                    HStack {
                                        Text(folder.kind.title).font(.headline)
                                        Spacer()
                                        Text(sizes[folder.kind].map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
                                             ?? (measured ? "Size unavailable" : "Calculating size…")).foregroundStyle(.secondary)
                                    }
                                }.toggleStyle(.checkbox)
                                Text(folder.url.path).font(.caption.monospaced()).textSelection(.enabled)
                                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([folder.url]) }.font(.caption)
                            }.padding(14).background(Theme.panel, in: RoundedRectangle(cornerRadius: 8))
                        }
                        ForEach(plan.notes, id: \.self) { Text($0).font(.callout).foregroundStyle(Theme.gold) }
                        if plan.folders.isEmpty { Text("No removable game folders were found.").foregroundStyle(.secondary) }
                        if !plan.runtime.executablePath.isEmpty, !plan.folders.contains(where: { $0.kind == .installation }) {
                            Button("Reveal configured executable") {
                                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: plan.runtime.executablePath)])
                            }
                        }
                    }
                    if selected.contains(.download) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Disconnect the download first").font(.headline)
                            Text("In Resilio, open this game's folder menu → Disconnect on this Mac. Pausing sync is not enough. macETI cannot verify the connection state.")
                                .font(.callout)
                            HStack {
                                Button("Open Resilio") { library.openResilio() }
                                Link("Resilio instructions", destination: URL(string: "https://help.resilio.com/hc/en-us/articles/205457785-Disconnecting-and-Removing-Folders")!)
                            }
                            Toggle("This folder is disconnected in Resilio on this Mac", isOn: $disconnected).toggleStyle(.checkbox)
                        }.padding(14).background(Theme.panel, in: RoundedRectangle(cornerRadius: 8))
                    }
                    if !selected.isEmpty {
                        Text("Saves and settings inside the selected folders will move with them. CrossOver bottles and saves elsewhere are kept. Restoring files from Trash may require selecting the executable again in Runtime.")
                            .font(.callout).foregroundStyle(.secondary)
                        Toggle("The game and its installers are closed", isOn: $gameClosed).toggleStyle(.checkbox)
                    }
                    Text("To reclaim disk space, empty these items from Trash in Finder after checking for saves. The game stays in the catalog and My games; use the star to unsave it.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let error { Text(error).font(.callout).foregroundStyle(Theme.gold).textSelection(.enabled) }
                }.frame(maxWidth: .infinity, alignment: .leading).disabled(busy)
            }
            Divider()
            HStack {
                if busy { ProgressView().controlSize(.small); Text("Moving files…").foregroundStyle(.secondary) }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).disabled(busy)
                Button("Move to Trash", role: .destructive) { remove() }
                    .disabled(plan == nil || selected.isEmpty || !gameClosed ||
                              (selected.contains(.download) && !disconnected) || busy ||
                              library.setupGameID != nil || library.launchingIDs.contains(game.id) || !library.preferencesAvailable)
            }
        }.padding(24).frame(width: 650, height: 680).background(Theme.background)
            .preferredColorScheme(.dark).tint(Theme.gold)
            .interactiveDismissDisabled(busy)
            .task { await prepare() }
    }

    private func prepare() async {
        do {
            let preview = try GameRemoval(paths: library.store.paths).plan(gameID: game.id)
            plan = preview
            if preview.folders.contains(where: { $0.kind == .installation }) { selected = [.installation] }
            else if preview.folders.contains(where: { $0.kind == .download }) { selected = [.download] }
            let worker = Task.detached {
                var sizes: [GameRemovalKind: Int64] = [:]
                for folder in preview.folders { sizes[folder.kind] = GameRemoval.allocatedBytes(at: folder.url) }
                return sizes
            }
            sizes = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            measured = true
        } catch { self.error = error.localizedDescription }
    }

    private func remove() {
        guard let plan else { return }
        Task {
            do {
                try await library.remove(game, plan: plan, kinds: selected, gameClosed: gameClosed, disconnected: disconnected)
                dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}
