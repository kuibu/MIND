import XCTest
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
}
