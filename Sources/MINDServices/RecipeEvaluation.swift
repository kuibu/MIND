import Foundation
import MINDProtocol
import MINDRecipes

public struct LowConfidenceReviewItem: Codable, Equatable, Identifiable {
    public let id: String
    public let sessionID: CaptureSessionID
    public let frameID: FrameID
    public let recipeID: String
    public let recipeVersion: Int
    public let confidence: Double
    public let predictedFields: [String: String]
    public let missingRequiredFields: [String]
    public let evidenceLocators: [String]

    public init(
        id: String,
        sessionID: CaptureSessionID,
        frameID: FrameID,
        recipeID: String,
        recipeVersion: Int,
        confidence: Double,
        predictedFields: [String: String],
        missingRequiredFields: [String],
        evidenceLocators: [String]
    ) {
        self.id = id
        self.sessionID = sessionID
        self.frameID = frameID
        self.recipeID = recipeID
        self.recipeVersion = recipeVersion
        self.confidence = confidence
        self.predictedFields = predictedFields
        self.missingRequiredFields = missingRequiredFields
        self.evidenceLocators = evidenceLocators
    }
}

public struct RecipeReplaySample: Codable, Equatable, Identifiable {
    public let id: String
    public let recipeID: String
    public let recipeVersion: Int
    public let frame: FrameContext
    public let expectedFields: [String: String]

    public init(
        id: String,
        recipeID: String,
        recipeVersion: Int,
        frame: FrameContext,
        expectedFields: [String: String]
    ) {
        self.id = id
        self.recipeID = recipeID
        self.recipeVersion = recipeVersion
        self.frame = frame
        self.expectedFields = expectedFields
    }
}

public struct RecipeFieldEvaluation: Codable, Equatable, Identifiable {
    public let id: String
    public let fieldName: String
    public let expectedValue: String?
    public let predictedValue: String?
    public let matched: Bool

    public init(fieldName: String, expectedValue: String?, predictedValue: String?) {
        self.id = fieldName
        self.fieldName = fieldName
        self.expectedValue = expectedValue
        self.predictedValue = predictedValue
        self.matched = RecipeEvaluationNormalizer.normalize(expectedValue) == RecipeEvaluationNormalizer.normalize(predictedValue)
    }
}

public struct RecipeSampleEvaluation: Codable, Equatable, Identifiable {
    public let id: String
    public let recipeID: String
    public let recipeVersion: Int
    public let batchConfidence: Double
    public let fieldEvaluations: [RecipeFieldEvaluation]

    public init(
        id: String,
        recipeID: String,
        recipeVersion: Int,
        batchConfidence: Double,
        fieldEvaluations: [RecipeFieldEvaluation]
    ) {
        self.id = id
        self.recipeID = recipeID
        self.recipeVersion = recipeVersion
        self.batchConfidence = batchConfidence
        self.fieldEvaluations = fieldEvaluations
    }
}

public struct RecipeFieldAccuracySummary: Codable, Equatable, Identifiable {
    public let id: String
    public let fieldName: String
    public let matchedCount: Int
    public let totalCount: Int

    public init(fieldName: String, matchedCount: Int, totalCount: Int) {
        self.id = fieldName
        self.fieldName = fieldName
        self.matchedCount = matchedCount
        self.totalCount = totalCount
    }

    public var accuracy: Double {
        guard totalCount > 0 else { return 0 }
        return Double(matchedCount) / Double(totalCount)
    }
}

public struct RecipeEvaluationReport: Codable, Equatable {
    public let recipeID: String
    public let recipeVersion: Int
    public let sampleCount: Int
    public let fieldSummaries: [RecipeFieldAccuracySummary]
    public let sampleEvaluations: [RecipeSampleEvaluation]

    public init(
        recipeID: String,
        recipeVersion: Int,
        sampleCount: Int,
        fieldSummaries: [RecipeFieldAccuracySummary],
        sampleEvaluations: [RecipeSampleEvaluation]
    ) {
        self.recipeID = recipeID
        self.recipeVersion = recipeVersion
        self.sampleCount = sampleCount
        self.fieldSummaries = fieldSummaries
        self.sampleEvaluations = sampleEvaluations
    }
}

public final class RecipeEvaluationHarness {
    private let extractor: VisionExtractor
    private let recipeRegistry: RecipeRegistry

    public init(extractor: VisionExtractor, recipeRegistry: RecipeRegistry) {
        self.extractor = extractor
        self.recipeRegistry = recipeRegistry
    }

    public func evaluate(samples: [RecipeReplaySample]) throws -> [RecipeEvaluationReport] {
        let grouped = Dictionary(grouping: samples, by: { "\($0.recipeID)#\($0.recipeVersion)" })
        return try grouped.values.map { samples in
            guard let first = samples.first, let recipe = recipeRegistry.recipe(id: first.recipeID) else {
                throw NSError(domain: "RecipeEvaluationHarness", code: 1, userInfo: [NSLocalizedDescriptionKey: "Recipe not found for evaluation sample"])
            }

            let sampleEvaluations = try samples.map { sample -> RecipeSampleEvaluation in
                let batch = try extractor.extract(frame: sample.frame, using: recipe)
                let fieldNames = Set(recipe.extractionSchema.fields.map(\.name)).union(sample.expectedFields.keys)
                let fields = fieldNames
                    .sorted()
                    .map { fieldName in
                        RecipeFieldEvaluation(
                            fieldName: fieldName,
                            expectedValue: sample.expectedFields[fieldName],
                            predictedValue: batch.extractedFields[fieldName]
                        )
                    }

                return RecipeSampleEvaluation(
                    id: sample.id,
                    recipeID: sample.recipeID,
                    recipeVersion: sample.recipeVersion,
                    batchConfidence: batch.confidence,
                    fieldEvaluations: fields
                )
            }

            let groupedFields = Dictionary(grouping: sampleEvaluations.flatMap(\.fieldEvaluations), by: \.fieldName)
            let summaries = groupedFields.keys.sorted().map { fieldName -> RecipeFieldAccuracySummary in
                let evaluations = groupedFields[fieldName] ?? []
                return RecipeFieldAccuracySummary(
                    fieldName: fieldName,
                    matchedCount: evaluations.filter(\.matched).count,
                    totalCount: evaluations.count
                )
            }

            return RecipeEvaluationReport(
                recipeID: first.recipeID,
                recipeVersion: first.recipeVersion,
                sampleCount: samples.count,
                fieldSummaries: summaries,
                sampleEvaluations: sampleEvaluations
            )
        }
        .sorted { $0.recipeID < $1.recipeID }
    }
}

private enum RecipeEvaluationNormalizer {
    static func normalize(_ raw: String?) -> String? {
        raw?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
