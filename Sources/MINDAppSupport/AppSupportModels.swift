import Combine
import Foundation
import MINDPipelines
import MINDProtocol
import MINDRecipes
import MINDSchemas
import MINDServices

public enum CaptureConnectionStatus: String, CaseIterable, Identifiable {
    case disconnected
    case discovering
    case paired
    case streaming

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .disconnected:
            return "未连接"
        case .discovering:
            return "发现中"
        case .paired:
            return "已配对"
        case .streaming:
            return "传输中"
        }
    }
}

public struct DiscoveredMacNode: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let host: String
    public let isTrusted: Bool
    public let latencyMillis: Int

    public init(id: String, name: String, host: String, isTrusted: Bool, latencyMillis: Int) {
        self.id = id
        self.name = name
        self.host = host
        self.isTrusted = isTrusted
        self.latencyMillis = latencyMillis
    }
}

public struct CaptureEventRow: Identifiable, Equatable {
    public let id: String
    public let timestamp: Date
    public let title: String
    public let detail: String

    public init(id: String, timestamp: Date, title: String, detail: String) {
        self.id = id
        self.timestamp = timestamp
        self.title = title
        self.detail = detail
    }
}

public struct CaptureSessionCard: Identifiable, Equatable {
    public let id: String
    public let sessionID: CaptureSessionID
    public let startedAt: Date
    public let destinationName: String
    public let modeLabel: String
    public let bufferedChunkCount: Int

    public init(
        id: String,
        sessionID: CaptureSessionID,
        startedAt: Date,
        destinationName: String,
        modeLabel: String,
        bufferedChunkCount: Int
    ) {
        self.id = id
        self.sessionID = sessionID
        self.startedAt = startedAt
        self.destinationName = destinationName
        self.modeLabel = modeLabel
        self.bufferedChunkCount = bufferedChunkCount
    }
}

public struct IngestSessionCard: Identifiable, Equatable {
    public let id: String
    public let sourceDeviceName: String
    public let sessionID: String
    public let stateLabel: String
    public let keyframeCount: Int
    public let mergedObservationCount: Int

    public init(
        id: String,
        sourceDeviceName: String,
        sessionID: String,
        stateLabel: String,
        keyframeCount: Int,
        mergedObservationCount: Int
    ) {
        self.id = id
        self.sourceDeviceName = sourceDeviceName
        self.sessionID = sessionID
        self.stateLabel = stateLabel
        self.keyframeCount = keyframeCount
        self.mergedObservationCount = mergedObservationCount
    }
}

public struct ObservationPreview: Identifiable, Equatable {
    public let id: String
    public let badge: String
    public let title: String
    public let subtitle: String

    public init(id: String, badge: String, title: String, subtitle: String) {
        self.id = id
        self.badge = badge
        self.title = title
        self.subtitle = subtitle
    }
}

public struct ReviewQueueCard: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let predictedFields: [String]
    public let evidenceLocators: [String]

    public init(id: String, title: String, subtitle: String, predictedFields: [String], evidenceLocators: [String]) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.predictedFields = predictedFields
        self.evidenceLocators = evidenceLocators
    }
}

public struct EvaluationReportCard: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let lines: [String]

    public init(id: String, title: String, subtitle: String, lines: [String]) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.lines = lines
    }
}

public struct PipelinePanelItem: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let summary: String
    public let lines: [String]

    public init(id: String, title: String, summary: String, lines: [String]) {
        self.id = id
        self.title = title
        self.summary = summary
        self.lines = lines
    }
}

