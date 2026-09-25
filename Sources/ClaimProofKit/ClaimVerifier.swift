// Copyright 2026 Daniel Kissel
// SPDX-License-Identifier: Apache-2.0

import Foundation

public struct ClaimVerifier: Sendable {
    public let policy: VerificationPolicy

    public init(policy: VerificationPolicy = VerificationPolicy()) {
        self.policy = policy
    }

    public func verify(document: String, against passages: [EvidencePassage]) -> ProofReport {
        let claims = ClaimExtractor().extract(from: document)
        return verify(claims: claims, against: passages)
    }

    public func verify(claims: [Claim], against passages: [EvidencePassage]) -> ProofReport {
        ProofReport(verdicts: claims.map { verify(claim: $0, against: passages) })
    }

    public func verify(claim: Claim, against passages: [EvidencePassage]) -> ClaimVerdict {
        guard isVerifiable(claim.type) else {
            return verdict(claim, .notVerifiable, 1, [], "This claim type requires a verifier or proof policy that is not configured.")
        }
        let eligiblePassages = passages.filter { isEligible($0.sourceType, for: claim.type) }
        let claimTerms = significantTerms(in: claim.text)
        let ranked = eligiblePassages.map { passage -> EvidenceMatch in
            let passageTerms = significantTerms(in: passage.text)
            let matched = claimTerms.intersection(passageTerms).sorted()
            let score = claimTerms.isEmpty ? 0 : Double(matched.count) / Double(claimTerms.count)
            return EvidenceMatch(passage: passage, score: score, matchedTerms: matched)
        }
        .sorted {
            // Deterministic ranking: passage id breaks score ties so verdicts and
            // report ordering are identical across stdlib sort implementations.
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.passage.id < $1.passage.id
        }

        guard let best = ranked.first, best.score > 0 else {
            return verdict(claim, .unsupported, 1, [], "No supplied evidence passage shares the claim's material terms.")
        }

        let evidence = Array(ranked.prefix(policy.maximumEvidenceMatches).filter { $0.score > 0 })
        if best.score >= policy.ambiguousThreshold,
           isSpeculative(best.passage.text),
           !isSpeculative(claim.text) {
            return verdict(claim, .unsupported, best.score, evidence, "The passage discusses only a possible or proposed event and does not support the claim that it occurred.")
        }
        let polarityConflict = hasNegation(claim.text) != hasNegation(best.passage.text)
            || hasOpposingTerms(claim.text, best.passage.text)
            || hasStructuredValueConflict(claim.text, best.passage.text)

        if best.score >= policy.contradictionThreshold, polarityConflict {
            return verdict(claim, .contradicted, best.score, evidence, "The closest evidence uses the same material terms but reverses the claim's polarity.")
        }
        if best.score >= policy.supportedThreshold {
            return verdict(claim, .directlySupported, best.score, evidence, "A supplied passage covers the claim's material terms.")
        }
        if best.score >= policy.ambiguousThreshold {
            return verdict(claim, .partiallySupported, best.score, evidence, "Related evidence exists, but it does not cover enough of the claim to prove it.")
        }
        return verdict(claim, .unsupported, 1 - best.score, evidence, "The closest passage does not sufficiently support the claim.")
    }

    private func verdict(
        _ claim: Claim,
        _ status: SupportStatus,
        _ confidence: Double,
        _ evidence: [EvidenceMatch],
        _ explanation: String
    ) -> ClaimVerdict {
        ClaimVerdict(
            claim: claim,
            status: status,
            confidence: min(max(confidence, 0), 1),
            evidence: evidence,
            explanation: explanation
        )
    }

    private func hasNegation(_ text: String) -> Bool {
        let terms = Set(text.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
        return !terms.isDisjoint(with: ["not", "no", "never", "without", "cannot"])
    }

    private func isSpeculative(_ text: String) -> Bool {
        let terms = Set(text.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
        return !terms.isDisjoint(with: [
            "considering", "possible", "possibly", "proposed", "proposal", "planned",
            "planning", "might", "could", "draft", "expected", "intends"
        ])
    }

    private func hasOpposingTerms(_ lhs: String, _ rhs: String) -> Bool {
        let left = significantTerms(in: lhs)
        let right = significantTerms(in: rhs)
        let opposites = [
            ("grant", "deny"), ("approve", "reject"), ("admit", "deny"), ("before", "after"),
            ("increase", "decrease"), ("present", "absent")
        ]
        return opposites.contains { pair in
            (left.contains(pair.0) && right.contains(pair.1))
                || (left.contains(pair.1) && right.contains(pair.0))
        }
    }

    private func hasStructuredValueConflict(_ lhs: String, _ rhs: String) -> Bool {
        let left = structuredValues(in: lhs)
        let right = structuredValues(in: rhs)
        guard !left.isEmpty, !right.isEmpty else { return false }
        return !left.isSubset(of: right) && !right.isSubset(of: left)
    }

    private func structuredValues(in text: String) -> Set<String> {
        let monthNames: Set<String> = [
            "january", "february", "march", "april", "may", "june",
            "july", "august", "september", "october", "november", "december"
        ]
        return Set(text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { token in token.contains(where: \.isNumber) || monthNames.contains(token) })
    }

    private func isVerifiable(_ type: Claim.ClaimType) -> Bool {
        type != .recommendation && type != .unknown
    }

    private func isEligible(_ source: EvidencePassage.SourceType, for type: Claim.ClaimType) -> Bool {
        if source == .unknown { return true }
        switch type {
        case .factual:
            return [.evidence, .declaration, .courtRecord].contains(source)
        case .legalRule:
            return [.statute, .regulation, .courtRule, .caseLaw].contains(source)
        case .legalConclusion:
            return source != .calculationInput
        case .calculation:
            return source == .calculationInput
        case .quotation:
            return true
        case .recommendation, .unknown:
            return false
        }
    }

    private func significantTerms(in text: String) -> Set<String> {
        let stopWords: Set<String> = [
            "a", "an", "and", "are", "as", "at", "be", "been", "by", "for", "from",
            "did", "does", "has", "have", "in", "is", "it", "no", "not", "of", "on", "or",
            "that", "the", "this", "to", "was", "were", "will", "with"
        ]
        return Set(text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .map(normalizedTerm)
            .filter { $0.count > 1 && !stopWords.contains($0) })
    }

    private func normalizedTerm(_ term: String) -> String {
        let irregular = [
            "admitted": "admit", "decreased": "decrease", "denied": "deny", "filed": "file",
            "granted": "grant", "increased": "increase", "received": "receive"
        ]
        if let normalized = irregular[term] { return normalized }
        if term.count > 5, term.hasSuffix("ing") { return String(term.dropLast(3)) }
        if term.count > 4, term.hasSuffix("ed") { return String(term.dropLast(2)) }
        if term.count > 4, term.hasSuffix("s") { return String(term.dropLast()) }
        return term
    }
}
