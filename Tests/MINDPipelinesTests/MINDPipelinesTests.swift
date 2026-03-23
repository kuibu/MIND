import XCTest
import Network
import MINDAppSupport
import MINDRecipes
import MINDProtocol
import MINDSchemas
import MINDServices
import MINDPipelines

final class MINDPipelinesTests: XCTestCase {
    func testWeeklyExpenseSummaryPipelineGroupsTravelDiningAndOther() {
        let repository = makeRepository()
        let pipeline = WeeklyExpenseSummaryPipeline(repository: repository)
        let interval = DateInterval(start: date("2026-03-15T00:00:00+08:00"), end: date("2026-03-22T00:00:00+08:00"))

        let report = pipeline.run(interval: interval, sources: [.alipay, .meituan, .didi])

        XCTAssertEqual(report.rows.count, 3)
        XCTAssertEqual(report.rows[0].category, .travel)
        XCTAssertEqual(report.rows[0].transactionCount, 1)
        XCTAssertEqual(report.rows[0].totalAmount, 86.0, accuracy: 0.001)

        XCTAssertEqual(report.rows[1].category, .dining)
        XCTAssertEqual(report.rows[1].transactionCount, 2)
        XCTAssertEqual(report.rows[1].totalAmount, 94.0, accuracy: 0.001)

        XCTAssertEqual(report.rows[2].category, .other)
        XCTAssertEqual(report.rows[2].transactionCount, 1)
        XCTAssertEqual(report.rows[2].totalAmount, 120.0, accuracy: 0.001)
    }

