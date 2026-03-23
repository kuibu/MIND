import Foundation
import MINDSchemas

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

public final class DiskCanonicalStore {
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
