// swift-tools-version: 6.2
// AlfredKit : le cœur de l'app Alfred, sans interface. Compilé et testé aussi sous Linux (`swift test`).
import PackageDescription

let package = Package(
    name: "AlfredKit",
    defaultLocalization: "fr",
    platforms: [.iOS(.v26), .macOS(.v26), .watchOS(.v26)],
    products: [
        .library(name: "AlfredKit", targets: ["AlfredKit"])
    ],
    targets: [
        .target(name: "AlfredKit"),
        .testTarget(name: "AlfredKitTests", dependencies: ["AlfredKit"]),
    ]
)
