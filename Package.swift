// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ArenaBridge",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ArenaBridge",
            path: "Sources/ArenaBridge"
        )
    ]
)
