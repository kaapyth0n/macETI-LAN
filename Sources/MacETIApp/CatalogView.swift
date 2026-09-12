import AppKit
import SwiftUI
import MacETICore

struct CatalogView: View {
    @ObservedObject var library: LibraryModel
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.gold.opacity(0.3))
            HStack(spacing: 0) {
                sidebar
                Divider()
                VStack(spacing: 0) {
                    filters
                    if let message = library.message {
                        HStack(alignment: .top) {
                            Image(systemName: "info.circle")
                            Text(message).textSelection(.enabled)
                            Spacer()
                            Button { library.message = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                                .accessibilityLabel("Dismiss message")
                        }.font(.callout).padding(12).background(Theme.gold.opacity(0.12))
                    }
                    if library.games.isEmpty { emptyState }
                    else if library.grid { grid }
                    else { rows }
                    footer
                }
            }
        }.background(Theme.background)
            .sheet(item: $library.selectedGame) { game in GameDetailView(library: library, game: game) }
    }

    private var header: some View {
        HStack(spacing: 14) {
            if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
               let appIcon = NSImage(contentsOf: iconURL) {
                Image(nsImage: appIcon).resizable().frame(width: 42, height: 42).accessibilityHidden(true)
            } else {
                Image(systemName: "gamecontroller").font(.system(size: 27)).foregroundStyle(Theme.gold)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("macETI-LAN").font(.title2.bold())
                Text("YOUR LAN. YOUR LIBRARY.").font(.system(size: 9, weight: .medium)).tracking(1.6).foregroundStyle(.secondary)
            }
            Spacer()
            Button { library.refresh() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
            Button { library.importFile() } label: { Label("Import", systemImage: "square.and.arrow.down") }
            Button { library.openResilio() } label: { Label("Resilio", systemImage: "arrow.triangle.2.circlepath") }
        }.buttonStyle(.bordered).padding(.horizontal, 22).padding(.vertical, 18)
            .background(Color.black.opacity(0.45))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("LIBRARY").font(.caption2.weight(.semibold)).tracking(1.2).foregroundStyle(.secondary).padding(.bottom, 10)
            ForEach(CatalogScope.allCases, id: \.self) { scope in
                Button { library.scope = scope } label: {
                    HStack(spacing: 10) {
                        Image(systemName: icon(scope)).frame(width: 18)
                        Text(scope.rawValue)
                        Spacer()
                        if scope == .all { Text("\(library.catalog?.games.count ?? 0)").font(.caption) }
                        if scope == .saved { Text("\(library.savedCount)").font(.caption) }
                    }.padding(10).contentShape(Rectangle())
                        .background(library.scope == scope ? Theme.gold.opacity(0.17) : .clear, in: RoundedRectangle(cornerRadius: 6))
                        .foregroundStyle(library.scope == scope ? Theme.gold : .secondary)
                }.buttonStyle(.plain)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 9) {
                Label(library.status.resilioRunning ? "Resilio running" : "Resilio offline",
                      systemImage: library.status.resilioRunning ? "circle.fill" : "circle")
                    .font(.caption).foregroundStyle(library.status.resilioRunning ? .green : .secondary)
                Text("Choose a game to sync. Configure its runtime when you're ready to play.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(16).frame(width: 190).background(Color.black.opacity(0.16))
    }

    private var filters: some View {
        HStack(spacing: 12) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search all games…", text: $library.search).textFieldStyle(.plain)
                    .accessibilityIdentifier("catalog-search")
                if !library.search.isEmpty {
                    Button { library.search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain)
                        .accessibilityLabel("Clear search")
                }
            }.padding(9).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
            Picker("Genre", selection: $library.genre) {
                Text("All genres").tag("")
                ForEach(library.genres, id: \.self) { Text($0).tag($0) }
            }.labelsHidden().frame(width: 170)
            Picker("Sort", selection: $library.sort) {
                ForEach(CatalogSort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.frame(width: 135)
            Button { library.grid.toggle() } label: { Image(systemName: library.grid ? "list.bullet" : "square.grid.3x3") }
                .help(library.grid ? "Switch to list" : "Switch to grid")
                .accessibilityLabel(library.grid ? "List view" : "Grid view")
        }.padding(16)
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 260), spacing: 14)], spacing: 14) {
                ForEach(library.games) { game in
                    Button { library.selectedGame = game } label: {
                        GameCard(game: game, preferences: library.preference(game), paths: library.store.paths)
                    }.buttonStyle(.plain).accessibilityLabel("Open \(game.title)")
                        .contextMenu {
                            Button("View game & sync…") { library.selectedGame = game }
                            Button(library.preference(game).saved ? "Remove from My games" : "Add to My games") { library.toggleSaved(game) }
                        }
                }
            }.padding(.horizontal, 16).padding(.bottom, 16)
        }
    }

    private var rows: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                HStack {
                    Text("GAME").frame(maxWidth: .infinity, alignment: .leading)
                    Text("GENRE").frame(width: 140, alignment: .leading)
                    Text("PLAYERS").frame(width: 65, alignment: .trailing)
                    Text("SIZE").frame(width: 70, alignment: .trailing)
                    Text("RUNTIME").frame(width: 130, alignment: .leading)
                }.font(.caption2).foregroundStyle(.secondary).padding(12)
                ForEach(library.games) { game in
                    Button { library.selectedGame = game } label: {
                        HStack {
                            Image(systemName: library.preference(game).saved ? "star.fill" : "gamecontroller").foregroundStyle(Theme.gold).frame(width: 18)
                            Text(game.title).frame(maxWidth: .infinity, alignment: .leading)
                            Text(game.metadata.genre).frame(width: 140, alignment: .leading)
                            Text(game.metadata.maximumPlayers.map(String.init) ?? "—").frame(width: 65, alignment: .trailing)
                            Text(sizeText(game)).frame(width: 70, alignment: .trailing)
                            Text(library.preference(game).runtime.kind.title).frame(width: 130, alignment: .leading)
                        }.font(.callout).padding(12).background(Theme.panel).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("Open \(game.title)")
                }
            }.padding(.horizontal, 16).padding(.bottom, 16)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass").font(.largeTitle).foregroundStyle(Theme.gold)
            Text(library.catalog == nil ? "Your library starts here" : "No games match these filters").font(.title2)
            Text(library.catalog == nil ? "Import ETI's game.db or connect the launcher share in Resilio." : "Try another search, genre or library view.").foregroundStyle(.secondary)
            if library.catalog != nil {
                Button("Show all games") { library.search = ""; library.genre = ""; library.scope = .all }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack {
            Text("\(library.games.count) \(library.games.count == 1 ? "game" : "games")")
            Spacer()
            if let date = library.receipt?.sourceModifiedAt { Text("Catalog · \(date.formatted(date: .abbreviated, time: .omitted))") }
            Text("Mac compatibility is untested").foregroundStyle(Theme.gold)
        }.font(.caption2).foregroundStyle(.secondary).padding(12).background(Color.black.opacity(0.3))
    }

    private func icon(_ scope: CatalogScope) -> String {
        switch scope {
        case .all: "square.grid.2x2"
        case .saved: "star"
        case .native: "desktopcomputer"
        case .crossOver: "app.connected.to.app.below.fill"
        }
    }
}

