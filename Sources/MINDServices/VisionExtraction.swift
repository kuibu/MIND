import Foundation
import MINDProtocol

public struct MiniCPMRuntimeDescriptor: Equatable {
    public let modelID: String
    public let runsLocallyOnMac: Bool
    public let notes: String

    public init(
        modelID: String = "MiniCPM-o-4.5",
        runsLocallyOnMac: Bool = true,
        notes: String = "Primary path uses local Ollama MiniCPM or a Python MiniCPM bridge; heuristic extraction is retained only as a fallback."
    ) {
        self.modelID = modelID
        self.runsLocallyOnMac = runsLocallyOnMac
        self.notes = notes
    }
}

public protocol VisionExtractor {
    func extract(frame: FrameContext, using recipe: GUIRecipe) throws -> ObservationBatch
}

public enum VisionExtractorError: Error {
    case missingStub(frameID: FrameID, recipeID: String)
    case imagePathMissing(frameID: FrameID)
    case pythonRuntimeUnavailable(String)
    case bridgeFailed(String)
    case invalidBridgeResponse
}

public final class StubVisionExtractor: VisionExtractor {
    private var outputs: [String: ObservationBatch]

    public init(outputs: [String: ObservationBatch] = [:]) {
        self.outputs = outputs
    }

    public func register(_ batch: ObservationBatch, for frameID: FrameID, recipeID: String) {
        outputs[key(frameID: frameID, recipeID: recipeID)] = batch
    }

    public func extract(frame: FrameContext, using recipe: GUIRecipe) throws -> ObservationBatch {
        let lookupKey = key(frameID: frame.keyframe.id, recipeID: recipe.id)
        guard let batch = outputs[lookupKey] else {
            throw VisionExtractorError.missingStub(frameID: frame.keyframe.id, recipeID: recipe.id)
        }
        return batch
    }

    private func key(frameID: FrameID, recipeID: String) -> String {
        frameID.rawValue + "#" + recipeID
    }
}

public final class HeuristicVisionExtractor: VisionExtractor {
    public init() {}

    public func extract(frame: FrameContext, using recipe: GUIRecipe) throws -> ObservationBatch {
        let transcript = frame.keyframe.transcriptHint ?? frame.keyframe.ocrText.joined(separator: "\n")
        let fields = parseStructuredHint(transcript)
        return ObservationBatchFieldMapper.makeBatch(
            fields: fields,
            rawText: transcript,
            frame: frame,
            recipe: recipe
        )
    }

    private func parseStructuredHint(_ hint: String) -> [String: String] {
        hint
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> (String, String)? in
                let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { return nil }
                return (parts[0].trimmingCharacters(in: .whitespacesAndNewlines), parts[1].trimmingCharacters(in: .whitespacesAndNewlines))
            }
            .reduce(into: [String: String]()) { partialResult, item in
                partialResult[item.0] = item.1
            }
    }
}

public struct MiniCPMBridgeConfiguration: Equatable {
    public let pythonExecutable: String
    public let modelID: String
    public let device: String
    public let enableThinking: Bool

    public static func discoverPythonExecutable() -> String {
        if let configured = ProcessInfo.processInfo.environment["MIND_MINICPM_PYTHON"], !configured.isEmpty {
            return configured
        }

        let candidates = [
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/Current/bin/python3",
            "/usr/bin/python3"
        ]

        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
        return "/usr/bin/python3"
    }

    public init(
        pythonExecutable: String = MiniCPMBridgeConfiguration.discoverPythonExecutable(),
        modelID: String = ProcessInfo.processInfo.environment["MIND_MINICPM_MODEL_ID"] ?? "openbmb/MiniCPM-o-4_5",
        device: String = ProcessInfo.processInfo.environment["MIND_MINICPM_DEVICE"] ?? "auto",
        enableThinking: Bool = false
    ) {
        self.pythonExecutable = pythonExecutable
        self.modelID = modelID
        self.device = device
        self.enableThinking = enableThinking
    }
}

public struct OllamaMiniCPMConfiguration: Equatable {
    public let hostURL: URL
    public let modelID: String
    public let keepAlive: String
    public let requestTimeout: TimeInterval

