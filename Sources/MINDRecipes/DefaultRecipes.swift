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

    public static let shortVideoCollection = GUIRecipe(
        id: "short-video.collection.v1",
        platform: .douyin,
        pageKind: "collection_list",
        description: "抽取短视频收藏列表中的标题、收藏时间与互动指标。",
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

    public static let all: [GUIRecipe] = [
        wechatConversation,
        alipayExpenseReceipt,
        shortVideoCollection
    ]
}

public final class RecipeRegistry {
    private var recipesByID: [String: GUIRecipe]

    public init(recipes: [GUIRecipe] = DefaultRecipes.all) {
        var storage: [String: GUIRecipe] = [:]
        for recipe in recipes {
            storage[recipe.id] = recipe
        }
        self.recipesByID = storage
    }

    public func recipe(id: String) -> GUIRecipe? {
        recipesByID[id]
    }

    public func recipes(for platform: SourcePlatform) -> [GUIRecipe] {
        recipesByID.values
            .filter { $0.platform == platform }
            .sorted { $0.id < $1.id }
    }

    public func register(_ recipe: GUIRecipe) {
        recipesByID[recipe.id] = recipe
    }
}