struct GameCard: View {
    let game: Game
    let preferences: GamePreferences
    let paths: LibraryPaths
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GameArtwork(game: game, paths: paths).frame(height: 108).clipped()
                .overlay(alignment: .topTrailing) {
                    if preferences.saved { Image(systemName: "star.fill").font(.caption).padding(7).background(.black.opacity(0.65), in: Circle()).padding(6).foregroundStyle(Theme.gold) }
                }
            VStack(alignment: .leading, spacing: 6) {
                Text(game.title).font(.system(size: 13, weight: .semibold)).lineLimit(2).frame(height: 33, alignment: .topLeading)
                HStack {
                    Text(preferences.runtime.kind == .native ? "Native port" : "CrossOver")
                        .foregroundStyle(preferences.runtime.kind == .native ? Theme.gold : .secondary)
                    Spacer()
                    Text(sizeText(game)).foregroundStyle(.secondary)
                }.font(.caption2)
            }.padding(11)
        }.background(Theme.panel, in: RoundedRectangle(cornerRadius: 7))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(.white.opacity(0.07)))
    }
}

struct GameArtwork: View {
    let game: Game
    let paths: LibraryPaths
    var body: some View {
        GeometryReader { geometry in
            if let image = ArtworkCache.image(for: game.id, paths: paths) {
                Image(nsImage: image).resizable().scaledToFill().frame(width: geometry.size.width, height: geometry.size.height).clipped()
            } else {
                ZStack {
                    LinearGradient(colors: [Theme.gold.opacity(0.20), Color.white.opacity(0.025)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    VStack(spacing: 9) {
                        Image(systemName: "gamecontroller").font(.system(size: 27, weight: .ultraLight)).foregroundStyle(Theme.gold.opacity(0.8))
                        Text(game.metadata.genre.isEmpty ? game.id.uppercased() : game.metadata.genre.uppercased())
                            .font(.system(size: 9, weight: .medium)).tracking(1.2).foregroundStyle(.secondary).lineLimit(1)
                    }.padding(12)
                }
            }
        }
    }
}

@MainActor
enum ArtworkCache {
    static let images = NSCache<NSString, NSImage>()
    static func image(for id: String, paths: LibraryPaths) -> NSImage? {
        guard CatalogReader.validID(id) else { return nil }
        let root = paths.support.appendingPathComponent("Artwork")
        for ext in ["jpg", "png", "jpeg"] {
            let file = root.appendingPathComponent("\(id).\(ext)")
            if let image = images.object(forKey: file.path as NSString) { return image }
            if let image = NSImage(contentsOf: file) { images.setObject(image, forKey: file.path as NSString); return image }
        }
        return nil
    }
}

func sizeText(_ game: Game) -> String { game.reportedSizeGB.map { "\($0.formatted()) GB" } ?? "—" }
