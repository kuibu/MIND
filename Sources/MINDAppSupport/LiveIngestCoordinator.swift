import Foundation
import MINDPipelines
import MINDProtocol
import MINDRecipes
import MINDSchemas
import MINDServices

public struct LiveFrameIngestUpdate {
    public let session: IngestSessionCard
    public let observationPreviews: [ObservationPreview]

    public init(session: IngestSessionCard, observationPreviews: [ObservationPreview]) {
        self.session = session
        self.observationPreviews = observationPreviews
    }
}

public struct LiveSessionCompletion {
    public let session: IngestSessionCard
    public let pipelinePanels: [PipelinePanelItem]
    public let commitSummaryLines: [String]

    public init(session: IngestSessionCard, pipelinePanels: [PipelinePanelItem], commitSummaryLines: [String]) {
        self.session = session
        self.pipelinePanels = pipelinePanels
        self.commitSummaryLines = commitSummaryLines
    }
}

public final class LiveIngestCoordinator {
    private struct SessionState {
        let manifest: CaptureSessionManifest
        let sourceDeviceName: String
        let recipe: GUIRecipe
        let sessionHint: String?
        var keyframeCount: Int
        var batches: [ObservationBatch]
        var savedPathsByFrameID: [FrameID: String]
    }

    private let repository: InMemoryMINDRepository
    private let recipeRegistry: RecipeRegistry
    private let extractor: VisionExtractor
    private let merger: SessionMerger
    private let calendar: Calendar
    private let now: () -> Date

    private var sessionStates: [CaptureSessionID: SessionState] = [:]

    public init(
        repository: InMemoryMINDRepository = InMemoryMINDRepository(),
        recipeRegistry: RecipeRegistry = RecipeRegistry(),
        extractor: VisionExtractor = HeuristicVisionExtractor(),
        merger: SessionMerger = SessionMerger(),
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.repository = repository
        self.recipeRegistry = recipeRegistry
        self.extractor = extractor
        self.merger = merger
        self.calendar = calendar
        self.now = now
        ensureOwnerIdentity()
    }

    public func recipeLabels() -> [String] {
        DefaultRecipes.all.map { "\($0.platform.rawValue): \($0.pageKind)" }
    }

    public func initialPipelinePanels() -> [PipelinePanelItem] {
        [
            PipelinePanelItem(
                id: "expense",
                title: "Weekly Expense Summary",
                summary: "等待支付宝 / 美团 / 滴滴消费凭证进入 canonical 资源层。",
                lines: ["暂无数据"]
            ),
            PipelinePanelItem(
                id: "attachment",
                title: "Attachment Search",
                summary: "等待微信会话与附件索引建立。",
                lines: ["暂无数据"]
            ),
            PipelinePanelItem(
                id: "saved-video",
                title: "Saved Video Timeline",
                summary: "等待抖音 / 快手 / 小红书 / 视频号的收藏快照进入时间线。",
                lines: ["暂无数据"]
            )
        ]
    }

    public func startSession(from message: StreamMessage) -> IngestSessionCard? {
        guard
            let sessionIDRaw = message.sessionID,
            let platform = message.platformHint,
            let recipe = recipeRegistry.defaultRecipe(for: platform)
        else {
            return nil
        }

        let sessionID = CaptureSessionID(rawValue: sessionIDRaw)
        let manifest = CaptureSessionManifest(
            sessionID: sessionID,
            deviceID: message.deviceID ?? "unknown-device",
            deviceKind: .iphone,
            startedAt: message.sentAt,
            platformHint: platform,
            tags: ["recipe_id": recipe.id]
        )

        sessionStates[sessionID] = SessionState(
            manifest: manifest,
            sourceDeviceName: message.deviceName ?? "未知 iPhone",
            recipe: recipe,
            sessionHint: message.note,
            keyframeCount: 0,
            batches: [],
            savedPathsByFrameID: [:]
        )

        return makeSessionCard(
            sessionID: sessionID,
            sourceDeviceName: message.deviceName ?? "未知 iPhone",
            stateLabel: "已建会话，等待关键帧",
            keyframeCount: 0,
            mergedObservationCount: 0
        )
    }

