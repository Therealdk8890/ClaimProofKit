// Copyright 2026 Daniel Kissel
// SPDX-License-Identifier: Apache-2.0

import Testing
@testable import ClaimProofKit

@Suite("BM25TopKRetriever")
struct BM25TopKRetrieverTests {
    private let retriever = BM25TopKRetriever()

    private let corpus = [
        EvidencePassage(
            id: "pass-0001",
            source: "Smith Declaration ¶2",
            sourceType: .declaration,
            text: "The response to the motion was filed on March 3 within the fourteen day deadline."
        ),
        EvidencePassage(
            id: "pass-0002",
            source: "Scheduling Order",
            sourceType: .courtRecord,
            text: "The court denied the request for an extension of the discovery deadline."
        ),
        EvidencePassage(
            id: "pass-0003",
            source: "Invoice 44",
            sourceType: .evidence,
            text: "Invoice 44 totals four thousand dollars for gravel delivered in February."
        ),
    ]

    private func claim(_ text: String) -> Claim {
        Claim(id: "c1", text: text)
    }

    @Test("ranks the passage sharing the most distinctive terms first")
    func ranksRelevantFirst() async throws {
        let results = try await retriever.retrieve(
            for: claim("The response was filed within the fourteen day deadline."),
            from: corpus,
            limit: 3
        )
        #expect(results.first?.id == "pass-0001")
    }

    @Test("excludes passages sharing no terms with the claim")
    func excludesDisjointPassages() async throws {
        let results = try await retriever.retrieve(
            for: claim("Gravel invoice totals were paid."),
            from: corpus,
            limit: 3
        )
        #expect(results.allSatisfy { $0.id != "pass-0002" })
        #expect(!results.isEmpty)
    }

    @Test("respects the limit")
    func respectsLimit() async throws {
        let results = try await retriever.retrieve(
            for: claim("The court deadline for the response and the extension."),
            from: corpus,
            limit: 1
        )
        #expect(results.count == 1)
    }

    @Test("empty corpus, empty claim, and non-positive limit return nothing")
    func degenerateInputs() async throws {
        #expect(try await retriever.retrieve(for: claim("Anything at all here."), from: [], limit: 3).isEmpty)
        #expect(try await retriever.retrieve(for: claim("!!!"), from: corpus, limit: 3).isEmpty)
        #expect(try await retriever.retrieve(for: claim("The court deadline."), from: corpus, limit: 0).isEmpty)
    }

    @Test("identical passages tie-break by ascending id")
    func deterministicTieBreak() async throws {
        let duplicated = [
            EvidencePassage(id: "dup-0002", source: "B", text: "The deadline was met."),
            EvidencePassage(id: "dup-0001", source: "A", text: "The deadline was met."),
        ]
        let results = try await retriever.retrieve(
            for: claim("The deadline was met on time."),
            from: duplicated,
            limit: 2
        )
        #expect(results.map(\.id) == ["dup-0001", "dup-0002"])
    }

    @Test("out-of-range parameters are clamped, never NaN-scoring")
    func parameterClamping() async throws {
        let wild = BM25TopKRetriever(k1: -1, b: 7)
        #expect(wild.k1 == 0)
        #expect(wild.b == 1)
        let results = try await wild.retrieve(
            for: claim("The court denied the extension request."),
            from: corpus,
            limit: 3
        )
        #expect(!results.isEmpty)
    }

    @Test("repeated retrieval is deterministic")
    func deterministicAcrossRuns() async throws {
        let query = claim("The court denied the extension request before the deadline.")
        let first = try await retriever.retrieve(for: query, from: corpus, limit: 3)
        for _ in 0..<20 {
            let again = try await retriever.retrieve(for: query, from: corpus, limit: 3)
            #expect(again == first)
        }
    }
}