    func testAttachmentSearchPipelineReturnsConversationScopedPdf() {
        let repository = makeRepository()
        let pipeline = AttachmentSearchPipeline(repository: repository)

        let results = pipeline.run(
            participantName: "陈攀",
            fileNameQuery: "宇树G1人形机器人操作经验手册.pdf"
        )

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].fileName, "宇树G1人形机器人操作经验手册.pdf")
        XCTAssertEqual(results[0].senderName, "陈攀")
        XCTAssertEqual(results[0].localPath, "/Users/a/Downloads/unitree-g1-manual.pdf")
    }

    func testSavedVideoTimelinePipelineUsesCollectionTimeSnapshot() {
        let repository = makeRepository()
        let pipeline = SavedVideoTimelinePipeline(repository: repository)
        let interval = DateInterval(start: date("2026-03-15T00:00:00+08:00"), end: date("2026-03-22T00:00:00+08:00"))

        let results = pipeline.run(interval: interval, sources: [.douyin, .kuaishou, .xiaohongshu, .channels])

        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].platform, .douyin)
        XCTAssertEqual(results[0].title, "宇树 G1 上手体验")
        XCTAssertEqual(results[0].likeCountAtCollection, 512)
        XCTAssertEqual(results[1].platform, .xiaohongshu)
        XCTAssertEqual(results[1].title, "东京差旅咖啡地图")
        XCTAssertEqual(results[1].likeCountAtCollection, 89)
        XCTAssertLessThan(results[0].collectedAt, results[1].collectedAt)
    }

    func testLiveIngestCoordinatorCommitsWechatAttachmentFlow() {
        let coordinator = LiveIngestCoordinator(store: nil, now: { self.date("2026-03-22T00:00:00+08:00") })
        let sessionID = "session-wechat"

        let started = coordinator.startSession(from: StreamMessage(
            kind: .startSession,
            sentAt: date("2026-03-20T08:58:00+08:00"),
            sessionID: sessionID,
            deviceID: "iphone-1",
            deviceName: "A 的 iPhone",
            platformHint: .wechat,
            note: CaptureIntentPreset.wechatAttachment.sessionNote
        ))

        XCTAssertEqual(started?.stateLabel, "已建会话，等待关键帧")

        let frameUpdate = coordinator.ingestKeyframe(
            from: StreamMessage(
                kind: .keyframe,
                sentAt: date("2026-03-20T08:58:03+08:00"),
                sessionID: sessionID,
                deviceID: "iphone-1",
                deviceName: "A 的 iPhone",
                platformHint: .wechat,
                frameID: "frame-1",
                note: CaptureIntentPreset.wechatAttachment.demoFrameHints[0],
                chunkSequence: 1
            ),
            imagePath: "/tmp/frame-1.jpg"
        )

        XCTAssertEqual(frameUpdate?.session.keyframeCount, 1)
        XCTAssertTrue(frameUpdate?.observationPreviews.contains(where: { $0.title.contains("宇树G1人形机器人操作经验手册.pdf") }) == true)

        let completion = coordinator.stopSession(from: StreamMessage(
            kind: .stopSession,
            sentAt: date("2026-03-20T08:58:05+08:00"),
            sessionID: sessionID,
            deviceID: "iphone-1",
            deviceName: "A 的 iPhone",
            platformHint: .wechat
        ))

        XCTAssertEqual(completion?.session.stateLabel, "会话已结束并完成 canonical commit")
        XCTAssertTrue(completion?.commitSummaryLines.contains("attachment: 宇树G1人形机器人操作经验手册.pdf") == true)
        XCTAssertTrue(completion?.pipelinePanels.first(where: { $0.id == "attachment" })?.lines.contains(where: { $0.contains("宇树G1人形机器人操作经验手册.pdf") }) == true)
    }

    func testReliableStreamClientSmokeTestCommitsWechatAttachmentOverSocket() throws {
        let relayReady = expectation(description: "relay ready")
        let clientConnected = expectation(description: "client connected")
        let sessionCommitted = expectation(description: "session committed")
        let pendingDrained = expectation(description: "pending drained")

        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let relay = SmokeIngestRelay(frameRoot: tempDirectory, now: { self.date("2026-03-22T00:00:00+08:00") })
        var endpoint: NWEndpoint?
        var completion: LiveSessionCompletion?
        relay.onCompletion = { value in
            completion = value
            sessionCommitted.fulfill()
        }
        try relay.start { readyEndpoint in
            endpoint = readyEndpoint
            relayReady.fulfill()
        }

        let client = ReliableStreamClient(
            queue: DispatchQueue(label: "mind.tests.smoke.client"),
            reconnectDelay: 0.2,
            resendInterval: 0.2,
            heartbeatInterval: 10
        )
        var didReportConnected = false
        var sawPendingMessages = false
        var didDrainPending = false
        client.onStateChange = { state in
            guard state == "已连接", didReportConnected == false else { return }
            didReportConnected = true
            clientConnected.fulfill()
        }
        client.onPendingCountChange = { count in
            if count > 0 {
                sawPendingMessages = true
            }
            if sawPendingMessages && count == 0 && didDrainPending == false {
                didDrainPending = true
                pendingDrained.fulfill()
            }
        }

        defer {
            client.disconnect()
            relay.stop()
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        wait(for: [relayReady], timeout: 2.0)
        client.connect(to: try XCTUnwrap(endpoint))
        wait(for: [clientConnected], timeout: 2.0)

        let deviceID = "iphone-smoke"
        let deviceName = "Smoke iPhone"
        let sessionID = "socket-smoke-wechat"
        let frameID = "socket-smoke-frame-1"
        let imageBase64 = Data("smoke-image".utf8).base64EncodedString()

        client.send(StreamMessage(
            kind: .hello,
            deviceID: deviceID,
            deviceName: deviceName,
            platformHint: .wechat,
            note: "ios-capture paired"
        ))
        client.send(StreamMessage(
            kind: .startSession,
            sessionID: sessionID,
            deviceID: deviceID,
            deviceName: deviceName,
            platformHint: .wechat,
            note: CaptureIntentPreset.wechatAttachment.sessionNote
        ))
        client.send(StreamMessage(
            kind: .keyframe,
            sessionID: sessionID,
            deviceID: deviceID,
            deviceName: deviceName,
            platformHint: .wechat,
            frameID: frameID,
            note: CaptureIntentPreset.wechatAttachment.demoFrameHints[0],
            imageBase64: imageBase64,
            chunkSequence: 1,
            width: 1179,
            height: 2556
        ))
        client.send(StreamMessage(
            kind: .stopSession,
            sessionID: sessionID,
            deviceID: deviceID,
            deviceName: deviceName,
            platformHint: .wechat
        ))
        client.disconnectWhenDrained(timeout: 2.0)

        wait(for: [sessionCommitted, pendingDrained], timeout: 5.0)

        let committed = try XCTUnwrap(completion)
        XCTAssertEqual(relay.receivedMessageKinds(), [.hello, .startSession, .keyframe, .stopSession])
        XCTAssertEqual(committed.session.stateLabel, "会话已结束并完成 canonical commit")
        XCTAssertTrue(committed.commitSummaryLines.contains("attachment: 宇树G1人形机器人操作经验手册.pdf"))
        XCTAssertTrue(
            committed.pipelinePanels
                .first(where: { $0.id == "attachment" })?
                .lines
                .contains("宇树G1人形机器人操作经验手册.pdf · 陈攀 · 陈攀") == true
        )
        XCTAssertTrue(
            relay.persistedFramePaths().contains {
                $0.hasSuffix("/\(sessionID)/\(frameID).jpg")
            }
        )
    }

    func testLiveIngestCoordinatorCommitsExpenseFlowsIntoWeeklySummary() {
        let coordinator = LiveIngestCoordinator(store: nil, now: { self.date("2026-03-22T00:00:00+08:00") })

        ingestExpenseSession(
            coordinator: coordinator,
            sessionID: "session-alipay",
            sentAt: "2026-03-17T10:15:00+08:00",
            preset: .alipayExpense
        )
        ingestExpenseSession(
            coordinator: coordinator,
            sessionID: "session-meituan",
            sentAt: "2026-03-19T20:00:00+08:00",
            preset: .meituanExpense
        )
        ingestExpenseSession(
            coordinator: coordinator,
            sessionID: "session-didi",
            sentAt: "2026-03-18T08:45:00+08:00",
            preset: .didiTrip
        )

        let finalCompletion = coordinator.stopSession(from: StreamMessage(
            kind: .stopSession,
            sentAt: date("2026-03-18T08:45:05+08:00"),
            sessionID: "session-didi",
            deviceID: "iphone-1",
            deviceName: "A 的 iPhone",
            platformHint: .didi
        ))

        let expenseLines = finalCompletion?.pipelinePanels.first(where: { $0.id == "expense" })?.lines ?? []
        XCTAssertTrue(expenseLines.contains("差旅: 86.0 CNY / 1 笔"))
        XCTAssertTrue(expenseLines.contains("餐饮: 94.0 CNY / 2 笔"))
    }

    func testLiveIngestCoordinatorCommitsSavedVideoSnapshotsAcrossPlatforms() {
        let coordinator = LiveIngestCoordinator(store: nil, now: { self.date("2026-03-22T00:00:00+08:00") })

        ingestCollectionSession(
            coordinator: coordinator,
            sessionID: "session-douyin",
            sentAt: "2026-03-16T21:00:00+08:00",
            preset: .douyinCollection
        )
        ingestCollectionSession(
            coordinator: coordinator,
            sessionID: "session-xhs",
            sentAt: "2026-03-18T18:20:00+08:00",
            preset: .xiaohongshuCollection
        )

        let completion = coordinator.stopSession(from: StreamMessage(
            kind: .stopSession,
            sentAt: date("2026-03-18T18:20:05+08:00"),
            sessionID: "session-xhs",
            deviceID: "iphone-1",
            deviceName: "A 的 iPhone",
            platformHint: .xiaohongshu
        ))

        let savedLines = completion?.pipelinePanels.first(where: { $0.id == "saved-video" })?.lines ?? []
        XCTAssertTrue(savedLines.first?.contains("douyin · 宇树 G1 上手体验 · 点赞 512") == true)
        XCTAssertTrue(savedLines.last?.contains("xiaohongshu · 东京差旅咖啡地图 · 点赞 89") == true)
    }

    func testDiskCanonicalStorePersistsCommittedResources() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let store = DiskCanonicalStore(fileURL: tempDirectory.appendingPathComponent("canonical-store.json"))
        let coordinator = LiveIngestCoordinator(store: store, extractor: HeuristicVisionExtractor(), now: {
            self.date("2026-03-22T00:00:00+08:00")
        })

        _ = coordinator.startSession(from: StreamMessage(
            kind: .startSession,
            sentAt: date("2026-03-20T08:58:00+08:00"),
            sessionID: "persist-wechat",
            deviceID: "iphone-1",
            deviceName: "A 的 iPhone",
            platformHint: .wechat,
            note: CaptureIntentPreset.wechatAttachment.sessionNote
        ))
        _ = coordinator.ingestKeyframe(
            from: StreamMessage(
                kind: .keyframe,
                sentAt: date("2026-03-20T08:58:03+08:00"),
                sessionID: "persist-wechat",
                deviceID: "iphone-1",
                deviceName: "A 的 iPhone",
                platformHint: .wechat,
                frameID: "frame-1",
                note: CaptureIntentPreset.wechatAttachment.demoFrameHints[0],
                chunkSequence: 1
            ),
            imagePath: "/tmp/frame-1.jpg"
        )
        _ = coordinator.stopSession(from: StreamMessage(
            kind: .stopSession,
            sentAt: date("2026-03-20T08:58:05+08:00"),
            sessionID: "persist-wechat",
            deviceID: "iphone-1",
            deviceName: "A 的 iPhone",
            platformHint: .wechat
        ))

        let loadedRepository = try store.load()
        let pipeline = AttachmentSearchPipeline(repository: loadedRepository)
        let results = pipeline.run(
            participantName: "陈攀",
            fileNameQuery: "宇树G1人形机器人操作经验手册.pdf"
        )

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.fileName, "宇树G1人形机器人操作经验手册.pdf")
    }

    func testSQLiteCanonicalStorePersistsCommittedResources() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let store = SQLiteCanonicalStore(fileURL: tempDirectory.appendingPathComponent("canonical-store.sqlite"))
        let coordinator = LiveIngestCoordinator(store: store, extractor: HeuristicVisionExtractor(), now: {
            self.date("2026-03-22T00:00:00+08:00")
        })

        _ = coordinator.startSession(from: StreamMessage(
            kind: .startSession,
            sentAt: date("2026-03-20T08:58:00+08:00"),
            sessionID: "sqlite-wechat",
            deviceID: "iphone-1",
            deviceName: "A 的 iPhone",
            platformHint: .wechat,
            note: CaptureIntentPreset.wechatAttachment.sessionNote
        ))
        _ = coordinator.ingestKeyframe(
            from: StreamMessage(
                kind: .keyframe,
                sentAt: date("2026-03-20T08:58:03+08:00"),
                sessionID: "sqlite-wechat",
                deviceID: "iphone-1",
                deviceName: "A 的 iPhone",
                platformHint: .wechat,
                frameID: "frame-1",
                note: CaptureIntentPreset.wechatAttachment.demoFrameHints[0],
                chunkSequence: 1
            ),
            imagePath: "/tmp/frame-1.jpg"
        )
        _ = coordinator.stopSession(from: StreamMessage(
            kind: .stopSession,
            sentAt: date("2026-03-20T08:58:05+08:00"),
            sessionID: "sqlite-wechat",
            deviceID: "iphone-1",
            deviceName: "A 的 iPhone",
            platformHint: .wechat
        ))

        let loadedRepository = try store.load()
        let pipeline = AttachmentSearchPipeline(repository: loadedRepository)
        let results = pipeline.run(
            participantName: "陈攀",
            fileNameQuery: "宇树G1人形机器人操作经验手册.pdf"
        )

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.fileName, "宇树G1人形机器人操作经验手册.pdf")
    }

    func testLiveIngestCoordinatorQueuesLowConfidenceReviewAndRetainsEvidence() {
        let coordinator = LiveIngestCoordinator(store: nil, extractor: HeuristicVisionExtractor(), now: {
            self.date("2026-03-22T00:00:00+08:00")
        })
        let sessionID = "review-wechat"

        _ = coordinator.startSession(from: StreamMessage(
            kind: .startSession,
            sentAt: date("2026-03-20T08:58:00+08:00"),
            sessionID: sessionID,
            deviceID: "iphone-1",
            deviceName: "A 的 iPhone",
            platformHint: .wechat,
            note: CaptureIntentPreset.wechatAttachment.sessionNote
        ))

        let frameUpdate = coordinator.ingestKeyframe(
            from: StreamMessage(
                kind: .keyframe,
                sentAt: date("2026-03-20T08:58:03+08:00"),
                sessionID: sessionID,
                deviceID: "iphone-1",
                deviceName: "A 的 iPhone",
                platformHint: .wechat,
                frameID: "frame-review-1",
                note: """
                message=把手册发你了
                file=宇树G1人形机器人操作经验手册.pdf
                path=/Users/a/Downloads/unitree-g1-manual.pdf
                """,
                chunkSequence: 1
            ),
            imagePath: "/tmp/review-frame-1.jpg"
        )

        XCTAssertEqual(frameUpdate?.reviewItems.count, 1)
        XCTAssertEqual(frameUpdate?.reviewItems.first?.missingRequiredFields, ["participant_name"])

        let completion = coordinator.stopSession(from: StreamMessage(
            kind: .stopSession,
            sentAt: date("2026-03-20T08:58:05+08:00"),
            sessionID: sessionID,
            deviceID: "iphone-1",
            deviceName: "A 的 iPhone",
            platformHint: .wechat
        ))

        XCTAssertEqual(completion?.retainedEvidencePaths, ["/tmp/review-frame-1.jpg"])

        guard let reviewID = completion?.reviewItems.first?.id else {
            return XCTFail("Expected review item")
        }
        let replaySample = coordinator.replaySample(
            forReviewID: reviewID,
            expectedFields: [
                "participant_name": "陈攀",
                "message_text": "把手册发你了",
                "attachment_filename": "宇树G1人形机器人操作经验手册.pdf"
            ]
        )

        XCTAssertEqual(replaySample?.recipeID, DefaultRecipes.wechatConversation.id)
        XCTAssertEqual(replaySample?.expectedFields["participant_name"], "陈攀")

        coordinator.resolveReviewItem(reviewID)
        XCTAssertTrue(coordinator.reviewItems().isEmpty)
    }

    func testRecipeEvaluationHarnessComputesFieldAccuracy() throws {
        let registry = RecipeRegistry(recipes: [DefaultRecipes.alipayExpenseReceipt])
        let harness = RecipeEvaluationHarness(extractor: HeuristicVisionExtractor(), recipeRegistry: registry)
        let samples = [
            RecipeReplaySample(
                id: "sample-1",
                recipeID: DefaultRecipes.alipayExpenseReceipt.id,
                recipeVersion: DefaultRecipes.alipayExpenseReceipt.version,
                frame: FrameContext(
                    keyframe: Keyframe(
                        id: "frame-sample-1",
                        sessionID: "session-sample-1",
                        ordinal: 1,
                        capturedAt: date("2026-03-17T10:15:00+08:00"),
                        sourcePlatform: .alipay,
                        imagePath: "/tmp/sample-1.jpg",
                        transcriptHint: CaptureIntentPreset.alipayExpense.demoFrameHints[0]
                    )
                ),
                expectedFields: [
                    "amount": "38.0",
                    "merchant_name": "Manner Coffee",
                    "occurred_at": "2026-03-17T10:15:00+08:00",
                    "order_title": "咖啡"
                ]
            ),
            RecipeReplaySample(
                id: "sample-2",
                recipeID: DefaultRecipes.alipayExpenseReceipt.id,
                recipeVersion: DefaultRecipes.alipayExpenseReceipt.version,
                frame: FrameContext(
                    keyframe: Keyframe(
                        id: "frame-sample-2",
                        sessionID: "session-sample-2",
                        ordinal: 1,
                        capturedAt: date("2026-03-17T10:15:00+08:00"),
                        sourcePlatform: .alipay,
                        imagePath: "/tmp/sample-2.jpg",
                        transcriptHint: CaptureIntentPreset.alipayExpense.demoFrameHints[0]
                    )
                ),
                expectedFields: [
                    "amount": "39.0",
                    "merchant_name": "Manner Coffee",
                    "occurred_at": "2026-03-17T10:15:00+08:00",
                    "order_title": "咖啡"
                ]
            )
        ]

        let reports = try harness.evaluate(samples: samples)
        XCTAssertEqual(reports.count, 1)
        XCTAssertEqual(reports.first?.sampleCount, 2)
        XCTAssertEqual(reports.first?.fieldSummaries.first(where: { $0.fieldName == "amount" })?.matchedCount, 1)
        XCTAssertEqual(reports.first?.fieldSummaries.first(where: { $0.fieldName == "merchant_name" })?.matchedCount, 2)
    }

    func testRecipeEvaluationHarnessUsesExactRecipeVersion() throws {
        let recipeV1 = GUIRecipe(
            id: "demo.manual",
            version: 1,
            platform: .manual,
            pageKind: "test",
            description: "v1",
            prompt: "v1",
            extractionSchema: ExtractionSchemaDescriptor(
                resourceType: "ManualObservation",
                fields: [ExtractionField(name: "version_marker", description: "Version marker")]
            ),
            retentionPolicy: .none,
            confidenceThreshold: 0.8
        )
        let recipeV2 = GUIRecipe(
            id: "demo.manual",
            version: 2,
            platform: .manual,
            pageKind: "test",
            description: "v2",
            prompt: "v2",
            extractionSchema: ExtractionSchemaDescriptor(
                resourceType: "ManualObservation",
                fields: [ExtractionField(name: "version_marker", description: "Version marker")]
            ),
            retentionPolicy: .none,
            confidenceThreshold: 0.8
        )

        let harness = RecipeEvaluationHarness(
            extractor: VersionAwareExtractor(),
            recipeRegistry: RecipeRegistry(recipes: [recipeV1, recipeV2])
        )
        let samples = [
            RecipeReplaySample(
                id: "version-sample-1",
                recipeID: recipeV1.id,
                recipeVersion: 1,
                frame: FrameContext(
                    keyframe: Keyframe(
                        id: "frame-version-1",
                        sessionID: "session-version-1",
                        ordinal: 1,
                        capturedAt: date("2026-03-17T10:15:00+08:00"),
                        sourcePlatform: .manual,
                        imagePath: "/tmp/version-1.jpg"
                    )
                ),
                expectedFields: ["version_marker": "v1"]
            ),
            RecipeReplaySample(
                id: "version-sample-2",
                recipeID: recipeV2.id,
                recipeVersion: 2,
                frame: FrameContext(
                    keyframe: Keyframe(
                        id: "frame-version-2",
                        sessionID: "session-version-2",
                        ordinal: 1,
                        capturedAt: date("2026-03-17T10:16:00+08:00"),
                        sourcePlatform: .manual,
                        imagePath: "/tmp/version-2.jpg"
                    )
                ),
                expectedFields: ["version_marker": "v2"]
            )
        ]

        let reports = try harness.evaluate(samples: samples)
        XCTAssertEqual(reports.count, 2)
        XCTAssertEqual(reports.first(where: { $0.recipeVersion == 1 })?.fieldSummaries.first?.matchedCount, 1)
        XCTAssertEqual(reports.first(where: { $0.recipeVersion == 2 })?.fieldSummaries.first?.matchedCount, 1)
    }

    func testRecipeDatasetStorePersistsSamplesAndReports() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let datasetStore = RecipeDatasetStore(rootURL: tempDirectory)
        let sample = RecipeReplaySample(
            id: "dataset-sample-1",
            recipeID: DefaultRecipes.meituanExpenseReceipt.id,
            recipeVersion: DefaultRecipes.meituanExpenseReceipt.version,
            frame: FrameContext(
                keyframe: Keyframe(
                    id: "frame-dataset-1",
                    sessionID: "session-dataset-1",
                    ordinal: 1,
                    capturedAt: date("2026-03-19T20:00:00+08:00"),
                    sourcePlatform: .meituan,
                    imagePath: "/tmp/dataset-1.jpg",
                    transcriptHint: CaptureIntentPreset.meituanExpense.demoFrameHints[0]
                )
            ),
            expectedFields: [
                "amount": "56.0",
                "merchant_name": "海底捞",
                "occurred_at": "2026-03-19T20:00:00+08:00",
                "order_title": "火锅晚餐"
            ]
        )

        try datasetStore.save(sample: sample)
        let loadedSamples = try datasetStore.loadSamples()
        XCTAssertEqual(loadedSamples.count, 1)
        XCTAssertEqual(loadedSamples.first?.id, sample.id)

        let harness = RecipeEvaluationHarness(
            extractor: HeuristicVisionExtractor(),
            recipeRegistry: RecipeRegistry(recipes: [DefaultRecipes.meituanExpenseReceipt])
        )
        let reports = try datasetStore.evaluate(using: harness)
        XCTAssertEqual(reports.count, 1)
        XCTAssertEqual(try datasetStore.loadReports().first?.recipeID, DefaultRecipes.meituanExpenseReceipt.id)
    }

    func testManualReviewCorrectionRewritesCommittedCanonicalData() {
        let coordinator = LiveIngestCoordinator(store: nil, extractor: HeuristicVisionExtractor(), now: {
            self.date("2026-03-22T00:00:00+08:00")
        })
        let sessionID = "review-fix-wechat"

        _ = coordinator.startSession(from: StreamMessage(
            kind: .startSession,
            sentAt: date("2026-03-20T08:58:00+08:00"),
            sessionID: sessionID,
            deviceID: "iphone-1",
            deviceName: "A 的 iPhone",
            platformHint: .wechat,
            note: CaptureIntentPreset.wechatAttachment.sessionNote
        ))

        _ = coordinator.ingestKeyframe(
            from: StreamMessage(
                kind: .keyframe,
                sentAt: date("2026-03-20T08:58:03+08:00"),
                sessionID: sessionID,
                deviceID: "iphone-1",
                deviceName: "A 的 iPhone",
                platformHint: .wechat,
                frameID: "frame-fix-1",
                note: """
                message=把手册发你了
                file=宇树G1人形机器人操作经验手册.pdf
                path=/Users/a/Downloads/unitree-g1-manual.pdf
                """,
                chunkSequence: 1
            ),
            imagePath: "/tmp/review-fix-frame-1.jpg"
        )

        let completion = coordinator.stopSession(from: StreamMessage(
            kind: .stopSession,
            sentAt: date("2026-03-20T08:58:05+08:00"),
            sessionID: sessionID,
            deviceID: "iphone-1",
            deviceName: "A 的 iPhone",
            platformHint: .wechat
        ))

        XCTAssertEqual(completion?.pipelinePanels.first(where: { $0.id == "attachment" })?.lines, ["暂无数据"])
        guard let reviewID = completion?.reviewItems.first?.id else {
            return XCTFail("Expected a low-confidence review item")
        }

        let correction = coordinator.applyReviewCorrection(
            reviewID,
            correctedFields: [
                "participant_name": "陈攀",
                "message_text": "把手册发你了",
                "attachment_filename": "宇树G1人形机器人操作经验手册.pdf",
                "path": "/Users/a/Downloads/unitree-g1-manual.pdf"
            ]
        )

        XCTAssertEqual(correction?.appliedToCommittedSession, true)
        XCTAssertTrue(correction?.commitSummaryLines.contains("attachment: 宇树G1人形机器人操作经验手册.pdf") == true)
        XCTAssertTrue(
            correction?.pipelinePanels
                .first(where: { $0.id == "attachment" })?
                .lines
                .contains(where: { $0.contains("宇树G1人形机器人操作经验手册.pdf") && $0.contains("陈攀") }) == true
        )
        XCTAssertTrue(coordinator.reviewItems().isEmpty)
    }

    private func makeRepository() -> InMemoryMINDRepository {
        let repository = InMemoryMINDRepository()

        let evidence = EvidenceRef(
            id: "ev-1",
            locator: "frame://session-1/frame-001",
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
            id: "ev-2",
            locator: "frame://session-2/frame-003",
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
        guard let date = formatter.date(from: value) else {
            fatalError("Invalid ISO8601 date: \(value)")
        }
        return date
    }

    private func ingestExpenseSession(
        coordinator: LiveIngestCoordinator,
        sessionID: String,
        sentAt: String,
        preset: CaptureIntentPreset
    ) {
        _ = coordinator.startSession(from: StreamMessage(
            kind: .startSession,
            sentAt: date(sentAt),
            sessionID: sessionID,
            deviceID: "iphone-1",
            deviceName: "A 的 iPhone",
            platformHint: preset.platform,
            note: preset.sessionNote
        ))
        _ = coordinator.ingestKeyframe(
            from: StreamMessage(
                kind: .keyframe,
                sentAt: date(sentAt),
                sessionID: sessionID,
                deviceID: "iphone-1",
                deviceName: "A 的 iPhone",
                platformHint: preset.platform,
                frameID: sessionID + "-frame-1",
                note: preset.demoFrameHints[0],
                chunkSequence: 1
            ),
            imagePath: "/tmp/" + sessionID + ".jpg"
        )
        if preset != .didiTrip {
            _ = coordinator.stopSession(from: StreamMessage(
                kind: .stopSession,
                sentAt: date(sentAt),
                sessionID: sessionID,
                deviceID: "iphone-1",
                deviceName: "A 的 iPhone",
                platformHint: preset.platform
            ))
        }
    }

    private func ingestCollectionSession(
        coordinator: LiveIngestCoordinator,
        sessionID: String,
        sentAt: String,
        preset: CaptureIntentPreset
    ) {
        _ = coordinator.startSession(from: StreamMessage(
            kind: .startSession,
            sentAt: date(sentAt),
            sessionID: sessionID,
            deviceID: "iphone-1",
            deviceName: "A 的 iPhone",
            platformHint: preset.platform,
            note: preset.sessionNote
        ))
        _ = coordinator.ingestKeyframe(
            from: StreamMessage(
                kind: .keyframe,
                sentAt: date(sentAt),
                sessionID: sessionID,
                deviceID: "iphone-1",
                deviceName: "A 的 iPhone",
                platformHint: preset.platform,
                frameID: sessionID + "-frame-1",
                note: preset.demoFrameHints[0],
                chunkSequence: 1
            ),
            imagePath: "/tmp/" + sessionID + ".jpg"
        )
        if preset != .xiaohongshuCollection {
            _ = coordinator.stopSession(from: StreamMessage(
                kind: .stopSession,
                sentAt: date(sentAt),
                sessionID: sessionID,
                deviceID: "iphone-1",
                deviceName: "A 的 iPhone",
                platformHint: preset.platform
            ))
        }
    }
}