    public init(
        hostURL: URL = URL(string: ProcessInfo.processInfo.environment["MIND_OLLAMA_HOST"] ?? "http://127.0.0.1:11434")!,
        modelID: String = ProcessInfo.processInfo.environment["MIND_OLLAMA_MODEL_ID"] ?? "openbmb/minicpm-o4.5:latest",
        keepAlive: String = ProcessInfo.processInfo.environment["MIND_OLLAMA_KEEPALIVE"] ?? "15m",
        requestTimeout: TimeInterval = 120
    ) {
        self.hostURL = hostURL
        self.modelID = modelID
        self.keepAlive = keepAlive
        self.requestTimeout = requestTimeout
    }
}

public final class OllamaMiniCPMExtractor: VisionExtractor {
#if os(macOS)
    private struct OllamaRequest: Encodable {
        let model: String
        let prompt: String
        let images: [String]
        let stream: Bool
        let format: String
        let keepAlive: String
        let options: OllamaOptions
    }

    private struct OllamaOptions: Encodable {
        let temperature: Double
    }

    private struct OllamaResponse: Decodable {
        let response: String
        let error: String?
    }

    private let configuration: OllamaMiniCPMConfiguration
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
#endif

    public init(configuration: OllamaMiniCPMConfiguration = OllamaMiniCPMConfiguration()) {
#if os(macOS)
        self.configuration = configuration
#endif
    }

    public func extract(frame: FrameContext, using recipe: GUIRecipe) throws -> ObservationBatch {
#if os(macOS)
        guard !frame.keyframe.imagePath.isEmpty else {
            throw VisionExtractorError.imagePathMissing(frameID: frame.keyframe.id)
        }

        let imageURL = URL(fileURLWithPath: frame.keyframe.imagePath)
        guard FileManager.default.fileExists(atPath: imageURL.path) else {
            throw VisionExtractorError.imagePathMissing(frameID: frame.keyframe.id)
        }

        let imageData = try Data(contentsOf: imageURL)
        let requestBody = OllamaRequest(
            model: configuration.modelID,
            prompt: StructuredPromptBuilder.makePrompt(for: recipe),
            images: [imageData.base64EncodedString()],
            stream: false,
            format: "json",
            keepAlive: configuration.keepAlive,
            options: OllamaOptions(temperature: 0)
        )

        var request = URLRequest(url: configuration.hostURL.appendingPathComponent("api/generate"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = configuration.requestTimeout
        request.httpBody = try encoder.encode(requestBody)

        let responseData = try SyncURLSession.execute(request)
        let response = try decoder.decode(OllamaResponse.self, from: responseData)
        if let error = response.error, !error.isEmpty {
            throw VisionExtractorError.bridgeFailed(error)
        }

        let fields = StructuredPromptBuilder.extractFields(from: response.response)
        return ObservationBatchFieldMapper.makeBatch(
            fields: fields,
            rawText: response.response,
            frame: frame,
            recipe: recipe
        )
#else
        throw VisionExtractorError.bridgeFailed("Ollama MiniCPM extractor is only available on macOS")
#endif
    }
}

public final class MiniCPMBridgeExtractor: VisionExtractor {
#if os(macOS)
    private struct BridgeField: Codable {
        let name: String
        let description: String
        let required: Bool
    }

    private struct BridgeRequest: Codable {
        let imagePath: String
        let prompt: String
        let platform: String
        let pageKind: String
        let schemaFields: [BridgeField]
        let modelID: String
        let device: String
        let enableThinking: Bool
    }

    private struct BridgeResponse: Codable {
        let ok: Bool
        let modelID: String?
        let device: String?
        let rawText: String?
        let fields: [String: StringOrNull]?
        let error: String?
    }

    private struct StringOrNull: Codable {
        let value: String?

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() {
                value = nil
            } else if let string = try? container.decode(String.self) {
                value = string
            } else if let intValue = try? container.decode(Int.self) {
                value = String(intValue)
            } else if let doubleValue = try? container.decode(Double.self) {
                value = String(doubleValue)
            } else if let boolValue = try? container.decode(Bool.self) {
                value = String(boolValue)
            } else {
                value = nil
            }
        }
    }

    private let configuration: MiniCPMBridgeConfiguration
    private let bridgeScriptURL: URL
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let bridgeLock = NSLock()
    private var bridgeSession: MiniCPMBridgeSession?
#endif

    public init(
        configuration: MiniCPMBridgeConfiguration = MiniCPMBridgeConfiguration(),
        bridgeScriptURL: URL? = nil
    ) {
#if os(macOS)
        self.configuration = configuration
        self.bridgeScriptURL = bridgeScriptURL
            ?? Bundle.module.url(forResource: "minicpm_vision_bridge", withExtension: "py")
            ?? URL(fileURLWithPath: "/__missing_minicpm_bridge__")
        encoder.keyEncodingStrategy = .convertToSnakeCase
        decoder.keyDecodingStrategy = .convertFromSnakeCase
#endif
    }

    public func extract(frame: FrameContext, using recipe: GUIRecipe) throws -> ObservationBatch {
#if os(macOS)
        guard !frame.keyframe.imagePath.isEmpty else {
            throw VisionExtractorError.imagePathMissing(frameID: frame.keyframe.id)
        }
        guard FileManager.default.isExecutableFile(atPath: configuration.pythonExecutable) else {
            throw VisionExtractorError.pythonRuntimeUnavailable(configuration.pythonExecutable)
        }
        guard FileManager.default.fileExists(atPath: bridgeScriptURL.path) else {
            throw VisionExtractorError.bridgeFailed("MiniCPM bridge script is missing")
        }

        let request = BridgeRequest(
            imagePath: frame.keyframe.imagePath,
            prompt: recipe.prompt,
            platform: recipe.platform.rawValue,
            pageKind: recipe.pageKind,
            schemaFields: recipe.extractionSchema.fields.map {
                BridgeField(name: $0.name, description: $0.description, required: $0.required)
            },
            modelID: configuration.modelID,
            device: configuration.device,
            enableThinking: configuration.enableThinking
        )

        let payload = try encoder.encode(request)
        let output = try bridgeLock.withLock { () throws -> Data in
            do {
                let session = try ensureBridgeSessionLocked()
                return try session.send(requestPayload: payload)
            } catch {
                bridgeSession?.stop()
                bridgeSession = nil
                throw error
            }
        }

        let response = try decoder.decode(BridgeResponse.self, from: output)
        guard response.ok else {
            throw VisionExtractorError.bridgeFailed(response.error ?? "MiniCPM bridge returned ok=false")
        }

        let fields = (response.fields ?? [:]).reduce(into: [String: String]()) { partialResult, item in
            if let value = item.value.value {
                partialResult[item.key] = value
            }
        }
        return ObservationBatchFieldMapper.makeBatch(
            fields: fields,
            rawText: response.rawText ?? "",
            frame: frame,
            recipe: recipe
        )
#else
        throw VisionExtractorError.bridgeFailed("MiniCPM bridge is only available on macOS")
#endif
    }

#if os(macOS)
    deinit {
        bridgeSession?.stop()
    }

    private func ensureBridgeSessionLocked() throws -> MiniCPMBridgeSession {
        if let bridgeSession = bridgeSession, bridgeSession.isRunning {
            return bridgeSession
        }

        let session = try MiniCPMBridgeSession(
            pythonExecutable: configuration.pythonExecutable,
            bridgeScriptURL: bridgeScriptURL
        )
        bridgeSession = session
        return session
    }
#endif
}

public final class PreferredVisionExtractor: VisionExtractor {
    private let primary: VisionExtractor
    private let fallback: VisionExtractor

