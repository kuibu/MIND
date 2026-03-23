import AVFoundation
import CoreImage
import Network
import ReplayKit
import SwiftUI
import UIKit
import MINDAppSupport
import MINDProtocol

private struct CapturedFramePayload {
    let data: Data
    let size: CGSize
    let note: String?
}

@MainActor
final class IOSCaptureRuntimeCoordinator: ObservableObject {
    let viewModel = IOSCaptureViewModel()

    private let browser = BonjourBrowserService()
    private let client = ReliableStreamClient()
    private let sharedSettingsStore = CaptureSharedSettingsStore()
    private lazy var captureSource = ReplayKitCaptureSource(
        onFrame: { [weak self] payload in
            self?.sendFrame(payload)
        },
        onEvent: { [weak self] title, detail in
            Task { @MainActor in
                self?.viewModel.logEvent(title: title, detail: detail)
            }
        }
    )

    private var endpointsByNodeID: [String: NWEndpoint] = [:]
    private var currentSessionID: CaptureSessionID?
    private var sentFrameCount = 0

    init() {
        browser.onResultsChanged = { [weak self] nodes, endpoints in
            Task { @MainActor in
                self?.endpointsByNodeID = endpoints
                self?.viewModel.replaceDiscoveredNodes(nodes)
                if nodes.isEmpty {
                    self?.viewModel.updateConnection(status: .discovering)
                }
            }
        }

        client.onStateChange = { [weak self] description in
            Task { @MainActor in
                self?.viewModel.logEvent(title: "连接状态", detail: description)
            }
        }

        client.onPendingCountChange = { [weak self] count in
            Task { @MainActor in
                self?.viewModel.updateBufferedChunkCount(count)
            }
        }
    }

    func onAppear() {
        viewModel.selectedPreset = sharedSettingsStore.load().selectedPreset
        viewModel.updateConnection(status: .discovering)
        browser.start()
    }

    func pair(with node: DiscoveredMacNode) {
        guard let endpoint = endpointsByNodeID[node.id] else {
            viewModel.logEvent(title: "配对失败", detail: "找不到 \(node.name) 对应的网络端点。")
            return
        }

        client.connect(to: endpoint)
        viewModel.updateConnection(status: .paired, pairedNode: node)
        viewModel.logEvent(title: "已选择目标节点", detail: "开始连接 \(node.name)。")
        persistSharedSettings(relayNode: node)

        let hello = StreamMessage(
            kind: .hello,
            deviceID: UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString,
            deviceName: UIDevice.current.name,
            platformHint: viewModel.selectedPreset.platform,
            note: "ios-capture paired"
        )
        client.send(hello)
    }

    func startCapture() {
        guard let destination = viewModel.pairedNode ?? viewModel.discoveredNodes.first else {
            viewModel.logEvent(title: "未配对", detail: "请先选择一台 Mac 节点。")
            return
        }

        if viewModel.pairedNode == nil {
            pair(with: destination)
        }

        let preset = viewModel.selectedPreset
        let sessionID = CaptureSessionID(rawValue: "iphone-\(Int(Date().timeIntervalSince1970))")
        currentSessionID = sessionID
        sentFrameCount = 0
        let deviceID = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        let deviceName = UIDevice.current.name

        viewModel.beginExternalSession(
            sessionID: sessionID,
            destinationName: destination.name,
            modeLabel: "\(preset.title) · \(viewModel.keepAliveModeEnabled ? "可恢复长会话" : "快捷采集")"
        )

        client.updateResumeContext(
            ReliableStreamClient.ResumeContext(
                sessionID: sessionID.rawValue,
                deviceID: deviceID,
                deviceName: deviceName,
                platformHint: preset.platform,
                note: viewModel.keepAliveModeEnabled ? "durable_session" : "quick_session"
            )
        )

        client.send(
            StreamMessage(
                kind: .startSession,
                sessionID: sessionID.rawValue,
                deviceID: deviceID,
                deviceName: deviceName,
                platformHint: preset.platform,
                note: preset.sessionNote + "\nmode=" + (viewModel.keepAliveModeEnabled ? "durable" : "quick")
            )
        )

        viewModel.logEvent(title: "已选择采集预设", detail: "\(preset.title) · \(preset.subtitle)")
        persistSharedSettings(relayNode: destination)
        captureSource.start(with: preset)
    }