private final class VersionAwareExtractor: VisionExtractor {
    func extract(frame: FrameContext, using recipe: GUIRecipe) throws -> ObservationBatch {
        ObservationBatch(
            sessionID: frame.keyframe.sessionID,
            frameID: frame.keyframe.id,
            platform: recipe.platform,
            pageKind: recipe.pageKind,
            recipeID: recipe.id,
            recipeVersion: recipe.version,
            capturedAt: frame.keyframe.capturedAt,
            extractedFields: ["version_marker": "v\(recipe.version)"],
            confidence: 0.99
        )
    }
}

private final class SmokeIngestRelay {
    var onCompletion: ((LiveSessionCompletion) -> Void)?

    private let queue = DispatchQueue(label: "mind.tests.smoke.relay")
    private let coordinator: LiveIngestCoordinator
    private let frameRoot: URL

    private var listener: NWListener?
    private var inboundConnections: [ObjectIdentifier: SmokeInboundConnection] = [:]
    private var receivedMessages: [StreamMessage] = []
    private var persistedFrames: [String] = []

    init(frameRoot: URL, now: @escaping () -> Date) {
        self.frameRoot = frameRoot
        self.coordinator = LiveIngestCoordinator(
            store: nil,
            extractor: HeuristicVisionExtractor(),
            now: now
        )
    }

