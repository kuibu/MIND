import Foundation
import Network
import MINDProtocol

public final class ReliableStreamClient {
    public struct ResumeContext: Equatable {
        public let sessionID: String
        public let deviceID: String
        public let deviceName: String
        public let platformHint: SourcePlatform?
        public let note: String?

        public init(
            sessionID: String,
            deviceID: String,
            deviceName: String,
            platformHint: SourcePlatform?,
            note: String? = nil
        ) {
            self.sessionID = sessionID
            self.deviceID = deviceID
            self.deviceName = deviceName
            self.platformHint = platformHint
            self.note = note
        }
    }

    private enum EndpointTarget {
        case endpoint(NWEndpoint)
        case relay(CaptureRelayConfiguration)

        func makeEndpoint() -> NWEndpoint {
            switch self {
            case .endpoint(let endpoint):
                return endpoint
            case .relay(let relay):
                return .service(
                    name: relay.serviceName,
                    type: BonjourServiceDescriptor.type,
                    domain: relay.serviceDomain,
                    interface: nil
                )
            }
        }
    }

    private struct PendingEnvelope {
        let messageID: String
        let message: StreamMessage
        let data: Data
        let requiresAck: Bool
        var attemptCount: Int
        var lastSentAt: Date?
    }

    public var onStateChange: ((String) -> Void)?
    public var onPendingCountChange: ((Int) -> Void)?
    public var onInboundMessage: ((StreamMessage) -> Void)?

    private let queue: DispatchQueue
    private let reconnectDelay: TimeInterval
    private let resendInterval: TimeInterval
    private let heartbeatInterval: TimeInterval
    private let maxBufferedKeyframes: Int

    private var connection: NWConnection?
    private var endpointTarget: EndpointTarget?
    private var inboundBuffer = Data()
    private var pendingOrder: [String] = []
    private var pendingByID: [String: PendingEnvelope] = [:]
    private var connectionReady = false
    private var reconnectWorkItem: DispatchWorkItem?
    private var drainTimeoutWorkItem: DispatchWorkItem?
    private var resendTimer: DispatchSourceTimer?
    private var heartbeatTimer: DispatchSourceTimer?
    private var resumeContext: ResumeContext?
    private var highestAckSequenceBySession: [String: Int] = [:]
    private var disconnectWhenPendingClears = false

    public init(
        queue: DispatchQueue = DispatchQueue(label: "mind.reliable.stream.client"),
        reconnectDelay: TimeInterval = 1.2,
        resendInterval: TimeInterval = 1.5,
        heartbeatInterval: TimeInterval = 5,
        maxBufferedKeyframes: Int = 12
    ) {
        self.queue = queue
        self.reconnectDelay = reconnectDelay
        self.resendInterval = resendInterval
        self.heartbeatInterval = heartbeatInterval
        self.maxBufferedKeyframes = maxBufferedKeyframes
    }

    public func connect(to endpoint: NWEndpoint) {
        queue.async {
            self.endpointTarget = .endpoint(endpoint)
            self.establishConnection(reason: "connect")
        }
    }

    public func connect(to relay: CaptureRelayConfiguration) {
        queue.async {
            self.endpointTarget = .relay(relay)
            self.establishConnection(reason: "connect")
        }
    }

    public func updateResumeContext(_ context: ResumeContext?) {
        queue.async {
            self.resumeContext = context
            self.restartHeartbeatTimerIfNeeded()
        }
    }

    public func send(_ message: StreamMessage, requiresAck: Bool = true) {
        queue.async {
            let finalized = message.messageID == nil
                ? message.assigning(messageID: UUID().uuidString, sentAt: Date())
                : message.assigning(sentAt: Date())

            guard let messageID = finalized.messageID,
                  let data = try? StreamMessageCodec.encodeLine(finalized) else {
                self.publishState("消息编码失败")
                return
            }

            let envelope = PendingEnvelope(
                messageID: messageID,
                message: finalized,
                data: data,
                requiresAck: requiresAck,
                attemptCount: 0,
                lastSentAt: nil
            )

            if requiresAck {
                self.pendingOrder.append(messageID)
                self.pendingByID[messageID] = envelope
                self.trimPendingKeyframesIfNeeded()
                self.publishPendingCount()
            }

            self.deliver(envelope)
        }
    }

