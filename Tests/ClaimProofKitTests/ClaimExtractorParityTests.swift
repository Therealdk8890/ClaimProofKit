// Copyright 2026 Daniel Kissel
// SPDX-License-Identifier: Apache-2.0

#if !os(WASI)

import Foundation
import Testing
@testable import ClaimProofKit

/// Locks the hand-rolled UTF-16 scanner in `ClaimExtractor` to the exact
/// behavior of the NSRegularExpression implementation it replaced. Extraction
/// is spec surface — claim IDs embed UTF-16 offsets — so the port must be
/// indistinguishable, including ICU's `$`-before-final-line-terminator rule and
/// its habit of dropping unterminated lines mid-document.
@Suite("ClaimExtractor ICU parity")
struct ClaimExtractorParityTests {
    private let ported = ClaimExtractor()
    private let reference = ReferenceClaimExtractor()

    private static let fixtures: [String] = [
        "",
        "\n",
        "\r\n",
        "\n\n",
        "Alpha beta gamma delta",
        "Alpha beta gamma delta\n",
        "Alpha beta gamma delta\n\n",
        "Alpha beta gamma delta\r\n",
        "Alpha beta gamma delta\r",
        "Alpha beta gamma delta\u{2028}",
        "Alpha beta gamma delta\u{0085}",
        "Alpha beta gamma delta\nEcho foxtrot golf hotel.",
        "Alpha beta gamma delta.\nEcho foxtrot golf hotel",
        "Alpha beta gamma delta.\nEcho foxtrot golf hotel\n",
        "Alpha beta gamma delta?! Echo foxtrot golf hotel...",
        "Alpha beta.\n.Echo foxtrot",
        "One two three four...Five six seven eight.",
        "  Alpha beta gamma delta. Next one two three.",
        "Alpha 😀 beta gamma delta. Echo foxtrot golf hotel.",
        "Alpha be\u{0301}ta gamma delta. Second sentence here now.",
        "Is this a question with many words?",
        "Too short.",
        "Please note this covers four words here.",
        "This document is not legal advice and should be ignored entirely.",
        "The court granted the motion and the case was dismissed.",
        "The court granted the motion AND the case was dismissed.",
        "One two three and four five six but seven eight nine.",
        "sand and gravel were delivered on time.",
        "A and B and C.",
        "tab\tand\tseparated words appear here often.",
        "nbsp\u{00A0}and\u{00A0}separated words appear here often.",
        "NEL\u{0085}and\u{0085}separated words appear here often.",
        "ideographic\u{3000}and\u{3000}spaces appear here often.",
        "double  and  spaced words appear here often.",
        "Ends with and ",
        " and starts with conjunction here.",
        "The statute requires timely filing. The response was calculated wrongly, therefore rules were violated.",
        "He said \"the check cleared\" and the ledger equals the total.",
        "The response must be filed within 14 days. The court denied the request.\nUnterminated trailing line with several words",
        "Mixed terminators!? And more!!! Then... nothing",
        "\u{2028}Leading line separator sentence with words.",
        "Trailing carriage return line with words\rAnd a second line with words\r\n",
        "alpha beta gamma\u{1F}delta epsilon zeta",
        "he said\u{1F}the check cleared and the ledger equals the total.",
        "one two three\u{1F}and four five six.",
    ]

    @Test("fixture parity", arguments: fixtures)
    func fixtureParity(document: String) {
        #expect(ported.extract(from: document) == reference.extract(from: document))
    }

    @Test("U+001F is ordinary text, never a clause boundary")
    func unitSeparatorIsOrdinaryText() {
        // The replaced NSRegularExpression implementation split clauses on
        // pre-existing U+001F via its sentinel collision; the port deliberately
        // does not. This locks the corrected, canonical behavior.
        let claims = ported.extract(from: "alpha beta gamma\u{1F}delta epsilon zeta")
        #expect(claims.count == 1)
        #expect(claims.first?.text == "alpha beta gamma\u{1F}delta epsilon zeta")
        #expect(claims.first?.parentText == nil)
    }

    @Test("seeded fuzz parity")
    func fuzzParity() {
        var rng = SplitMix64(seed: 0x00C1A1_50F4_2026)
        let tokens: [String] = [
            "alpha", "beta", "gamma", "delta", "epsilon", "and", "but", "AND", "aNd", "BuT",
            "andiron", "brand", "sand", "abut", ".", "!", "?", "...", "?!", "\n", "\r", "\r\n",
            "\n\n", " ", "  ", "\t", "\u{00A0}", "\u{0085}", "\u{000B}", "\u{2028}", "\u{2029}",
            "\u{3000}", "\u{001F}", "😀", "e\u{0301}", "\u{FEFF}", "\"", "must be filed", "statute",
            "therefore", "equals", "recommend", "recommends", "please note",
            "this document is not legal advice", "one two three four",
        ]
        for _ in 0..<500 {
            var document = ""
            for _ in 0..<Int(rng.next() % 40) {
                document += tokens[Int(rng.next() % UInt64(tokens.count))]
            }
            let expected = reference.extract(from: document)
            let actual = ported.extract(from: document)
            #expect(actual == expected, "diverged on: \(document.debugDescription)")
        }
    }
}

