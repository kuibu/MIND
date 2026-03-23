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
    case ack
    case resumeSession
}

public struct StreamMessage: Codable, Equatable {
    public let kind: StreamMessageKind
    public let sentAt: Date
    public let messageID: String?
    public let sessionID: String?
    public let deviceID: String?
    public let deviceName: String?
    public let platformHint: SourcePlatform?
    public let frameID: String?
    public let ackMessageID: String?
    public let ackSequence: Int?
    public let resumeFromSequence: Int?
    public let note: String?
    public let imageBase64: String?
    public let chunkSequence: Int?
    public let width: Int?
    public let height: Int?

    public init(
        kind: StreamMessageKind,
        sentAt: Date = Date(),
        messageID: String? = nil,
        sessionID: String? = nil,
        deviceID: String? = nil,
        deviceName: String? = nil,
        platformHint: SourcePlatform? = nil,
        frameID: String? = nil,
        ackMessageID: String? = nil,
        ackSequence: Int? = nil,
        resumeFromSequence: Int? = nil,
        note: String? = nil,
        imageBase64: String? = nil,
        chunkSequence: Int? = nil,
        width: Int? = nil,
        height: Int? = nil
    ) {
        self.kind = kind
        self.sentAt = sentAt
        self.messageID = messageID
        self.sessionID = sessionID
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.platformHint = platformHint
        self.frameID = frameID
        self.ackMessageID = ackMessageID
        self.ackSequence = ackSequence
        self.resumeFromSequence = resumeFromSequence
        self.note = note
        self.imageBase64 = imageBase64
        self.chunkSequence = chunkSequence
        self.width = width
        self.height = height
    }

    public func assigning(messageID: String? = nil, sentAt: Date? = nil) -> StreamMessage {
        StreamMessage(
            kind: kind,
            sentAt: sentAt ?? self.sentAt,
            messageID: messageID ?? self.messageID,
            sessionID: sessionID,
            deviceID: deviceID,
            deviceName: deviceName,
            platformHint: platformHint,
            frameID: frameID,
            ackMessageID: ackMessageID,
            ackSequence: ackSequence,
            resumeFromSequence: resumeFromSequence,
            note: note,
            imageBase64: imageBase64,
            chunkSequence: chunkSequence,
            width: width,
            height: height
        )
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
