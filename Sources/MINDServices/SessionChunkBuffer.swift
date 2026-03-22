import Foundation
import MINDProtocol

public struct SessionWindow: Equatable {
    public let sessionID: CaptureSessionID
    public let chunks: [CaptureChunkDescriptor]

    public init(sessionID: CaptureSessionID, chunks: [CaptureChunkDescriptor]) {
        self.sessionID = sessionID
        self.chunks = chunks
    }
}

public final class SessionChunkBuffer {
    private var buffers: [CaptureSessionID: [CaptureChunkDescriptor]]

    public init() {
        self.buffers = [:]
    }

    public func append(_ chunk: CaptureChunkDescriptor) {
        var existing = buffers[chunk.sessionID, default: []]
        existing.append(chunk)
        existing.sort { $0.sequenceNumber < $1.sequenceNumber }
        buffers[chunk.sessionID] = existing
    }

    public func chunks(for sessionID: CaptureSessionID) -> [CaptureChunkDescriptor] {
        buffers[sessionID] ?? []
    }

    public func drain(sessionID: CaptureSessionID) -> SessionWindow? {
        guard let chunks = buffers.removeValue(forKey: sessionID) else {
            return nil
        }
        return SessionWindow(sessionID: sessionID, chunks: chunks)
    }
}

public protocol FrameSampler {
    func sample(from keyframes: [Keyframe]) -> [Keyframe]
}

public struct IntervalFrameSampler: FrameSampler {
    public let every: Int

    public init(every: Int = 3) {
        self.every = max(1, every)
    }

    public func sample(from keyframes: [Keyframe]) -> [Keyframe] {
        keyframes.enumerated().compactMap { index, keyframe in
            if index == 0 || index % every == 0 {
                return keyframe
            }
            return nil
        }
    }
}
