import Foundation

public enum SourcePlatform: String, Codable, CaseIterable {
    case alipay
    case meituan
    case didi
    case wechat
    case douyin
    case kuaishou
    case xiaohongshu
    case channels
    case manual
}

public enum CaptureDeviceKind: String, Codable {
    case iphone
    case mac
}

public struct CaptureSessionID: RawRepresentable, Codable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.rawValue = value
    }
}

public struct FrameID: RawRepresentable, Codable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.rawValue = value
    }
}

public struct CaptureSessionManifest: Codable, Equatable {
    public let sessionID: CaptureSessionID
    public let deviceID: String
    public let deviceKind: CaptureDeviceKind
    public let startedAt: Date
    public let platformHint: SourcePlatform?
    public let tags: [String: String]

    public init(
        sessionID: CaptureSessionID,
        deviceID: String,
        deviceKind: CaptureDeviceKind,
        startedAt: Date,
        platformHint: SourcePlatform? = nil,
        tags: [String: String] = [:]
    ) {
        self.sessionID = sessionID
        self.deviceID = deviceID
        self.deviceKind = deviceKind
        self.startedAt = startedAt
        self.platformHint = platformHint
        self.tags = tags
    }
}

public struct CaptureChunkDescriptor: Codable, Equatable {
    public let sessionID: CaptureSessionID
    public let sequenceNumber: Int
    public let startedAt: Date
    public let durationMillis: Int
    public let byteCount: Int
    public let temporaryPath: String

    public init(
        sessionID: CaptureSessionID,
        sequenceNumber: Int,
        startedAt: Date,
        durationMillis: Int,
        byteCount: Int,
        temporaryPath: String
    ) {
        self.sessionID = sessionID
        self.sequenceNumber = sequenceNumber
        self.startedAt = startedAt
        self.durationMillis = durationMillis
        self.byteCount = byteCount
        self.temporaryPath = temporaryPath
    }
}

public struct Keyframe: Codable, Equatable {
    public let id: FrameID
    public let sessionID: CaptureSessionID
    public let ordinal: Int
    public let capturedAt: Date
    public let sourcePlatform: SourcePlatform
    public let imagePath: String
    public let transcriptHint: String?
    public let ocrText: [String]

    public init(
        id: FrameID,
        sessionID: CaptureSessionID,
        ordinal: Int,
        capturedAt: Date,
        sourcePlatform: SourcePlatform,
        imagePath: String,
        transcriptHint: String? = nil,
        ocrText: [String] = []
    ) {
        self.id = id
        self.sessionID = sessionID
        self.ordinal = ordinal
        self.capturedAt = capturedAt
        self.sourcePlatform = sourcePlatform
        self.imagePath = imagePath
        self.transcriptHint = transcriptHint
        self.ocrText = ocrText
    }
}

public struct FrameContext: Codable, Equatable {
    public let keyframe: Keyframe
    public let neighboringText: [String]
    public let sessionMetadata: [String: String]

    public init(
        keyframe: Keyframe,
        neighboringText: [String] = [],
        sessionMetadata: [String: String] = [:]
    ) {
        self.keyframe = keyframe
        self.neighboringText = neighboringText
        self.sessionMetadata = sessionMetadata
    }
}
