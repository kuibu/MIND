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
