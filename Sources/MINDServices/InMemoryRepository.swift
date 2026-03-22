import Foundation
import MINDProtocol
import MINDSchemas

public struct LinkedAttachment {
    public let attachment: Attachment
    public let fileAsset: FileAsset?
    public let message: Message?
    public let conversation: Conversation?
    public let sender: Identity?

    public init(
        attachment: Attachment,
        fileAsset: FileAsset?,
        message: Message?,
        conversation: Conversation?,
        sender: Identity?
    ) {
        self.attachment = attachment
        self.fileAsset = fileAsset
        self.message = message
        self.conversation = conversation
        self.sender = sender
    }
}

public struct LinkedCollection {
    public let event: CollectionEvent
    public let contentItem: ContentItem?
    public let metricSnapshot: MetricSnapshot?

    public init(event: CollectionEvent, contentItem: ContentItem?, metricSnapshot: MetricSnapshot?) {
        self.event = event
        self.contentItem = contentItem
        self.metricSnapshot = metricSnapshot
    }
}

public final class InMemoryMINDRepository {
    public private(set) var identities: [Identity]
    public private(set) var conversations: [Conversation]
    public private(set) var messages: [Message]
    public private(set) var attachments: [Attachment]
    public private(set) var fileAssets: [FileAsset]
    public private(set) var merchants: [Merchant]
    public private(set) var orders: [Order]
    public private(set) var trips: [Trip]
    public private(set) var expenses: [Expense]
    public private(set) var contentItems: [ContentItem]
    public private(set) var metricSnapshots: [MetricSnapshot]
    public private(set) var collectionEvents: [CollectionEvent]

    public init() {
        self.identities = []
        self.conversations = []
        self.messages = []
        self.attachments = []
        self.fileAssets = []
        self.merchants = []
        self.orders = []
        self.trips = []
        self.expenses = []
        self.contentItems = []
        self.metricSnapshots = []
        self.collectionEvents = []
    }

    public func add(identity: Identity) { identities.append(identity) }
    public func add(conversation: Conversation) { conversations.append(conversation) }
    public func add(message: Message) { messages.append(message) }
    public func add(attachment: Attachment) { attachments.append(attachment) }
    public func add(fileAsset: FileAsset) { fileAssets.append(fileAsset) }
    public func add(merchant: Merchant) { merchants.append(merchant) }
    public func add(order: Order) { orders.append(order) }
    public func add(trip: Trip) { trips.append(trip) }
    public func add(expense: Expense) { expenses.append(expense) }
    public func add(contentItem: ContentItem) { contentItems.append(contentItem) }
    public func add(metricSnapshot: MetricSnapshot) { metricSnapshots.append(metricSnapshot) }
    public func add(collectionEvent: CollectionEvent) { collectionEvents.append(collectionEvent) }

    public func merchant(id: String?) -> Merchant? {
        guard let id = id else { return nil }
        return merchants.first { $0.id == id }
    }

    public func order(id: String?) -> Order? {
        guard let id = id else { return nil }
        return orders.first { $0.id == id }
    }

    public func trip(id: String?) -> Trip? {
        guard let id = id else { return nil }
        return trips.first { $0.id == id }
    }

    public func expenses(in interval: DateInterval, from sources: Set<SourcePlatform>) -> [Expense] {
        expenses
            .filter { sources.contains($0.source) && interval.contains($0.occurredAt) }
            .sorted { $0.occurredAt < $1.occurredAt }
    }

    public func conversations(participantMatching name: String) -> [Conversation] {
        let matchedIDs = Set(identities(matching: name).map(\.id))
        return conversations.filter { !$0.participantIDs.filter(matchedIDs.contains).isEmpty }
    }

    public func linkedAttachments(participantName: String, fileNameQuery: String) -> [LinkedAttachment] {
        let conversationIDs = Set(conversations(participantMatching: participantName).map(\.id))
        let query = normalize(fileNameQuery)

        return attachments.compactMap { attachment in
            guard let message = messages.first(where: { $0.id == attachment.messageID }) else {
                return nil
            }
            guard conversationIDs.contains(message.conversationID) else {
                return nil
            }

            let fileAsset = fileAssets.first(where: { $0.id == attachment.fileAssetID })
            let searchable = [
                attachment.fileName,
                fileAsset?.canonicalName ?? "",
                message.text ?? ""
            ].map(normalize)

            guard searchable.contains(where: { $0.contains(query) }) else {
                return nil
            }

            let conversation = conversations.first(where: { $0.id == message.conversationID })
            let sender = identities.first(where: { $0.id == message.senderIdentityID })

            return LinkedAttachment(
                attachment: attachment,
                fileAsset: fileAsset,
                message: message,
                conversation: conversation,
                sender: sender
            )
        }
    }

    public func linkedCollections(in interval: DateInterval, from sources: Set<SourcePlatform>) -> [LinkedCollection] {
        collectionEvents
            .filter { sources.contains($0.source) && interval.contains($0.collectedAt) }
            .map { event in
                LinkedCollection(
                    event: event,
                    contentItem: contentItems.first(where: { $0.id == event.contentItemID }),
                    metricSnapshot: metricSnapshots.first(where: { $0.id == event.metricSnapshotID })
                )
            }
            .sorted { $0.event.collectedAt < $1.event.collectedAt }
    }

    private func identities(matching name: String) -> [Identity] {
        let query = normalize(name)
        return identities.filter { identity in
            normalize(identity.displayName).contains(query) ||
            identity.aliases.map(normalize).contains(where: { $0.contains(query) })
        }
    }

    private func normalize(_ input: String) -> String {
        input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