public enum CaptureIntentPreset: String, CaseIterable, Identifiable {
    case wechatAttachment
    case alipayExpense
    case meituanExpense
    case didiTrip
    case douyinCollection
    case kuaishouCollection
    case xiaohongshuCollection
    case channelsCollection

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .wechatAttachment:
            return "微信附件"
        case .alipayExpense:
            return "支付宝消费"
        case .meituanExpense:
            return "美团消费"
        case .didiTrip:
            return "滴滴行程"
        case .douyinCollection:
            return "抖音收藏"
        case .kuaishouCollection:
            return "快手收藏"
        case .xiaohongshuCollection:
            return "小红书收藏"
        case .channelsCollection:
            return "视频号收藏"
        }
    }

    public var subtitle: String {
        switch self {
        case .wechatAttachment:
            return "为 PDF 附件检索任务提供聊天上下文。"
        case .alipayExpense, .meituanExpense, .didiTrip:
            return "为差旅/餐饮/其他汇总任务补充消费凭证。"
        case .douyinCollection, .kuaishouCollection, .xiaohongshuCollection, .channelsCollection:
            return "为收藏时间线任务补充标题、时间和点赞快照。"
        }
    }

    public var platform: SourcePlatform {
        switch self {
        case .wechatAttachment:
            return .wechat
        case .alipayExpense:
            return .alipay
        case .meituanExpense:
            return .meituan
        case .didiTrip:
            return .didi
        case .douyinCollection:
            return .douyin
        case .kuaishouCollection:
            return .kuaishou
        case .xiaohongshuCollection:
            return .xiaohongshu
        case .channelsCollection:
            return .channels
        }
    }

    public var sessionNote: String {
        switch self {
        case .wechatAttachment:
            return "preset=wechat_attachment"
        case .alipayExpense:
            return "preset=alipay_expense"
        case .meituanExpense:
            return "preset=meituan_expense"
        case .didiTrip:
            return "preset=didi_trip"
        case .douyinCollection:
            return "preset=douyin_collection"
        case .kuaishouCollection:
            return "preset=kuaishou_collection"
        case .xiaohongshuCollection:
            return "preset=xiaohongshu_collection"
        case .channelsCollection:
            return "preset=channels_collection"
        }
    }

    public var demoFrameHints: [String] {
        switch self {
        case .wechatAttachment:
            return [
                """
                participant=陈攀
                message=把宇树G1人形机器人操作经验手册.pdf 发你了
                file=宇树G1人形机器人操作经验手册.pdf
                path=/Users/a/Downloads/unitree-g1-manual.pdf
                """,
                """
                participant=陈攀
                message=你先看第 3 章和第 5 章
                file=宇树G1人形机器人操作经验手册.pdf
                path=/Users/a/Downloads/unitree-g1-manual.pdf
                """
            ]
        case .alipayExpense:
            return [
                """
                merchant=Manner Coffee
                amount=38.0
                currency=CNY
                occurred_at=2026-03-17T10:15:00+08:00
                order_title=咖啡
                """
            ]
        case .meituanExpense:
            return [
                """
                merchant=海底捞
                amount=56.0
                currency=CNY
                occurred_at=2026-03-19T20:00:00+08:00
                order_title=火锅晚餐
                """
            ]
        case .didiTrip:
            return [
                """
                merchant=滴滴出行
                amount=86.0
                currency=CNY
                occurred_at=2026-03-18T08:45:00+08:00
                route=浦东机场 -> 张江
                """
            ]
        case .douyinCollection:
            return [
                """
                title=宇树 G1 上手体验
                collected_at=2026-03-16T21:00:00+08:00
                like_count=512
                permalink=https://douyin.example/g1
                """
            ]
        case .kuaishouCollection:
            return [
                """
                title=深圳出差三天省时攻略
                collected_at=2026-03-17T12:30:00+08:00
                like_count=203
                permalink=https://kuaishou.example/sz-trip
                """
            ]
        case .xiaohongshuCollection:
            return [
                """
                title=东京差旅咖啡地图
                collected_at=2026-03-18T18:20:00+08:00
                like_count=89
                permalink=https://xhs.example/tokyo
                """
            ]
        case .channelsCollection:
            return [
                """
                title=产品经理周报工具流
                collected_at=2026-03-19T22:10:00+08:00
                like_count=144
                permalink=https://channels.example/pm-weekly
                """
            ]
        }
    }
}

public final class MockDeviceDiscoveryService {
    public init() {}

