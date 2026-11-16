/// One model's prices in USD per 1M tokens, as listed on the provider's pricing page.
///
/// A `nil` price means the page lists no price for it (embedding models have no output
/// price, many models have no batch price). Never treat a missing price as zero.
public struct Price: Sendable, Hashable {
    /// The company that sells the model at these prices: "anthropic", "openai", "google",
    /// "deepseek", "mistral", "xai", "cohere", "groq", "together" or "fireworks".
    public var provider: String
    /// The API model id.
    public var model: String
    /// The model's display name on the pricing page ("" when it has none).
    public var name: String
    /// Other ids the provider documents for the same model.
    public var aliases: [String]
    /// "listed", "retired" (still sold on some cloud platforms) or "limited".
    public var status: String
    /// Uncached input price, USD per 1M tokens.
    public var input: Double?
    /// Output price, USD per 1M tokens. Reasoning tokens bill at this price. `nil` for
    /// embedding models.
    public var output: Double?
    /// Price of input tokens served from the prompt cache, USD per 1M tokens.
    public var cacheRead: Double?
    /// Cache write price per cache lifetime, for example `["5m": 3.75, "1h": 6]`. Empty when
    /// the provider does not charge for cache writes.
    public var cacheWrite: [String: Double]
    /// Batch API input price, USD per 1M tokens.
    public var batchInput: Double?
    /// Batch API output price, USD per 1M tokens.
    public var batchOutput: Double?
    /// Prices for requests over a long-context threshold, or `nil`.
    public var longContext: LongContext?
    /// The provider's official pricing page this row was read from.
    public var sourceURL: String
    /// The ISO 8601 date the row was checked against `sourceURL`.
    public var checked: String
    /// Notes from the table (tiers, conditions, why a price is missing).
    public var note: String

    /// `input` in USD per token, or `nil` when the page lists no price.
    public var inputPerToken: Double? { input.map { $0 / perMillion } }

    /// `output` in USD per token, or `nil` when the page lists no price (embedding models).
    public var outputPerToken: Double? { output.map { $0 / perMillion } }

    /// The standard (non-batch, uncached) cost in USD of one request.
    ///
    /// Uses the long-context prices when `input` is over the model's threshold. Returns `nil`
    /// when a needed price is not listed or a token count is negative. When the response
    /// reports cached tokens, use ``cost(_:)``: cached tokens count toward the long-context
    /// threshold and bill at their own price.
    public func cost(input inputTokens: Int, output outputTokens: Int) -> Double? {
        cost(Usage(input: inputTokens, output: outputTokens))?.total
    }

    /// The cost in USD of one response from its token counts, split by token kind.
    ///
    /// The rules are the same as the Rust crate's `Price::cost_usage`:
    /// - Long context: when the model has a ``LongContext`` tier and
    ///   ``Usage/promptTokens`` is strictly greater than its threshold, every token bills at
    ///   the long-context prices.
    /// - Batch: when ``Usage/batch`` is set, input and output bill at the batch prices; cache
    ///   reads and writes get the same discount as input.
    /// - Cache reads bill at the cache-read price, or as ordinary input when none is listed.
    /// - Cache writes bill at `cacheWrite["5m"]` and `cacheWrite["1h"]`.
    ///
    /// Returns `nil` when a price it needs is not listed or a token count is negative.
    public func cost(_ usage: Usage) -> CostBreakdown? {
        let u = usage
        guard u.input >= 0, u.output >= 0, u.cacheRead >= 0, u.cacheWrite5m >= 0, u.cacheWrite1h >= 0 else {
            return nil
        }
        var t = Tier(input: input, output: output, cacheRead: cacheRead, cacheWrite: cacheWrite,
                     batchInput: batchInput, batchOutput: batchOutput)
        var isLong = false
        if let l = longContext, u.promptTokens > l.thresholdTokens {
            t = Tier(input: l.input, output: l.output, cacheRead: l.cacheRead, cacheWrite: l.cacheWrite,
                     batchInput: l.batchInput, batchOutput: l.batchOutput)
            isLong = true
        }
        guard let standardInput = t.input else { return nil }
        let inRate: Double
        let outRate: Double
        let discount: Double
        if u.batch {
            guard let bi = t.batchInput, let bo = t.batchOutput else { return nil }
            inRate = bi
            outRate = bo
            discount = standardInput > 0 ? bi / standardInput : 1.0
        } else {
            guard let o = t.output else { return nil }
            inRate = standardInput
            outRate = o
            discount = 1.0
        }
        let readRate = t.cacheRead.map { $0 * discount } ?? inRate
        var writes = 0.0
        for (ttl, tokens) in [("5m", u.cacheWrite5m), ("1h", u.cacheWrite1h)] where tokens != 0 {
            guard let rate = t.cacheWrite[ttl] else { return nil }
            writes += Double(tokens) * rate * discount
        }
        // Each product is tokens x USD-per-1M; the total adds the products before dividing
        // once, in the same order as the Rust crate, the Python package and the Go module.
        let pInput = Double(u.input) * inRate
        let pRead = Double(u.cacheRead) * readRate
        let pOutput = Double(u.output) * outRate
        let total = (((pInput + pRead) + writes) + pOutput) / perMillion
        return CostBreakdown(input: pInput / perMillion, output: pOutput / perMillion,
                             cacheRead: pRead / perMillion, cacheWrite: writes / perMillion,
                             total: total, longContext: isLong)
    }
}

