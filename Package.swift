// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "lighthouse-swift",
    platforms: [.macOS("10.15")],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "LighthouseClient",
            targets: ["LighthouseClient"]
        ),
        .executable(
            name: "LighthouseDemo",
            targets: ["LighthouseDemo"]
        )
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(url: "https://github.com/vapor/websocket-kit.git", from: "2.3.0"),
        .package(url: "https://github.com/Flight-School/MessagePack.git", from: "1.2.4"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.4.2"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "LighthouseClient",
            dependencies: [
                .product(name: "WebSocketKit", package: "websocket-kit"),
                .product(name: "MessagePack", package: "MessagePack"),
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .executableTarget(
            name: "LighthouseDemo",
            dependencies: [
                .target(name: "LighthouseClient"),
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        // .testTarget(
        //     name: "LighthouseClientTests",
        //     dependencies: [
        //         .target(name: "LighthouseClient"),
        //     ]
        // ),
    ]
)
