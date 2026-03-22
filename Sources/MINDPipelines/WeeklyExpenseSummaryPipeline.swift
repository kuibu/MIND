import Foundation
import MINDProtocol
import MINDSchemas
import MINDServices

public struct WeeklyExpenseSummaryRow: Equatable {
    public let category: ExpenseCategory
    public let totalAmount: Double
    public let transactionCount: Int
    public let sources: [SourcePlatform]
    public let expenseIDs: [String]

    public init(
        category: ExpenseCategory,
        totalAmount: Double,
        transactionCount: Int,
        sources: [SourcePlatform],
        expenseIDs: [String]
    ) {
        self.category = category
        self.totalAmount = totalAmount
        self.transactionCount = transactionCount
        self.sources = sources
        self.expenseIDs = expenseIDs
    }
}

public struct WeeklyExpenseSummaryReport: Equatable {
    public let interval: DateInterval
    public let rows: [WeeklyExpenseSummaryRow]

    public init(interval: DateInterval, rows: [WeeklyExpenseSummaryRow]) {
        self.interval = interval
        self.rows = rows
    }
}

public final class WeeklyExpenseSummaryPipeline {
    private let repository: InMemoryMINDRepository
    private let normalizer: CanonicalNormalizer

    public init(repository: InMemoryMINDRepository, normalizer: CanonicalNormalizer = CanonicalNormalizer()) {
        self.repository = repository
        self.normalizer = normalizer
    }

    public func run(interval: DateInterval, sources: Set<SourcePlatform>) -> WeeklyExpenseSummaryReport {
        let expenses = repository.expenses(in: interval, from: sources)

        let grouped = Dictionary(grouping: expenses) { expense in
            normalizer.assignment(for: expense, in: repository).category
        }

        let orderedCategories: [ExpenseCategory] = [.travel, .dining, .other]
        let rows = orderedCategories.compactMap { category -> WeeklyExpenseSummaryRow? in
            guard let expensesInCategory = grouped[category], !expensesInCategory.isEmpty else {
                return nil
            }

            let total = expensesInCategory.reduce(0.0) { $0 + $1.amount }
            let platforms = Array(Set(expensesInCategory.map(\.source))).sorted { $0.rawValue < $1.rawValue }
            return WeeklyExpenseSummaryRow(
                category: category,
                totalAmount: total,
                transactionCount: expensesInCategory.count,
                sources: platforms,
                expenseIDs: expensesInCategory.map(\.id)
            )
        }

        return WeeklyExpenseSummaryReport(interval: interval, rows: rows)
    }
}
