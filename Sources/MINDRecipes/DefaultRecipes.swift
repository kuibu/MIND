import Foundation
import MINDProtocol

public enum DefaultRecipes {
    public static let wechatConversation = GUIRecipe(
        id: "wechat.conversation.v1",
        platform: .wechat,
        pageKind: "conversation",
        description: "抽取微信会话中的消息、附件与文件引用。",
        prompt: "识别当前微信聊天页面中的联系人、消息文本、附件卡片与文件名。",
        extractionSchema: ExtractionSchemaDescriptor(
            resourceType: "ConversationObservation",
            fields: [
                ExtractionField(name: "participant_name", description: "当前会话联系人或群名"),
                ExtractionField(name: "message_text", description: "可见消息文本", required: false),
                ExtractionField(name: "attachment_filename", description: "可见附件文件名", required: false)
            ]
        ),
        retentionPolicy: .lowConfidenceOnly,
        confidenceThreshold: 0.82
    )

    public static let alipayExpenseReceipt = GUIRecipe(
        id: "alipay.expense-receipt.v1",
        platform: .alipay,
        pageKind: "expense_receipt",
        description: "抽取支付宝支付详情中的金额、商户、时间和订单信息。",
        prompt: "识别当前支付详情页面中的金额、商户名称、时间、订单号和订单标题。",
        extractionSchema: ExtractionSchemaDescriptor(
            resourceType: "ExpenseObservation",
            fields: [
                ExtractionField(name: "amount", description: "支付金额"),
                ExtractionField(name: "merchant_name", description: "商户名称"),
                ExtractionField(name: "occurred_at", description: "交易时间"),
                ExtractionField(name: "order_title", description: "订单标题", required: false)
            ]
        ),
        retentionPolicy: .lowConfidenceOnly,
        confidenceThreshold: 0.88
    )

    public static let meituanExpenseReceipt = GUIRecipe(
        id: "meituan.expense-receipt.v1",
        platform: .meituan,
        pageKind: "expense_receipt",
        description: "抽取美团订单详情中的金额、商户、时间和订单信息。",
        prompt: "识别当前订单详情中的金额、商户名称、时间和订单标题。",
        extractionSchema: ExtractionSchemaDescriptor(
            resourceType: "ExpenseObservation",
            fields: [
                ExtractionField(name: "amount", description: "订单金额"),
                ExtractionField(name: "merchant_name", description: "商户名称"),
                ExtractionField(name: "occurred_at", description: "订单时间"),
                ExtractionField(name: "order_title", description: "订单标题", required: false)
            ]
        ),
        retentionPolicy: .lowConfidenceOnly,
        confidenceThreshold: 0.86
    )

    public static let didiTripReceipt = GUIRecipe(
        id: "didi.trip-receipt.v1",
        platform: .didi,
        pageKind: "trip_receipt",
        description: "抽取滴滴行程详情中的金额、时间和路线信息。",
        prompt: "识别当前行程详情中的金额、时间、起终点和行程描述。",
        extractionSchema: ExtractionSchemaDescriptor(
            resourceType: "TripExpenseObservation",
            fields: [
                ExtractionField(name: "amount", description: "行程金额"),
                ExtractionField(name: "occurred_at", description: "结束或支付时间"),
                ExtractionField(name: "route", description: "路线摘要")
            ]
        ),
        retentionPolicy: .lowConfidenceOnly,
        confidenceThreshold: 0.87
    )

    public static let douyinCollection = collectionRecipe(
        id: "douyin.collection.v1",
        platform: .douyin,
        platformLabel: "抖音"
    )

    public static let kuaishouCollection = collectionRecipe(
        id: "kuaishou.collection.v1",
        platform: .kuaishou,
        platformLabel: "快手"
    )

    public static let xiaohongshuCollection = collectionRecipe(
        id: "xiaohongshu.collection.v1",
        platform: .xiaohongshu,
        platformLabel: "小红书"
    )

    public static let channelsCollection = collectionRecipe(
        id: "channels.collection.v1",
        platform: .channels,
        platformLabel: "视频号"
    )

    public static let all: [GUIRecipe] = [
        wechatConversation,
        alipayExpenseReceipt,
        meituanExpenseReceipt,
        didiTripReceipt,
        douyinCollection,
        kuaishouCollection,
        xiaohongshuCollection,
        channelsCollection
    ]

    private static func collectionRecipe(id: String, platform: SourcePlatform, platformLabel: String) -> GUIRecipe {
        GUIRecipe(
            id: id,
            platform: platform,
            pageKind: "collection_list",
            description: "抽取\(platformLabel)收藏列表中的标题、收藏时间与互动指标。",
            prompt: "识别收藏列表中的视频标题、收藏时间、点赞数和平台内容链接。",
            extractionSchema: ExtractionSchemaDescriptor(
                resourceType: "CollectionObservation",
                fields: [
                    ExtractionField(name: "title", description: "视频标题"),
                    ExtractionField(name: "collected_at", description: "收藏时间"),
                    ExtractionField(name: "like_count", description: "收藏时点赞数"),
                    ExtractionField(name: "permalink", description: "内容链接", required: false)
                ]
            ),
            retentionPolicy: .lowConfidenceOnly,
            confidenceThreshold: 0.84
        )
    }
}

public final class RecipeRegistry {
    private var recipesByID: [String: [Int: GUIRecipe]]

    public init(recipes: [GUIRecipe] = DefaultRecipes.all) {
        var storage: [String: [Int: GUIRecipe]] = [:]
        for recipe in recipes {
            var versions = storage[recipe.id] ?? [:]
            versions[recipe.version] = recipe
            storage[recipe.id] = versions
        }
        self.recipesByID = storage
    }

    public func recipe(id: String) -> GUIRecipe? {
        guard let versions = recipesByID[id], let latestVersion = versions.keys.max() else {
            return nil
        }
        return versions[latestVersion]
    }

    public func recipe(id: String, version: Int) -> GUIRecipe? {
        recipesByID[id]?[version]
    }

    public func recipes(for platform: SourcePlatform) -> [GUIRecipe] {
        recipesByID.values
            .flatMap(\.values)
            .filter { $0.platform == platform }
            .sorted {
                if $0.id == $1.id {
                    return $0.version > $1.version
                }
                return $0.id < $1.id
            }
    }

    public func register(_ recipe: GUIRecipe) {
        var versions = recipesByID[recipe.id] ?? [:]
        versions[recipe.version] = recipe
        recipesByID[recipe.id] = versions
    }

    public func defaultRecipe(for platform: SourcePlatform) -> GUIRecipe? {
        recipes(for: platform).first
    }
}
