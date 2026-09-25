// Copyright 2026 Daniel Kissel
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Splits a document into reviewable sentences, decomposes simple compound
/// sentences, classifies claim type, and preserves source ranges.
///
/// Extraction behavior is part of Claim Proof Specification v1: claim IDs embed
/// the UTF-16 offset of the sentence match, so any change to segmentation is a
/// spec break gated by the conformance vectors. The scanner below reproduces the
/// exact semantics of the NSRegularExpression implementation it replaced
/// (pattern `[^.!?\n]+(?:[.!?]+|$)` and clause separator `\s+(?:and|but)\s+`),
/// without depending on a regex engine — NSRegularExpression is unavailable in
/// FoundationEssentials-only environments (e.g. the wasm32-wasi SDK), and regex
/// engine drift would silently change claim identities.
/// `ClaimExtractorParityTests` locks the port against the original ICU behavior.
///
/// One deliberate divergence from the replaced implementation: a literal U+001F
/// in the document is ordinary text here. The original replaced conjunction
/// separators with a U+001F sentinel and then split on it, so pre-existing
/// U+001F characters accidentally acted as clause boundaries. That was an
/// implementation artifact, not intent; the corrected behavior is locked by an
/// explicit test in the parity suite.
public struct ClaimExtractor: Sendable {
    public init() {}

    public func extract(from document: String) -> [Claim] {
        let units = Array(document.utf16)
        return sentenceMatches(in: units).flatMap { match -> [Claim] in
            let raw = String(decoding: units[match.start..<match.end], as: UTF16.self)
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isMaterialClaim(text) else { return [] }
            return atomicClauses(in: text).enumerated().map { index, clause in
                Claim(
                    id: "claim-\(match.start)-\(index)",
                    text: clause,
                    type: classify(clause),
                    parentText: clause == text ? nil : text,
                    range: match.start..<match.end
                )
            }
        }
    }

    // MARK: - Sentence scanning

    private struct SentenceMatch {
        let start: Int
        let end: Int
    }

    private enum UTF16Unit {
        static let newline: UInt16 = 0x0A       // \n
        static let carriageReturn: UInt16 = 0x0D // \r
        static let nextLine: UInt16 = 0x85       // NEL
        static let lineSeparator: UInt16 = 0x2028
        static let paragraphSeparator: UInt16 = 0x2029
        static let period: UInt16 = 0x2E
        static let exclamation: UInt16 = 0x21
        static let question: UInt16 = 0x3F
    }

    private func isSentenceTerminator(_ unit: UInt16) -> Bool {
        unit == UTF16Unit.period || unit == UTF16Unit.exclamation || unit == UTF16Unit.question
    }

    private func endsSentenceRun(_ unit: UInt16) -> Bool {
        isSentenceTerminator(unit) || unit == UTF16Unit.newline
    }

    /// The one position (besides end-of-input) where ICU's `$` matches in
    /// non-multiline mode: the start of the input's *final* line terminator,
    /// with `\r\n` counting as a single terminator. `$` never matches before a
    /// terminator that is not the last one, and never between `\r` and `\n`.
    private func finalLineTerminatorStart(in units: [UInt16]) -> Int? {
        guard let last = units.last else { return nil }
        let n = units.count
        if last == UTF16Unit.newline, n >= 2, units[n - 2] == UTF16Unit.carriageReturn {
            return n - 2
        }
        switch last {
        case UTF16Unit.newline, UTF16Unit.carriageReturn, UTF16Unit.nextLine,
             UTF16Unit.lineSeparator, UTF16Unit.paragraphSeparator:
            return n - 1
        default:
            return nil
        }
    }

