import AppKit
import SwiftUI
import MacETICore

@MainActor
final class LibraryModel: ObservableObject {
    let store = LibraryStore()
    @Published var catalog: Catalog?
    @Published var receipt: CatalogReceipt?
    @Published var userLibrary = UserLibrary()
    @Published var status: SystemStatus
    @Published var message: String?
    @Published var search = ""
    @Published var genre = ""
    @Published var scope = CatalogScope.all
    @Published var sort = CatalogSort.title
    @Published var grid = true
    @Published var selectedGame: Game?
    @Published var preferencesAvailable = true
    @Published var compatibilityCatalog: CompatibilityCatalog?
    @Published var compatibilityError: String?
    @Published var compatibilityTests: [CompatibilityTest] = []
    @Published var testLogError: String?
    private var processes: [String: Process] = [:]
    @Published var launchingIDs: Set<String> = []
    @Published var setupGameID: String?
    @Published var setupMessages: [String: String] = [:]
    private var setupCancellation: SetupCancellation?

    init() {
        status = ResilioDesktop.status(paths: store.paths)
        do { compatibilityCatalog = try CompatibilityCatalog.bundled() }
        catch { compatibilityError = error.localizedDescription }
        refresh()
    }

    var preferences: PreferencesStore { .init(paths: store.paths) }
    var games: [Game] {
        guard let catalog else { return [] }
        return CatalogFilter.games(in: catalog, library: userLibrary, search: search, genre: genre, scope: scope, sort: sort)
    }
    var genres: [String] { Array(Set(catalog?.games.map(\.metadata.genre).filter { !$0.isEmpty } ?? [])).sorted() }
    var savedCount: Int { catalog?.games.filter { userLibrary.preferences(for: $0.id).saved }.count ?? 0 }
    func preference(_ game: Game) -> GamePreferences { userLibrary.preferences(for: game.id) }

    func refresh(source: URL? = nil) {
        message = nil
        do {
            let candidate = source ?? store.paths.liveCatalog
            if source != nil || FileManager.default.fileExists(atPath: candidate.path) { try store.importCatalog(from: candidate) }
            (catalog, receipt) = try store.load()
            if let selectedGame { self.selectedGame = catalog?.game(id: selectedGame.id) }
        } catch {
            if let saved = try? store.load() {
                (catalog, receipt) = saved
                message = "Showing the saved catalog. \(error.localizedDescription)"
            } else { message = "Connect ETI's launcher share in Resilio, then refresh. \(error.localizedDescription)" }
        }
        do { userLibrary = try preferences.load(); preferencesAvailable = true }
        catch { message = error.localizedDescription; preferencesAvailable = false }
        do {
            compatibilityTests = try CompatibilityTestStore(paths: store.paths).load()
            testLogError = nil
        } catch { compatibilityTests = []; testLogError = error.localizedDescription }
        status = ResilioDesktop.status(paths: store.paths)
    }

    func recordTest(_ test: CompatibilityTest) throws {
        compatibilityTests = try CompatibilityTestStore(paths: store.paths).append(test)
        testLogError = nil
    }

    func toggleSaved(_ game: Game) {
        do { userLibrary = try preferences.update(game.id) { $0.saved.toggle() } }
        catch { message = error.localizedDescription }
    }

    func saveRuntime(_ config: RuntimeConfiguration, for game: Game) throws {
        guard setupGameID != game.id else { throw ETIError("Wait for setup to finish before changing this runtime.") }
        userLibrary = try preferences.update(game.id) { $0.runtime = config }
    }

    func setUp(_ game: Game, mode: CrossOverSetupMode) {
        guard setupGameID == nil, preferencesAvailable, !launchingIDs.contains(game.id) else { return }
        let cancellation = SetupCancellation()
        setupCancellation = cancellation
        setupGameID = game.id
        setupMessages[game.id] = "Preparing setup…"
        let worker = CrossOverSetup(paths: store.paths, cancellation: cancellation)
        let expected = preference(game).runtime
        Task {
            do {
                _ = try await Task.detached {
                    try worker.perform(gameID: game.id, revision: game.packageRevision, mode: mode, expectedRuntime: expected) { [weak self] message in
                        Task { @MainActor [weak self] in
                            if self?.setupGameID == game.id { self?.setupMessages[game.id] = message }
                        }
                    }
                }.value
                setupMessages[game.id] = mode == .installPackage ? "Ready to launch." : "Bottle ready. Select the installed executable in Runtime; see Compatibility for extra setup."
            } catch is CancellationError {
                setupMessages[game.id] = "Setup cancelled. Extracted staging files were removed. Any new bottle was kept for the next attempt."
            } catch {
                setupMessages[game.id] = error.localizedDescription
            }
            do { userLibrary = try preferences.load() }
            catch { message = error.localizedDescription; preferencesAvailable = false }
            setupCancellation = nil
            setupGameID = nil
        }
    }

    func cancelSetup() {
        setupCancellation?.cancel()
        if let setupGameID { setupMessages[setupGameID] = "Cancelling… Bottle creation, if underway, will finish first." }
    }

    func launch(_ game: Game) {
        guard !launchingIDs.contains(game.id), setupGameID != game.id else { return }
        do {
            let command = try GameLauncher.command(for: preference(game).runtime)
            let process = try GameLauncher.launch(command)
            processes[game.id] = process
            launchingIDs.insert(game.id)
            message = "Launch request sent for \(game.title). See Compatibility for the recorded test results."
            process.terminationHandler = { [weak self] process in
                let code = process.terminationStatus
                Task { @MainActor [weak self] in
                    self?.processes.removeValue(forKey: game.id)
                    self?.launchingIDs.remove(game.id)
                    if code != 0 { self?.message = "\(game.title)'s launch process exited with code \(code). Check its runtime settings in CrossOver or the native app." }
                }
            }
        } catch { message = error.localizedDescription }
    }

    func importFile() {
        let panel = NSOpenPanel()
        panel.title = "Import ETI game.db"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let source = panel.url { refresh(source: source) }
    }

    func openResilio() {
        do { try ResilioDesktop.open() } catch { message = error.localizedDescription }
    }
}
