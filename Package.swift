// swift-tools-version: 5.6
import PackageDescription

let package = Package(
    name: "MIND",
    platforms: [
        .macOS(.v12),
        .iOS(.v15)
    ],
    products: [
        .library(name: "MINDProtocol", targets: ["MINDProtocol"]),
        .library(name: "MINDSchemas", targets: ["MINDSchemas"]),
        .library(name: "MINDRecipes", targets: ["MINDRecipes"]),
        .library(name: "MINDServices", targets: ["MINDServices"]),
        .library(name: "MINDPipelines", targets: ["MINDPipelines"]),
        .library(name: "MINDAppSupport", targets: ["MINDAppSupport"])
    ],
    targets: [
        .target(name: "MINDProtocol"),
        .target(
            name: "MINDSchemas",
            dependencies: ["MINDProtocol"]
        ),
        .target(
            name: "MINDRecipes",
            dependencies: ["MINDProtocol"]
        ),
        .target(
            name: "MINDServices",
            dependencies: ["MINDProtocol", "MINDSchemas", "MINDRecipes"],
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .target(
            name: "MINDPipelines",
            dependencies: ["MINDProtocol", "MINDSchemas", "MINDServices"]
        ),
        .target(
            name: "MINDAppSupport",
            dependencies: ["MINDProtocol", "MINDSchemas", "MINDRecipes", "MINDServices", "MINDPipelines"]
        ),
        .testTarget(
            name: "MINDPipelinesTests",
            dependencies: ["MINDProtocol", "MINDSchemas", "MINDServices", "MINDPipelines", "MINDAppSupport"]
        )
    ]
)