    public init(primary: VisionExtractor, fallback: VisionExtractor = HeuristicVisionExtractor()) {
        self.primary = primary
        self.fallback = fallback
    }

    public func extract(frame: FrameContext, using recipe: GUIRecipe) throws -> ObservationBatch {
        do {
            return try primary.extract(frame: frame, using: recipe)
        } catch {
            return try fallback.extract(frame: frame, using: recipe)
        }
    }
}

public enum VisionExtractorFactory {
    public static func defaultExtractor() -> VisionExtractor {
#if os(macOS)
        return PreferredVisionExtractor(
            primary: OllamaMiniCPMExtractor(),
            fallback: PreferredVisionExtractor(
                primary: MiniCPMBridgeExtractor(),
                fallback: HeuristicVisionExtractor()
            )
        )
#else
        return HeuristicVisionExtractor()
#endif
    }
}

#if os(macOS)
private final class MiniCPMBridgeSession {
    private let process = Process()
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()

    var isRunning: Bool {
        process.isRunning
    }

    init(pythonExecutable: String, bridgeScriptURL: URL) throws {
        process.executableURL = URL(fileURLWithPath: pythonExecutable)
        process.arguments = [bridgeScriptURL.path]
        process.environment = ProcessInfo.processInfo.environment.merging([
            "PYTORCH_ENABLE_MPS_FALLBACK": "1",
            "TOKENIZERS_PARALLELISM": "false"
        ]) { current, _ in current }
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        try process.run()
    }