    public func discoverNodes() -> [DiscoveredMacNode] {
        [
            DiscoveredMacNode(
                id: "mac-studio",
                name: "A 的 MacBook Pro",
                host: "mind-macbook-pro.local",
                isTrusted: true,
                latencyMillis: 12
            ),
            DiscoveredMacNode(
                id: "office-mac-mini",
                name: "Office Mac mini",
                host: "office-mac-mini.local",
                isTrusted: false,
                latencyMillis: 31
            )
        ]
    }
}

@MainActor
public final class IOSCaptureViewModel: ObservableObject {
    @Published public private(set) var discoveredNodes: [DiscoveredMacNode] = []
    @Published public private(set) var status: CaptureConnectionStatus = .discovering
    @Published public private(set) var pairedNode: DiscoveredMacNode?
    @Published public private(set) var activeSession: CaptureSessionCard?
    @Published public private(set) var recentEvents: [CaptureEventRow] = []
    @Published public var keepAliveModeEnabled: Bool = true
    @Published public var selectedPreset: CaptureIntentPreset = .wechatAttachment

    private let discoveryService: MockDeviceDiscoveryService

    public init(discoveryService: MockDeviceDiscoveryService = MockDeviceDiscoveryService()) {
        self.discoveryService = discoveryService
    }

    public func onAppear() {
        guard discoveredNodes.isEmpty else { return }
        discoveredNodes = discoveryService.discoverNodes()
        appendEvent(title: "局域网发现完成", detail: "找到 \(discoveredNodes.count) 台可连接的 Mac。")
    }

    public func pair(with node: DiscoveredMacNode) {
        pairedNode = node
        status = .paired
        appendEvent(title: "完成配对", detail: "当前目标节点：\(node.name)。")
    }

    public func startCapture() {
        let destination = pairedNode ?? discoveryService.discoverNodes().first
        if let destination = destination {
            pairedNode = destination
        }

        status = .streaming
        let sessionID = CaptureSessionID(rawValue: "iphone-\(Int(Date().timeIntervalSince1970))")
        activeSession = CaptureSessionCard(
            id: sessionID.rawValue,
            sessionID: sessionID,
            startedAt: Date(),
            destinationName: destination?.name ?? "未配对 Mac",
            modeLabel: keepAliveModeEnabled ? "可恢复长会话" : "快捷采集",
            bufferedChunkCount: 3
        )

        appendEvent(
            title: "开始推流",
            detail: "iPhone 端仅保留极小 ring buffer，视频块持续送往 Mac。"
        )
        appendEvent(
            title: "关键帧策略已启用",
            detail: "Mac 端会负责抽关键帧、运行 OCR 与 MiniCPM。"
        )
    }

    public func stopCapture() {
        if let activeSession = activeSession {
            appendEvent(
                title: "结束会话",
                detail: "会话 \(activeSession.sessionID.rawValue) 已停止，等待 Mac 清理热数据区。"
            )
        }
        self.activeSession = nil
        status = pairedNode == nil ? .disconnected : .paired
    }

    private func appendEvent(title: String, detail: String) {
        recentEvents.insert(
            CaptureEventRow(
                id: UUID().uuidString,
                timestamp: Date(),
                title: title,
                detail: detail
            ),
            at: 0
        )
    }

    public func replaceDiscoveredNodes(_ nodes: [DiscoveredMacNode]) {
        discoveredNodes = nodes
    }

    public func updateConnection(status: CaptureConnectionStatus, pairedNode: DiscoveredMacNode? = nil) {
        self.status = status
        if let pairedNode = pairedNode {
            self.pairedNode = pairedNode
        }
    }

    public func beginExternalSession(sessionID: CaptureSessionID, destinationName: String, modeLabel: String) {
        status = .streaming
        activeSession = CaptureSessionCard(
            id: sessionID.rawValue,
            sessionID: sessionID,
            startedAt: Date(),
            destinationName: destinationName,
            modeLabel: modeLabel,
            bufferedChunkCount: activeSession?.bufferedChunkCount ?? 0
        )
    }

