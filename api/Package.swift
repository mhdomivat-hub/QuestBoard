// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "QuestBoardAPI",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", exact: "4.121.2"),
        .package(url: "https://github.com/vapor/fluent.git", exact: "4.13.0"),
        .package(url: "https://github.com/vapor/fluent-postgres-driver.git", exact: "2.12.0"),
        .package(url: "https://github.com/vapor/sql-kit.git", exact: "3.34.0"),
        .package(url: "https://github.com/vapor/postgres-kit.git", exact: "2.15.1"),
        .package(url: "https://github.com/apple/swift-crypto.git", exact: "3.15.1")
    ],
    targets: [
        .executableTarget(
            name: "Run",
            dependencies: [
                .target(name: "App")
            ]
        ),
        .target(
            name: "App",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),
                .product(name: "SQLKit", package: "sql-kit"),
                .product(name: "PostgresKit", package: "postgres-kit"),
                .product(name: "Crypto", package: "swift-crypto")
            ]
        ),
        .testTarget(
            name: "AppTests",
            dependencies: [
                .target(name: "App")
            ]
        )
    ]
)