    public func ingestKeyframe(from message: StreamMessage, imagePath: String?) -> LiveFrameIngestUpdate? {
        guard
            let sessionIDRaw = message.sessionID,
            let frameIDRaw = message.frameID
        else {
            return nil
        }

        let sessionID = CaptureSessionID(rawValue: sessionIDRaw)
        guard var state = sessionStates[sessionID] else {
            return nil
        }

        let frameID = FrameID(rawValue: frameIDRaw)
        let keyframe = Keyframe(
            id: frameID,
            sessionID: sessionID,
            ordinal: message.chunkSequence ?? (state.keyframeCount + 1),
            capturedAt: message.sentAt,
            sourcePlatform: state.recipe.platform,
            imagePath: imagePath ?? "",
            transcriptHint: message.note,
            ocrText: []
        )
        let frameContext = FrameContext(
            keyframe: keyframe,
            neighboringText: [],
            sessionMetadata: ["session_note": state.sessionHint ?? ""]
        )

        guard let batch = try? extractor.extract(frame: frameContext, using: state.recipe) else {
            return nil
        }

        state.keyframeCount += 1
        state.batches.append(batch)
        if let imagePath = imagePath {
            state.savedPathsByFrameID[frameID] = imagePath
        }
        sessionStates[sessionID] = state

        let mergedCount = mergedObservationCount(for: batch)
        let sessionCard = makeSessionCard(
            sessionID: sessionID,
            sourceDeviceName: state.sourceDeviceName,
            stateLabel: "关键帧已抽取，等待 commit",
            keyframeCount: state.keyframeCount,
            mergedObservationCount: mergedCount
        )

        return LiveFrameIngestUpdate(
            session: sessionCard,
            observationPreviews: previews(for: batch)
        )
    }

    public func stopSession(from message: StreamMessage) -> LiveSessionCompletion? {
        guard let sessionIDRaw = message.sessionID else {
            return nil
        }
        let sessionID = CaptureSessionID(rawValue: sessionIDRaw)
        guard let state = sessionStates.removeValue(forKey: sessionID) else {
            return nil
        }
        guard let merged = merger.merge(state.batches) else {
            let session = makeSessionCard(
                sessionID: sessionID,
                sourceDeviceName: state.sourceDeviceName,
                stateLabel: "会话已结束，无有效 observation",
                keyframeCount: state.keyframeCount,
                mergedObservationCount: 0
            )
            return LiveSessionCompletion(session: session, pipelinePanels: initialPipelinePanels(), commitSummaryLines: ["未抽取到结构化数据"])
        }

        let commitSummaryLines = commit(merged: merged, state: state)
        let session = makeSessionCard(
            sessionID: sessionID,
            sourceDeviceName: state.sourceDeviceName,
            stateLabel: "会话已结束并完成 canonical commit",
            keyframeCount: state.keyframeCount,
            mergedObservationCount: merged.textObservations.count + merged.fileReferences.count + merged.eventObservations.count
        )

        return LiveSessionCompletion(
            session: session,
            pipelinePanels: buildPipelinePanels(),
            commitSummaryLines: commitSummaryLines
        )
    }

    private func previews(for batch: ObservationBatch) -> [ObservationPreview] {
        let textPreviews = batch.texts.prefix(3).map {
            ObservationPreview(
                id: $0.id,
                badge: $0.role.map(roleBadge(for:)) ?? "UI Text",
                title: $0.text,
                subtitle: "置信度 \(Int($0.confidence * 100))%"
            )
        }
        let filePreviews = batch.fileReferences.map {
            ObservationPreview(
                id: $0.id,
                badge: "File Ref",
                title: $0.fileName,
                subtitle: $0.resolvedPath ?? "待定位"
            )
        }
        return Array((filePreviews + textPreviews).prefix(4))
    }

    private func roleBadge(for role: String) -> String {
        switch role {
        case "participant":
            return "Participant"
        case "message":
            return "Message"
        case "merchant":
            return "Merchant"
        case "amount":
            return "Amount"
        case "title":
            return "Title"
        case "like_count":
            return "Likes"
        default:
            return "UI Text"
        }
    }

