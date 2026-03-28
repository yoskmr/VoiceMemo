// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "SoyokaModules",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "FeatureRecording", targets: ["FeatureRecording"]),
        .library(name: "FeatureMemo", targets: ["FeatureMemo"]),
        .library(name: "FeatureAI", targets: ["FeatureAI"]),
        .library(name: "FeatureSearch", targets: ["FeatureSearch"]),
        .library(name: "FeatureSettings", targets: ["FeatureSettings"]),
        .library(name: "FeatureSubscription", targets: ["FeatureSubscription"]),
        .library(name: "Domain", targets: ["Domain"]),
        .library(name: "Data", targets: ["Data"]),
        .library(name: "InfraSTT", targets: ["InfraSTT"]),
        .library(name: "InfraLLM", targets: ["InfraLLM"]),
        .library(name: "InfraStorage", targets: ["InfraStorage"]),
        .library(name: "InfraNetwork", targets: ["InfraNetwork"]),
        .library(name: "SharedUI", targets: ["SharedUI"]),
        .library(name: "SharedUtil", targets: ["SharedUtil"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/pointfreeco/swift-composable-architecture",
            from: "1.17.0"
        ),
        .package(
            url: "https://github.com/pointfreeco/swift-dependencies",
            from: "1.6.0"
        ),
        .package(
            url: "https://github.com/weichsel/ZIPFoundation",
            from: "0.9.19"
        ),
        // SwiftLint: Xcode Build Phase で別途実行（SPMプラグインは互換性問題あり）
    ],
    targets: [
        // MARK: - Domain Layer (最内層 - 依存なし)
        .target(
            name: "Domain",
            dependencies: [
                .product(name: "Dependencies", package: "swift-dependencies"),
            ],
            plugins: []
        ),

        // MARK: - Shared Modules
        .target(
            name: "SharedUtil",
            dependencies: [],
            plugins: []
        ),
        .target(
            name: "SharedUI",
            dependencies: [
                "Domain",
            ],
            plugins: []
        ),

        // MARK: - Infrastructure Modules (Infra -> Domain)
        .target(
            name: "InfraSTT",
            dependencies: [
                "Domain",
            ],
            plugins: []
        ),
        .target(
            name: "InfraLLM",
            dependencies: [
                "Domain",
            ],
            plugins: []
        ),
        .target(
            name: "InfraStorage",
            dependencies: [
                "Domain",
                "SharedUtil",
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ],
            plugins: []
        ),
        .target(
            name: "InfraNetwork",
            dependencies: [
                "Domain",
                "SharedUtil",
            ],
            plugins: []
        ),

        // MARK: - Data Layer (Data -> Domain, InfraStorage, InfraNetwork)
        .target(
            name: "Data",
            dependencies: [
                "Domain",
                "InfraStorage",
                "InfraNetwork",
            ],
            plugins: []
        ),

        // MARK: - Feature Modules (Feature -> Domain, SharedUI のみ。Infra直接依存禁止)
        .target(
            name: "FeatureRecording",
            dependencies: [
                "Domain",
                "SharedUI",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            ],
            plugins: []
        ),
        .target(
            name: "FeatureMemo",
            dependencies: [
                "Domain",
                "SharedUI",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            ],
            plugins: []
        ),
        .target(
            name: "FeatureAI",
            dependencies: [
                "Domain",
                "SharedUI",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            ],
            plugins: []
        ),
        .target(
            name: "FeatureSearch",
            dependencies: [
                "Domain",
                "SharedUI",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            ],
            plugins: []
        ),
        .target(
            name: "FeatureSettings",
            dependencies: [
                "Domain",
                "SharedUI",
                "SharedUtil",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            ],
            plugins: []
        ),
        .target(
            name: "FeatureSubscription",
            dependencies: [
                "Domain",
                "SharedUI",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            ],
            plugins: []
        ),

        // MARK: - Test Targets
        .testTarget(name: "DomainTests", dependencies: ["Domain"]),
        .testTarget(name: "FeatureRecordingTests", dependencies: ["FeatureRecording"]),
        .testTarget(name: "FeatureMemoTests", dependencies: ["FeatureMemo"]),
        .testTarget(name: "FeatureAITests", dependencies: ["FeatureAI"]),
        .testTarget(name: "InfraSTTTests", dependencies: ["InfraSTT"]),
        .testTarget(name: "InfraLLMTests", dependencies: ["InfraLLM"]),
        .testTarget(name: "InfraStorageTests", dependencies: [
            "InfraStorage",
            "Domain",
            .product(name: "ZIPFoundation", package: "ZIPFoundation"),
        ]),
        .testTarget(name: "FeatureSearchTests", dependencies: ["FeatureSearch", "Domain"]),
        .testTarget(name: "FeatureSettingsTests", dependencies: ["FeatureSettings", "Domain"]),
    ]
)
