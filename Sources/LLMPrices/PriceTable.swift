import Foundation

/// Dated, source-cited LLM API prices with model-id lookup and per-request costs.
///
/// The table is `prices.json` from https://github.com/Mattbusel/llm-prices, compiled into
/// the package: no network access, no dependencies beyond Foundation.
///
/// ```swift
/// let usd = PriceTable.cost(model: "claude-sonnet-4-6", input: 12_000, output: 800)
/// let p = PriceTable.lookup(provider: "google_genai", model: "gemini-2.5-flash")
/// // p?.input == 0.3, p?.output == 2.5 (USD per 1M tokens)
/// ```
///
/// A `nil` result means the table has no price: keep your own fallback, never treat it as
/// zero.
public enum PriceTable {
    /// The date the table was generated (ISO 8601).
    public static var generated: String { table.generated }

    /// Every row of the table, in `prices.json` order: Anthropic, OpenAI, Google and DeepSeek
    /// first, then Mistral, xAI, Cohere, Groq, Together AI and Fireworks AI.
    public static var all: [Price] { table.rows }

    /// Finds a model by id across every provider in the table.
    ///
    /// Accepts aliases, any ASCII case, dated snapshots (`"gpt-4o-2024-08-06"` finds
    /// `"gpt-4o"` unless the snapshot has its own row), `-latest` ids, Bedrock ids
    /// (`"us.anthropic.claude-sonnet-4-20250514-v1:0"`), Vertex `@date` ids and provider
    /// prefixes (`"models/"`, `"openai/"`, `"together_ai/"`, ...). When the id starts with a
    /// provider name and a slash, that provider is tried first; otherwise the first matching
    /// row in table order wins. Use ``lookup(provider:model:)`` whenever you know which
    /// provider served the request.
    public static func lookup(_ model: String) -> Price? {
        lookupIndex(model).map { table.rows[$0] }
    }

    /// Finds `model` as sold by `provider`, any name ``Provider/init(name:)`` accepts
    /// (`"openai"`, `"google_genai"`, `"vertex_ai"`, `"bedrock_converse"`, `"azure_openai"`,
    /// `"together_ai"`, ...). Vertex AI, Bedrock, Azure and OpenRouter, which have no rows of
    /// their own, fall back to the list price of the model makers they resell; the returned
    /// row's `provider` says whose price it is. `nil` when the provider is unknown
    /// (`"ollama"`) or the table has no price for the model there.
    public static func lookup(provider: String, model: String) -> Price? {
        Provider(name: provider)?.lookup(model)
    }

    /// The standard (non-batch, uncached) cost in USD of one request to `model`, found with
    /// ``lookup(_:)``. `nil` when the model is not in the table or a needed price is not
    /// listed.
    public static func cost(model: String, input: Int, output: Int) -> Double? {
        lookup(model)?.cost(input: input, output: output)
    }

    /// ``cost(model:input:output:)`` for a model found with ``lookup(provider:model:)``.
    public static func cost(provider: String, model: String, input: Int, output: Int) -> Double? {
        lookup(provider: provider, model: model)?.cost(input: input, output: output)
    }

    /// The cost of one response, split by token kind, for a model found with ``lookup(_:)``.
    public static func cost(model: String, usage: Usage) -> CostBreakdown? {
        lookup(model)?.cost(usage)
    }

    /// The cost of one response, split by token kind, for a model found with
    /// ``lookup(provider:model:)``.
    public static func cost(provider: String, model: String, usage: Usage) -> CostBreakdown? {
        lookup(provider: provider, model: model)?.cost(usage)
    }
}

// MARK: - Loading prices.json

struct Table: Sendable {
    let generated: String
    let rows: [Price]
    /// Per row: the model id and aliases, ASCII-lowercased.
    let ids: [[Bytes]]
    /// Per row: `ids` without provider prefixes.
    let stripped: [[Bytes]]
    /// Per row: `stripped` without a trailing snapshot date (nil when there is none).
    let undated: [[Bytes?]]
}

let table: Table = loadTable(pricesJSON)

private struct RawTier: Decodable {
    var input: Double?
    var output: Double?
    var cacheRead: Double?
    var cacheWrite: [String: Double]?
    var batchInput: Double?
    var batchOutput: Double?
    var thresholdTokens: Int?

    enum CodingKeys: String, CodingKey {
        case input, output
        case cacheRead = "cache_read"
        case cacheWrite = "cache_write"
        case batchInput = "batch_input"
        case batchOutput = "batch_output"
        case thresholdTokens = "threshold_tokens"
    }
}

private struct RawRow: Decodable {
    var provider: String
    var model: String
    var name: String?
    var aliases: [String]?
    var status: String
    var input: Double?
    var output: Double?
    var cacheRead: Double?
    var cacheWrite: [String: Double]?
    var batchInput: Double?
    var batchOutput: Double?
    var longContext: RawTier?
    var sourceURL: String
    var checked: String
    var note: String?

    enum CodingKeys: String, CodingKey {
        case provider, model, name, aliases, status, input, output, checked, note
        case cacheRead = "cache_read"
        case cacheWrite = "cache_write"
        case batchInput = "batch_input"
        case batchOutput = "batch_output"
        case longContext = "long_context"
        case sourceURL = "source_url"
    }
}

private struct RawDoc: Decodable {
    var generated: String
    var models: [RawRow]
}

private func loadTable(_ json: String) -> Table {
    let doc: RawDoc
    do {
        doc = try JSONDecoder().decode(RawDoc.self, from: Data(json.utf8))
    } catch {
        fatalError("LLMPrices: embedded prices.json: \(error)")
    }
    let rows = doc.models.map { r -> Price in
        Price(
            provider: r.provider,
            model: r.model,
            name: r.name ?? "",
            aliases: r.aliases ?? [],
            status: r.status,
            input: r.input,
            output: r.output,
            cacheRead: r.cacheRead,
            cacheWrite: r.cacheWrite ?? [:],
            batchInput: r.batchInput,
            batchOutput: r.batchOutput,
            longContext: r.longContext.map {
                LongContext(thresholdTokens: $0.thresholdTokens ?? 0, input: $0.input, output: $0.output,
                            cacheRead: $0.cacheRead, cacheWrite: $0.cacheWrite ?? [:],
                            batchInput: $0.batchInput, batchOutput: $0.batchOutput)
            },
            sourceURL: r.sourceURL,
            checked: r.checked,
            note: r.note ?? ""
        )
    }
    let ids = rows.map { ([$0.model] + $0.aliases).map { asciiLower(Bytes($0.utf8)) } }
    let stripped = ids.map { $0.map(stripPrefix) }
    let undated = stripped.map { $0.map(stripDate) }
    return Table(generated: doc.generated, rows: rows, ids: ids, stripped: stripped, undated: undated)
}
