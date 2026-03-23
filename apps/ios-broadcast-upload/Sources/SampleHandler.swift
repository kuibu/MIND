import AVFoundation
import CoreImage
import Foundation
import Network
import ReplayKit
import UIKit
import MINDAppSupport
import MINDProtocol

final class SampleHandler: RPBroadcastSampleHandler {
    private let relayClient = ReliableStreamClient()
    private let settingsStore = CaptureSharedSettingsStore()
    private let ciContext = CIContext()

    private var currentSessionID: CaptureSessionID?
    private var frameIndex = 0
    private var lastSentAt = Date.distantPast
    private var currentPreset: CaptureIntentPreset = .wechatAttachment

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        let settings = settingsStore.load()
        currentPreset = settings.selectedPreset

        guard let relay = settings.relay else {
            finishBroadcastWithError(NSError(domain: "MINDBroadcastUpload", code: 1001, userInfo: [
                NSLocalizedDescriptionKey: "No paired Mac relay found in shared app-group settings."
            ]))
            return
        }

        relayClient.connect(to: relay)
        let sessionID = CaptureSessionID(rawValue: "broadcast-\(Int(Date().timeIntervalSince1970))")
        currentSessionID = sessionID
        frameIndex = 0
        let deviceID = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        let deviceName = UIDevice.current.name + " Broadcast"

        relayClient.updateResumeContext(
            ReliableStreamClient.ResumeContext(
                sessionID: sessionID.rawValue,
                deviceID: deviceID,
                deviceName: deviceName,
                platformHint: currentPreset.platform,
                note: "broadcast_extension"
            )
        )

        relayClient.send(
            StreamMessage(
                kind: .startSession,
                sessionID: sessionID.rawValue,
                deviceID: deviceID,
                deviceName: deviceName,
                platformHint: currentPreset.platform,
                note: currentPreset.sessionNote + "\nmode=broadcast_extension"
            )
        )
    }

    override func broadcastPaused() {}

    override func broadcastResumed() {}

    override func broadcastFinished() {
        guard let currentSessionID = currentSessionID else {
            relayClient.disconnect()
            return
        }

        relayClient.send(
            StreamMessage(
                kind: .stopSession,
                sessionID: currentSessionID.rawValue,
                deviceID: UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString,
                deviceName: UIDevice.current.name + " Broadcast",
                platformHint: currentPreset.platform,
                note: "broadcast finished"
            )
        )
        relayClient.updateResumeContext(nil)
        relayClient.disconnectWhenDrained(timeout: 5)
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video else {
            return
        }
        guard let currentSessionID = currentSessionID else {
            return
        }

        let now = Date()
        guard now.timeIntervalSince(lastSentAt) >= 1.0 else {
            return
        }
        lastSentAt = now

        guard
            let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
            let jpegData = makeJPEG(from: imageBuffer)
        else {
            return
        }

        frameIndex += 1
        let width = CVPixelBufferGetWidth(imageBuffer)
        let height = CVPixelBufferGetHeight(imageBuffer)

        relayClient.send(
            StreamMessage(
                kind: .keyframe,
                sessionID: currentSessionID.rawValue,
                deviceID: UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString,
                deviceName: UIDevice.current.name + " Broadcast",
                platformHint: currentPreset.platform,
                frameID: "frame-\(frameIndex)",
                note: nil,
                imageBase64: jpegData.base64EncodedString(),
                chunkSequence: frameIndex,
                width: width,
                height: height
            )
        )
    }

    private func makeJPEG(from imageBuffer: CVPixelBuffer) -> Data? {
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        return ciContext.jpegRepresentation(of: ciImage, colorSpace: colorSpace)
    }
}
