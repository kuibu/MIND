import Foundation
import Network
import SwiftUI
import MINDAppSupport
import MINDProtocol

@MainActor
final class MacIngestRuntimeCoordinator: ObservableObject {
    let viewModel = MacIngestViewModel()

    @Published private(set) var listenerStatus = "未启动"
    @Published private(set) var storagePath = FrameStorage.rootURL.path

    private let server = MacIngestServer()
    private let ingestCoordinator = LiveIngestCoordinator()
    private var sessionStates: [String: IngestSessionCard] = [:]

    init() {
        server.onStateChange = { [weak self] status in
            Task { @MainActor in
                self?.listenerStatus = status
            }
        }

        server.onMessage = { [weak self] message in
            Task { @MainActor in
                self?.handle(message: message)
            }
        }
    }

    func onAppear() {
        viewModel.resetLiveState(
            recipeLabels: ingestCoordinator.recipeLabels(),
            pipelinePanels: ingestCoordinator.initialPipelinePanels()
        )
        server.start()
    }

    func onDisappear() {
        server.stop()
    }

    private func handle(message: StreamMessage) {
        switch message.kind {
        case .hello:
            let title = message.deviceName ?? "未知设备"
            viewModel.prependObservationPreview(
                ObservationPreview(
                    id: UUID().uuidString,
                    badge: "Peer",
                    title: title,
                    subtitle: "已建立 Bonjour/NWConnection 通道"
                )
            )
        case .startSession:
            guard let sessionID = message.sessionID else { return }
            let card = ingestCoordinator.startSession(from: message) ?? IngestSessionCard(
                id: sessionID,
                sourceDeviceName: message.deviceName ?? "未知 iPhone",
                sessionID: sessionID,
                stateLabel: "正在接收关键帧",
                keyframeCount: 0,
                mergedObservationCount: 0
            )
            sessionStates[sessionID] = card
            viewModel.upsertSession(card)
        case .keyframe:
            guard let sessionID = message.sessionID else { return }

            let savedURL = FrameStorage.persist(
                imageBase64: message.imageBase64,
                sessionID: sessionID,
                frameID: message.frameID ?? UUID().uuidString
            )
            let frameUpdate = ingestCoordinator.ingestKeyframe(from: message, imagePath: savedURL?.path)

            let updated = frameUpdate?.session
                ?? IngestSessionCard(
                    id: sessionID,
                    sourceDeviceName: message.deviceName ?? "未知 iPhone",
                    sessionID: sessionID,
                    stateLabel: "收到关键帧并已落盘",
                    keyframeCount: (sessionStates[sessionID]?.keyframeCount ?? 0) + 1,
                    mergedObservationCount: (sessionStates[sessionID]?.mergedObservationCount ?? 0) + 1
            )
            sessionStates[sessionID] = updated
            viewModel.upsertSession(updated)

            let previews = frameUpdate?.observationPreviews
            if let previews = previews, !previews.isEmpty {
                previews.reversed().forEach { preview in
                    viewModel.prependObservationPreview(preview)
                }
            } else {
                viewModel.prependObservationPreview(
                    ObservationPreview(
                        id: UUID().uuidString,
                        badge: "Keyframe",
                        title: message.frameID ?? "unnamed-frame",
                        subtitle: savedURL?.path ?? "关键帧解码失败"
                    )
                )
            }
        case .stopSession:
            guard let sessionID = message.sessionID, let existing = sessionStates[sessionID] else { return }
            let completion = ingestCoordinator.stopSession(from: message)
            let updated = completion?.session ?? IngestSessionCard(
                id: existing.id,
                sourceDeviceName: existing.sourceDeviceName,
                sessionID: existing.sessionID,
                stateLabel: "会话已结束",
                keyframeCount: existing.keyframeCount,
                mergedObservationCount: existing.mergedObservationCount
            )
            sessionStates[sessionID] = updated
            viewModel.upsertSession(updated)
            if let completion = completion {
                viewModel.replacePipelinePanels(completion.pipelinePanels)
                completion.commitSummaryLines.reversed().forEach { line in
                    viewModel.prependObservationPreview(
                        ObservationPreview(
                            id: UUID().uuidString,
                            badge: "Commit",
                            title: line,
                            subtitle: sessionID
                        )
                    )
                }
            }
        case .heartbeat:
            listenerStatus = "已收到 heartbeat @ \(message.sentAt.formatted(date: .omitted, time: .standard))"
        }
    }
}

private final class MacIngestServer {
    var onStateChange: ((String) -> Void)?
    var onMessage: ((StreamMessage) -> Void)?

    private let queue = DispatchQueue(label: "mind.mac.listener")
    private var listener: NWListener?
    private var inboundConnections: [ObjectIdentifier: InboundConnection] = [:]

    func start() {
        do {
            let listener = try NWListener(using: .tcp, on: .any)
            self.listener = listener
            listener.service = NWListener.Service(
                name: Host.current().localizedName ?? "MIND Mac",
                type: BonjourServiceDescriptor.type
            )

            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .setup:
                    self?.onStateChange?("监听初始化中")
                case .ready:
                    let port = listener.port?.rawValue ?? 0
                    self?.onStateChange?("Bonjour 已广播，监听端口 \(port)")
                case .failed(let error):
                    self?.onStateChange?("监听失败: \(error.localizedDescription)")
                case .cancelled:
                    self?.onStateChange?("监听已停止")
                default:
                    self?.onStateChange?("监听状态更新")
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection: connection)
            }

            listener.start(queue: queue)
        } catch {
            onStateChange?("无法启动监听: \(error.localizedDescription)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        inboundConnections.values.forEach { $0.cancel() }
        inboundConnections.removeAll()
    }

    private func accept(connection: NWConnection) {
        let inbound = InboundConnection(connection: connection)
        inbound.onMessage = { [weak self] message in
            self?.onMessage?(message)
        }
        let identifier = ObjectIdentifier(inbound)
        inbound.onCompletion = { [weak self] in
            self?.inboundConnections.removeValue(forKey: identifier)
        }
        inboundConnections[identifier] = inbound
        inbound.start(queue: queue)
    }
}

private final class InboundConnection {
    var onMessage: ((StreamMessage) -> Void)?
    var onCompletion: (() -> Void)?

    private let connection: NWConnection
    private var buffer = Data()

    init(connection: NWConnection) {
        self.connection = connection
    }

    func start(queue: DispatchQueue) {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.receive()
            case .failed, .cancelled:
                self?.onCompletion?()
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    func cancel() {
        connection.cancel()
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 262_144) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let data = data, !data.isEmpty {
                self.buffer.append(data)
                self.processBuffer()
            }

            if isComplete || error != nil {
                self.onCompletion?()
                return
            }

            self.receive()
        }
    }

    private func processBuffer() {
        let newline = Data([0x0A])
        while let range = buffer.range(of: newline) {
            let line = buffer.subdata(in: 0..<range.lowerBound)
            buffer.removeSubrange(0..<range.upperBound)
            guard !line.isEmpty else { continue }
            if let message = try? StreamMessageCodec.decodeLine(line) {
                onMessage?(message)
            }
        }
    }
}

private enum FrameStorage {
    static var rootURL: URL = {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MIND/runtime/frames/keyframes", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    static func persist(imageBase64: String?, sessionID: String, frameID: String) -> URL? {
        guard let imageBase64 = imageBase64, let data = Data(base64Encoded: imageBase64) else {
            return nil
        }

        let directory = rootURL.appendingPathComponent(sessionID, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(frameID + ".jpg")
        do {
            try data.write(to: destination, options: .atomic)
            return destination
        } catch {
            return nil
        }
    }
}
