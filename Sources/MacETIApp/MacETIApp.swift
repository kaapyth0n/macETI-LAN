import AppKit
import SwiftUI
import MacETICore

@main
struct MacETIApp: App {
    @StateObject private var library = LibraryModel()
    var body: some Scene {
        WindowGroup("macETI-LAN") {
            CatalogView(library: library)
                .frame(minWidth: 930, minHeight: 630)
                .preferredColorScheme(.dark).tint(Theme.gold)
                .onAppear {
                    NSApplication.shared.setActivationPolicy(.regular)
                    // Refresh the running Dock tile even when Launch Services cached an older bundle icon.
                    if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
                       let icon = NSImage(contentsOf: iconURL) {
                        NSApplication.shared.applicationIconImage = icon
                    }
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
        }
        .defaultSize(width: 1200, height: 780)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Import catalog…") { library.importFile() }
                Button("Refresh catalog") { library.refresh() }.keyboardShortcut("r")
            }
        }
    }
}

enum Theme {
    static let gold = Color(red: 0.79, green: 0.64, blue: 0.32)
    static let background = Color(red: 0.065, green: 0.067, blue: 0.073)
    static let panel = Color(red: 0.10, green: 0.105, blue: 0.115)
}