    private func mergedObservationCount(for batch: ObservationBatch) -> Int {
        batch.texts.count + batch.fileReferences.count + batch.events.count
    }

    private func makeSessionCard(
        sessionID: CaptureSessionID,
        sourceDeviceName: String,
        stateLabel: String,
        keyframeCount: Int,
        mergedObservationCount: Int
    ) -> IngestSessionCard {
        IngestSessionCard(
            id: sessionID.rawValue,
            sourceDeviceName: sourceDeviceName,
            sessionID: sessionID.rawValue,
            stateLabel: stateLabel,
            keyframeCount: keyframeCount,
            mergedObservationCount: mergedObservationCount
        )
    }

    private func buildPipelinePanels() -> [PipelinePanelItem] {
        let interval = recentWeekInterval()

        let expenseReport = WeeklyExpenseSummaryPipeline(repository: repository)
            .run(interval: interval, sources: [.alipay, .meituan, .didi])
        let expenseLines = expenseReport.rows.isEmpty
            ? ["暂无数据"]
            : expenseReport.rows.map { row in
                "\(row.category.rawValue): \(formatAmount(row.totalAmount)) CNY / \(row.transactionCount) 笔"
            }

        let attachmentResults = AttachmentSearchPipeline(repository: repository)
            .run(participantName: "陈攀", fileNameQuery: "宇树G1人形机器人操作经验手册.pdf")
        let attachmentLines = attachmentResults.isEmpty
            ? ["暂无数据"]
            : attachmentResults.map {
                "\($0.fileName) · \($0.senderName) · \($0.conversationTitle)"
            }

        let savedVideoResults = SavedVideoTimelinePipeline(repository: repository)
            .run(interval: interval, sources: [.douyin, .kuaishou, .xiaohongshu, .channels])
        let savedVideoLines = savedVideoResults.isEmpty
            ? ["暂无数据"]
            : savedVideoResults.map {
                "\($0.platform.rawValue) · \($0.title) · 点赞 \($0.likeCountAtCollection ?? 0)"
            }

        return [
            PipelinePanelItem(
                id: "expense",
                title: "Weekly Expense Summary",
                summary: "跨支付宝 / 美团 / 滴滴的本周消费汇总。",
                lines: expenseLines
            ),
            PipelinePanelItem(
                id: "attachment",
                title: "Attachment Search",
                summary: "会话上下文驱动的附件检索结果。",
                lines: attachmentLines
            ),
            PipelinePanelItem(
                id: "saved-video",
                title: "Saved Video Timeline",
                summary: "收藏时快照，而不是当前点赞数。",
                lines: savedVideoLines
            )
        ]
    }

