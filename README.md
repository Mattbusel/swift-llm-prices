# LLMPrices for Swift

Dated, source-cited LLM API prices compiled into your Swift app: Anthropic, OpenAI, Google Gemini, DeepSeek, Mistral, xAI, Cohere, Groq, Together AI and Fireworks AI, in USD per 1M tokens. Every row carries the provider's pricing page and the date it was checked. It makes no network calls and needs nothing beyond Foundation, so it works on iOS, macOS, watchOS, tvOS, visionOS and Linux. The table comes from [llm-prices](https://github.com/Mattbusel/llm-prices).

## Install

In `Package.swift`:

```swift
.package(url: "https://github.com/Mattbusel/swift-llm-prices.git", from: "0.1.0")
```

and add `.product(name: "LLMPrices", package: "swift-llm-prices")` to your target. In Xcode, use File > Add Package Dependencies with the same URL.

## Example

```swift
import LLMPrices

// 12,000 input and 800 output tokens on Claude Sonnet 4.6 ($3 / $15 per 1M)
if let usd = PriceTable.cost(model: "claude-sonnet-4-6", input: 12_000, output: 800) {
    print(usd) // 0.048
}

// Cap what the app spends
let budget = Budget(limitUSD: 2.00)
try budget.check(model: "gpt-5.4", input: 3_000, maxOutput: 1_024)
```

A `nil` price means the table does not list the model. Keep your own fallback and never treat it as zero.

## Docs and license

- API docs: [LLMPrices.docc](https://github.com/Mattbusel/swift-llm-prices/blob/main/Sources/LLMPrices/LLMPrices.docc/LLMPrices.md), also built on the Swift Package Index
- Changes: [CHANGELOG.md](https://github.com/Mattbusel/swift-llm-prices/blob/main/CHANGELOG.md)
- MIT license: [LICENSE](https://github.com/Mattbusel/swift-llm-prices/blob/main/LICENSE)
