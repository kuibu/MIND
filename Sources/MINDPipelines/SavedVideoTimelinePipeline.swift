import Foundation
import MINDProtocol
import MINDSchemas
import MINDServices

public struct SavedVideoTimelineEntry: Equatable {
    public let platform: SourcePlatform
    public let title: String
    public let collectedAt: Date
    public let likeCountAtCollection: Int?
    public let permalink: String?
    public let evidenceRefs: [EvidenceRef]

    public init(
        platform: SourcePlatform,
        title: String,
        collectedAt: Date,
        likeCountAtCollection: Int?,
        permalink: String?,
        evidenceRefs: [EvidenceRef]
    ) {
        self.platform = platform
        self.title = title
        self.collectedAt = collectedAt
        self.likeCountAtCollection = likeCountAtCollection
        self.permalink = permalink
        self.evidenceRefs = evidenceRefs
    }
}

public final class SavedVideoTimelinePipeline {
    private let repository: InMemoryMINDRepository

    public init(repository: InMemoryMINDRepository) {
        self.repository = repository
    }

    public func run(interval: DateInterval, sources: Set<SourcePlatform>) -> [SavedVideoTimelineEntry] {
        repository.linkedCollections(in: interval, from: sources)
            .map { linked in
                SavedVideoTimelineEntry(
                    platform: linked.event.source,
                    title: linked.contentItem?.title ?? "unknown",
                    collectedAt: linked.event.collectedAt,
                    likeCountAtCollection: linked.metricSnapshot?.likeCount,
                    permalink: linked.contentItem?.permalink,
                    evidenceRefs: linked.event.evidenceRefs + (linked.metricSnapshot?.evidenceRefs ?? [])
                )
            }
            .sorted { $0.collectedAt < $1.collectedAt }
    }
}
