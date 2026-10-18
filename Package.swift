// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Yomi",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "YomiCore", targets: ["YomiCore"]),
        .library(name: "YomiDatabase", targets: ["YomiDatabase"]),
        .library(name: "YomiExtensions", targets: ["YomiExtensions"]),
        .library(name: "YomiReader", targets: ["YomiReader"]),
        .library(name: "YomiDownload", targets: ["YomiDownload"]),
        .library(name: "YomiSync", targets: ["YomiSync"]),
        .library(name: "YomiUI", targets: ["YomiUI"]),
        .library(name: "YomiApp", targets: ["YomiApp"])
    ],
    dependencies: [
        // High-performance SQLite ORM with WAL and FTS5 support
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.24.2"),
        // Fast native HTML parser for scraping without Node.js dependencies
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.2"),
        // Apple Official Swift Protocol Buffers for Tachiyomi/Mihon .tachibk compatibility
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.26.0"),
        // Swift-native ZIP/CBZ archive manager for downloaded chapters
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19")
    ],
    targets: [
        // MARK: - Core Domain & Security
        .target(
            name: "YomiCore",
            dependencies: [],
            path: "Sources/YomiCore"
        ),
        
        // MARK: - Persistence & Database
        .target(
            name: "YomiDatabase",
            dependencies: [
                "YomiCore",
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "Sources/YomiDatabase"
        ),
        
        // MARK: - Extensions & JavaScriptCore Scraper Engine
        .target(
            name: "YomiExtensions",
            dependencies: [
                "YomiCore",
                .product(name: "SwiftSoup", package: "SwiftSoup")
            ],
            path: "Sources/YomiExtensions"
        ),
        
        // MARK: - Reader Engine & Hybrid Viewport
        .target(
            name: "YomiReader",
            dependencies: [
                "YomiCore"
            ],
            path: "Sources/YomiReader"
        ),
        
        // MARK: - Background Downloads & CBZ Archival
        .target(
            name: "YomiDownload",
            dependencies: [
                "YomiCore",
                .product(name: "ZIPFoundation", package: "ZIPFoundation")
            ],
            path: "Sources/YomiDownload"
        ),
        
        // MARK: - Sync, Tachiyomi Backup & Trackers
        .target(
            name: "YomiSync",
            dependencies: [
                "YomiCore",
                "YomiDatabase",
                .product(name: "SwiftProtobuf", package: "swift-protobuf")
            ],
            path: "Sources/YomiSync"
        ),
        
        // MARK: - UI Presentation & SwiftUI Views
        .target(
            name: "YomiUI",
            dependencies: [
                "YomiCore",
                "YomiDatabase",
                "YomiExtensions",
                "YomiReader",
                "YomiDownload",
                "YomiSync"
            ],
            path: "Sources/YomiUI"
        ),
        
        // MARK: - Main Application Module
        .target(
            name: "YomiApp",
            dependencies: [
                "YomiUI"
            ],
            path: "Sources/YomiApp"
        ),
        
        // MARK: - Tests
        .testTarget(
            name: "YomiCoreTests",
            dependencies: ["YomiCore"],
            path: "Tests/YomiCoreTests"
        ),
        .testTarget(
            name: "YomiDatabaseTests",
            dependencies: ["YomiDatabase", "YomiCore"],
            path: "Tests/YomiDatabaseTests"
        ),
        .testTarget(
            name: "YomiExtensionsTests",
            dependencies: ["YomiExtensions", "YomiCore"],
            path: "Tests/YomiExtensionsTests"
        )
    ]
)