    public func updateBufferedChunkCount(_ count: Int) {
        guard let activeSession = activeSession else { return }
        self.activeSession = CaptureSessionCard(
            id: activeSession.id,
            sessionID: activeSession.sessionID,
            startedAt: activeSession.startedAt,
            destinationName: activeSession.destinationName,
            modeLabel: activeSession.modeLabel,
            bufferedChunkCount: count
        )
    }

    public func endExternalSession() {
        activeSession = nil
        status = pairedNode == nil ? .disconnected : .paired
    }

    public func logEvent(title: String, detail: String) {
        appendEvent(title: title, detail: detail)
    }
}

@MainActor
public final class MacIngestViewModel: ObservableObject {
    @Published public private(set) var runtimeDescriptor = MiniCPMRuntimeDescriptor()
    @Published public private(set) var sessions: [IngestSessionCard] = []
    @Published public private(set) var observationPreviews: [ObservationPreview] = []
    @Published public private(set) var reviewQueue: [ReviewQueueCard] = []
    @Published public private(set) var evaluationReports: [EvaluationReportCard] = []
    @Published public private(set) var pipelinePanels: [PipelinePanelItem] = []
    @Published public private(set) var recipeLabels: [String] = []

    public init() {}

    public func loadDemoState() {
        guard sessions.isEmpty else { return }

        let demo = DemoStateFactory().make()
        sessions = demo.sessions
        observationPreviews = demo.observationPreviews
        pipelinePanels = demo.pipelinePanels
        recipeLabels = demo.recipeLabels
    }

    public func upsertSession(_ session: IngestSessionCard) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.insert(session, at: 0)
        }
    }

    public func prependObservationPreview(_ preview: ObservationPreview, limit: Int = 8) {
        observationPreviews.insert(preview, at: 0)
        if observationPreviews.count > limit {
            observationPreviews = Array(observationPreviews.prefix(limit))
        }
    }

    public func appendPipelineLine(panelID: String, line: String) {
        guard let index = pipelinePanels.firstIndex(where: { $0.id == panelID }) else { return }
        var panel = pipelinePanels[index]
        panel = PipelinePanelItem(
            id: panel.id,
            title: panel.title,
            summary: panel.summary,
            lines: panel.lines + [line]
        )
        pipelinePanels[index] = panel
    }

    public func setRecipeLabels(_ labels: [String]) {
        recipeLabels = labels
    }

    public func replacePipelinePanels(_ panels: [PipelinePanelItem]) {
        pipelinePanels = panels
    }

    public func replaceReviewQueue(_ items: [LowConfidenceReviewItem]) {
        reviewQueue = items.map { item in
            let fieldLines = item.predictedFields.keys.sorted().map { key in
                "\(key)=\(item.predictedFields[key] ?? "")"
            }
            let missing = item.missingRequiredFields.isEmpty ? "字段完整" : "缺少: " + item.missingRequiredFields.joined(separator: ", ")
            return ReviewQueueCard(
                id: item.id,
                title: "\(item.recipeID) · \(Int(item.confidence * 100))%",
                subtitle: "\(item.sessionID.rawValue) / \(item.frameID.rawValue) · \(missing)",
                predictedFields: fieldLines,
                evidenceLocators: item.evidenceLocators
            )
        }
    }

    public func replaceEvaluationReports(_ reports: [RecipeEvaluationReport]) {
        evaluationReports = reports.map { report in
            let lines = report.fieldSummaries.map { summary -> String in
                let accuracy = Int((summary.accuracy * 100).rounded())
                return "\(summary.fieldName): \(accuracy)% (\(summary.matchedCount)/\(summary.totalCount))"
            }
            return EvaluationReportCard(
                id: report.recipeID,
                title: report.recipeID,
                subtitle: "v\(report.recipeVersion) · \(report.sampleCount) 个标注样本",
                lines: lines.isEmpty ? ["暂无字段准确率"] : lines
            )
        }
    }

    public func resetLiveState(recipeLabels: [String], pipelinePanels: [PipelinePanelItem]) {
        sessions = []
        observationPreviews = []
        reviewQueue = []
        evaluationReports = []
        self.pipelinePanels = pipelinePanels
        self.recipeLabels = recipeLabels
    }
}

