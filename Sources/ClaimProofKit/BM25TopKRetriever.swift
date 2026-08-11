// Copyright 2026 Daniel Kissel
// SPDX-License-Identifier: BUSL-1.1

import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#elseif canImport(Android)
import Android
#elseif os(Windows)
import CRT
#endif

/// Ranks corpus passages against a claim with Okapi BM25 and returns the top
/// `limit`. Replaces `PassthroughEvidenceRetriever` for real corpora, where
/// handing the verifier the first N passages of a thousand-passage record would
/// starve it of the relevant ones.
///
/// Deterministic by construction: term contributions are summed in sorted term
/// order, and ties break by ascending passage `id` (zero-pad numeric suffixes —
/// spec §6 ordering is lexicographic, so `"p10" < "p2"`). Passages sharing no
/// term with the claim are never returned.
public struct BM25TopKRetriever: EvidenceRetrieving, Sendable {
    public let k1: Double
    public let b: Double

    /// Parameters are clamped to their BM25 domains (`k1 >= 0`, `b` in 0...1):
    /// out-of-range values would produce NaN scores, and NaN breaks the sort
    /// comparator's strict weak ordering — silently destroying the determinism
    /// this type promises.
    public init(k1: Double = 1.2, b: Double = 0.75) {
        self.k1 = max(k1.isNaN ? 1.2 : k1, 0)
        self.b = min(max(b.isNaN ? 0.75 : b, 0), 1)
    }

    public func retrieve(
        for claim: Claim,
        from corpus: [EvidencePassage],
        limit: Int
    ) async throws -> [EvidencePassage] {
        guard limit > 0, !corpus.isEmpty else { return [] }
        let queryTerms = Set(Self.terms(in: claim.text))
        guard !queryTerms.isEmpty else { return [] }

        let documents = corpus.map { Self.terms(in: $0.text) }
        let corpusSize = Double(corpus.count)
        let averageLength = documents.reduce(0.0) { $0 + Double($1.count) } / corpusSize

        var documentFrequency: [String: Double] = [:]
        for terms in documents {
            for term in Set(terms) where queryTerms.contains(term) {
                documentFrequency[term, default: 0] += 1
            }
        }

        var scored: [(score: Double, id: String, passage: EvidencePassage)] = []
        for (index, passage) in corpus.enumerated() {
            let terms = documents[index]
            var frequency: [String: Double] = [:]
            for term in terms where queryTerms.contains(term) {
                frequency[term, default: 0] += 1
            }
            guard !frequency.isEmpty else { continue }

            let lengthNorm = k1 * (1 - b + b * Double(terms.count) / max(averageLength, 1))
            var score = 0.0
            for (term, count) in frequency.sorted(by: { $0.key < $1.key }) {
                let df = documentFrequency[term] ?? 0
                let idf = log((corpusSize - df + 0.5) / (df + 0.5) + 1)
                score += idf * (count * (k1 + 1)) / (count + lengthNorm)
            }
            scored.append((score, passage.id, passage))
        }

        return scored
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.id < $1.id }
            .prefix(limit)
            .map(\.passage)
    }

    /// Same word shape the extractor's material-claim gate uses: lowercased
    /// runs of letters and numbers.
    static func terms(in text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }
}
