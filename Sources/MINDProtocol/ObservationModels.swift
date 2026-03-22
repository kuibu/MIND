import Foundation

public enum UIEventKind: String, Codable {
    case openConversation
    case scroll
    case tapAttachment
    case openFile
    case favoriteContent
    case sendMessage
    case unknown
}

public struct UITextObservation: Codable, Equatable {
    public let id: String
    public let frameID: FrameID
    public let observedAt: Date
    public let text: String
    public let role: String?
    public let confidence: Double

    public init(
        id: String,
        frameID: FrameID,
        observedAt: Date,
        text: String,
        role: String? = nil,
        confidence: Double
    ) {
        self.id = id
        self.frameID = frameID
        self.observedAt = observedAt
        self.text = text
        self.role = role
        self.confidence = confidence
    }
}

public struct UIObjectObservation: Codable, Equatable {
    public let id: String
    public let frameID: FrameID
    public let observedAt: Date
    public let kind: String
    public let label: String?
    public let confidence: Double

    public init(
        id: String,
        frameID: FrameID,
        observedAt: Date,
        kind: String,
        label: String? = nil,
        confidence: Double
    ) {
        self.id = id
        self.frameID = frameID
        self.observedAt = observedAt
        self.kind = kind
        self.label = label
        self.confidence = confidence
    }
}

public struct UIEventObservation: Codable, Equatable {
    public let id: String
    public let frameID: FrameID
    public let observedAt: Date
    public let kind: UIEventKind
    public let targetLabel: String?
    public let confidence: Double

    public init(
        id: String,
        frameID: FrameID,
        observedAt: Date,
        kind: UIEventKind,
        targetLabel: String? = nil,
        confidence: Double
    ) {
        self.id = id
        self.frameID = frameID
        self.observedAt = observedAt
        self.kind = kind
        self.targetLabel = targetLabel
        self.confidence = confidence
    }
}

public struct FileReferenceObservation: Codable, Equatable {
    public let id: String
    public let frameID: FrameID
    public let observedAt: Date
    public let fileName: String
    public let resolvedPath: String?
    public let mimeType: String?
    public let confidence: Double

    public init(
        id: String,
        frameID: FrameID,
        observedAt: Date,
        fileName: String,
        resolvedPath: String? = nil,
        mimeType: String? = nil,
        confidence: Double
    ) {
        self.id = id
        self.frameID = frameID
        self.observedAt = observedAt
        self.fileName = fileName
        self.resolvedPath = resolvedPath
        self.mimeType = mimeType
        self.confidence = confidence
    }
}

public struct ExtractionField: Codable, Equatable {
    public let name: String
    public let description: String
    public let required: Bool

    public init(name: String, description: String, required: Bool = true) {
        self.name = name
        self.description = description
        self.required = required
    }
}

public struct ExtractionSchemaDescriptor: Codable, Equatable {
    public let resourceType: String
    public let fields: [ExtractionField]

    public init(resourceType: String, fields: [ExtractionField]) {
        self.resourceType = resourceType
        self.fields = fields
    }
}

public enum EvidenceRetentionPolicy: String, Codable {
    case none
    case lowConfidenceOnly
    case always
}

public struct GUIRecipe: Codable, Equatable {
    public let id: String
    public let platform: SourcePlatform
    public let pageKind: String
    public let description: String
    public let prompt: String
    public let extractionSchema: ExtractionSchemaDescriptor
    public let retentionPolicy: EvidenceRetentionPolicy
    public let confidenceThreshold: Double

    public init(
        id: String,
        platform: SourcePlatform,
        pageKind: String,
        description: String,
        prompt: String,
        extractionSchema: ExtractionSchemaDescriptor,
        retentionPolicy: EvidenceRetentionPolicy,
        confidenceThreshold: Double
    ) {
        self.id = id
        self.platform = platform
        self.pageKind = pageKind
        self.description = description
        self.prompt = prompt
        self.extractionSchema = extractionSchema
        self.retentionPolicy = retentionPolicy
        self.confidenceThreshold = confidenceThreshold
    }
}

public struct ObservationBatch: Codable, Equatable {
    public let sessionID: CaptureSessionID
    public let frameID: FrameID
    public let platform: SourcePlatform
    public let pageKind: String
    public let recipeID: String
    public let capturedAt: Date
    public let texts: [UITextObservation]
    public let objects: [UIObjectObservation]
    public let events: [UIEventObservation]
    public let fileReferences: [FileReferenceObservation]
    public let confidence: Double

    public init(
        sessionID: CaptureSessionID,
        frameID: FrameID,
        platform: SourcePlatform,
        pageKind: String,
        recipeID: String,
        capturedAt: Date,
        texts: [UITextObservation] = [],
        objects: [UIObjectObservation] = [],
        events: [UIEventObservation] = [],
        fileReferences: [FileReferenceObservation] = [],
        confidence: Double
    ) {
        self.sessionID = sessionID
        self.frameID = frameID
        self.platform = platform
        self.pageKind = pageKind
        self.recipeID = recipeID
        self.capturedAt = capturedAt
        self.texts = texts
        self.objects = objects
        self.events = events
        self.fileReferences = fileReferences
        self.confidence = confidence
    }
}