    func stopCapture() {
        captureSource.stop()

        if let currentSessionID = currentSessionID {
            client.send(
                StreamMessage(
                    kind: .stopSession,
                    sessionID: currentSessionID.rawValue,
                    deviceID: UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString,
                    deviceName: UIDevice.current.name,
                    platformHint: viewModel.selectedPreset.platform,
                    note: "capture stopped"
                )
            )
        }

        client.updateResumeContext(nil)
        currentSessionID = nil
        sentFrameCount = 0
        viewModel.endExternalSession()
    }

    func syncSharedSettings() {
        persistSharedSettings(relayNode: viewModel.pairedNode)
    }

    private func sendFrame(_ payload: CapturedFramePayload) {
        guard let currentSessionID = currentSessionID else { return }

        sentFrameCount += 1
        let frameID = "frame-\(sentFrameCount)"
        let message = StreamMessage(
            kind: .keyframe,
            sessionID: currentSessionID.rawValue,
            deviceID: UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString,
            deviceName: UIDevice.current.name,
            platformHint: viewModel.selectedPreset.platform,
            frameID: frameID,
            note: payload.note,
            imageBase64: payload.data.base64EncodedString(),
            chunkSequence: sentFrameCount,
            width: Int(payload.size.width),
            height: Int(payload.size.height)
        )

        client.send(message)
    }

    private func persistSharedSettings(relayNode: DiscoveredMacNode?) {
        let relay = relayNode.flatMap { node -> CaptureRelayConfiguration? in
            let parts = node.id.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            return CaptureRelayConfiguration(
                serviceName: parts[0],
                serviceDomain: parts[1],
                displayName: node.name
            )
        }
        sharedSettingsStore.save(
            CaptureSharedSettings(
                selectedPresetRawValue: viewModel.selectedPreset.rawValue,
                relay: relay
            )
        )
    }
}

private final class BonjourBrowserService {
    var onResultsChanged: (([DiscoveredMacNode], [String: NWEndpoint]) -> Void)?

    private let queue = DispatchQueue(label: "mind.ios.browser")
    private var browser: NWBrowser?

    func start() {
        let parameters = NWParameters.tcp
        let descriptor = NWBrowser.Descriptor.bonjour(type: BonjourServiceDescriptor.type, domain: BonjourServiceDescriptor.domain)
        let browser = NWBrowser(for: descriptor, using: parameters)
        self.browser = browser

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            var nodes: [DiscoveredMacNode] = []
            var endpoints: [String: NWEndpoint] = [:]

            for result in results {
                switch result.endpoint {
                case let .service(name, _, domain, _):
                    let id = name + "|" + domain
                    let node = DiscoveredMacNode(
                        id: id,
                        name: name,
                        host: "\(name).\(domain)",
                        isTrusted: true,
                        latencyMillis: Int.random(in: 8...35)
                    )
                    nodes.append(node)
                    endpoints[id] = result.endpoint
                default:
                    continue
                }
            }

            self?.onResultsChanged?(nodes.sorted { $0.name < $1.name }, endpoints)
        }

        browser.start(queue: queue)
    }
}

private final class ReplayKitCaptureSource {
    private let onFrame: (CapturedFramePayload) -> Void
    private let onEvent: (String, String) -> Void
    private let recorder = RPScreenRecorder.shared()
    private let ciContext = CIContext()

    private var timer: Timer?
    private var lastSentAt = Date.distantPast
    private var frameIndex = 0
    private var currentPreset: CaptureIntentPreset = .wechatAttachment

