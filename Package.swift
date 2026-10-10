// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Skyline",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Skyline", targets: ["Skyline"])
    ],
    dependencies: [
        // nimbi's shared cloud, tokens and components. To work on both at once, swap in
        // .package(path: "../nimbi-kit") with a checkout next to this repo.
        .package(url: "https://github.com/behkha/nimbi-kit.git", from: "0.3.0")
    ],
    targets: [
        // Everything that isn't a view: MET client, cache, location, sky reading, moods.
        .target(
            name: "SkylineCore",
            dependencies: [.product(name: "NimbiKit", package: "nimbi-kit")],
            path: "Sources/SkylineCore"
        ),
        .executableTarget(
            name: "Skyline",
            dependencies: ["SkylineCore", .product(name: "NimbiKit", package: "nimbi-kit")],
            path: "Sources/Skyline"
        ),
        .testTarget(
            name: "SkylineCoreTests",
            dependencies: ["SkylineCore", .product(name: "NimbiKit", package: "nimbi-kit")],
            path: "Tests/SkylineCoreTests"
        )
    ]
)