    public func disconnect(after gracePeriod: TimeInterval = 0) {
        queue.async {
            let cancelConnection: () -> Void = { [weak self] in
                self?.finalizeDisconnect()
            }

            if gracePeriod > 0 {
                self.queue.asyncAfter(deadline: .now() + gracePeriod, execute: cancelConnection)
            } else {
                cancelConnection()
            }
        }
    }

    public func disconnectWhenDrained(timeout: TimeInterval = 5) {
        queue.async {
            self.disconnectWhenPendingClears = true
            self.resumeContext = nil
            self.restartHeartbeatTimerIfNeeded()

            if self.pendingByID.isEmpty {
                self.finalizeDisconnect()
                return
            }

            self.scheduleDrainTimeout(timeout: timeout)
            if self.connectionReady == false {
                self.scheduleReconnect()
            }
        }
    }

    private func establishConnection(reason: String) {
        reconnectWorkItem?.cancel()
        teardownConnection()

        guard let endpoint = endpointTarget?.makeEndpoint() else {
            publishState("缺少可连接的目标节点")
            return
        }

        let connection = NWConnection(to: endpoint, using: .tcp)
        self.connection = connection
        publishState(reason == "reconnect" ? "正在重连" : "准备连接")

        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            self.queue.async {
                switch state {
                case .setup:
                    self.publishState("连接初始化中")
                case .waiting(let error):
                    self.connectionReady = false
                    self.publishState("等待中: \(error.localizedDescription)")
                    self.scheduleReconnect()
                case .ready:
                    self.connectionReady = true
                    self.publishState("已连接")
                    self.receiveLoop()
                    self.startResendTimerIfNeeded()
                    self.restartHeartbeatTimerIfNeeded()
                    self.sendResumeIfNeeded()
                    self.flushPending()
                case .failed(let error):
                    self.connectionReady = false
                    self.publishState("连接失败: \(error.localizedDescription)")
                    self.scheduleReconnect()
                case .cancelled:
                    self.connectionReady = false
                    self.publishState("连接已取消")
                default:
                    self.publishState("连接状态更新")
                }
            }
        }

