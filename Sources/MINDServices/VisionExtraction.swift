import Foundation
import MINDProtocol

public struct MiniCPMRuntimeDescriptor: Equatable {
    public let modelID: String
    public let runsLocallyOnMac: Bool
    public let notes: String

    public init(
        modelID: String = "MiniCPM-o-4.5",
        runsLocallyOnMac: Bool = true,
        notes: String = "Stub descriptor for the local Mac perception engine."
    ) {
        self.modelID = modelID
        self.runsLocallyOnMac = runsLocallyOnMac
        self.notes = notes
    }
}

public protocol VisionExtractor {
    func extract(frame: FrameContext, using recipe: GUIRecipe) throws -> ObservationBatch
}

public enum VisionExtractorError: Error {
    case missingStub(frameID: FrameID, recipeID: String)
}

public final class StubVisionExtractor: VisionExtractor {
    private var outputs: [String: ObservationBatch]

    public init(outputs: [String: ObservationBatch] = [:]) {
        self.outputs = outputs
    }

    public func register(_ batch: ObservationBatch, for frameID: FrameID, recipeID: String) {
        outputs[key(frameID: frameID, recipeID: recipeID)] = batch
    }

    public func extract(frame: FrameContext, using recipe: GUIRecipe) throws -> ObservationBatch {
        let lookupKey = key(frameID: frame.keyframe.id, recipeID: recipe.id)
        guard let batch = outputs[lookupKey] else {
            throw VisionExtractorError.missingStub(frameID: frame.keyframe.id, recipeID: recipe.id)
        }
        return batch
    }

    private func key(frameID: FrameID, recipeID: String) -> String {
        frameID.rawValue + "#" + recipeID
    }
}

public final class HeuristicVisionExtractor: VisionExtractor {
    public init() {}

    public func extract(frame: FrameContext, using recipe: GUIRecipe) throws -> ObservationBatch {
        let capturedAt = frame.keyframe.capturedAt
        let frameID = frame.keyframe.id
        let transcript = frame.keyframe.transcriptHint ?? frame.keyframe.ocrText.joined(separator: "\n")
        let fields = parseStructuredHint(transcript)

        var texts: [UITextObservation] = []
        var events: [UIEventObservation] = []
        var fileReferences: [FileReferenceObservation] = []

        switch recipe.platform {
        case .wechat:
            if let participant = fields["participant"] {
                texts.append(
                    UITextObservation(
                        id: identifier(prefix: "text", frameID: frameID, suffix: "participant"),
                        frameID: frameID,
                        observedAt: capturedAt,
                        text: participant,
                        role: "participant",
                        confidence: 0.97
                    )
                )
            }

            if let message = fields["message"] {
                texts.append(
                    UITextObservation(
                        id: identifier(prefix: "text", frameID: frameID, suffix: "message"),
                        frameID: frameID,
                        observedAt: capturedAt,
                        text: message,
                        role: "message",
                        confidence: 0.94
                    )
                )
            }

            if let fileName = fields["file"] {
                fileReferences.append(
                    FileReferenceObservation(
                        id: identifier(prefix: "file", frameID: frameID, suffix: sanitize(fileName)),
                        frameID: frameID,
                        observedAt: capturedAt,
                        fileName: fileName,
                        resolvedPath: fields["path"],
                        mimeType: mimeType(for: fileName),
                        confidence: 0.95
                    )
                )
                events.append(
                    UIEventObservation(
                        id: identifier(prefix: "event", frameID: frameID, suffix: "tapAttachment"),
                        frameID: frameID,
                        observedAt: capturedAt,
                        kind: .tapAttachment,
                        targetLabel: fileName,
                        confidence: 0.9
                    )
                )
            }

        case .alipay, .meituan, .didi:
            for role in ["merchant", "amount", "currency", "occurred_at", "order_title", "route"] {
                if let value = fields[role] {
                    texts.append(
                        UITextObservation(
                            id: identifier(prefix: "text", frameID: frameID, suffix: role),
                            frameID: frameID,
                            observedAt: capturedAt,
                            text: value,
                            role: role,
                            confidence: role == "amount" ? 0.96 : 0.9
                        )
                    )
                }
            }

        case .douyin, .kuaishou, .xiaohongshu, .channels:
            for role in ["title", "collected_at", "like_count", "permalink"] {
                if let value = fields[role] {
                    texts.append(
                        UITextObservation(
                            id: identifier(prefix: "text", frameID: frameID, suffix: role),
                            frameID: frameID,
                            observedAt: capturedAt,
                            text: value,
                            role: role,
                            confidence: role == "title" ? 0.95 : 0.88
                        )
                    )
                }
            }
            events.append(
                UIEventObservation(
                    id: identifier(prefix: "event", frameID: frameID, suffix: "favoriteContent"),
                    frameID: frameID,
                    observedAt: capturedAt,
                    kind: .favoriteContent,
                    targetLabel: fields["title"],
                    confidence: 0.89
                )
            )

        case .manual:
            if !transcript.isEmpty {
                texts.append(
                    UITextObservation(
                        id: identifier(prefix: "text", frameID: frameID, suffix: "manual"),
                        frameID: frameID,
                        observedAt: capturedAt,
                        text: transcript,
                        role: "raw_hint",
                        confidence: 0.6
                    )
                )
            }
        }

        return ObservationBatch(
            sessionID: frame.keyframe.sessionID,
            frameID: frameID,
            platform: recipe.platform,
            pageKind: recipe.pageKind,
            recipeID: recipe.id,
            capturedAt: capturedAt,
            texts: texts,
            events: events,
            fileReferences: fileReferences,
            confidence: confidence(for: texts, files: fileReferences)
        )
    }

    private func parseStructuredHint(_ hint: String) -> [String: String] {
        hint
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> (String, String)? in
                let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { return nil }
                return (parts[0].trimmingCharacters(in: .whitespacesAndNewlines), parts[1].trimmingCharacters(in: .whitespacesAndNewlines))
            }
            .reduce(into: [String: String]()) { partialResult, item in
                partialResult[item.0] = item.1
            }
    }

    private func confidence(for texts: [UITextObservation], files: [FileReferenceObservation]) -> Double {
        if !files.isEmpty {
            return 0.94
        }
        if !texts.isEmpty {
            return 0.9
        }
        return 0.55
    }

    private func identifier(prefix: String, frameID: FrameID, suffix: String) -> String {
        prefix + ":" + frameID.rawValue + ":" + suffix
    }

    private func sanitize(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
    }

    private func mimeType(for fileName: String) -> String? {
        if fileName.lowercased().hasSuffix(".pdf") {
            return "application/pdf"
        }
        return nil
    }
}
