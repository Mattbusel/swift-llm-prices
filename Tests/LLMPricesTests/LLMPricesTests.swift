import XCTest
@testable import LLMPrices

// Ports of the Go module's tests (llm-prices/go), which port the Python and Rust tests: every
// id form those resolve must resolve to the same row here, and costs must match.

final class LLMPricesTests: XCTestCase {
    private func row(_ id: String, file: StaticString = #filePath, line: UInt = #line) throws -> Price {
        try XCTUnwrap(PriceTable.lookup(id), "lookup(\(id)) found nothing", file: file, line: line)
    }

    private func near(_ a: Double?, _ b: Double) -> Bool {
        guard let a else { return false }
        return abs(a - b) <= 1e-12 * max(1, abs(b))
    }

    private func same(_ a: Price?, _ b: Price) -> Bool {
        a?.provider == b.provider && a?.model == b.model
    }

    private func ids(_ p: Price) -> [String] { [p.model] + p.aliases }

    func testEveryRowHasASourceAndDate() throws {
        let all = PriceTable.all
        XCTAssertGreaterThanOrEqual(all.count, 50)
        let date = try NSRegularExpression(pattern: #"^\d{4}-\d{2}-\d{2}$"#)
        func isDate(_ s: String) -> Bool {
            date.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
        }
        for p in all {
            XCTAssertTrue(p.sourceURL.hasPrefix("https://"), "\(p.provider)/\(p.model)")
            XCTAssertTrue(isDate(p.checked), "\(p.provider)/\(p.model) checked \(p.checked)")
        }
        XCTAssertTrue(isDate(PriceTable.generated))
    }

    func testLookups() throws {
        XCTAssertEqual(try row("claude-opus-5-5").input, 4.0)
        let cases: [String: String] = [
            "us.anthropic.claude-sonnet-4-20250514-v1:0": "claude-sonnet-4-20250514",
            "claude-opus-4-1@20250805": "claude-opus-4-1-20250805",
            "claude-haiku-4-5-20251001": "claude-haiku-4-5",
            "deepseek-v4-flash": "deepseek-flash",
            "gpt-4o-2024-08-06": "gpt-4o",
            "gpt-4o-2024-05-13": "gpt-4o-2024-05-13",
            "gpt-4o-2024-11-20": "gpt-4o",
            "openai/gpt-4o-2024-11-20": "gpt-4o",
            "azure/gpt-4.1-2025-04-14": "gpt-4.1",
            "o3-2025-04-16": "o3",
            "gpt-4o-mini-2024-07-18": "gpt-4o-mini",
            "gpt-5-2025-08-07": "gpt-5",
            "mistral-large-latest": "mistral-large-4",
            "mistral-small-latest": "mistral-small-2603",
            "codestral-latest": "codestral-2508",
            "grok-4.7-latest": "grok-4.7",
            "xai/grok-4.3-latest": "grok-4.3",
            "claude-3-5-haiku-latest": "claude-3-5-haiku-20241022",
            "claude-opus-5-5-latest": "claude-opus-5-5",
            "  GPT-4o  ": "gpt-4o",
        ]
        for (id, want) in cases {
            XCTAssertEqual(PriceTable.lookup(id)?.model, want, id)
        }
        XCTAssertEqual(try row("models/gemini-2.5-pro").output, 10.0)
        XCTAssertEqual(try row("gpt-4o-2024-05-13").input, 5.0)
        XCTAssertEqual(try row("gpt-4o").input, 2.5)
    }

    func testUnknownIDsDoNotResolve() {
        for id in ["", "   ", "not-a-model", "anthropic/", "claude", "gpt", "models/", "groq/", "-latest", "latest",
                   "2024-08-06"] {
            XCTAssertNil(PriceTable.lookup(id), id)
        }
    }

    func testAnthropicIDForms() {
        for p in Provider.anthropic.rows {
            for id in ids(p) {
                var base = id
                var date = "20990101"
                if let r = id.range(of: #"-20\d{6}$"#, options: .regularExpression) {
                    base = String(id[..<r.lowerBound])
                    date = String(id[id.index(after: r.lowerBound)...])
                }
                var forms = [base, base + "-20990101", "anthropic/" + base + "-20990101", base + "-latest",
                             base + "@" + date, "vertex_ai/" + base + "@" + date]
                for region in ["", "us.", "eu.", "apac.", "global."] {
                    forms += [region + "anthropic." + id + "-v1:0", region + "anthropic." + id + "-v2:0"]
                }
                for form in forms {
                    XCTAssertTrue(same(PriceTable.lookup(form), p), "\(form) -> \(String(describing: PriceTable.lookup(form)?.model)), want \(p.model)")
                }
                XCTAssertTrue(same(Provider.bedrock.lookup("us.anthropic." + id + "-v1:0"), p), id)
                XCTAssertTrue(same(PriceTable.lookup(provider: "vertex_ai", model: base + "@" + date), p), id)
            }
        }
    }

    func testEveryIDResolvesUnderItsProvider() {
        for p in PriceTable.all {
            for id in ids(p) {
                for form in [id, id.uppercased(), id + "-2099-01-01"] {
                    XCTAssertTrue(same(PriceTable.lookup(provider: p.provider, model: form), p), "\(p.provider) \(form)")
                }
                XCTAssertTrue(same(PriceTable.lookup(p.provider + "/" + id), p), p.provider + "/" + id)
            }
        }
    }

    func testProviderLookupKeepsHostsApart() throws {
        let groq = try XCTUnwrap(PriceTable.lookup(provider: "groq", model: "openai/gpt-oss-120b"))
        let together = try XCTUnwrap(PriceTable.lookup(provider: "together_ai", model: "openai/gpt-oss-120b"))
        let fireworks = try XCTUnwrap(PriceTable.lookup(provider: "fireworks", model: "accounts/fireworks/models/gpt-oss-120b"))
        XCTAssertEqual([groq.provider, together.provider, fireworks.provider], ["groq", "together", "fireworks"])
        XCTAssertNil(groq.cacheRead)
        XCTAssertNil(together.cacheRead)
        XCTAssertEqual(fireworks.cacheRead, 0.015)
        let none: [(String, String)] = [
            ("openai", "openai/gpt-oss-120b"), ("openai", "gpt-oss-120b"), ("anthropic", "gpt-4o"),
            ("groq", "claude-sonnet-4-6"), ("together", "gpt-4o"), ("bedrock", "gpt-4o"),
            ("azure", "claude-sonnet-4-6"), ("vertex", "mistral-large-4"), ("bedrock", "deepseek-flash"),
            ("acme", "gpt-4o"), ("groq", "llama-3.3-70b-versatile"), ("bedrock", "mistral.mistral-large-2407-v1:0"),
            ("deepseek", "gpt-4o"), ("ollama", "llama3"), ("huggingface", "deepseek-ai/DeepSeek-V4-Pro"),
        ]
        for (provider, model) in none {
            XCTAssertNil(PriceTable.lookup(provider: provider, model: model), "\(provider) \(model)")
        }
        let some: [(String, String, String)] = [
            ("fireworks_ai", "fireworks_ai/accounts/fireworks/models/gpt-oss-120b", "fireworks"),
            ("bedrock", "claude-sonnet-4-6", "anthropic"),
            ("vertex", "gemini-2.5-pro", "google"),
            ("azure", "gpt-4o", "openai"),
            ("openrouter", "mistralai/mistral-large-4", "mistral"),
            ("openrouter", "x-ai/grok-4.7", "xai"),
            ("together", "moonshotai/Kimi-K3", "together"),
            ("fireworks", "accounts/fireworks/models/kimi-k3", "fireworks"),
            ("bedrock", "global.anthropic.claude-opus-4-5-20251101-v1:0", "anthropic"),
        ]
        for (provider, model, want) in some {
            XCTAssertEqual(PriceTable.lookup(provider: provider, model: model)?.provider, want, "\(provider) \(model)")
        }
    }

    func testCostCallbackCases() throws {
        let cases: [(String, String, String, String, Double, Double)] = [
            ("openai", "gpt-4o", "openai", "gpt-4o", 2.5, 10),
            ("openai", "gpt-4o-2024-05-13", "openai", "gpt-4o-2024-05-13", 5, 15),
            ("anthropic", "claude-sonnet-4-5", "anthropic", "claude-sonnet-4-5-20250929", 3, 15),
            ("google_genai", "gemini-2.5-flash", "google", "gemini-2.5-flash", 0.3, 2.5),
            ("google_vertexai", "gemini-2.5-pro", "google", "gemini-2.5-pro", 1.25, 10),
            ("deepseek", "deepseek-chat", "deepseek", "deepseek-flash", 0.3, 1.2),
            ("deepseek", "deepseek-reasoner", "deepseek", "deepseek-flash", 0.3, 1.2),
            ("mistralai", "mistral-large-latest", "mistral", "mistral-large-4", 0.7, 2.1),
            ("xai", "grok-4.7", "xai", "grok-4.7", 2, 6),
            ("groq", "openai/gpt-oss-120b", "groq", "openai/gpt-oss-120b", 0.15, 0.6),
            ("together", "openai/gpt-oss-120b", "together", "openai/gpt-oss-120b", 0.15, 0.6),
            ("fireworks", "accounts/fireworks/models/gpt-oss-120b", "fireworks", "accounts/fireworks/models/gpt-oss-120b", 0.15, 0.6),
            ("cohere", "command-r-plus-08-2024", "cohere", "command-r-plus-08-2024", 2.5, 10),
            ("bedrock", "anthropic.claude-haiku-4-5-20251001-v1:0", "anthropic", "claude-haiku-4-5", 1, 5),
            ("bedrock_converse", "us.anthropic.claude-sonnet-4-20250514-v1:0", "anthropic", "claude-sonnet-4-20250514", 3, 15),
            ("azure_openai", "gpt-4o-mini", "openai", "gpt-4o-mini", 0.15, 0.6),
        ]
        for (provider, model, wantProvider, wantModel, inPrice, outPrice) in cases {
            let p = try XCTUnwrap(PriceTable.lookup(provider: provider, model: model), "\(provider) \(model)")
            XCTAssertEqual(p.provider, wantProvider, model)
            XCTAssertEqual(p.model, wantModel, model)
            XCTAssertEqual(p.input, inPrice, model)
            XCTAssertEqual(p.output, outPrice, model)
            XCTAssertTrue(near(p.inputPerToken, inPrice / 1e6), model)
            XCTAssertTrue(near(p.outputPerToken, outPrice / 1e6), model)
        }
        XCTAssertNil(PriceTable.lookup(provider: "openai", model: "text-embedding-3-small")?.outputPerToken)
        XCTAssertNil(PriceTable.cost(model: "text-embedding-3-small", input: 10, output: 0))
    }

    func testProviderNames() {
        let cases: [String: Provider] = [
            "fireworks_ai": .fireworks, "x-ai": .xai, "open_router": .openrouter, "google_genai": .google,
            "google_vertexai": .vertex, "bedrock_converse": .bedrock, "google-generativeai": .google,
            "azure_ai_foundry": .azure, "GroqCloud": .groq, "cohere_ai": .cohere, " Together AI ": .together,
            "vertex_ai": .vertex, "gemini": .google, "claude": .anthropic, "grok": .xai,
        ]
        for (name, want) in cases {
            XCTAssertEqual(Provider(name: name), want, name)
        }
        for bad in ["", "deepseek-ai", "meta-llama", "qwen", "ollama", "huggingface",
                    "a-very-long-provider-name-that-is-not-real"] {
            XCTAssertNil(Provider(name: bad), bad)
        }
        var n = 0
        for p in Provider.allCases {
            XCTAssertEqual(Provider(name: p.rawValue), p)
            n += p.rows.count
        }
        XCTAssertEqual(n, PriceTable.all.count)
    }

    func testDelistedRowsStillPrice() throws {
        for m in ["gpt-3.5-turbo", "o1", "claude-3-5-haiku-20241022"] {
            let p = try row(m)
            XCTAssertEqual(p.status, "retired", m)
            XCTAssertTrue(p.note.contains("no longer on the pricing page"), m)
        }
    }

    func testAnthropicCacheExample() throws {
        let c = try XCTUnwrap(try row("claude-sonnet-4-6").cost(
            Usage(input: 2_048, output: 1_024, cacheRead: 45_000, cacheWrite5m: 3_500)))
        XCTAssertFalse(c.longContext)
        XCTAssertTrue(near(c.input, 0.006_144))
        XCTAssertTrue(near(c.cacheRead, 0.013_5))
        XCTAssertTrue(near(c.cacheWrite, 0.013_125))
        XCTAssertTrue(near(c.output, 0.015_36))
        XCTAssertTrue(near(c.total, 0.048_129))
    }

    func testOpenAILongContextExample() throws {
        let p = try row("gpt-5.4")
        let c = try XCTUnwrap(p.cost(Usage(input: 100_000, output: 4_000, cacheRead: 200_000)))
        XCTAssertTrue(c.longContext)
        XCTAssertTrue(near(c.input, 0.5))
        XCTAssertTrue(near(c.cacheRead, 0.1))
        XCTAssertTrue(near(c.output, 0.09))
        XCTAssertTrue(near(c.total, 0.69))
        XCTAssertTrue(near(p.cost(input: 100_000, output: 4_000), 0.31))
    }

    func testSimpleAndLongContextCost() throws {
        XCTAssertTrue(near(PriceTable.cost(model: "claude-haiku-5-5", input: 10_000, output: 2_000), 0.002))
        let h = try row("claude-haiku-5-5")
        XCTAssertTrue(near(h.cost(input: 100_000, output: 0), 0.01))
        XCTAssertTrue(near(h.cost(input: 100_001, output: 0), 100_001 * 0.5 / 1e6))
        XCTAssertEqual(h.cacheWrite["1h"], 0.2)
        var at = Usage(input: 60_000, cacheRead: 40_000)
        let c1 = try XCTUnwrap(h.cost(at))
        XCTAssertFalse(c1.longContext)
        XCTAssertLessThanOrEqual(abs(c1.total - (60_000 * 0.1 + 40_000 * 0.01) / 1e6), 1e-15)
        at.cacheWrite1h = 1
        let c2 = try XCTUnwrap(h.cost(at))
        XCTAssertTrue(c2.longContext)
        XCTAssertLessThanOrEqual(abs(c2.input - 60_000 * 0.5 / 1e6), 1e-15)
        XCTAssertLessThanOrEqual(abs(c2.cacheWrite - 1.0 / 1e6), 1e-15)
        let g = try row("grok-4.7")
        XCTAssertEqual(g.longContext?.thresholdTokens, 199_999)
        XCTAssertEqual(g.cost(Usage(input: 200_000))?.longContext, true)
    }

    /// The Rust crate's 1.0 cost, which `cost(input:output:)` must equal bit for bit.
    private func cost10(_ p: Price, _ i: Int, _ o: Int) -> Double? {
        var ip = p.input
        var op = p.output
        if let l = p.longContext, i > l.thresholdTokens {
            ip = l.input
            op = l.output
        }
        guard let ip, let op else { return nil }
        return (Double(i) * ip + Double(o) * op) / 1_000_000.0
    }

    func testCostAgreesWithCostUsageAnd10() {
        let counts = [0, 1, 999, 100_000, 100_001, 200_000, 200_001, 272_000, 272_001, 1_000_000, 12_345_678]
        for p in PriceTable.all {
            for i in counts {
                for o in counts {
                    let got = p.cost(input: i, output: o)
                    XCTAssertEqual(got, cost10(p, i, o), "\(p.model) \(i) \(o)")
                    XCTAssertEqual(p.cost(Usage(input: i, output: o))?.total, got, "\(p.model) \(i) \(o)")
                }
            }
        }
    }

    func testCacheBatchAndMissingPrices() throws {
        let pro = try row("gpt-5.5-pro")
        let r1 = try XCTUnwrap(pro.cost(Usage(cacheRead: 100_000)))
        XCTAssertEqual(r1.cacheRead, 3.0)
        XCTAssertEqual(r1.input, 0)
        let r2 = try XCTUnwrap(pro.cost(Usage(cacheRead: 1_000_000)))
        XCTAssertTrue(r2.longContext)
        XCTAssertEqual(r2.cacheRead, 60.0)
        XCTAssertNil(pro.cost(Usage(input: 272_001, batch: true)))
        XCTAssertNotNil(pro.cost(Usage(input: 272_000, batch: true)))
        let s = try row("claude-sonnet-4-6")
        var u = Usage(cacheWrite5m: 1_000_000, cacheWrite1h: 1_000_000)
        XCTAssertEqual(s.cost(u)?.cacheWrite, 3.75 + 6.0)
        u.batch = true
        XCTAssertEqual(s.cost(u)?.cacheWrite, (3.75 + 6.0) / 2.0)
        let b = Usage(input: 10_000, output: 1_000, cacheRead: 90_000, batch: true)
        let hb = try XCTUnwrap(try row("claude-haiku-4-5").cost(b))
        XCTAssertTrue(near(hb.input, 0.005))
        XCTAssertTrue(near(hb.cacheRead, 0.0045))
        XCTAssertTrue(near(hb.output, 0.0025))
        XCTAssertNil(try row("gpt-3.5-turbo").cost(b))
        XCTAssertNil(try row("gpt-6-sol").cost(Usage(input: 1, cacheWrite5m: 1)))
        XCTAssertNil(try row("text-embedding-3-small").cost(Usage()))
        XCTAssertNil(s.cost(Usage(input: -1)))
    }

    func testRowsAreValues() throws {
        var p = try row("claude-sonnet-4-6")
        p.input = 999
        p.cacheWrite["5m"] = 999
        let q = try row("claude-sonnet-4-6")
        XCTAssertNotEqual(q.input, 999)
        XCTAssertNotEqual(q.cacheWrite["5m"], 999)
    }

    func testBudget() throws {
        let budget = Budget(limitUSD: 0.01)
        XCTAssertNoThrow(try budget.check(model: "claude-haiku-5-5", input: 10_000, maxOutput: 2_000))
        let spent = try budget.record(model: "claude-haiku-5-5", usage: Usage(input: 10_000, output: 2_000))
        XCTAssertTrue(near(spent, 0.002))
        XCTAssertTrue(near(budget.spentUSD, 0.002))
        XCTAssertTrue(near(budget.remainingUSD, 0.008))
        XCTAssertThrowsError(try budget.check(model: "claude-haiku-5-5", input: 100_000, maxOutput: 0)) { error in
            guard case BudgetError.wouldExceed = error else { return XCTFail("\(error)") }
        }
        XCTAssertThrowsError(try budget.record(model: "not-a-model", usage: Usage(input: 1))) { error in
            XCTAssertEqual(error as? BudgetError, .unknownPrice(model: "not-a-model"))
        }
        XCTAssertNoThrow(try budget.record(model: "claude-sonnet-4-6", provider: "bedrock",
                                           usage: Usage(input: 1_000, output: 1_000)))
        budget.record(costUSD: 1)
        XCTAssertTrue(budget.isExhausted)
        XCTAssertEqual(budget.remainingUSD, 0)
        budget.reset()
        XCTAssertEqual(budget.spentUSD, 0)
    }
}
