import Foundation
import MINDProtocol

public enum ActorRole: String, Codable {
    case owner
    case assistant
    case agent
    case reviewer
}

public enum ActionMode: String, Codable {
    case readOnly
    case ownerApprovalRequired
    case autoApproved
}

public enum RetentionMode: String, Codable {
    case canonicalOnly
    case retainEvidenceOnLowConfidence
    case retainAll
}

public struct PermissionPolicy: Codable, Equatable {
    public let readers: [ActorRole]
    public let actionMode: ActionMode
    public let retentionMode: RetentionMode

    public init(
        readers: [ActorRole],
        actionMode: ActionMode,
        retentionMode: RetentionMode
    ) {
        self.readers = readers
        self.actionMode = actionMode
        self.retentionMode = retentionMode
    }

    public static let `private` = PermissionPolicy(
        readers: [.owner, .assistant],
        actionMode: .ownerApprovalRequired,
        retentionMode: .retainEvidenceOnLowConfidence
    )
}

public struct EvidenceRef: Codable, Equatable {
    public let id: String
    public let locator: String
    public let source: SourcePlatform
    public let confidence: Double
    public let retained: Bool

    public init(
        id: String,
        locator: String,
        source: SourcePlatform,
        confidence: Double,
        retained: Bool
    ) {
        self.id = id
        self.locator = locator
        self.source = source
        self.confidence = confidence
        self.retained = retained
    }
}

public struct Identity: Codable, Equatable {
    public let id: String
    public let displayName: String
    public let aliases: [String]
    public let permissions: PermissionPolicy

    public init(id: String, displayName: String, aliases: [String] = [], permissions: PermissionPolicy = .private) {
        self.id = id
        self.displayName = displayName
        self.aliases = aliases
        self.permissions = permissions
    }
}

public struct Conversation: Codable, Equatable {
    public let id: String
    public let source: SourcePlatform
    public let title: String?
    public let participantIDs: [String]
    public let lastMessageAt: Date?
    public let evidenceRefs: [EvidenceRef]
    public let permissions: PermissionPolicy

    public init(
        id: String,
        source: SourcePlatform,
        title: String? = nil,
        participantIDs: [String],
        lastMessageAt: Date? = nil,
        evidenceRefs: [EvidenceRef] = [],
        permissions: PermissionPolicy = .private
    ) {
        self.id = id
        self.source = source
        self.title = title
        self.participantIDs = participantIDs
        self.lastMessageAt = lastMessageAt
        self.evidenceRefs = evidenceRefs
        self.permissions = permissions
    }
}

public struct Message: Codable, Equatable {
    public let id: String
    public let conversationID: String
    public let senderIdentityID: String
    public let text: String?
    public let sentAt: Date
    public let attachmentIDs: [String]
    public let evidenceRefs: [EvidenceRef]
    public let permissions: PermissionPolicy

    public init(
        id: String,
        conversationID: String,
        senderIdentityID: String,
        text: String? = nil,
        sentAt: Date,
        attachmentIDs: [String] = [],
        evidenceRefs: [EvidenceRef] = [],
        permissions: PermissionPolicy = .private
    ) {
        self.id = id
        self.conversationID = conversationID
        self.senderIdentityID = senderIdentityID
        self.text = text
        self.sentAt = sentAt
        self.attachmentIDs = attachmentIDs
        self.evidenceRefs = evidenceRefs
        self.permissions = permissions
    }
}

public struct FileAsset: Codable, Equatable {
    public let id: String
    public let canonicalName: String
    public let localPath: String?
    public let blobID: String?
    public let sha256: String?
    public let evidenceRefs: [EvidenceRef]
    public let permissions: PermissionPolicy

    public init(
        id: String,
        canonicalName: String,
        localPath: String? = nil,
        blobID: String? = nil,
        sha256: String? = nil,
        evidenceRefs: [EvidenceRef] = [],
        permissions: PermissionPolicy = .private
    ) {
        self.id = id
        self.canonicalName = canonicalName
        self.localPath = localPath
        self.blobID = blobID
        self.sha256 = sha256
        self.evidenceRefs = evidenceRefs
        self.permissions = permissions
    }
}

public struct Attachment: Codable, Equatable {
    public let id: String
    public let messageID: String
    public let fileAssetID: String
    public let fileName: String
    public let mimeType: String?
    public let evidenceRefs: [EvidenceRef]
    public let permissions: PermissionPolicy

    public init(
        id: String,
        messageID: String,
        fileAssetID: String,
        fileName: String,
        mimeType: String? = nil,
        evidenceRefs: [EvidenceRef] = [],
        permissions: PermissionPolicy = .private
    ) {
        self.id = id
        self.messageID = messageID
        self.fileAssetID = fileAssetID
        self.fileName = fileName
        self.mimeType = mimeType
        self.evidenceRefs = evidenceRefs
        self.permissions = permissions
    }
}

