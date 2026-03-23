import Foundation

public enum BonjourServiceDescriptor {
    public static let type = "_mindcap._tcp"
    public static let domain = "local."
}

public enum StreamMessageKind: String, Codable {
    case hello
    case startSession
    case keyframe
    case stopSession
    case heartbeat
}

public struct StreamMessage: Codable, Equatable {
    public let kind: StreamMessageKind
    public let sentAt: Date
    public let sessionID: String?
    public let deviceID: String?
    public let deviceName: String?
    public let platformHint: SourcePlatform?
    public let frameID: String?
    public let note: String?
    public let imageBase64: String?
    public let chunkSequence: Int?
    public let width: Int?
    public let height: Int?

    public init(
        kind: StreamMessageKind,
        sentAt: Date = Date(),
        sessionID: String? = nil,
        deviceID: String? = nil,
        deviceName: String? = nil,
        platformHint: SourcePlatform? = nil,
        frameID: String? = nil,
        note: String? = nil,
        imageBase64: String? = nil,
        chunkSequence: Int? = nil,
        width: Int? = nil,
        height: Int? = nil
    ) {
        self.kind = kind
        self.sentAt = sentAt
        self.sessionID = sessionID
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.platformHint = platformHint
        self.frameID = frameID
        self.note = note
        self.imageBase64 = imageBase64
        self.chunkSequence = chunkSequence
        self.width = width
        self.height = height
    }
}

public enum StreamMessageCodec {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    public static func encodeLine(_ message: StreamMessage) throws -> Data {
        let payload = try encoder.encode(message)
        var line = payload
        line.append(0x0A)
        return line
    }

    public static func decodeLine(_ data: Data) throws -> StreamMessage {
        try decoder.decode(StreamMessage.self, from: data)
    }
}