/// Prices that apply when a request is over a provider's long-context threshold. `nil`
/// fields mean the page lists no price.
public struct LongContext: Sendable, Hashable {
    /// Requests whose prompt is over this many tokens pay these prices. The prompt counts
    /// uncached input, cache reads and cache writes together.
    public var thresholdTokens: Int
    /// Uncached input price above the threshold, USD per 1M tokens.
    public var input: Double?
    /// Output price above the threshold (reasoning tokens included), USD per 1M tokens.
    public var output: Double?
    /// Price of input tokens served from the prompt cache above the threshold.
    public var cacheRead: Double?
    /// Cache write price per cache lifetime, for example `["5m": 0.625]`.
    public var cacheWrite: [String: Double]
    /// Batch API input price above the threshold, USD per 1M tokens.
    public var batchInput: Double?
    /// Batch API output price above the threshold, USD per 1M tokens.
    public var batchOutput: Double?
}

/// The token counts of one API response, the input to ``Price/cost(_:)``.
///
/// From provider responses: `input` is Anthropic's `input_tokens`, OpenAI's `prompt_tokens`
/// minus `cached_tokens`, or Gemini's `promptTokenCount` minus `cachedContentTokenCount`.
/// `cacheRead` is `cache_read_input_tokens`, `prompt_tokens_details.cached_tokens` or
/// `cachedContentTokenCount`. `cacheWrite5m` and `cacheWrite1h` are Anthropic's
/// `cache_creation.ephemeral_5m_input_tokens` and `ephemeral_1h_input_tokens` (a bare
/// `cache_creation_input_tokens` is the 5-minute lifetime). `output` is `output_tokens`,
/// `completion_tokens`, or `candidatesTokenCount` plus `thoughtsTokenCount`.
public struct Usage: Sendable, Hashable {
    /// Uncached input tokens. Do not include tokens counted in `cacheRead` or the cache writes.
    public var input: Int
    /// Output tokens, reasoning or thinking tokens included.
    public var output: Int
    /// Input tokens served from the prompt cache.
    public var cacheRead: Int
    /// Input tokens written to the cache with a 5-minute lifetime.
    public var cacheWrite5m: Int
    /// Input tokens written to the cache with a 1-hour lifetime.
    public var cacheWrite1h: Int
    /// The request went through the provider's Batch API.
    public var batch: Bool

    public init(input: Int = 0, output: Int = 0, cacheRead: Int = 0, cacheWrite5m: Int = 0,
                cacheWrite1h: Int = 0, batch: Bool = false) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheWrite5m = cacheWrite5m
        self.cacheWrite1h = cacheWrite1h
        self.batch = batch
    }

    /// Uncached input plus cache reads plus cache writes: the number compared against a
    /// model's long-context threshold.
    public var promptTokens: Int { input + cacheRead + cacheWrite5m + cacheWrite1h }
}

/// The cost in USD of one response, split by token kind.
public struct CostBreakdown: Sendable, Hashable {
    /// Uncached input tokens.
    public var input: Double
    /// Output tokens.
    public var output: Double
    /// Input tokens served from the prompt cache.
    public var cacheRead: Double
    /// Cache writes, all lifetimes together.
    public var cacheWrite: Double
    /// Sum of the other amounts.
    public var total: Double
    /// `true` when the prompt was over the model's long-context threshold, so long-context
    /// prices applied.
    public var longContext: Bool
}

let perMillion = 1_000_000.0

private struct Tier {
    var input: Double?
    var output: Double?
    var cacheRead: Double?
    var cacheWrite: [String: Double]
    var batchInput: Double?
    var batchOutput: Double?
}
