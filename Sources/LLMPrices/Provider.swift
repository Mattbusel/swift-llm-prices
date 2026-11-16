import Foundation

/// A company that sells model access: a model maker's own API, a cloud platform that resells
/// it, or a host for open-weight models.
///
/// The raw value is the canonical lowercase name, the ``Price/provider`` of that provider's
/// rows. Vertex, Bedrock, Azure and OpenRouter have no rows of their own; lookups through them
/// fall back to the model makers they resell.
public enum Provider: String, CaseIterable, Sendable {
    case anthropic, openai, google, vertex, bedrock, azure, deepseek, mistral
    case groq, together, fireworks, xai, cohere, openrouter

    /// Parses a provider name, ignoring ASCII case and treating `_`, `-` and spaces alike.
    ///
    /// Accepts the canonical names and the spellings LiteLLM, LangChain, OpenRouter and the
    /// provider SDKs use (`"gemini"`, `"google_genai"`, `"vertex_ai"`, `"google_vertexai"`,
    /// `"bedrock_converse"`, `"azure_openai"`, `"together_ai"`, `"x-ai"`, ...). `nil` for
    /// anything else (`"ollama"`, `"huggingface"`).
    public init?(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.utf8.count <= 24 else { return nil }
        let key = String(decoding: asciiLower(Bytes(trimmed.utf8)).map { $0 == 0x5F || $0 == 0x20 ? 0x2D : $0 },
                         as: UTF8.self)
        guard let p = providerNames[key] else { return nil }
        self = p
    }

    /// The rows this provider sells, in table order. Empty for Vertex, Bedrock, Azure and
    /// OpenRouter.
    public var rows: [Price] { table.rows.filter { $0.provider == rawValue } }

    /// The model makers whose list prices ``lookup(_:)`` falls back to when this provider has
    /// no row for a model: Vertex AI to Google and Anthropic, Bedrock to Anthropic, Azure to
    /// OpenAI, OpenRouter to every model maker in the table. Empty for the others.
    public var fallbackProviders: [Provider] { fallbacks[self] ?? [] }

    /// Finds `model` among the rows this provider sells, with the same id handling as
    /// ``PriceTable/lookup(_:)``. When the provider has no row for it, the rows of its
    /// ``fallbackProviders`` are tried, so Claude on Bedrock gets Anthropic's row.
    public func lookup(_ model: String) -> Price? {
        lookupIndex(model).map { table.rows[$0] }
    }

    /// The standard (non-batch, uncached) cost in USD of one request to `model` as sold by
    /// this provider.
    public func cost(model: String, input: Int, output: Int) -> Double? {
        lookup(model)?.cost(input: input, output: output)
    }

    func lookupIndex(_ model: String) -> Int? {
        let name = rawValue
        if let i = resolve(model, keep: { table.rows[$0].provider == name }) { return i }
        let makers = Set((fallbacks[self] ?? []).map(\.rawValue))
        if makers.isEmpty { return nil }
        return resolve(model, keep: { makers.contains(table.rows[$0].provider) })
    }
}

private let providerNames: [String: Provider] = {
    let names: [Provider: [String]] = [
        .anthropic: ["anthropic", "claude"],
        .openai: ["openai", "open-ai"],
        .google: ["google", "gemini", "google-ai-studio", "google-gemini", "ai-studio", "google-genai",
                  "google-generativeai", "genai", "google-ai", "googleai"],
        .vertex: ["vertex", "vertex-ai", "vertexai", "google-vertex", "google-vertex-ai", "vertex-ai-beta",
                  "google-vertexai"],
        .bedrock: ["bedrock", "aws", "aws-bedrock", "amazon-bedrock", "bedrock-converse", "bedrock-runtime",
                   "amazon"],
        .azure: ["azure", "azure-openai", "azure-ai", "azure-foundry", "microsoft-foundry", "azure-ai-foundry"],
        .deepseek: ["deepseek"],
        .mistral: ["mistral", "mistralai", "mistral-ai"],
        .groq: ["groq", "groqcloud", "groq-cloud"],
        .together: ["together", "together-ai", "togetherai"],
        .fireworks: ["fireworks", "fireworks-ai", "fireworksai"],
        .xai: ["xai", "x-ai", "grok"],
        .cohere: ["cohere", "cohere-chat", "cohere-ai"],
        .openrouter: ["openrouter", "open-router"],
    ]
    var out: [String: Provider] = [:]
    for (p, list) in names {
        for n in list { out[n] = p }
    }
    return out
}()

private let fallbacks: [Provider: [Provider]] = [
    .vertex: [.google, .anthropic],
    .bedrock: [.anthropic],
    .azure: [.openai],
    .openrouter: [.anthropic, .openai, .google, .deepseek, .mistral, .xai, .cohere],
]

private let platforms: Set<String> = ["vertex", "bedrock", "azure", "openrouter"]

// MARK: - Model ids

typealias Bytes = [UInt8]

private let prefixes: [Bytes] = [
    "models/", "anthropic/", "openai/", "google/", "gemini/", "vertex_ai/", "bedrock/", "azure/",
    "openrouter/", "deepseek/", "mistral/", "mistralai/", "xai/", "x-ai/", "cohere/", "groq/",
    "together/", "together_ai/", "fireworks/", "fireworks_ai/", "accounts/fireworks/models/",
    // Bedrock's vendor prefix with an optional cross-region inference profile.
    "us.anthropic.", "eu.anthropic.", "apac.anthropic.", "global.anthropic.", "anthropic.",
].map { Bytes($0.utf8) }

