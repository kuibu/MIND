import Foundation
import MINDProtocol

public struct MergedSessionObservations: Equatable {
    public let sessionID: CaptureSessionID
    public let platform: SourcePlatform
    public let textObservations: [UITextObservation]
    public let objectObservations: [UIObjectObservation]
    public let eventObservations: [UIEventObservation]
    public let fileReferences: [FileReferenceObservation]
    public let evidenceFrameIDs: [FrameID]

    public init(
        sessionID: CaptureSessionID,
        platform: SourcePlatform,
        textObservations: [UITextObservation],
        objectObservations: [UIObjectObservation],
        eventObservations: [UIEventObservation],
        fileReferences: [FileReferenceObservation],
        evidenceFrameIDs: [FrameID]
    ) {
        self.sessionID = sessionID
        self.platform = platform
        self.textObservations = textObservations
        self.objectObservations = objectObservations
        self.eventObservations = eventObservations
        self.fileReferences = fileReferences
        self.evidenceFrameIDs = evidenceFrameIDs
    }
}

public final class SessionMerger {
    public init() {}

    public func merge(_ batches: [ObservationBatch]) -> MergedSessionObservations? {
        guard let first = batches.first else {
            return nil
        }

        let texts = dedupeTexts(batches.flatMap(\.texts))
        let objects = dedupeObjects(batches.flatMap(\.objects))
        let events = batches.flatMap(\.events).sorted { $0.observedAt < $1.observedAt }
        let fileReferences = dedupeFiles(batches.flatMap(\.fileReferences))
        let evidenceFrames = Array(Set(batches.map(\.frameID))).sorted { $0.rawValue < $1.rawValue }

        return MergedSessionObservations(
            sessionID: first.sessionID,
            platform: first.platform,
            textObservations: texts,
            objectObservations: objects,
            eventObservations: events,
            fileReferences: fileReferences,
            evidenceFrameIDs: evidenceFrames
        )
    }

    private func dedupeTexts(_ items: [UITextObservation]) -> [UITextObservation] {
        var seen: Set<String> = []
        var output: [UITextObservation] = []
        for item in items.sorted(by: { $0.observedAt < $1.observedAt }) {
            let key = normalize(item.text) + "|" + (item.role ?? "")
            if seen.insert(key).inserted {
                output.append(item)
            }
        }
        return output
    }

    private func dedupeObjects(_ items: [UIObjectObservation]) -> [UIObjectObservation] {
        var seen: Set<String> = []
        var output: [UIObjectObservation] = []
        for item in items.sorted(by: { $0.observedAt < $1.observedAt }) {
            let key = normalize(item.kind) + "|" + normalize(item.label ?? "")
            if seen.insert(key).inserted {
                output.append(item)
            }
        }
        return output
    }

    private func dedupeFiles(_ items: [FileReferenceObservation]) -> [FileReferenceObservation] {
        var seen: Set<String> = []
        var output: [FileReferenceObservation] = []
        for item in items.sorted(by: { $0.observedAt < $1.observedAt }) {
            let key = normalize(item.fileName) + "|" + normalize(item.resolvedPath ?? "")
            if seen.insert(key).inserted {
                output.append(item)
            }
        }
        return output
    }

    private func normalize(_ input: String) -> String {
        input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