    deinit {
        stop()
    }

    func send(requestPayload: Data) throws -> Data {
        guard process.isRunning else {
            throw VisionExtractorError.bridgeFailed("MiniCPM bridge process is not running")
        }

        stdinPipe.fileHandleForWriting.write(requestPayload)
        stdinPipe.fileHandleForWriting.write(Data([0x0A]))
        return try readResponseLine()
    }

    func stop() {
        if process.isRunning {
            stdinPipe.fileHandleForWriting.closeFile()
            process.terminate()
            process.waitUntilExit()
        }
    }

    private func readResponseLine() throws -> Data {
        var response = Data()
        while true {
            let chunk = try stdoutPipe.fileHandleForReading.read(upToCount: 1) ?? Data()
            if chunk.isEmpty {
                let errorText = String(decoding: stderrPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                if response.isEmpty {
                    throw VisionExtractorError.bridgeFailed(errorText.isEmpty ? "MiniCPM bridge closed without a response" : errorText)
                }
                return response
            }
            if chunk == Data([0x0A]) {
                return response
            }
            response.append(chunk)
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}

private enum SyncURLSession {
    static func execute(_ request: URLRequest) throws -> Data {
        let semaphore = DispatchSemaphore(value: 0)
        let session = URLSession(configuration: {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = request.timeoutInterval
            configuration.timeoutIntervalForResource = request.timeoutInterval
            return configuration
        }())

        var result: Result<Data, Error>?
        let task = session.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }

            if let error = error {
                result = .failure(error)
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                result = .failure(VisionExtractorError.bridgeFailed("Ollama returned a non-HTTP response"))
                return
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                let body = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
                result = .failure(VisionExtractorError.bridgeFailed("Ollama returned HTTP \(httpResponse.statusCode): \(body)"))
                return
            }

            result = .success(data ?? Data())
        }

        task.resume()
        semaphore.wait()
        session.finishTasksAndInvalidate()

        switch result {
        case .success(let data):
            return data
        case .failure(let error):
            throw error
        case .none:
            throw VisionExtractorError.bridgeFailed("Ollama request finished without a result")
        }
    }
}
#endif

private enum StructuredPromptBuilder {
    static func makePrompt(for recipe: GUIRecipe) -> String {
        let fieldLines: [String] = recipe.extractionSchema.fields.map { field -> String in
            let requiredText = field.required ? "required" : "optional"
            return #"- "\#(field.name)" (\#(requiredText)): \#(field.description)"#
        }

        return (
            [
                "You are extracting structured GUI data from a single keyframe.",
                "Platform: \(recipe.platform.rawValue).",
                "Page kind: \(recipe.pageKind).",
                recipe.prompt,
                "Return one strict JSON object and nothing else.",
                "If a field is unavailable, use null.",
                "Schema fields:"
            ] + fieldLines
        ).joined(separator: "\n")
    }

    static func extractFields(from rawText: String) -> [String: String] {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let start = trimmed.firstIndex(of: "{"),
            let end = trimmed.lastIndex(of: "}")
        else {
            return [:]
        }

        let jsonSlice = trimmed[start...end]
        guard let data = String(jsonSlice).data(using: .utf8) else {
            return [:]
        }

        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }

