# ``LLMPrices``

Dated, source-cited LLM API prices for Swift, with model-id lookup, per-request costs and a spending cap.

## Overview

LLMPrices compiles the [llm-prices](https://github.com/Mattbusel/llm-prices) table into your app: Anthropic, OpenAI, Google Gemini, DeepSeek, Mistral, xAI, Cohere, Groq, Together AI and Fireworks AI, in USD per 1M tokens. Every row carries the provider's pricing page and the date it was checked. There are no network calls and no dependencies beyond Foundation, so it works in iOS, macOS, watchOS, tvOS and visionOS apps and on Linux servers.

```swift
import LLMPrices

// Cost of one request.
let usd = PriceTable.cost(model: "claude-sonnet-4-6", input: 12_000, output: 800)

// Lookup accepts snapshot dates, -latest, Bedrock and Vertex ids and provider prefixes.
let p = PriceTable.lookup("us.anthropic.claude-sonnet-4-20250514-v1:0")
print(p?.input ?? 0, p?.output ?? 0, p?.sourceURL ?? "")

// Cached tokens, cache writes, batch and long-context tiers.
let c = PriceTable.cost(
    model: "claude-sonnet-4-6",
    usage: Usage(input: 2_048, output: 1_024, cacheRead: 45_000, cacheWrite5m: 3_500)
)
print(c?.total ?? 0) // 0.048129
```

When you know which provider served the request, say so. The host's own price wins, and cloud platforms with no rows of their own fall back to the model maker's list price:

```swift
PriceTable.lookup(provider: "groq", model: "openai/gpt-oss-120b")       // Groq's price
PriceTable.lookup(provider: "bedrock", model: "claude-sonnet-4-6")      // Anthropic's list price
PriceTable.lookup(provider: "ollama", model: "llama3")                  // nil: not priced
```

A `nil` result means the table has no price. Keep your own fallback; never treat it as zero.

### Cap what an app spends

``Budget`` checks a request before you send it and records the real cost after the response arrives. One instance is safe to share across threads.

```swift
let budget = Budget(limitUSD: 2.00)

try budget.check(model: "gpt-5.4", input: promptTokens, maxOutput: 1_024)
// ... call the API ...
try budget.record(model: "gpt-5.4", usage: Usage(input: inTokens, output: outTokens))
```

### Updating the table

The table is generated from `prices.json` in the llm-prices repository by `scripts/sync.py`, and new versions of this package ship when the prices change. ``PriceTable/generated`` says when the compiled table was built.

## Topics

### Looking up prices

- ``PriceTable``
- ``Price``
- ``Provider``
- ``LongContext``

### Computing costs

- ``Usage``
- ``CostBreakdown``

### Spending caps

- ``Budget``
- ``BudgetError``
