# Changelog

## 0.1.0 (2026-11-15)

First release.

- `PriceTable`: the llm-prices table (146 rows, generated 2026-11-15) compiled in, with `lookup(_:)`, `lookup(provider:model:)` and `cost(model:input:output:)`.
- Lookup accepts aliases, any ASCII case, snapshot dates, `-latest`, Bedrock ids, Vertex `@date` ids and provider prefixes, with the same rules as the Rust, Python, Go and JavaScript packages.
- `Price.cost(_:)` prices cache reads, 5-minute and 1-hour cache writes, Batch API requests and long-context tiers.
- `Provider` parses the provider names LiteLLM, LangChain, OpenRouter and the provider SDKs use, with fallbacks for Vertex AI, Bedrock, Azure and OpenRouter.
- `Budget`: a thread-safe USD spending cap with `check` before a request and `record` after it.
