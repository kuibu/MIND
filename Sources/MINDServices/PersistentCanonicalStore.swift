import CryptoKit
import Foundation
import MINDSchemas
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public protocol CanonicalStore {
    func load() throws -> InMemoryMINDRepository
    func persist(repository: InMemoryMINDRepository) throws
}

public struct CanonicalStoreSnapshot: Codable, Equatable {
    public let identities: [Identity]
    public let conversations: [Conversation]
    public let messages: [Message]
    public let attachments: [Attachment]
    public let fileAssets: [FileAsset]
    public let merchants: [Merchant]
    public let orders: [Order]
    public let trips: [Trip]
    public let expenses: [Expense]
    public let contentItems: [ContentItem]
    public let metricSnapshots: [MetricSnapshot]
    public let collectionEvents: [CollectionEvent]

    public init(repository: InMemoryMINDRepository) {
        self.identities = repository.identities
        self.conversations = repository.conversations
        self.messages = repository.messages
        self.attachments = repository.attachments
        self.fileAssets = repository.fileAssets
        self.merchants = repository.merchants
        self.orders = repository.orders
        self.trips = repository.trips
        self.expenses = repository.expenses
        self.contentItems = repository.contentItems
        self.metricSnapshots = repository.metricSnapshots
        self.collectionEvents = repository.collectionEvents
    }

    public func makeRepository() -> InMemoryMINDRepository {
        let repository = InMemoryMINDRepository()
        identities.forEach { repository.add(identity: $0) }
        conversations.forEach { repository.add(conversation: $0) }
        messages.forEach { repository.add(message: $0) }
        attachments.forEach { repository.add(attachment: $0) }
        fileAssets.forEach { repository.add(fileAsset: $0) }
        merchants.forEach { repository.add(merchant: $0) }
        orders.forEach { repository.add(order: $0) }
        trips.forEach { repository.add(trip: $0) }
        expenses.forEach { repository.add(expense: $0) }
        contentItems.forEach { repository.add(contentItem: $0) }
        metricSnapshots.forEach { repository.add(metricSnapshot: $0) }
        collectionEvents.forEach { repository.add(collectionEvent: $0) }
        return repository
    }
}

public final class DiskCanonicalStore: CanonicalStore {
    public let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL) {
        self.fileURL = fileURL
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func load() throws -> InMemoryMINDRepository {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return InMemoryMINDRepository()
        }

        let data = try Data(contentsOf: fileURL)
        let snapshot = try decoder.decode(CanonicalStoreSnapshot.self, from: data)
        return snapshot.makeRepository()
    }

    public func persist(repository: InMemoryMINDRepository) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(CanonicalStoreSnapshot(repository: repository))
        try data.write(to: fileURL, options: .atomic)
    }
}

public final class SQLiteCanonicalStore: CanonicalStore {
    private struct MaterializedTable {
        let name: String
        let resourceType: String
    }

    private static let materializedTables: [MaterializedTable] = [
        MaterializedTable(name: "identities", resourceType: "Identity"),
        MaterializedTable(name: "conversations", resourceType: "Conversation"),
        MaterializedTable(name: "messages", resourceType: "Message"),
        MaterializedTable(name: "attachments", resourceType: "Attachment"),
        MaterializedTable(name: "file_assets", resourceType: "FileAsset"),
        MaterializedTable(name: "merchants", resourceType: "Merchant"),
        MaterializedTable(name: "orders", resourceType: "Order"),
        MaterializedTable(name: "trips", resourceType: "Trip"),
        MaterializedTable(name: "expenses", resourceType: "Expense"),
        MaterializedTable(name: "content_items", resourceType: "ContentItem"),
        MaterializedTable(name: "metric_snapshots", resourceType: "MetricSnapshot"),
        MaterializedTable(name: "collection_events", resourceType: "CollectionEvent")
    ]

    public let fileURL: URL
    public let legacySnapshotURL: URL?

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let formatter = ISO8601DateFormatter()