private struct DemoState {
    let sessions: [IngestSessionCard]
    let observationPreviews: [ObservationPreview]
    let pipelinePanels: [PipelinePanelItem]
    let recipeLabels: [String]
}

private struct DemoStateFactory {
    func make() -> DemoState {
        let repository = makeRepository()
        let expensePipeline = WeeklyExpenseSummaryPipeline(repository: repository)
        let attachmentPipeline = AttachmentSearchPipeline(repository: repository)
        let savedPipeline = SavedVideoTimelinePipeline(repository: repository)

        let weeklyInterval = DateInterval(
            start: date("2026-03-15T00:00:00+08:00"),
            end: date("2026-03-22T00:00:00+08:00")
        )
        let expenseReport = expensePipeline.run(interval: weeklyInterval, sources: [.alipay, .meituan, .didi])
        let attachments = attachmentPipeline.run(
            participantName: "陈攀",
            fileNameQuery: "宇树G1人形机器人操作经验手册.pdf"
        )
        let savedVideos = savedPipeline.run(interval: weeklyInterval, sources: [.douyin, .kuaishou, .xiaohongshu, .channels])
        let merged = makeMergedObservations()

        let sessionCard = IngestSessionCard(
            id: "ingest-1",
            sourceDeviceName: "A 的 iPhone",
            sessionID: merged.sessionID.rawValue,
            stateLabel: "关键帧已抽样，正在做 session merge",
            keyframeCount: merged.evidenceFrameIDs.count,
            mergedObservationCount: merged.textObservations.count + merged.fileReferences.count + merged.eventObservations.count
        )

        let observationPreviews = merged.textObservations.prefix(2).map {
            ObservationPreview(
                id: $0.id,
                badge: "UI Text",
                title: $0.text,
                subtitle: "置信度 \((Int($0.confidence * 100)))%"
            )
        } + merged.fileReferences.map {
            ObservationPreview(
                id: $0.id,
                badge: "File Ref",
                title: $0.fileName,
                subtitle: $0.resolvedPath ?? "待下载定位"
            )
        }

        let expensePanel = PipelinePanelItem(
            id: "expense",
            title: "Weekly Expense Summary",
            summary: "跨支付宝 / 美团 / 滴滴的本周消费汇总。",
            lines: expenseReport.rows.map { row in
                "\(row.category.rawValue): \(row.totalAmount) CNY / \(row.transactionCount) 笔"
            }
        )

        let attachmentPanel = PipelinePanelItem(
            id: "attachment",
            title: "Attachment Search",
            summary: "会话上下文驱动的附件检索结果。",
            lines: attachments.map {
                "\($0.fileName) · \($0.senderName) · \($0.conversationTitle)"
            }
        )

        let savedPanel = PipelinePanelItem(
            id: "saved-video",
            title: "Saved Video Timeline",
            summary: "收藏时快照，而不是当前点赞数。",
            lines: savedVideos.map {
                "\($0.platform.rawValue) · \($0.title) · 点赞 \($0.likeCountAtCollection ?? 0)"
            }
        )

        let recipes = DefaultRecipes.all.map { "\($0.platform.rawValue): \($0.pageKind)" }

        return DemoState(
            sessions: [sessionCard],
            observationPreviews: observationPreviews,
            pipelinePanels: [expensePanel, attachmentPanel, savedPanel],
            recipeLabels: recipes
        )
    }

