import Foundation
import Network
import SwiftUI
import MINDAppSupport
import MINDRecipes
import MINDProtocol
import MINDServices

@MainActor
final class MacIngestRuntimeCoordinator: ObservableObject {
    let viewModel = MacIngestViewModel()

    @Published private(set) var listenerStatus = "未启动"
    @Published private(set) var storagePath = FrameStorage.rootURL.path

    private let server = MacIngestServer()
    private let ingestCoordinator = LiveIngestCoordinator()
    private let recipeRegistry = RecipeRegistry()
    private let recipeDatasetStore = RecipeDatasetStore()
    private lazy var evaluationHarness = RecipeEvaluationHarness(
        extractor: VisionExtractorFactory.defaultExtractor(),
        recipeRegistry: recipeRegistry
    )
    private var sessionStates: [String: IngestSessionCard] = [:]
    private var processedMessageIDs: Set<String> = []

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
        viewModel.replaceReviewQueue(ingestCoordinator.reviewItems())
        refreshEvaluationReports()
        FrameStorage.pruneExpiredSessions()
        server.start()
    }

    func onDisappear() {
        server.stop()
    }

    func submitReview(reviewID: String, fieldText: String) {
        let correctedFields = parseFieldText(fieldText)
        guard correctedFields.isEmpty == false,
              let replaySample = ingestCoordinator.replaySample(forReviewID: reviewID, expectedFields: correctedFields) else {
            viewModel.prependObservationPreview(
                ObservationPreview(
                    id: UUID().uuidString,
                    badge: "Review",
                    title: "标注未保存",
                    subtitle: "review id=\(reviewID)"
                )
            )
            return
        }

        let correction = ingestCoordinator.applyReviewCorrection(reviewID, correctedFields: correctedFields)
        guard let correction = correction else {
            viewModel.prependObservationPreview(
                ObservationPreview(
                    id: UUID().uuidString,
                    badge: "Review",
                    title: "纠错未写回",
                    subtitle: "review id=\(reviewID)"
                )
            )
            return
        }

        viewModel.replaceReviewQueue(ingestCoordinator.reviewItems())
        viewModel.replacePipelinePanels(correction.pipelinePanels)
        correction.commitSummaryLines.reversed().forEach { line in
            viewModel.prependObservationPreview(
                ObservationPreview(
                    id: UUID().uuidString,
                    badge: correction.appliedToCommittedSession ? "Correction" : "Review",
                    title: line,
                    subtitle: correction.appliedToCommittedSession ? "已写回 canonical store" : "等待 session commit"
                )
            )
        }

        do {
            try recipeDatasetStore.save(sample: replaySample)
            refreshEvaluationReports()
            viewModel.prependObservationPreview(
                ObservationPreview(
                    id: UUID().uuidString,
                    badge: "Review",
                    title: "已保存人工标注",
                    subtitle: "\(replaySample.recipeID) · \(replaySample.id)"
                )
            )
        } catch {
            viewModel.prependObservationPreview(
                ObservationPreview(
                    id: UUID().uuidString,
                    badge: "Review",
                    title: "标注样本保存失败",
                    subtitle: "canonical 已更新，样本落盘失败: \(error.localizedDescription)"
                )
            )
        }
    }

    private func handle(message: StreamMessage) {
        if let messageID = message.messageID, processedMessageIDs.contains(messageID) {
            return
        }
        if let messageID = message.messageID {
            processedMessageIDs.insert(messageID)
        }

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
            viewModel.replaceReviewQueue(ingestCoordinator.reviewItems())
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
                viewModel.replaceReviewQueue(completion.reviewItems)
                FrameStorage.cleanupSession(sessionID: sessionID, retaining: completion.retainedEvidencePaths)
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
        case .resumeSession:
            listenerStatus = "会话恢复请求: \(message.sessionID ?? "unknown-session")"
        case .heartbeat:
            listenerStatus = "已收到 heartbeat @ \(message.sentAt.formatted(date: .omitted, time: .standard))"
        case .ack:
            break
        }
    }

    private func refreshEvaluationReports() {
        do {
            let reports = try recipeDatasetStore.evaluate(using: evaluationHarness)
            viewModel.replaceEvaluationReports(reports)
        } catch {
            viewModel.replaceEvaluationReports([])
            viewModel.prependObservationPreview(
                ObservationPreview(
                    id: UUID().uuidString,
                    badge: "Eval",
                    title: "评估报告刷新失败",
                    subtitle: error.localizedDescription
                )
            )
        }
    }

    private func parseFieldText(_ raw: String) -> [String: String] {
        raw
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> (String, String)? in
                let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { return nil }
                let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                guard key.isEmpty == false, value.isEmpty == false else { return nil }
                return (key, value)
            }
            .reduce(into: [String: String]()) { partialResult, item in
                partialResult[item.0] = item.1
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
                sendAck(for: message)
                onMessage?(message)
            }
        }
    }

    private func sendAck(for message: StreamMessage) {
        guard message.kind != .ack, let messageID = message.messageID else {
            return
        }

        let ack = StreamMessage(
            kind: .ack,
            messageID: UUID().uuidString,
            sessionID: message.sessionID,
            deviceID: message.deviceID,
            deviceName: Host.current().localizedName,
            platformHint: message.platformHint,
            ackMessageID: messageID,
            ackSequence: message.chunkSequence,
            note: "ack"
        )

        guard let data = try? StreamMessageCodec.encodeLine(ack) else {
            return
        }
        connection.send(content: data, completion: .contentProcessed { _ in })
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

    static func cleanupSession(sessionID: String, retaining paths: [String]) {
        let protectedPaths = Set(paths)
        let directory = rootURL.appendingPathComponent(sessionID, isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return
        }

        for case let fileURL as URL in enumerator {
            guard protectedPaths.contains(fileURL.path) == false else {
                continue
            }
            try? FileManager.default.removeItem(at: fileURL)
        }

        if (try? FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty) == true {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    static func pruneExpiredSessions(maxAgeHours: Double = 12) {
        guard let sessionDirectories = try? FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let cutoff = Date().addingTimeInterval(-(maxAgeHours * 60 * 60))
        for directory in sessionDirectories {
            let values = try? directory.resourceValues(forKeys: [.contentModificationDateKey])
            if let modifiedAt = values?.contentModificationDate, modifiedAt < cutoff {
                try? FileManager.default.removeItem(at: directory)
            }
        }
    }
}