    public init(fileURL: URL, legacySnapshotURL: URL? = nil) {
        self.fileURL = fileURL
        self.legacySnapshotURL = legacySnapshotURL

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func load() throws -> InMemoryMINDRepository {
        if FileManager.default.fileExists(atPath: fileURL.path) == false,
           let legacySnapshotURL = legacySnapshotURL,
           FileManager.default.fileExists(atPath: legacySnapshotURL.path) {
            let legacyStore = DiskCanonicalStore(fileURL: legacySnapshotURL)
            let repository = try legacyStore.load()
            try persist(repository: repository)
            return repository
        }

        let database = try openDatabase()
        defer { sqlite3_close(database) }
        try ensureSchema(in: database)

        let repository = InMemoryMINDRepository()
        try loadResources(table: "identities", as: Identity.self, using: database).forEach { repository.add(identity: $0) }
        try loadResources(table: "conversations", as: Conversation.self, using: database).forEach { repository.add(conversation: $0) }
        try loadResources(table: "messages", as: Message.self, using: database).forEach { repository.add(message: $0) }
        try loadResources(table: "attachments", as: Attachment.self, using: database).forEach { repository.add(attachment: $0) }
        try loadResources(table: "file_assets", as: FileAsset.self, using: database).forEach { repository.add(fileAsset: $0) }
        try loadResources(table: "merchants", as: Merchant.self, using: database).forEach { repository.add(merchant: $0) }
        try loadResources(table: "orders", as: Order.self, using: database).forEach { repository.add(order: $0) }
        try loadResources(table: "trips", as: Trip.self, using: database).forEach { repository.add(trip: $0) }
        try loadResources(table: "expenses", as: Expense.self, using: database).forEach { repository.add(expense: $0) }
        try loadResources(table: "content_items", as: ContentItem.self, using: database).forEach { repository.add(contentItem: $0) }
        try loadResources(table: "metric_snapshots", as: MetricSnapshot.self, using: database).forEach { repository.add(metricSnapshot: $0) }
        try loadResources(table: "collection_events", as: CollectionEvent.self, using: database).forEach { repository.add(collectionEvent: $0) }
        return repository
    }

    public func persist(repository: InMemoryMINDRepository) throws {
        let database = try openDatabase()
        defer { sqlite3_close(database) }
        try ensureSchema(in: database)

        try sync(resources: repository.identities, table: "identities", resourceType: "Identity", occurredAt: { _ in Date() }, id: \.id, using: database)
        try sync(resources: repository.conversations, table: "conversations", resourceType: "Conversation", occurredAt: { $0.lastMessageAt ?? Date() }, id: \.id, using: database)
        try sync(resources: repository.messages, table: "messages", resourceType: "Message", occurredAt: \.sentAt, id: \.id, using: database)
        try sync(resources: repository.attachments, table: "attachments", resourceType: "Attachment", occurredAt: { _ in Date() }, id: \.id, using: database)
        try sync(resources: repository.fileAssets, table: "file_assets", resourceType: "FileAsset", occurredAt: { _ in Date() }, id: \.id, using: database)
        try sync(resources: repository.merchants, table: "merchants", resourceType: "Merchant", occurredAt: { _ in Date() }, id: \.id, using: database)
        try sync(resources: repository.orders, table: "orders", resourceType: "Order", occurredAt: { _ in Date() }, id: \.id, using: database)
        try sync(resources: repository.trips, table: "trips", resourceType: "Trip", occurredAt: \.startedAt, id: \.id, using: database)
        try sync(resources: repository.expenses, table: "expenses", resourceType: "Expense", occurredAt: \.occurredAt, id: \.id, using: database)
        try sync(resources: repository.contentItems, table: "content_items", resourceType: "ContentItem", occurredAt: { _ in Date() }, id: \.id, using: database)
        try sync(resources: repository.metricSnapshots, table: "metric_snapshots", resourceType: "MetricSnapshot", occurredAt: \.capturedAt, id: \.id, using: database)
        try sync(resources: repository.collectionEvents, table: "collection_events", resourceType: "CollectionEvent", occurredAt: \.collectedAt, id: \.id, using: database)
    }

    private func openDatabase() throws -> OpaquePointer? {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var database: OpaquePointer?
        let status = sqlite3_open(fileURL.path, &database)
        guard status == SQLITE_OK else {
            defer { sqlite3_close(database) }
            throw storeError(database, fallback: "failed to open sqlite database")
        }
        return database
    }

    private func ensureSchema(in database: OpaquePointer?) throws {
        try execute(
            """
            CREATE TABLE IF NOT EXISTS event_log (
                row_id INTEGER PRIMARY KEY AUTOINCREMENT,
                event_key TEXT NOT NULL UNIQUE,
                resource_type TEXT NOT NULL,
                resource_id TEXT NOT NULL,
                payload_json TEXT NOT NULL,
                occurred_at TEXT NOT NULL,
                recorded_at TEXT NOT NULL
            );
            """,
            using: database
        )

        for table in Self.materializedTables {
            try execute(
                """
                CREATE TABLE IF NOT EXISTS \(table.name) (
                    id TEXT PRIMARY KEY,
                    payload_json TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );
                """,
                using: database
            )
        }
    }

    private func loadResources<Resource: Decodable>(
        table: String,
        as type: Resource.Type,
        using database: OpaquePointer?
    ) throws -> [Resource] {
        var statement: OpaquePointer?
        let sql = "SELECT payload_json FROM \(table) ORDER BY rowid ASC;"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw storeError(database, fallback: "failed to prepare load statement for \(table)")
        }
        defer { sqlite3_finalize(statement) }

        var resources: [Resource] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let pointer = sqlite3_column_text(statement, 0) else { continue }
            let payload = String(cString: pointer)
            let data = Data(payload.utf8)
            resources.append(try decoder.decode(Resource.self, from: data))
        }
        return resources
    }

    private func sync<Resource: Encodable>(
        resources: [Resource],
        table: String,
        resourceType: String,
        occurredAt: (Resource) -> Date,
        id: KeyPath<Resource, String>,
        using database: OpaquePointer?
    ) throws {
        for resource in resources {
            let payloadData = try encoder.encode(resource)
            guard let payload = String(data: payloadData, encoding: .utf8) else {
                continue
            }

            let resourceID = resource[keyPath: id]
            let existingPayload = try fetchPayload(table: table, id: resourceID, using: database)
            guard existingPayload != payload else { continue }

            let updatedAt = formatter.string(from: Date())
            try upsert(table: table, id: resourceID, payload: payload, updatedAt: updatedAt, using: database)
            try appendEvent(
                resourceType: resourceType,
                resourceID: resourceID,
                payload: payload,
                occurredAt: formatter.string(from: occurredAt(resource)),
                using: database
            )
        }
    }

    private func fetchPayload(table: String, id: String, using database: OpaquePointer?) throws -> String? {
        var statement: OpaquePointer?
        let sql = "SELECT payload_json FROM \(table) WHERE id = ? LIMIT 1;"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw storeError(database, fallback: "failed to prepare payload lookup for \(table)")
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, id, -1, SQLITE_TRANSIENT)
        if sqlite3_step(statement) == SQLITE_ROW, let pointer = sqlite3_column_text(statement, 0) {
            return String(cString: pointer)
        }
        return nil
    }

    private func upsert(table: String, id: String, payload: String, updatedAt: String, using database: OpaquePointer?) throws {
        var statement: OpaquePointer?
        let sql = """
        INSERT INTO \(table) (id, payload_json, updated_at)
        VALUES (?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            payload_json = excluded.payload_json,
            updated_at = excluded.updated_at;
        """
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw storeError(database, fallback: "failed to prepare upsert for \(table)")
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, id, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, payload, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 3, updatedAt, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw storeError(database, fallback: "failed to upsert row into \(table)")
        }
    }

    private func appendEvent(
        resourceType: String,
        resourceID: String,
        payload: String,
        occurredAt: String,
        using database: OpaquePointer?
    ) throws {
        let payloadHash = Self.hash(payload)
        let eventKey = "\(resourceType)|\(resourceID)|\(payloadHash)"
        let recordedAt = formatter.string(from: Date())

        var statement: OpaquePointer?
        let sql = """
        INSERT OR IGNORE INTO event_log (
            event_key,
            resource_type,
            resource_id,
            payload_json,
            occurred_at,
            recorded_at
        ) VALUES (?, ?, ?, ?, ?, ?);
        """
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw storeError(database, fallback: "failed to prepare append event statement")
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, eventKey, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, resourceType, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 3, resourceID, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 4, payload, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 5, occurredAt, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 6, recordedAt, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw storeError(database, fallback: "failed to append event log row")
        }
    }

    private func execute(_ sql: String, using database: OpaquePointer?) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw storeError(database, fallback: "failed to execute sqlite statement")
        }
    }

    private func storeError(_ database: OpaquePointer?, fallback: String) -> NSError {
        let detail = database.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? fallback
        return NSError(domain: "SQLiteCanonicalStore", code: 1, userInfo: [NSLocalizedDescriptionKey: detail])
    }

    private static func hash(_ payload: String) -> String {
        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