public struct Merchant: Codable, Equatable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct Order: Codable, Equatable {
    public let id: String
    public let source: SourcePlatform
    public let externalID: String
    public let title: String

    public init(id: String, source: SourcePlatform, externalID: String, title: String) {
        self.id = id
        self.source = source
        self.externalID = externalID
        self.title = title
    }
}

public struct Trip: Codable, Equatable {
    public let id: String
    public let source: SourcePlatform
    public let startedAt: Date
    public let endedAt: Date?
    public let routeSummary: String?

    public init(
        id: String,
        source: SourcePlatform,
        startedAt: Date,
        endedAt: Date? = nil,
        routeSummary: String? = nil
    ) {
        self.id = id
        self.source = source
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.routeSummary = routeSummary
    }
}

public enum ExpenseCategory: String, Codable, CaseIterable {
    case travel = "差旅"
    case dining = "餐饮"
    case other = "其他"
}

public struct CategoryAssignment: Codable, Equatable {
    public let category: ExpenseCategory
    public let strategy: String
    public let confidence: Double

    public init(category: ExpenseCategory, strategy: String, confidence: Double) {
        self.category = category
        self.strategy = strategy
        self.confidence = confidence
    }
}

public struct Expense: Codable, Equatable {
    public let id: String
    public let source: SourcePlatform
    public let amount: Double
    public let currency: String
    public let occurredAt: Date
    public let merchantID: String?
    public let orderID: String?
    public let tripID: String?
    public let categoryAssignment: CategoryAssignment?
    public let evidenceRefs: [EvidenceRef]
    public let permissions: PermissionPolicy

    public init(
        id: String,
        source: SourcePlatform,
        amount: Double,
        currency: String,
        occurredAt: Date,
        merchantID: String? = nil,
        orderID: String? = nil,
        tripID: String? = nil,
        categoryAssignment: CategoryAssignment? = nil,
        evidenceRefs: [EvidenceRef] = [],
        permissions: PermissionPolicy = .private
    ) {
        self.id = id
        self.source = source
        self.amount = amount
        self.currency = currency
        self.occurredAt = occurredAt
        self.merchantID = merchantID
        self.orderID = orderID
        self.tripID = tripID
        self.categoryAssignment = categoryAssignment
        self.evidenceRefs = evidenceRefs
        self.permissions = permissions
    }
}

public struct ContentItem: Codable, Equatable {
    public let id: String
    public let source: SourcePlatform
    public let title: String
    public let creatorName: String?
    public let permalink: String?
    public let evidenceRefs: [EvidenceRef]
    public let permissions: PermissionPolicy

    public init(
        id: String,
        source: SourcePlatform,
        title: String,
        creatorName: String? = nil,
        permalink: String? = nil,
        evidenceRefs: [EvidenceRef] = [],
        permissions: PermissionPolicy = .private
    ) {
        self.id = id
        self.source = source
        self.title = title
        self.creatorName = creatorName
        self.permalink = permalink
        self.evidenceRefs = evidenceRefs
        self.permissions = permissions
    }
}

public struct MetricSnapshot: Codable, Equatable {
    public let id: String
    public let contentItemID: String
    public let capturedAt: Date
    public let likeCount: Int
    public let commentCount: Int?
    public let shareCount: Int?
    public let evidenceRefs: [EvidenceRef]

    public init(
        id: String,
        contentItemID: String,
        capturedAt: Date,
        likeCount: Int,
        commentCount: Int? = nil,
        shareCount: Int? = nil,
        evidenceRefs: [EvidenceRef] = []
    ) {
        self.id = id
        self.contentItemID = contentItemID
        self.capturedAt = capturedAt
        self.likeCount = likeCount
        self.commentCount = commentCount
        self.shareCount = shareCount
        self.evidenceRefs = evidenceRefs
    }
}

public struct CollectionEvent: Codable, Equatable {
    public let id: String
    public let contentItemID: String
    public let source: SourcePlatform
    public let collectedAt: Date
    public let metricSnapshotID: String?
    public let evidenceRefs: [EvidenceRef]
    public let permissions: PermissionPolicy

    public init(
        id: String,
        contentItemID: String,
        source: SourcePlatform,
        collectedAt: Date,
        metricSnapshotID: String? = nil,
        evidenceRefs: [EvidenceRef] = [],
        permissions: PermissionPolicy = .private
    ) {
        self.id = id
        self.contentItemID = contentItemID
        self.source = source
        self.collectedAt = collectedAt
        self.metricSnapshotID = metricSnapshotID
        self.evidenceRefs = evidenceRefs
        self.permissions = permissions
    }
}