        return object.reduce(into: [String: String]()) { partialResult, item in
            switch item.value {
            case let value as String:
                partialResult[item.key] = value
            case let value as NSNumber:
                partialResult[item.key] = value.stringValue
            default:
                break
            }
        }
    }
}

private enum ObservationBatchFieldMapper {
    static func makeBatch(
        fields: [String: String],
        rawText: String,
        frame: FrameContext,
        recipe: GUIRecipe
    ) -> ObservationBatch {
        let canonicalFields = canonicalize(fields: fields, for: recipe)
        let capturedAt = frame.keyframe.capturedAt
        let frameID = frame.keyframe.id

        var texts: [UITextObservation] = []
        var events: [UIEventObservation] = []
        var fileReferences: [FileReferenceObservation] = []

        switch recipe.platform {
        case .wechat:
            if let participant = canonicalFields["participant_name"] {
                texts.append(textObservation(frameID: frameID, capturedAt: capturedAt, role: "participant", text: participant, confidence: 0.97))
            }
            if let message = canonicalFields["message_text"] {
                texts.append(textObservation(frameID: frameID, capturedAt: capturedAt, role: "message", text: message, confidence: 0.94))
            }
            if let fileName = canonicalFields["attachment_filename"] {
                fileReferences.append(
                    FileReferenceObservation(
                        id: identifier(prefix: "file", frameID: frameID, suffix: sanitize(fileName)),
                        frameID: frameID,
                        observedAt: capturedAt,
                        fileName: fileName,
                        resolvedPath: canonicalFields["path"],
                        mimeType: mimeType(for: fileName),
                        confidence: 0.95
                    )
                )
                events.append(
                    UIEventObservation(
                        id: identifier(prefix: "event", frameID: frameID, suffix: "tapAttachment"),
                        frameID: frameID,
                        observedAt: capturedAt,
                        kind: .tapAttachment,
                        targetLabel: fileName,
                        confidence: 0.9
                    )
                )
            }

        case .alipay, .meituan, .didi:
            for role in ["merchant_name", "merchant", "amount", "currency", "occurred_at", "order_title", "route"] {
                if let value = canonicalFields[role] {
                    let normalizedRole = role == "merchant_name" ? "merchant" : role
                    texts.append(
                        textObservation(
                            frameID: frameID,
                            capturedAt: capturedAt,
                            role: normalizedRole,
                            text: value,
                            confidence: normalizedRole == "amount" ? 0.96 : 0.9
                        )
                    )
                }
            }

        case .douyin, .kuaishou, .xiaohongshu, .channels:
            for role in ["title", "collected_at", "like_count", "permalink"] {
                if let value = canonicalFields[role] {
                    texts.append(
                        textObservation(
                            frameID: frameID,
                            capturedAt: capturedAt,
                            role: role,
                            text: value,
                            confidence: role == "title" ? 0.95 : 0.88
                        )
                    )
                }
            }
            events.append(
                UIEventObservation(
                    id: identifier(prefix: "event", frameID: frameID, suffix: "favoriteContent"),
                    frameID: frameID,
                    observedAt: capturedAt,
                    kind: .favoriteContent,
                    targetLabel: canonicalFields["title"],
                    confidence: 0.89
                )
            )

        case .manual:
            if !rawText.isEmpty {
                texts.append(
                    textObservation(
                        frameID: frameID,
                        capturedAt: capturedAt,
                        role: "raw_hint",
                        text: rawText,
                        confidence: 0.6
                    )
                )
            }
        }

        return ObservationBatch(
            sessionID: frame.keyframe.sessionID,
            frameID: frameID,
            platform: recipe.platform,
            pageKind: recipe.pageKind,
            recipeID: recipe.id,
            recipeVersion: recipe.version,
            capturedAt: capturedAt,
            extractedFields: canonicalFields,
            texts: texts,
            events: events,
            fileReferences: fileReferences,
            confidence: confidence(for: texts, files: fileReferences)
        )
    }

    private static func canonicalize(fields: [String: String], for recipe: GUIRecipe) -> [String: String] {
        var canonical = fields

        switch recipe.platform {
        case .wechat:
            if canonical["participant_name"] == nil {
                canonical["participant_name"] = fields["participant"]
            }
            if canonical["message_text"] == nil {
                canonical["message_text"] = fields["message"]
            }
            if canonical["attachment_filename"] == nil {
                canonical["attachment_filename"] = fields["file"]
            }
        case .alipay, .meituan, .didi:
            if canonical["merchant_name"] == nil {
                canonical["merchant_name"] = fields["merchant"]
            }
        case .douyin, .kuaishou, .xiaohongshu, .channels, .manual:
            break
        }

        return canonical.compactMapValues { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    private static func textObservation(
        frameID: FrameID,
        capturedAt: Date,
        role: String,
        text: String,
        confidence: Double
    ) -> UITextObservation {
        UITextObservation(
            id: identifier(prefix: "text", frameID: frameID, suffix: role),
            frameID: frameID,
            observedAt: capturedAt,
            text: text,
            role: role,
            confidence: confidence
        )
    }

    private static func confidence(for texts: [UITextObservation], files: [FileReferenceObservation]) -> Double {
        if !files.isEmpty {
            return 0.94
        }
        if !texts.isEmpty {
            return 0.9
        }
        return 0.55
    }

    private static func identifier(prefix: String, frameID: FrameID, suffix: String) -> String {
        prefix + ":" + frameID.rawValue + ":" + suffix
    }

    private static func sanitize(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
    }

    private static func mimeType(for fileName: String) -> String? {
        if fileName.lowercased().hasSuffix(".pdf") {
            return "application/pdf"
        }
        return nil
    }
}