    func start(onReady: @escaping (NWEndpoint) -> Void) throws {
        let listener = try NWListener(using: .tcp, on: .any)
        self.listener = listener
        listener.stateUpdateHandler = { [weak listener] state in
            guard case .ready = state, let port = listener?.port else { return }
            onReady(.hostPort(host: "127.0.0.1", port: port))
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection: connection)
        }
        listener.start(queue: queue)
    }

    func stop() {
        queue.sync {
            self.listener?.cancel()
            self.listener = nil
            self.inboundConnections.values.forEach { $0.cancel() }
            self.inboundConnections.removeAll()
        }
    }

    func receivedMessageKinds() -> [StreamMessageKind] {
        queue.sync { receivedMessages.map(\.kind) }
    }

    func persistedFramePaths() -> [String] {
        queue.sync { persistedFrames }
    }

    private func accept(connection: NWConnection) {
        let inbound = SmokeInboundConnection(connection: connection)
        inbound.onMessage = { [weak self] message in
            self?.handle(message)
        }
        let identifier = ObjectIdentifier(inbound)
        inbound.onCompletion = { [weak self] in
            self?.inboundConnections.removeValue(forKey: identifier)
        }
        inboundConnections[identifier] = inbound
        inbound.start(queue: queue)
    }

    private func handle(_ message: StreamMessage) {
        receivedMessages.append(message)

        switch message.kind {
        case .hello, .ack, .resumeSession, .heartbeat:
            break
        case .startSession:
            _ = coordinator.startSession(from: message)
        case .keyframe:
            let imagePath = persistImageIfPresent(for: message)
            _ = coordinator.ingestKeyframe(from: message, imagePath: imagePath?.path)
        case .stopSession:
            if let completion = coordinator.stopSession(from: message) {
                onCompletion?(completion)
            }
        }
    }

    private func persistImageIfPresent(for message: StreamMessage) -> URL? {
        guard let sessionID = message.sessionID,
              let frameID = message.frameID,
              let imageBase64 = message.imageBase64,
              let data = Data(base64Encoded: imageBase64) else {
            return nil
        }

        let sessionDirectory = frameRoot.appendingPathComponent(sessionID, isDirectory: true)
        try? FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
        let destination = sessionDirectory.appendingPathComponent(frameID + ".jpg")
        do {
            try data.write(to: destination, options: .atomic)
            persistedFrames.append(destination.path)
            return destination
        } catch {
            return nil
        }
    }
}

private final class SmokeInboundConnection {
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

            if let data = data, data.isEmpty == false {
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
            guard line.isEmpty == false,
                  let message = try? StreamMessageCodec.decodeLine(line) else {
                continue
            }
            sendAck(for: message)
            onMessage?(message)
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
            deviceID: "mac-smoke",
            deviceName: "Smoke Relay",
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
