import Foundation

/// A spending cap in USD for the LLM calls an app makes, priced from ``PriceTable``.
///
/// Check before you send, record after the response arrives:
///
/// ```swift
/// let budget = Budget(limitUSD: 2.00)
///
/// try budget.check(model: "claude-sonnet-4-6", input: promptTokens, maxOutput: 1_024)
/// // ... call the API ...
/// try budget.record(model: "claude-sonnet-4-6",
///                   usage: Usage(input: r.inputTokens, output: r.outputTokens))
/// print(budget.remainingUSD)
/// ```
///
/// `Budget` is thread-safe: one instance can be shared by every request in the app.
public final class Budget: @unchecked Sendable {
    /// The cap in USD.
    public let limitUSD: Double

    private let lock = NSLock()
    private var spent = 0.0

    /// A budget of `limitUSD` dollars with nothing spent yet.
    public init(limitUSD: Double) {
        self.limitUSD = limitUSD
    }

    /// The USD recorded so far.
    public var spentUSD: Double {
        lock.lock()
        defer { lock.unlock() }
        return spent
    }

    /// The USD left before the cap, never below zero.
    public var remainingUSD: Double { max(0, limitUSD - spentUSD) }

    /// `true` once the recorded spend has reached the cap.
    public var isExhausted: Bool { spentUSD >= limitUSD }

    /// Throws ``BudgetError/wouldExceed(estimateUSD:remainingUSD:)`` when a request with
    /// `input` prompt tokens and up to `maxOutput` output tokens could take the spend past the
    /// cap, and ``BudgetError/unknownPrice(model:)`` when the table has no price for `model`.
    /// Pass `provider` when you know who serves the request (`"bedrock"`, `"groq"`, ...).
    public func check(model: String, provider: String? = nil, input: Int, maxOutput: Int) throws {
        guard let estimate = price(model: model, provider: provider)?.cost(input: input, output: maxOutput) else {
            throw BudgetError.unknownPrice(model: model)
        }
        try check(estimateUSD: estimate)
    }

    /// Throws ``BudgetError/wouldExceed(estimateUSD:remainingUSD:)`` when spending
    /// `estimateUSD` more would take the spend past the cap.
    public func check(estimateUSD: Double) throws {
        let left = remainingUSD
        if estimateUSD > left {
            throw BudgetError.wouldExceed(estimateUSD: estimateUSD, remainingUSD: left)
        }
    }

    /// Prices one response with ``Price/cost(_:)``, adds it to the spend and returns its
    /// cost. Throws ``BudgetError/unknownPrice(model:)`` and records nothing when the table
    /// has no price for it.
    @discardableResult
    public func record(model: String, provider: String? = nil, usage: Usage) throws -> Double {
        guard let cost = price(model: model, provider: provider)?.cost(usage)?.total else {
            throw BudgetError.unknownPrice(model: model)
        }
        record(costUSD: cost)
        return cost
    }

    /// Adds a cost you priced yourself to the spend.
    public func record(costUSD: Double) {
        lock.lock()
        spent += costUSD
        lock.unlock()
    }

    /// Sets the spend back to zero, for example at the start of a new day.
    public func reset() {
        lock.lock()
        spent = 0
        lock.unlock()
    }

    private func price(model: String, provider: String?) -> Price? {
        if let provider { return PriceTable.lookup(provider: provider, model: model) }
        return PriceTable.lookup(model)
    }
}

/// Why a ``Budget`` refused a request.
public enum BudgetError: Error, Equatable, Sendable {
    /// The table has no price for this model, so the cost is unknown.
    case unknownPrice(model: String)
    /// The request could cost more than what is left of the budget.
    case wouldExceed(estimateUSD: Double, remainingUSD: Double)
}