private let dash = UInt8(ascii: "-")
private let latest = Bytes("-latest".utf8)
private let fireworksAccounts = Bytes("accounts/fireworks/".utf8)

func asciiLower(_ s: Bytes) -> Bytes {
    s.map { $0 >= 0x41 && $0 <= 0x5A ? $0 + 0x20 : $0 }
}

private func trimmedLower(_ s: String) -> Bytes {
    asciiLower(Bytes(s.trimmingCharacters(in: .whitespacesAndNewlines).utf8))
}

/// Case-insensitive prefix test against an all-lowercase prefix.
private func hasPrefixCI(_ s: Bytes, _ p: Bytes) -> Bool {
    guard s.count >= p.count else { return false }
    for i in 0..<p.count {
        let c = s[i] >= 0x41 && s[i] <= 0x5A ? s[i] + 0x20 : s[i]
        if c != p[i] { return false }
    }
    return true
}

private func allDigits(_ s: Bytes) -> Bool {
    s.allSatisfy { $0 >= 0x30 && $0 <= 0x39 }
}

private func isYear(_ s: Bytes) -> Bool {
    s.count == 4 && s[0] == 0x32 && s[1] == 0x30
}

func stripPrefix(_ id: Bytes) -> Bytes {
    var s = id
    while true {
        let before = s
        for p in prefixes where hasPrefixCI(s, p) {
            s.removeFirst(p.count)
        }
        if s == before { return s }
    }
}

private func cutLast(_ s: Bytes, _ sep: UInt8) -> (Bytes, Bytes)? {
    guard let i = s.lastIndex(of: sep) else { return nil }
    return (Bytes(s[..<i]), Bytes(s[(i + 1)...]))
}

/// The id without a trailing -YYYYMMDD (Anthropic) or -YYYY-MM-DD (OpenAI), or nil.
func stripDate(_ id: Bytes) -> Bytes? {
    guard case let (head, tail)? = cutLast(id, dash) else { return nil }
    if tail.count == 8 && tail[0] == 0x32 && tail[1] == 0x30 && allDigits(tail) {
        return head
    }
    guard case let (rest, month)? = cutLast(head, dash), case let (base, year)? = cutLast(rest, dash) else {
        return nil
    }
    if tail.count == 2 && month.count == 2 && isYear(year) && allDigits(tail) && allDigits(month)
        && allDigits(year) && !base.isEmpty {
        return base
    }
    return nil
}

/// The id without a trailing -latest, then without a trailing snapshot date.
private func stripVersion(_ id: Bytes) -> Bytes {
    var s = id
    if id.count > latest.count && asciiLower(Bytes(id.suffix(latest.count))) == latest {
        s = Bytes(id.dropLast(latest.count))
    }
    return stripDate(s) ?? s
}

/// The id without provider prefixes, without Bedrock's -v1:0 suffix, and with Vertex's @
/// turned into -.
private func normalizeID(_ lower: Bytes) -> Bytes {
    var s = stripPrefix(lower)
    if let i = firstIndex(of: [dash, UInt8(ascii: "v")], in: s) {
        let rest = s[(i + 2)...]
        if let first = rest.first, first >= 0x30 && first <= 0x39, !rest.contains(dash) {
            s = Bytes(s[..<i])
        }
    }
    if let at = s.firstIndex(of: UInt8(ascii: "@")) {
        s[at] = dash
    }
    return s
}

private func firstIndex(of needle: Bytes, in s: Bytes) -> Int? {
    guard s.count >= needle.count else { return nil }
    for i in 0...(s.count - needle.count) where s[i] == needle[0] && s[i + 1] == needle[1] {
        return i
    }
    return nil
}

private func resolve(_ id: String, keep: (Int) -> Bool) -> Int? {
    let rows = table.rows.indices.filter(keep)
    let lower = trimmedLower(id)
    for i in rows where table.ids[i].contains(lower) {
        return i
    }
    let s = normalizeID(lower)
    if s.isEmpty { return nil }
    func strippedEq(_ want: Bytes) -> Int? {
        rows.first { table.stripped[$0].contains(want) }
    }
    if let i = strippedEq(s) { return i }
    let base = stripVersion(s)
    if base != s, let i = strippedEq(base) { return i }
    return rows.first { table.undated[$0].contains(base) }
}

func lookupIndex(_ model: String) -> Int? {
    let lower = trimmedLower(model)
    if hasPrefixCI(lower, fireworksAccounts) {
        if let i = Provider.fireworks.lookupIndex(String(decoding: lower, as: UTF8.self)) { return i }
    } else if let slash = lower.firstIndex(of: UInt8(ascii: "/")) {
        let head = String(decoding: lower[..<slash], as: UTF8.self)
        let rest = String(decoding: lower[(slash + 1)...], as: UTF8.self)
        if let p = Provider(name: head), let i = p.lookupIndex(rest) { return i }
    }
    let lowerString = String(decoding: lower, as: UTF8.self)
    if let i = resolve(lowerString, keep: { !platforms.contains(table.rows[$0].provider) }) { return i }
    return resolve(lowerString, keep: { platforms.contains(table.rows[$0].provider) })
}