    /// All matches of `[^.!?\n]+(?:[.!?]+|$)`, leftmost and greedy:
    /// a maximal run of non-terminator, non-newline units followed by either a
    /// maximal run of `.!?` or a `$` position. A run that stops at a newline
    /// which is not the input's final line terminator matches nothing — the
    /// whole line is dropped, exactly as ICU drops it.
    private func sentenceMatches(in units: [UInt16]) -> [SentenceMatch] {
        var matches: [SentenceMatch] = []
        let n = units.count
        let dollar = finalLineTerminatorStart(in: units)
        var i = 0
        while i < n {
            guard !endsSentenceRun(units[i]) else {
                i += 1
                continue
            }
            var j = i
            while j < n, !endsSentenceRun(units[j]) { j += 1 }
            if j == n {
                // Greedy run reached end-of-input; `$` matches there, so any
                // trailing `\r`/NEL/U+2028 stays inside the match.
                matches.append(SentenceMatch(start: i, end: n))
                break
            }
            if isSentenceTerminator(units[j]) {
                var k = j
                while k < n, isSentenceTerminator(units[k]) { k += 1 }
                matches.append(SentenceMatch(start: i, end: k))
                i = k
            } else if let dollar, dollar > i, dollar <= j {
                // Run stopped at a newline: backtracking can still succeed if
                // the final-terminator `$` position falls inside the run (e.g.
                // "…delta\r\n" matches "…delta").
                matches.append(SentenceMatch(start: i, end: dollar))
                i = j + 1
            } else {
                // Every start position inside [i, j) fails against the same
                // newline, so skip past it in one step.
                i = j + 1
            }
        }
        return matches
    }

    // MARK: - Material-claim gate

    private func isMaterialClaim(_ text: String) -> Bool {
        guard !text.isEmpty, !text.hasSuffix("?") else { return false }
        let words = text.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        guard words.count >= 4 else { return false }
        let lower = text.lowercased()
        let nonClaims = ["please note", "this document is not legal advice"]
        return !nonClaims.contains(where: lower.contains)
    }

    // MARK: - Clause splitting

    /// Splits on `\s+(?:and|but)\s+` (case-insensitive), matching ICU exactly:
    /// `\s` is the Unicode White_Space set (the scalar property), and the only
    /// case variants of the ASCII conjunctions are themselves ASCII.
    private func atomicClauses(in sentence: String) -> [String] {
        let scalars = Array(sentence.unicodeScalars)
        var parts: [String] = []
        var segmentStart = 0
        var i = 0
        let n = scalars.count
        while i < n {
            guard scalars[i].properties.isWhitespace else {
                i += 1
                continue
            }
            var j = i
            while j < n, scalars[j].properties.isWhitespace { j += 1 }
            guard j + 3 <= n, isConjunction(scalars[j..<(j + 3)]),
                  j + 3 < n, scalars[j + 3].properties.isWhitespace else {
                // No shorter whitespace run can succeed where the maximal one
                // failed, so resume scanning at the first non-whitespace unit.
                i = j
                continue
            }
            var m = j + 4
            while m < n, scalars[m].properties.isWhitespace { m += 1 }
            if i > segmentStart {
                parts.append(String(String.UnicodeScalarView(scalars[segmentStart..<i])))
            }
            segmentStart = m
            i = m
        }
        if segmentStart < n {
            parts.append(String(String.UnicodeScalarView(scalars[segmentStart...])))
        }

        let trimmed = parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard trimmed.count > 1, trimmed.allSatisfy({ $0.split(separator: " ").count >= 3 }) else {
            return [sentence]
        }
        return trimmed
    }

    private func isConjunction(_ scalars: ArraySlice<Unicode.Scalar>) -> Bool {
        var folded: [UInt32] = []
        folded.reserveCapacity(3)
        for scalar in scalars {
            let value = scalar.value
            guard (0x41...0x5A).contains(value) || (0x61...0x7A).contains(value) else { return false }
            folded.append(value | 0x20)
        }
        return folded == [0x61, 0x6E, 0x64] || folded == [0x62, 0x75, 0x74] // "and" | "but"
    }

    // MARK: - Classification

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