    private func makeMergedObservations() -> MergedSessionObservations {
        let merger = SessionMerger()
        let sessionID: CaptureSessionID = "session-demo-001"
        let frame1: FrameID = "frame-001"
        let frame2: FrameID = "frame-002"

        let batch1 = ObservationBatch(
            sessionID: sessionID,
            frameID: frame1,
            platform: .wechat,
            pageKind: "conversation",
            recipeID: DefaultRecipes.wechatConversation.id,
            capturedAt: date("2026-03-20T08:58:00+08:00"),
            texts: [
                UITextObservation(
                    id: "text-1",
                    frameID: frame1,
                    observedAt: date("2026-03-20T08:58:00+08:00"),
                    text: "陈攀",
                    role: "participant",
                    confidence: 0.97
                ),
                UITextObservation(
                    id: "text-2",
                    frameID: frame1,
                    observedAt: date("2026-03-20T08:58:01+08:00"),
                    text: "把宇树G1人形机器人操作经验手册.pdf 发你了",
                    role: "message",
                    confidence: 0.93
                )
            ],
            events: [
                UIEventObservation(
                    id: "event-1",
                    frameID: frame1,
                    observedAt: date("2026-03-20T08:58:02+08:00"),
                    kind: .tapAttachment,
                    targetLabel: "宇树G1人形机器人操作经验手册.pdf",
                    confidence: 0.9
                )
            ],
            confidence: 0.92
        )

        let batch2 = ObservationBatch(
            sessionID: sessionID,
            frameID: frame2,
            platform: .wechat,
            pageKind: "conversation",
            recipeID: DefaultRecipes.wechatConversation.id,
            capturedAt: date("2026-03-20T08:58:03+08:00"),
            fileReferences: [
                FileReferenceObservation(
                    id: "file-1",
                    frameID: frame2,
                    observedAt: date("2026-03-20T08:58:03+08:00"),
                    fileName: "宇树G1人形机器人操作经验手册.pdf",
                    resolvedPath: "/Users/a/Downloads/unitree-g1-manual.pdf",
                    mimeType: "application/pdf",
                    confidence: 0.95
                )
            ],
            confidence: 0.94
        )

        return merger.merge([batch1, batch2])!
    }