    private func recentWeekInterval() -> DateInterval {
        let anchors = repository.expenses.map(\.occurredAt)
            + repository.collectionEvents.map(\.collectedAt)
            + repository.messages.map(\.sentAt)
        let anchor = anchors.max() ?? now()
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: anchor)) ?? anchor
        let start = calendar.date(byAdding: .day, value: -7, to: end) ?? end.addingTimeInterval(-7 * 24 * 60 * 60)
        return DateInterval(start: start, end: end)
    }

    private func commit(merged: MergedSessionObservations, state: SessionState) -> [String] {
        switch merged.platform {
        case .wechat:
            return commitWechatSession(merged: merged, state: state)
        case .alipay, .meituan, .didi:
            return commitExpenseSession(merged: merged, state: state)
        case .douyin, .kuaishou, .xiaohongshu, .channels:
            return commitCollectionSession(merged: merged, state: state)
        case .manual:
            return ["manual session: no canonical commit"]
        }
    }

    private func commitWechatSession(merged: MergedSessionObservations, state: SessionState) -> [String] {
        let participantName = text(role: "participant", in: merged) ?? "未知联系人"
        let messageText = text(role: "message", in: merged) ?? "捕获到附件"
        let participantID = ensureIdentity(named: participantName)
        let conversationID = stableID(prefix: "conv", components: ["wechat", participantName])
        let evidenceRefs = evidenceRefs(for: merged, state: state)
        if repository.conversations.contains(where: { $0.id == conversationID }) == false {
            repository.add(conversation: Conversation(
                id: conversationID,
                source: .wechat,
                title: participantName,
                participantIDs: ["id:self", participantID],
                lastMessageAt: merged.textObservations.last?.observedAt,
                evidenceRefs: evidenceRefs
            ))
        }

        var summary: [String] = []
        for fileReference in merged.fileReferences {
            let fileAssetID = stableID(prefix: "file", components: [fileReference.fileName])
            if repository.fileAssets.contains(where: { $0.id == fileAssetID }) == false {
                repository.add(fileAsset: FileAsset(
                    id: fileAssetID,
                    canonicalName: fileReference.fileName,
                    localPath: fileReference.resolvedPath,
                    blobID: "blob:" + fileAssetID,
                    evidenceRefs: evidenceRefs
                ))
            }

            let messageID = stableID(prefix: "msg", components: [merged.sessionID.rawValue, fileReference.fileName])
            if repository.messages.contains(where: { $0.id == messageID }) == false {
                repository.add(message: Message(
                    id: messageID,
                    conversationID: conversationID,
                    senderIdentityID: participantID,
                    text: messageText,
                    sentAt: merged.textObservations.last?.observedAt ?? now(),
                    attachmentIDs: [stableID(prefix: "att", components: [merged.sessionID.rawValue, fileReference.fileName])],
                    evidenceRefs: evidenceRefs
                ))
            }

            let attachmentID = stableID(prefix: "att", components: [merged.sessionID.rawValue, fileReference.fileName])
            if repository.attachments.contains(where: { $0.id == attachmentID }) == false {
                repository.add(attachment: Attachment(
                    id: attachmentID,
                    messageID: messageID,
                    fileAssetID: fileAssetID,
                    fileName: fileReference.fileName,
                    mimeType: fileReference.mimeType,
                    evidenceRefs: evidenceRefs
                ))
            }

            summary.append("attachment: \(fileReference.fileName)")
        }

        return summary
    }

    private func commitExpenseSession(merged: MergedSessionObservations, state: SessionState) -> [String] {
        let merchantName = text(role: "merchant", in: merged) ?? defaultMerchantName(for: merged.platform)
        let merchantID = stableID(prefix: "merchant", components: [merchantName])
        if repository.merchants.contains(where: { $0.id == merchantID }) == false {
            repository.add(merchant: Merchant(id: merchantID, name: merchantName))
        }

        let amount = Double(text(role: "amount", in: merged) ?? "") ?? 0
        let occurredAt = parseDate(text(role: "occurred_at", in: merged)) ?? now()
        let evidenceRefs = evidenceRefs(for: merged, state: state)
        let orderTitle = text(role: "order_title", in: merged) ?? text(role: "route", in: merged) ?? merchantName
        let orderID = stableID(prefix: "order", components: [merged.platform.rawValue, orderTitle, occurredAt.ISO8601Format()])
        if repository.orders.contains(where: { $0.id == orderID }) == false {
            repository.add(order: Order(id: orderID, source: merged.platform, externalID: orderID, title: orderTitle))
        }

        var tripID: String?
        if merged.platform == .didi {
            let route = text(role: "route", in: merged)
            let id = stableID(prefix: "trip", components: [orderTitle, occurredAt.ISO8601Format()])
            tripID = id
            if repository.trips.contains(where: { $0.id == id }) == false {
                repository.add(trip: Trip(
                    id: id,
                    source: .didi,
                    startedAt: occurredAt,
                    endedAt: occurredAt,
                    routeSummary: route
                ))
            }
        }

        let expenseID = stableID(prefix: "exp", components: [merged.platform.rawValue, orderTitle, occurredAt.ISO8601Format()])
        if repository.expenses.contains(where: { $0.id == expenseID }) == false {
            repository.add(expense: Expense(
                id: expenseID,
                source: merged.platform,
                amount: amount,
                currency: text(role: "currency", in: merged) ?? "CNY",
                occurredAt: occurredAt,
                merchantID: merchantID,
                orderID: orderID,
                tripID: tripID,
                evidenceRefs: evidenceRefs
            ))
        }

        return ["expense: \(merchantName) \(formatAmount(amount)) CNY"]
    }

    private func commitCollectionSession(merged: MergedSessionObservations, state: SessionState) -> [String] {
        let title = text(role: "title", in: merged) ?? "untitled"
        let collectedAt = parseDate(text(role: "collected_at", in: merged)) ?? now()
        let permalink = text(role: "permalink", in: merged)
        let likeCount = Int(text(role: "like_count", in: merged) ?? "")
        let evidenceRefs = evidenceRefs(for: merged, state: state)

        let contentItemID = stableID(prefix: "content", components: [merged.platform.rawValue, title])
        if repository.contentItems.contains(where: { $0.id == contentItemID }) == false {
            repository.add(contentItem: ContentItem(
                id: contentItemID,
                source: merged.platform,
                title: title,
                creatorName: nil,
                permalink: permalink,
                evidenceRefs: evidenceRefs
            ))
        }

        var metricSnapshotID: String?
        if let likeCount = likeCount {
            let snapshotID = stableID(prefix: "metric", components: [contentItemID, collectedAt.ISO8601Format()])
            metricSnapshotID = snapshotID
            if repository.metricSnapshots.contains(where: { $0.id == snapshotID }) == false {
                repository.add(metricSnapshot: MetricSnapshot(
                    id: snapshotID,
                    contentItemID: contentItemID,
                    capturedAt: collectedAt,
                    likeCount: likeCount,
                    evidenceRefs: evidenceRefs
                ))
            }
        }

        let collectionID = stableID(prefix: "collect", components: [contentItemID, collectedAt.ISO8601Format()])
        if repository.collectionEvents.contains(where: { $0.id == collectionID }) == false {
            repository.add(collectionEvent: CollectionEvent(
                id: collectionID,
                contentItemID: contentItemID,
                source: merged.platform,
                collectedAt: collectedAt,
                metricSnapshotID: metricSnapshotID,
                evidenceRefs: evidenceRefs
            ))
        }

        return ["collection: \(merged.platform.rawValue) \(title)"]
    }

    private func ensureOwnerIdentity() {
        if repository.identities.contains(where: { $0.id == "id:self" }) == false {
            repository.add(identity: Identity(id: "id:self", displayName: "我"))
        }
    }

    private func ensureIdentity(named displayName: String) -> String {
        let id = stableID(prefix: "id", components: [displayName])
        if repository.identities.contains(where: { $0.id == id }) == false {
            repository.add(identity: Identity(id: id, displayName: displayName))
        }
        return id
    }

    private func evidenceRefs(for merged: MergedSessionObservations, state: SessionState) -> [EvidenceRef] {
        merged.evidenceFrameIDs.map { frameID in
            let locator = state.savedPathsByFrameID[frameID] ?? "frame://\(merged.sessionID.rawValue)/\(frameID.rawValue)"
            return EvidenceRef(
                id: stableID(prefix: "ev", components: [merged.sessionID.rawValue, frameID.rawValue]),
                locator: locator,
                source: merged.platform,
                confidence: 0.9,
                retained: true
            )
        }
    }

    private func text(role: String, in merged: MergedSessionObservations) -> String? {
        merged.textObservations.last(where: { $0.role == role })?.text
    }

    private func parseDate(_ raw: String?) -> Date? {
        guard let raw = raw else {
            return nil
        }
        return ISO8601DateFormatter().date(from: raw)
    }

    private func defaultMerchantName(for platform: SourcePlatform) -> String {
        switch platform {
        case .alipay:
            return "支付宝商户"
        case .meituan:
            return "美团商户"
        case .didi:
            return "滴滴出行"
        default:
            return platform.rawValue
        }
    }

    private func formatAmount(_ amount: Double) -> String {
        String(format: "%.1f", amount)
    }

    private func stableID(prefix: String, components: [String]) -> String {
        let normalized = components
            .joined(separator: "|")
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
        return prefix + ":" + normalized
    }
}
