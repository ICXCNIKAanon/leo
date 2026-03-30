// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Leo",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.0.0")
    ],
    targets: [
        .executableTarget(
            name: "Leo",
            dependencies: ["SwiftTerm"],
            path: "Sources/Leo"
        )
    ]
)