        connection.start(queue: queue)
    }

    private func teardownConnection() {
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        resendTimer?.cancel()
        resendTimer = nil
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
        connectionReady = false
        connection?.cancel()
        connection = nil
        inboundBuffer.removeAll(keepingCapacity: false)
    }

    private func receiveLoop() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 262_144) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            self.queue.async {
                if let data = data, data.isEmpty == false {
                    self.inboundBuffer.append(data)
                    self.processInboundBuffer()
                }

                if isComplete || error != nil {
                    self.connectionReady = false
                    self.publishState(error.map { "连接中断: \($0.localizedDescription)" } ?? "连接已关闭")
                    self.scheduleReconnect()
                    return
                }

                self.receiveLoop()
            }
        }
    }

    private func processInboundBuffer() {
        let newline = Data([0x0A])
        while let range = inboundBuffer.range(of: newline) {
            let line = inboundBuffer.subdata(in: 0..<range.lowerBound)
            inboundBuffer.removeSubrange(0..<range.upperBound)
            guard line.isEmpty == false,
                  let message = try? StreamMessageCodec.decodeLine(line) else {
                continue
            }
            handleInbound(message)
        }
    }

    private func handleInbound(_ message: StreamMessage) {
        if message.kind == .ack {
            if let ackMessageID = message.ackMessageID {
                pendingOrder.removeAll { $0 == ackMessageID }
                pendingByID.removeValue(forKey: ackMessageID)
                publishPendingCount()
                finishDrainIfPossible()
            }
            if let sessionID = message.sessionID, let ackSequence = message.ackSequence {
                highestAckSequenceBySession[sessionID] = max(highestAckSequenceBySession[sessionID] ?? 0, ackSequence)
            }
        } else {
            onInboundMessage?(message)
        }
    }

    private func deliver(_ envelope: PendingEnvelope) {
        guard let connection = connection, connectionReady else {
            scheduleReconnect()
            return
        }

        connection.send(content: envelope.data, completion: .contentProcessed { [weak self] error in
            guard let self = self else { return }
            self.queue.async {
                guard error == nil else {
                    self.connectionReady = false
                    self.publishState("发送失败: \(error!.localizedDescription)")
                    self.scheduleReconnect()
                    return
                }

                if envelope.requiresAck, var stored = self.pendingByID[envelope.messageID] {
                    stored.attemptCount += 1
                    stored.lastSentAt = Date()
                    self.pendingByID[envelope.messageID] = stored
                }
            }
        })
    }

    private func flushPending() {
        for messageID in pendingOrder {
            guard let envelope = pendingByID[messageID] else { continue }
            deliver(envelope)
        }
    }

    private func scheduleReconnect() {
        guard endpointTarget != nil else { return }
        if reconnectWorkItem != nil { return }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.reconnectWorkItem = nil
            self.establishConnection(reason: "reconnect")
        }
        reconnectWorkItem = workItem
        queue.asyncAfter(deadline: .now() + reconnectDelay, execute: workItem)
    }

    private func startResendTimerIfNeeded() {
        guard resendTimer == nil else { return }

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + resendInterval, repeating: resendInterval)
        timer.setEventHandler { [weak self] in
            self?.retryExpiredPending()
        }
        resendTimer = timer
        timer.resume()
    }

    private func restartHeartbeatTimerIfNeeded() {
        heartbeatTimer?.cancel()
        heartbeatTimer = nil

        guard let resumeContext = resumeContext else { return }

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + heartbeatInterval, repeating: heartbeatInterval)
        timer.setEventHandler { [weak self] in
            self?.send(
                StreamMessage(
                    kind: .heartbeat,
                    sessionID: resumeContext.sessionID,
                    deviceID: resumeContext.deviceID,
                    deviceName: resumeContext.deviceName,
                    platformHint: resumeContext.platformHint,
                    note: resumeContext.note ?? "heartbeat"
                ),
                requiresAck: false
            )
        }
        heartbeatTimer = timer
        timer.resume()
    }

    private func retryExpiredPending() {
        let now = Date()
        let expiredIDs = pendingOrder.filter { messageID in
            guard let envelope = pendingByID[messageID], let lastSentAt = envelope.lastSentAt else {
                return false
            }
            return now.timeIntervalSince(lastSentAt) >= resendInterval
        }

        if expiredIDs.isEmpty == false && connectionReady == false {
            scheduleReconnect()
        }

        for messageID in expiredIDs {
            guard let envelope = pendingByID[messageID] else { continue }
            deliver(envelope)
        }
    }

    private func sendResumeIfNeeded() {
        guard let resumeContext = resumeContext else { return }
        let nextSequence = (highestAckSequenceBySession[resumeContext.sessionID] ?? 0) + 1

        send(
            StreamMessage(
                kind: .resumeSession,
                sessionID: resumeContext.sessionID,
                deviceID: resumeContext.deviceID,
                deviceName: resumeContext.deviceName,
                platformHint: resumeContext.platformHint,
                resumeFromSequence: nextSequence,
                note: resumeContext.note ?? "resume"
            ),
            requiresAck: false
        )
    }

    private func trimPendingKeyframesIfNeeded() {
        let keyframeIDs = pendingOrder.filter { pendingByID[$0]?.message.kind == .keyframe }
        guard keyframeIDs.count > maxBufferedKeyframes else { return }

        let overflowCount = keyframeIDs.count - maxBufferedKeyframes
        for messageID in keyframeIDs.prefix(overflowCount) {
            pendingOrder.removeAll { $0 == messageID }
            pendingByID.removeValue(forKey: messageID)
        }
        publishPendingCount()
        publishState("本地热缓冲已裁剪，仅保留最近 \(maxBufferedKeyframes) 个关键帧等待确认")
    }

    private func publishState(_ text: String) {
        DispatchQueue.main.async {
            self.onStateChange?(text)
        }
    }

    private func publishPendingCount() {
        let count = pendingByID.values.filter { $0.message.kind == .keyframe }.count
        DispatchQueue.main.async {
            self.onPendingCountChange?(count)
        }
    }

    private func scheduleDrainTimeout(timeout: TimeInterval) {
        drainTimeoutWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.finalizeDisconnect()
        }
        drainTimeoutWorkItem = workItem
        queue.asyncAfter(deadline: .now() + timeout, execute: workItem)
    }

    private func finishDrainIfPossible() {
        guard disconnectWhenPendingClears, pendingByID.isEmpty else {
            return
        }
        finalizeDisconnect()
    }

    private func finalizeDisconnect() {
        drainTimeoutWorkItem?.cancel()
        drainTimeoutWorkItem = nil
        disconnectWhenPendingClears = false
        teardownConnection()
        endpointTarget = nil
        resumeContext = nil
        pendingOrder.removeAll()
        pendingByID.removeAll()
        publishPendingCount()
    }
}
