// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "macETI-LAN",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MacETICore", targets: ["MacETICore"]),
        .executable(name: "maceti", targets: ["MacETICLI"]),
        .executable(name: "MacETILAN", targets: ["MacETIApp"])
    ],
    targets: [
        .systemLibrary(name: "CSQLite", pkgConfig: "sqlite3"),
        .target(name: "MacETICore", dependencies: ["CSQLite"], resources: [.process("Resources")]),
        .executableTarget(name: "MacETICLI", dependencies: ["MacETICore"]),
        .executableTarget(name: "MacETIApp", dependencies: ["MacETICore"]),
        .testTarget(name: "MacETICoreTests", dependencies: ["MacETICore", "CSQLite"])
    ]
)