    init(
        onFrame: @escaping (CapturedFramePayload) -> Void,
        onEvent: @escaping (String, String) -> Void
    ) {
        self.onFrame = onFrame
        self.onEvent = onEvent
    }

    func start(with preset: CaptureIntentPreset) {
        frameIndex = 0
        currentPreset = preset

#if targetEnvironment(simulator)
        startDemoFrames(reason: "Simulator fallback")
#else
        recorder.isMicrophoneEnabled = false
        recorder.startCapture(handler: { [weak self] sampleBuffer, sampleType, error in
            if let error = error {
                self?.onEvent("ReplayKit 错误", error.localizedDescription)
                return
            }
            guard sampleType == .video else { return }
            self?.handleVideoSample(sampleBuffer)
        }, completionHandler: { [weak self] error in
            if let error = error {
                self?.onEvent("ReplayKit 启动失败", error.localizedDescription)
                self?.startDemoFrames(reason: "ReplayKit unavailable")
                return
            }
            self?.onEvent("ReplayKit 已启动", "正在从当前 App 的屏幕会话提取关键帧。")
        })
#endif
    }

    func stop() {
        timer?.invalidate()
        timer = nil

#if !targetEnvironment(simulator)
        recorder.stopCapture { [weak self] error in
            if let error = error {
                self?.onEvent("停止采集失败", error.localizedDescription)
            } else {
                self?.onEvent("采集已停止", "结束当前帧流。")
            }
        }
#else
        onEvent("采集已停止", "Simulator demo frame source stopped.")
#endif
    }

    private func handleVideoSample(_ sampleBuffer: CMSampleBuffer) {
        let now = Date()
        guard now.timeIntervalSince(lastSentAt) >= 1.0 else { return }
        lastSentAt = now

        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let width = CVPixelBufferGetWidth(imageBuffer)
        let height = CVPixelBufferGetHeight(imageBuffer)

        guard let jpegData = ciContext.jpegRepresentation(of: ciImage, colorSpace: colorSpace) else {
            return
        }

        onFrame(CapturedFramePayload(data: jpegData, size: CGSize(width: width, height: height), note: nil))
        onEvent("发送关键帧", "ReplayKit frame \(width)x\(height) 已发往 Mac。")
    }

    private func startDemoFrames(reason: String) {
        onEvent("启用 demo frame source", reason)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.frameIndex += 1
            guard let data = self.makeSyntheticFrame(index: self.frameIndex) else { return }
            let hint = self.currentPreset.demoFrameHints[(self.frameIndex - 1) % max(self.currentPreset.demoFrameHints.count, 1)]
            self.onFrame(CapturedFramePayload(data: data, size: CGSize(width: 960, height: 540), note: hint))
            self.onEvent("发送 demo 帧", "frame-\(self.frameIndex) 已发往 Mac。")
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func makeSyntheticFrame(index: Int) -> Data? {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 960, height: 540))
        let image = renderer.image { context in
            let colors = [UIColor(red: 0.92, green: 0.83, blue: 0.48, alpha: 1.0).cgColor,
                          UIColor(red: 0.22, green: 0.57, blue: 0.66, alpha: 1.0).cgColor]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
            context.cgContext.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: 960, y: 540),
                options: []
            )

            let title = "MIND Capture Demo"
            let subtitle = "\(currentPreset.title) · frame-\(index)"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 38, weight: .bold),
                .foregroundColor: UIColor.white
            ]
            let subAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 22, weight: .medium),
                .foregroundColor: UIColor.white.withAlphaComponent(0.92)
            ]

            title.draw(at: CGPoint(x: 46, y: 72), withAttributes: attrs)
            subtitle.draw(at: CGPoint(x: 46, y: 132), withAttributes: subAttrs)
        }
        return image.jpegData(compressionQuality: 0.72)
    }
}
