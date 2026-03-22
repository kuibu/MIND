import Foundation
import MINDSchemas

public final class RuleBasedExpenseClassifier {
    private let diningKeywords: [String]
    private let travelKeywords: [String]

    public init(
        diningKeywords: [String] = ["餐", "food", "coffee", "cafe", "饭", "外卖", "火锅", "面", "茶饮"],
        travelKeywords: [String] = ["滴滴", "出行", "taxi", "trip", "flight", "hotel", "打车", "车费"]
    ) {
        self.diningKeywords = diningKeywords
        self.travelKeywords = travelKeywords
    }

    public func classify(expense: Expense, merchant: Merchant?, order: Order?, trip: Trip?) -> CategoryAssignment {
        if expense.source == .didi || trip != nil || containsTravelHint(merchant: merchant, order: order) {
            return CategoryAssignment(category: .travel, strategy: "rule:travel", confidence: 0.93)
        }

        if containsDiningHint(expense: expense, merchant: merchant, order: order) {
            return CategoryAssignment(category: .dining, strategy: "rule:dining", confidence: 0.9)
        }

        return CategoryAssignment(category: .other, strategy: "rule:fallback", confidence: 0.66)
    }

    private func containsDiningHint(expense: Expense, merchant: Merchant?, order: Order?) -> Bool {
        let texts = [
            merchant?.name ?? "",
            order?.title ?? ""
        ]
        let normalizedTexts = texts.map(normalize)

        if expense.source == .meituan && normalizedTexts.contains(where: containsAny(of: diningKeywords)) {
            return true
        }

        if expense.source == .alipay && normalizedTexts.contains(where: containsAny(of: diningKeywords)) {
            return true
        }

        return normalizedTexts.contains(where: containsAny(of: diningKeywords))
    }

    private func containsTravelHint(merchant: Merchant?, order: Order?) -> Bool {
        let texts = [
            merchant?.name ?? "",
            order?.title ?? ""
        ].map(normalize)

        return texts.contains(where: containsAny(of: travelKeywords))
    }

    private func containsAny(of keywords: [String]) -> (String) -> Bool {
        { text in
            keywords.map(self.normalize).contains { keyword in
                text.contains(keyword)
            }
        }
    }

    private func normalize(_ input: String) -> String {
        input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

public final class CanonicalNormalizer {
    private let classifier: RuleBasedExpenseClassifier

    public init(classifier: RuleBasedExpenseClassifier = RuleBasedExpenseClassifier()) {
        self.classifier = classifier
    }

    public func assignment(for expense: Expense, in repository: InMemoryMINDRepository) -> CategoryAssignment {
        if let existing = expense.categoryAssignment {
            return existing
        }

        return classifier.classify(
            expense: expense,
            merchant: repository.merchant(id: expense.merchantID),
            order: repository.order(id: expense.orderID),
            trip: repository.trip(id: expense.tripID)
        )
    }
}
