// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CodexClient",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "CodexClient", targets: ["CodexClient"]),
    ],
    targets: [
        .target(name: "CodexClient"),
        .testTarget(
            name: "CodexClientTests",
            dependencies: ["CodexClient"],
            exclude: ["FakeAppServer.py"]
        ),
    ]
)
