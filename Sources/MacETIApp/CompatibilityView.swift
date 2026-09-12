import SwiftUI
import MacETICore

struct CompatibilityView: View {
    @ObservedObject var library: LibraryModel
    let game: Game
    let openRuntime: () -> Void
    @State private var recording = false
    private var runtime: RuntimeConfiguration { library.preference(game).runtime }
    private var tests: [CompatibilityTest] { library.compatibilityTests.filter { $0.gameID == game.id } }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let catalog = library.compatibilityCatalog {
                let guide = catalog.guide(for: game.id, runtime: runtime.kind, packageRevision: game.packageRevision)
                header(guide)
                results
                HStack {
                    Button("Record a test…", systemImage: "square.and.pencil") { recording = true }
                        .disabled(library.testLogError != nil || !library.preferencesAvailable)
                    Button("Runtime settings…", systemImage: "slider.horizontal.3", action: openRuntime)
                }
                Text(guide.automaticSetupAvailable ? "Set up this package from Overview or Runtime. Test results describe the recorded environment and are saved only on this Mac." : runtime.kind == .crossOver ? "CrossOver bottle creation is available in Runtime. Follow the guidance below for the remaining game-specific setup; test results are saved only on this Mac." : "Follow the native engine's setup guide, then choose its executable in Runtime. Test results are saved only on this Mac.")
                    .font(.callout).foregroundStyle(.secondary)
                Divider()
                notes("Suggested setup", guide.setup, sources: guide.sources)
                DisclosureGroup("Troubleshooting & known issues") {
                    notes(nil, guide.troubleshooting, sources: guide.sources).padding(.top, 12)
                }
                DisclosureGroup("Windows LAN test checklist") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(guide.lanChecklist.enumerated()), id: \.offset) { index, item in
                            Text("\(index + 1). \(item)").frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.font(.callout).padding(.top, 12)
                }
                DisclosureGroup("Sources (\(guide.sources.count))") {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(guide.sources) { source in
                            VStack(alignment: .leading, spacing: 4) {
                                Link(source.title, destination: source.url)
                                Text(source.context).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }.padding(.top, 12).frame(maxWidth: .infinity, alignment: .leading)
                }
                if !tests.isEmpty {
                    DisclosureGroup("Local test history (\(tests.count))") {
                        VStack(alignment: .leading, spacing: 18) {
                            ForEach(tests) { test in
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(test.recordedAt.formatted(date: .abbreviated, time: .shortened)).font(.headline)
                                    Text("Gameplay: \(test.gameplay.title) · LAN: \(test.lan.title)")
                                    testContext(test)
                                    Text("Game: \(test.gameVersion.isEmpty ? "Not recorded" : test.gameVersion) · Windows host: \(test.windowsGameVersion.isEmpty ? "Not recorded" : test.windowsGameVersion)")
                                    if !test.notes.isEmpty { Text(test.notes).textSelection(.enabled) }
                                }.font(.callout)
                                Divider()
                            }
                        }.padding(.top, 12)
                    }
                }
            } else {
                Label("Compatibility guidance could not be loaded", systemImage: "exclamationmark.triangle")
                Text(library.compatibilityError ?? "Rebuild the app with its bundled resources.").foregroundStyle(.secondary)
            }
        }.sheet(isPresented: $recording) {
            RecordCompatibilityTestView(library: library, game: game, runtime: runtime,
                                        guidanceRevision: library.compatibilityCatalog?.contentRevision ?? "unknown")
        }
    }

    private func header(_ guide: CompatibilityGuide) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(guide.profile == nil ? "General guidance" : "Game-specific guidance", systemImage: "book.closed")
                    .font(.headline).foregroundStyle(Theme.gold)
                Spacer()
                Text("Reviewed \(guide.reviewedAt)").font(.caption).foregroundStyle(.secondary)
            }
            Text(guide.profile?.summary ?? "No game-specific profile has been researched yet. These are general setup and testing steps; this game's Mac compatibility is unknown.")
            Text("Guidance route: \(guide.route.title)").font(.callout).foregroundStyle(.secondary)
            if guide.route != runtime.kind {
                Label("Your saved runtime is \(runtime.kind.title). These notes describe the \(guide.route.title) route.", systemImage: "info.circle")
                    .font(.callout).foregroundStyle(Theme.gold)
            }
            if let profile = guide.profile {
                Text("Profile v\(profile.revision) · Reviewed ETI package \(profile.reviewedPackageRevision) · Game testing pending")
                    .font(.caption).foregroundStyle(.secondary)
                if profile.reviewedPackageRevision != game.packageRevision {
                    Label("The catalog package is now \(game.packageRevision). Recheck this guidance against the new package.", systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(Theme.gold)
                }
            }
        }
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tests.isEmpty ? "No local test recorded" : "Your latest recorded test").font(.headline)
            HStack(alignment: .top, spacing: 32) {
                result("GAMEPLAY", tests.first?.gameplay.title ?? "Not tested")
                result("WINDOWS LAN", tests.first?.lan.title ?? "Not tested")
            }
            if let test = tests.first {
                testContext(test)
                if !test.matchesPackageAndSettings(game: game, runtime: runtime) {
                    Label("Recorded with a different package or runtime configuration.", systemImage: "clock.arrow.circlepath")
                        .font(.caption).foregroundStyle(Theme.gold)
                }
                Text("This is a manual observation for the recorded environment, not a verified automatic setup profile.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error = library.testLogError { Text(error).font(.callout).foregroundStyle(Theme.gold) }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 8))
    }

    private func result(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.callout.weight(.medium))
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func testContext(_ test: CompatibilityTest) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(test.runtime.kind.title) \(test.runtimeVersion) · \(test.hardware)")
            Text("\(test.macOSVersion) · ETI package \(test.packageRevision)")
            Text("Recorded \(test.recordedAt.formatted(date: .abbreviated, time: .shortened)) · Guidance \(test.guidanceRevision)")
        }.font(.caption).foregroundStyle(.secondary)
    }

    private func notes(_ title: String?, _ notes: [CompatibilityNote], sources: [CompatibilitySource]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let title { Text(title).font(.title3.bold()) }
            ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                VStack(alignment: .leading, spacing: 6) {
                    Text(note.title).font(.callout.bold())
                    Text(note.detail).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    ForEach(sources.filter { note.sourceIDs.contains($0.id) }) { source in
                        Link(destination: source.url) {
                            Label(source.title, systemImage: "arrow.up.right.square").font(.caption)
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct RecordCompatibilityTestView: View {
    @ObservedObject var library: LibraryModel
    let game: Game
    let runtime: RuntimeConfiguration
    let guidanceRevision: String
    @Environment(\.dismiss) private var dismiss
    @State private var runtimeVersion = ""
    @State private var gameVersion = ""
    @State private var windowsVersion = ""
    @State private var gameplay = GameplayResult.notTested
    @State private var lan = LANResult.notTested
    @State private var notes = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Record a test · \(game.title)").font(.title2.bold())
            Text("Record what you observed after a manual test. Saving this form does not launch the game or apply settings.")
                .font(.callout).foregroundStyle(.secondary)
            Text("\(runtime.kind.title) · ETI package \(game.packageRevision)\n\(CompatibilityEnvironment.hardware) · \(ProcessInfo.processInfo.operatingSystemVersionString)")
                .font(.caption).foregroundStyle(.secondary)
            Form {
                TextField(runtime.kind == .crossOver ? "CrossOver version" : "Engine / Mac app version", text: $runtimeVersion)
                TextField("Mac client's game version", text: $gameVersion)
                TextField("Windows host's game version", text: $windowsVersion)
                Picker("Gameplay", selection: $gameplay) {
                    ForEach(GameplayResult.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Windows LAN", selection: $lan) {
                    ForEach(LANResult.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }.textFieldStyle(.roundedBorder)
            Text("Settings & observations").font(.headline)
            Text("Include graphics backend, MSync, bottle Windows version, dependencies, symptoms and whether WAN was disconnected.")
                .font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $notes).font(.callout).frame(height: 95).border(.white.opacity(0.15))
                .accessibilityLabel("Test settings and observations")
            if let error { Text(error).font(.callout).foregroundStyle(Theme.gold) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save local result") {
                    do {
                        let test = CompatibilityTest(game: game, guidanceRevision: guidanceRevision, runtime: runtime,
                            runtimeVersion: runtimeVersion, gameVersion: gameVersion, windowsGameVersion: windowsVersion,
                            gameplay: gameplay, lan: lan, notes: notes)
                        try library.recordTest(test)
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }.buttonStyle(.borderedProminent)
                    .disabled(runtimeVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (gameplay == .notTested && lan == .notTested))
            }
        }.padding(24).frame(width: 610).background(Theme.background).preferredColorScheme(.dark).tint(Theme.gold)
            .onAppear {
                if runtime.kind == .crossOver { runtimeVersion = CompatibilityEnvironment.crossOverVersion ?? "" }
            }
    }
}
