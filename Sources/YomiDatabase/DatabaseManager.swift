import Foundation
import GRDB

/// Central SQLite coordinator using GRDB.swift with WAL concurrency and FTS5 indexing.
public final class DatabaseManager: @unchecked Sendable {
    public static let shared = DatabaseManager()

    public let dbWriter: any DatabaseWriter

    /// Standard initializer creating or opening the production SQLite database file.
    public convenience init() {
        do {
            let fileManager = FileManager.default
            let appSupportURL = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let yomiDirURL = appSupportURL.appendingPathComponent("Yomi", isDirectory: true)
            if !fileManager.fileExists(atPath: yomiDirURL.path) {
                try fileManager.createDirectory(at: yomiDirURL, withIntermediateDirectories: true)
            }
            let dbURL = yomiDirURL.appendingPathComponent("yomi.sqlite")
            
            var config = Configuration()
            config.qos = .userInitiated
            // Write-Ahead Logging for non-blocking concurrent reads
            config.foreignKeysEnabled = true
            
            let pool = try DatabasePool(path: dbURL.path, configuration: config)
            self.init(dbWriter: pool)
            try setupMigrations()
        } catch {
            fatalError("Failed to initialize Yomi SQLite database: \(error)")
        }
    }

    /// In-memory initializer for automated unit testing and isolated environments.
    public static func makeInMemory() throws -> DatabaseManager {
        var config = Configuration()
        config.foreignKeysEnabled = true
        let queue = try DatabaseQueue(configuration: config)
        let manager = DatabaseManager(dbWriter: queue)
        try manager.setupMigrations()
        return manager
    }

    public init(dbWriter: any DatabaseWriter) {
        self.dbWriter = dbWriter
    }

    /// Registers and executes migrations.
    private func setupMigrations() throws {
        var migrator = DatabaseMigrator()
        #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = false
        #endif
        SchemaMigrations.registerMigrations(in: &migrator)
        try migrator.migrate(dbWriter)
    }

    /// Performs an asynchronous read transaction on a background thread.
    public func read<T: Sendable>(_ value: @Sendable @escaping (Database) throws -> T) async throws -> T {
        try await dbWriter.read(value)
    }

    /// Performs an asynchronous write transaction on a serialized queue.
    public func write<T: Sendable>(_ updates: @Sendable @escaping (Database) throws -> T) async throws -> T {
        try await dbWriter.write(updates)
    }
}