/// Deterministic RNG so fuzz failures reproduce exactly.
private struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// Copy of the NSRegularExpression-based extractor this port replaced, with one
/// deliberate correction: clause segments derive from match *ranges* instead of
/// the original's replace-with-U+001F-sentinel-then-split, which accidentally
/// treated pre-existing U+001F characters as clause boundaries. The port treats
/// U+001F as ordinary text; this reference locks that corrected behavior while
/// remaining byte-identical to the original on every U+001F-free input.
private struct ReferenceClaimExtractor {
    func extract(from document: String) -> [Claim] {
        let pattern = #"[^.!?\n]+(?:[.!?]+|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsDocument = document as NSString
        let fullRange = NSRange(location: 0, length: nsDocument.length)

        return regex.matches(in: document, range: fullRange).flatMap { match -> [Claim] in
            let raw = nsDocument.substring(with: match.range)
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isMaterialClaim(text) else { return [] }
            let start = match.range.location
            return atomicClauses(in: text).enumerated().map { index, clause in
                Claim(
                    id: "claim-\(start)-\(index)",
                    text: clause,
                    type: classify(clause),
                    parentText: clause == text ? nil : text,
                    range: start..<(start + match.range.length)
                )
            }
        }
    }

    private func isMaterialClaim(_ text: String) -> Bool {
        guard !text.isEmpty, !text.hasSuffix("?") else { return false }
        let words = text.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        guard words.count >= 4 else { return false }
        let lower = text.lowercased()
        let nonClaims = ["please note", "this document is not legal advice"]
        return !nonClaims.contains(where: lower.contains)
    }

    private func atomicClauses(in sentence: String) -> [String] {
        let separators = try? NSRegularExpression(pattern: #"\s+(?:and|but)\s+"#, options: [.caseInsensitive])
        guard let separators else { return [sentence] }
        let ns = sentence as NSString
        let matches = separators.matches(in: sentence, range: NSRange(location: 0, length: ns.length))
        var segments: [String] = []
        var cursor = 0
        for match in matches {
            if match.range.location > cursor {
                segments.append(ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))
            }
            cursor = match.range.location + match.range.length
        }
        if cursor < ns.length {
            segments.append(ns.substring(from: cursor))
        }
        let parts = segments.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard parts.count > 1, parts.allSatisfy({ $0.split(separator: " ").count >= 3 }) else {
            return [sentence]
        }
        return parts
    }

    private func classify(_ claim: String) -> Claim.ClaimType {
        let lower = claim.lowercased()
        if lower.contains(" recommends ") || lower.hasPrefix("recommend ") { return .recommendation }
        if lower.contains(" therefore ") || lower.contains(" violated ") { return .legalConclusion }
        if lower.contains(" law requires ") || lower.contains(" statute ") || lower.contains(" rule requires ")
            || lower.contains(" must be filed") || lower.contains(" shall be filed") {
            return .legalRule
        }
        if lower.contains(" calculated ") || lower.contains(" equals ") { return .calculation }
        if lower.contains("\"") { return .quotation }
        return .factual
    }
}

/// The formatter that replaced `String(format:)` must agree with it byte-for-byte
/// over the value shapes the benchmark report produces; the committed-report
/// drift check in CI depends on it.
@Suite("Benchmark renderer formatting parity")
struct BenchmarkRendererFormattingTests {
    @Test("percent and fixed match printf over benchmark-shaped values")
    func formatParity() {
        let renderer = BenchmarkReportRenderer()
        for denominator in 1...60 {
            for numerator in 0...denominator {
                let value = Double(numerator) / Double(denominator)
                #expect(renderer.fixed(value * 100, decimals: 1) == String(format: "%.1f", value * 100))
                #expect(renderer.fixed(value, decimals: 2) == String(format: "%.2f", value))
                #expect(renderer.fixed(value, decimals: 3) == String(format: "%.3f", value))
            }
        }
        for step in 0...20 {
            let value = Double(step) * 0.05
            #expect(renderer.fixed(value, decimals: 1) == String(format: "%.1f", value))
        }
    }

    @Test("seeded fuzz against printf")
    func fuzzAgainstPrintf() {
        let renderer = BenchmarkReportRenderer()
        var rng = SplitMix64(seed: 0xF0_44A7)
        for _ in 0..<2000 {
            let value = Double(rng.next() >> 11) * (1.0 / Double(1 << 53)) // uniform [0, 1)
            for decimals in 1...3 {
                #expect(
                    renderer.fixed(value, decimals: decimals)
                        == String(format: "%.\(decimals)f", value),
                    "diverged on \(value.debugDescription) at \(decimals) decimals"
                )
                #expect(
                    renderer.fixed(value * 100, decimals: decimals)
                        == String(format: "%.\(decimals)f", value * 100),
                    "diverged on \((value * 100).debugDescription) at \(decimals) decimals"
                )
            }
        }
    }
}

#endif
