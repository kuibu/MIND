import Foundation
import MINDSchemas
import MINDServices

public struct AttachmentSearchResult: Equatable {
    public let attachmentID: String
    public let fileName: String
    public let conversationID: String
    public let conversationTitle: String
    public let senderName: String
    public let sentAt: Date
    public let localPath: String?
    public let blobID: String?
    public let evidenceRefs: [EvidenceRef]
    public let relevanceScore: Double

    public init(
        attachmentID: String,
        fileName: String,
        conversationID: String,
        conversationTitle: String,
        senderName: String,
        sentAt: Date,
        localPath: String?,
        blobID: String?,
        evidenceRefs: [EvidenceRef],
        relevanceScore: Double
    ) {
        self.attachmentID = attachmentID
        self.fileName = fileName
        self.conversationID = conversationID
        self.conversationTitle = conversationTitle
        self.senderName = senderName
        self.sentAt = sentAt
        self.localPath = localPath
        self.blobID = blobID
        self.evidenceRefs = evidenceRefs
        self.relevanceScore = relevanceScore
    }
}

public final class AttachmentSearchPipeline {
    private let repository: InMemoryMINDRepository

    public init(repository: InMemoryMINDRepository) {
        self.repository = repository
    }

    public func run(participantName: String, fileNameQuery: String, limit: Int = 10) -> [AttachmentSearchResult] {
        repository.linkedAttachments(participantName: participantName, fileNameQuery: fileNameQuery)
            .map { hit in
                let score = relevanceScore(for: hit, query: fileNameQuery)
                let conversationTitle = hit.conversation?.title ?? participantName
                return AttachmentSearchResult(
                    attachmentID: hit.attachment.id,
                    fileName: hit.attachment.fileName,
                    conversationID: hit.conversation?.id ?? "",
                    conversationTitle: conversationTitle,
                    senderName: hit.sender?.displayName ?? "unknown",
                    sentAt: hit.message?.sentAt ?? .distantPast,
                    localPath: hit.fileAsset?.localPath,
                    blobID: hit.fileAsset?.blobID,
                    evidenceRefs: hit.attachment.evidenceRefs + (hit.message?.evidenceRefs ?? []),
                    relevanceScore: score
                )
            }
            .sorted {
                if $0.relevanceScore == $1.relevanceScore {
                    return $0.sentAt > $1.sentAt
                }
                return $0.relevanceScore > $1.relevanceScore
            }
            .prefix(limit)
            .map { $0 }
    }

    private func relevanceScore(for hit: LinkedAttachment, query: String) -> Double {
        let normalizedQuery = normalize(query)
        let candidate = normalize(hit.attachment.fileName)
        let asset = normalize(hit.fileAsset?.canonicalName ?? "")
        let message = normalize(hit.message?.text ?? "")

        if candidate == normalizedQuery || asset == normalizedQuery {
            return 1.0
        }
        if candidate.contains(normalizedQuery) || asset.contains(normalizedQuery) {
            return 0.9
        }
        if message.contains(normalizedQuery) {
            return 0.7
        }
        return 0.4
    }

    private func normalize(_ input: String) -> String {
        input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