    private func makeRepository() -> InMemoryMINDRepository {
        let repository = InMemoryMINDRepository()

        let evidence = EvidenceRef(
            id: "ev-demo-1",
            locator: "frame://session-demo-001/frame-002",
            source: .wechat,
            confidence: 0.94,
            retained: true
        )

        repository.add(identity: Identity(id: "id:self", displayName: "我"))
        repository.add(identity: Identity(id: "id:chenpan", displayName: "陈攀", aliases: ["攀哥"]))
        repository.add(conversation: Conversation(
            id: "conv:wechat:chenpan",
            source: .wechat,
            title: "陈攀",
            participantIDs: ["id:self", "id:chenpan"],
            lastMessageAt: date("2026-03-20T09:00:00+08:00"),
            evidenceRefs: [evidence]
        ))
        repository.add(fileAsset: FileAsset(
            id: "file:unitree-manual",
            canonicalName: "宇树G1人形机器人操作经验手册.pdf",
            localPath: "/Users/a/Downloads/unitree-g1-manual.pdf",
            blobID: "blob:file:unitree-manual",
            evidenceRefs: [evidence]
        ))
        repository.add(message: Message(
            id: "msg:manual",
            conversationID: "conv:wechat:chenpan",
            senderIdentityID: "id:chenpan",
            text: "把宇树G1人形机器人操作经验手册.pdf 发你了",
            sentAt: date("2026-03-20T09:00:00+08:00"),
            attachmentIDs: ["att:manual"],
            evidenceRefs: [evidence]
        ))
        repository.add(attachment: Attachment(
            id: "att:manual",
            messageID: "msg:manual",
            fileAssetID: "file:unitree-manual",
            fileName: "宇树G1人形机器人操作经验手册.pdf",
            mimeType: "application/pdf",
            evidenceRefs: [evidence]
        ))

        repository.add(merchant: Merchant(id: "merchant:coffee", name: "Manner Coffee"))
        repository.add(merchant: Merchant(id: "merchant:haidilao", name: "海底捞"))
        repository.add(merchant: Merchant(id: "merchant:meituan", name: "美团闪购"))
        repository.add(order: Order(id: "order:coffee", source: .alipay, externalID: "ALP-001", title: "咖啡"))
        repository.add(order: Order(id: "order:hotpot", source: .meituan, externalID: "MT-001", title: "火锅晚餐"))
        repository.add(order: Order(id: "order:battery", source: .meituan, externalID: "MT-002", title: "电池"))
        repository.add(trip: Trip(
            id: "trip:didi:1",
            source: .didi,
            startedAt: date("2026-03-18T08:00:00+08:00"),
            endedAt: date("2026-03-18T08:45:00+08:00"),
            routeSummary: "浦东机场 -> 张江"
        ))
        repository.add(expense: Expense(
            id: "exp:coffee",
            source: .alipay,
            amount: 38.0,
            currency: "CNY",
            occurredAt: date("2026-03-17T10:15:00+08:00"),
            merchantID: "merchant:coffee",
            orderID: "order:coffee"
        ))
        repository.add(expense: Expense(
            id: "exp:didi",
            source: .didi,
            amount: 86.0,
            currency: "CNY",
            occurredAt: date("2026-03-18T08:45:00+08:00"),
            tripID: "trip:didi:1"
        ))
        repository.add(expense: Expense(
            id: "exp:hotpot",
            source: .meituan,
            amount: 56.0,
            currency: "CNY",
            occurredAt: date("2026-03-19T20:00:00+08:00"),
            merchantID: "merchant:haidilao",
            orderID: "order:hotpot"
        ))
        repository.add(expense: Expense(
            id: "exp:battery",
            source: .meituan,
            amount: 120.0,
            currency: "CNY",
            occurredAt: date("2026-03-20T11:30:00+08:00"),
            merchantID: "merchant:meituan",
            orderID: "order:battery"
        ))

        let contentEvidence = EvidenceRef(
            id: "ev-demo-2",
            locator: "frame://session-demo-002/frame-010",
            source: .douyin,
            confidence: 0.91,
            retained: true
        )
        repository.add(contentItem: ContentItem(
            id: "content:douyin:g1",
            source: .douyin,
            title: "宇树 G1 上手体验",
            creatorName: "机器人研究员",
            permalink: "https://douyin.example/g1",
            evidenceRefs: [contentEvidence]
        ))
        repository.add(metricSnapshot: MetricSnapshot(
            id: "metric:douyin:g1",
            contentItemID: "content:douyin:g1",
            capturedAt: date("2026-03-16T21:00:00+08:00"),
            likeCount: 512,
            evidenceRefs: [contentEvidence]
        ))
        repository.add(collectionEvent: CollectionEvent(
            id: "collect:douyin:g1",
            contentItemID: "content:douyin:g1",
            source: .douyin,
            collectedAt: date("2026-03-16T21:00:00+08:00"),
            metricSnapshotID: "metric:douyin:g1",
            evidenceRefs: [contentEvidence]
        ))

        repository.add(contentItem: ContentItem(
            id: "content:xhs:tokyo",
            source: .xiaohongshu,
            title: "东京差旅咖啡地图",
            creatorName: "Yuki",
            permalink: "https://xhs.example/tokyo",
            evidenceRefs: [contentEvidence]
        ))
        repository.add(metricSnapshot: MetricSnapshot(
            id: "metric:xhs:tokyo",
            contentItemID: "content:xhs:tokyo",
            capturedAt: date("2026-03-18T18:20:00+08:00"),
            likeCount: 89,
            evidenceRefs: [contentEvidence]
        ))
        repository.add(collectionEvent: CollectionEvent(
            id: "collect:xhs:tokyo",
            contentItemID: "content:xhs:tokyo",
            source: .xiaohongshu,
            collectedAt: date("2026-03-18T18:20:00+08:00"),
            metricSnapshotID: "metric:xhs:tokyo",
            evidenceRefs: [contentEvidence]
        ))

        return repository
    }

    private func date(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withColonSeparatorInTimeZone]
        guard let output = formatter.date(from: value) else {
            fatalError("Invalid date \(value)")
        }
        return output
    }
}
