// Copyright 2026 Daniel Kissel
// SPDX-License-Identifier: Apache-2.0

import Foundation

public struct BenchmarkRunner: Sendable {
    public let verifier: ClaimVerifier
    public let extractor: ClaimExtractor
    public let thresholds: BenchmarkThresholds
    public let releaseThresholds: BenchmarkReleaseThresholds

    public init(
        verifier: ClaimVerifier = ClaimVerifier(),
        extractor: ClaimExtractor = ClaimExtractor(),
        thresholds: BenchmarkThresholds = BenchmarkThresholds(),
        releaseThresholds: BenchmarkReleaseThresholds = BenchmarkReleaseThresholds()
    ) {
        self.verifier = verifier
        self.extractor = extractor
        self.thresholds = thresholds
        self.releaseThresholds = releaseThresholds
    }

    public func run(_ corpus: BenchmarkCorpus) -> BenchmarkReport {
        let claimResults = corpus.claimCases.map(runClaimCase)
        let extractionResults = corpus.extractionCases.map(runExtractionCase)

        let accurate = claimResults.filter(\.passed).count
        let verdictAccuracy = ratio(accurate, claimResults.count)

        let unsafeCases = claimResults.filter { !isApproved($0.expected) }
        let dangerous = unsafeCases.filter(\.dangerouslyApproved).count
        // A failure rate is vacuously 0 (not 1) when no unsafe-expected cases exist.
        let falseSupportedRate = unsafeCases.isEmpty ? 0 : ratio(dangerous, unsafeCases.count)
        let falseSupportedUpperBound95 = falseSupportedUpperConfidenceBound95(
            events: dangerous,
            trials: unsafeCases.count
        )

        let expectedContradictions = claimResults.filter { $0.expected == .contradicted }
        let foundContradictions = expectedContradictions.filter { $0.predicted == .contradicted }.count
        let contradictionRecall = ratio(foundContradictions, expectedContradictions.count)

        let extractionTruePositives = extractionResults.reduce(0) { $0 + $1.truePositiveCount }
        let extractionFalsePositives = extractionResults.reduce(0) { $0 + $1.falsePositiveCount }
        let extractionFalseNegatives = extractionResults.reduce(0) { $0 + $1.falseNegativeCount }
        let extractionPrecision = ratio(
            extractionTruePositives,
            extractionTruePositives + extractionFalsePositives
        )
        let extractionRecall = ratio(
            extractionTruePositives,
            extractionTruePositives + extractionFalseNegatives
        )

        var confusion: [String: [String: Int]] = [:]
        for result in claimResults {
            confusion[result.expected.rawValue, default: [:]][result.predicted.rawValue, default: 0] += 1
        }

        // Binary safe/unsafe metrics. "Approved" is the load-bearing outcome:
        // supportedPrecision is "verified means verified", unsupportedRecall is
        // "dangerous claims get caught", warningPrecision is the alarm-fatigue
        // number (a flag on a deserving claim counts as legitimate even when
        // the exact status differs).
        let predictedApproved = claimResults.filter { isApproved($0.predicted) }
        let expectedApproved = claimResults.filter { isApproved($0.expected) }
        let supportedPrecision = ratio(
            predictedApproved.filter { isApproved($0.expected) }.count,
            predictedApproved.count
        )
        let approvalRecall = ratio(
            expectedApproved.filter { isApproved($0.predicted) }.count,
            expectedApproved.count
        )
        let unsupportedRecall = ratio(
            unsafeCases.filter { !isApproved($0.predicted) }.count,
            unsafeCases.count
        )
        let predictedFlagged = claimResults.filter { !isApproved($0.predicted) }
        let warningPrecision = ratio(
            predictedFlagged.filter { !isApproved($0.expected) }.count,
            predictedFlagged.count
        )

        let predictedAbstain = claimResults.filter { isAbstention($0.predicted) }
        let expectedAbstain = claimResults.filter { isAbstention($0.expected) }
        let abstentionPrecision = ratio(
            predictedAbstain.filter { isAbstention($0.expected) }.count,
            predictedAbstain.count
        )
        let abstentionRecall = ratio(
            expectedAbstain.filter { isAbstention($0.predicted) }.count,
            expectedAbstain.count
        )

        var statusMetrics: [String: StatusMetric] = [:]
        for status in SupportStatus.allCases {
            let expectedCount = claimResults.filter { $0.expected == status }.count
            let predictedCount = claimResults.filter { $0.predicted == status }.count
            let matches = claimResults.filter { $0.expected == status && $0.predicted == status }.count
            statusMetrics[status.rawValue] = StatusMetric(
                expectedCount: expectedCount,
                predictedCount: predictedCount,
                matchCount: matches,
                precision: ratio(matches, predictedCount),
                recall: ratio(matches, expectedCount)
            )
        }

        var categoryBreakdown: [String: CategoryMetric] = [:]
        for category in ClaimBenchmarkCase.Category.allCases {
            let cases = claimResults.filter { $0.category == category }
            guard !cases.isEmpty else { continue }
            let exact = cases.filter(\.passed).count
            categoryBreakdown[category.rawValue] = CategoryMetric(
                caseCount: cases.count,
                exactMatchCount: exact,
                dangerousApprovalCount: cases.filter(\.dangerouslyApproved).count,
                exactMatchRate: ratio(exact, cases.count)
            )
        }

        let calibration = calibrationSummary(of: claimResults)
        let matterIDs = Set(corpus.claimCases.compactMap { item -> String? in
            guard let id = item.matterID?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty else {
                return nil
            }
            return id
        })
        var challengeTagCounts: [String: Int] = [:]
        for item in corpus.claimCases {
            for tag in Set(item.challengeTags ?? []) {
                challengeTagCounts[tag, default: 0] += 1
            }
        }

        // A corpus with no unsafe-expected cases cannot measure false approvals,
        // so it must not pass the safety gate vacuously.
        let passes = !unsafeCases.isEmpty
            && verdictAccuracy >= thresholds.minimumVerdictAccuracy
            && falseSupportedRate <= thresholds.maximumFalseSupportedRate
            && contradictionRecall >= thresholds.minimumContradictionRecall
            && extractionPrecision >= thresholds.minimumExtractionPrecision
            && extractionRecall >= thresholds.minimumExtractionRecall

        // The ship criteria are a stricter, separate bar: they gate whether the
        // verifier is fit to face users, not whether the build regressed.
        let ships = !unsafeCases.isEmpty
            && supportedPrecision >= thresholds.minimumSupportedPrecision
            && unsupportedRecall >= thresholds.minimumUnsupportedRecall

        let releaseFailures = productionReleaseFailures(
            corpus: corpus,
            claimResults: claimResults,
            extractionResults: extractionResults,
            unsafeCaseCount: unsafeCases.count,
            dangerousApprovalCount: dangerous,
            approvalEligibleCaseCount: expectedApproved.count,
            falseSupportedUpperBound95: falseSupportedUpperBound95,
            approvalRecall: approvalRecall,
            contradictionRecall: contradictionRecall,
            warningPrecision: warningPrecision,
            extractionRecall: extractionRecall,
            matterCount: matterIDs.count,
            challengeTagCounts: challengeTagCounts
        )

        return BenchmarkReport(
            corpusVersion: corpus.version,
            corpusName: corpus.name,
            corpusMetadata: corpus.metadata,
            thresholds: thresholds,
            releaseThresholds: releaseThresholds,
            claimResults: claimResults,
            extractionResults: extractionResults,
            verdictAccuracy: verdictAccuracy,
            falseSupportedRate: falseSupportedRate,
            falseSupportedUpperBound95: falseSupportedUpperBound95,
            unsafeCaseCount: unsafeCases.count,
            approvalEligibleCaseCount: expectedApproved.count,
            dangerousApprovalCount: dangerous,
            contradictionRecall: contradictionRecall,
            extractionPrecision: extractionPrecision,
            extractionRecall: extractionRecall,
            supportedPrecision: supportedPrecision,
            approvalRecall: approvalRecall,
            unsupportedRecall: unsupportedRecall,
            warningPrecision: warningPrecision,
            abstentionPrecision: abstentionPrecision,
            abstentionRecall: abstentionRecall,
            statusMetrics: statusMetrics,
            categoryBreakdown: categoryBreakdown,
            calibration: calibration,
            confusionMatrix: confusion,
            matterCount: matterIDs.count,
            challengeTagCounts: challengeTagCounts,
            passesSafetyGate: passes,
            meetsShipCriteria: ships,
            passesProductionReleaseGate: releaseFailures.isEmpty,
            productionReleaseGateFailures: releaseFailures
        )
    }

    /// For zero dangerous approvals this is the exact one-sided Clopper-Pearson
    /// upper bound: 1 - alpha^(1/n). That is the load-bearing release path. If a
    /// failure exists the release gate already fails unconditionally; a Wilson
    /// upper bound still provides a useful diagnostic instead of hiding the rate.
    private func falseSupportedUpperConfidenceBound95(events: Int, trials: Int) -> Double {
        guard trials > 0 else { return 1 }
        if events == 0 {
            return 1 - pow(0.05, 1 / Double(trials))
        }
        let z = 1.6448536269514722 // one-sided 95%
        let n = Double(trials)
        let p = Double(events) / n
        let z2 = z * z
        let denominator = 1 + z2 / n
        let center = (p + z2 / (2 * n)) / denominator
        let margin = z * sqrt((p * (1 - p) / n) + (z2 / (4 * n * n))) / denominator
        return min(1, center + margin)
    }

    private func productionReleaseFailures(
        corpus: BenchmarkCorpus,
        claimResults: [BenchmarkCaseResult],
        extractionResults: [ExtractionCaseResult],
        unsafeCaseCount: Int,
        dangerousApprovalCount: Int,
        approvalEligibleCaseCount: Int,
        falseSupportedUpperBound95: Double,
        approvalRecall: Double,
        contradictionRecall: Double,
        warningPrecision: Double,
        extractionRecall: Double,
        matterCount: Int,
        challengeTagCounts: [String: Int]
    ) -> [String] {
        var failures: [String] = []

        if let metadata = corpus.metadata {
            if metadata.origin == .authoredSynthetic {
                failures.append("corpus origin is authoredSynthetic; a realistic legal corpus is required")
            }
            if metadata.split != .sealedHoldout {
                failures.append("corpus split is \(metadata.split.rawValue); sealedHoldout is required")
            }
            if !metadata.independentlyLabeled {
                failures.append("corpus was not independently labeled")
            }
            if metadata.annotatorsPerClaim < releaseThresholds.minimumAnnotatorsPerClaim {
                failures.append("annotators per claim \(metadata.annotatorsPerClaim) < \(releaseThresholds.minimumAnnotatorsPerClaim)")
            }
            if !metadata.binaryLabelAgreement.isFinite ||
                metadata.binaryLabelAgreement < releaseThresholds.minimumBinaryLabelAgreement ||
                metadata.binaryLabelAgreement > 1
            {
                failures.append("binary label agreement is outside the accepted range")
            }
            if metadata.annotationPolicyVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                failures.append("annotation policy version is missing")
            }
        } else {
            failures.append("realistic-corpus metadata is missing")
        }

        if corpus.claimCases.contains(where: { item in
            guard let matterID = item.matterID?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                return true
            }
            return matterID.isEmpty
        }) {
            failures.append("one or more claim cases have no matterID")
        }
        if matterCount < releaseThresholds.minimumMatterCount {
            failures.append("independent matter count \(matterCount) < \(releaseThresholds.minimumMatterCount)")
        }
        if unsafeCaseCount < releaseThresholds.minimumUnsafeCaseCount {
            failures.append("non-approvable claim count \(unsafeCaseCount) < \(releaseThresholds.minimumUnsafeCaseCount)")
        }
        if approvalEligibleCaseCount < releaseThresholds.minimumApprovalEligibleCaseCount {
            failures.append("approval-eligible claim count \(approvalEligibleCaseCount) < \(releaseThresholds.minimumApprovalEligibleCaseCount)")
        }
        if dangerousApprovalCount != 0 {
            failures.append("dangerous approval count \(dangerousApprovalCount) != 0")
        }
        if falseSupportedUpperBound95 > releaseThresholds.maximumFalseSupportedUpperBound95 {
            failures.append("false-supported 95% upper bound exceeds the required maximum")
        }
        if approvalRecall < releaseThresholds.minimumApprovalRecall {
            failures.append("approval recall is below the required minimum")
        }

        let contradictionCaseCount = claimResults.filter { $0.expected == .contradicted }.count
        if contradictionCaseCount < releaseThresholds.minimumContradictionCaseCount {
            failures.append("contradiction case count \(contradictionCaseCount) < \(releaseThresholds.minimumContradictionCaseCount)")
        }
        if contradictionRecall < releaseThresholds.minimumContradictionRecall {
            failures.append("contradiction recall is below the required minimum")
        }
        if extractionResults.count < releaseThresholds.minimumExtractionCaseCount {
            failures.append("extraction case count \(extractionResults.count) < \(releaseThresholds.minimumExtractionCaseCount)")
        }
        if extractionRecall < releaseThresholds.minimumExtractionRecall {
            failures.append("extraction recall is below the required minimum")
        }
        if warningPrecision < releaseThresholds.minimumWarningPrecision {
            failures.append("warning precision is below the required minimum")
        }

        for tag in releaseThresholds.requiredChallengeTags.sorted() {
            let count = challengeTagCounts[tag, default: 0]
            if count < releaseThresholds.minimumCasesPerChallengeTag {
                failures.append("challenge tag \(tag) count \(count) < \(releaseThresholds.minimumCasesPerChallengeTag)")
            }
        }

        let spanRequiredCases = corpus.claimCases.filter {
            isApproved($0.expectedStatus) || $0.expectedStatus == .contradicted
        }
        let invalidGoldSpans = spanRequiredCases.filter { item in
            guard let spans = item.goldEvidenceSpans, !spans.isEmpty else { return true }
            return !spans.allSatisfy { span in
                guard !span.exactQuote.isEmpty,
                      let evidence = item.evidence.first(where: { $0.id == span.evidenceID })
                else { return false }
                guard Data(evidence.text.utf8).range(of: Data(span.exactQuote.utf8)) != nil else {
                    return false
                }
                switch (span.startUTF16, span.endUTF16) {
                case (nil, nil):
                    return true
                case let (.some(start), .some(end)):
                    let units = Array(evidence.text.utf16)
                    guard start >= 0, end >= start, end <= units.count else { return false }
                    return Array(units[start..<end]) == Array(span.exactQuote.utf16)
                default:
                    return false
                }
            }
        }
        if !invalidGoldSpans.isEmpty {
            failures.append("\(invalidGoldSpans.count) approval-eligible/contradicted cases lack valid exact gold evidence spans")
        }

        return failures
    }

    private func calibrationSummary(of results: [BenchmarkCaseResult]) -> CalibrationSummary {
        let binCount = 5
        var binned: [[BenchmarkCaseResult]] = Array(repeating: [], count: binCount)
        for result in results {
            let index = min(binCount - 1, max(0, Int(result.confidence * Double(binCount))))
            binned[index].append(result)
        }
        var bins: [CalibrationBin] = []
        var errorSum = 0.0
        for (index, contents) in binned.enumerated() {
            let lower = Double(index) / Double(binCount)
            let upper = Double(index + 1) / Double(binCount)
            let averageConfidence = contents.isEmpty
                ? 0 : contents.reduce(0.0) { $0 + $1.confidence } / Double(contents.count)
            let exactMatchRate = contents.isEmpty
                ? 0 : Double(contents.filter(\.passed).count) / Double(contents.count)
            bins.append(CalibrationBin(
                lowerBound: lower,
                upperBound: upper,
                caseCount: contents.count,
                averageConfidence: averageConfidence,
                exactMatchRate: exactMatchRate
            ))
            if !contents.isEmpty, !results.isEmpty {
                let weight = Double(contents.count) / Double(results.count)
                errorSum += weight * abs(exactMatchRate - averageConfidence)
            }
        }
        return CalibrationSummary(bins: bins, expectedCalibrationError: errorSum)
    }

    private func isAbstention(_ status: SupportStatus) -> Bool {
        status == .notVerifiable || status == .ambiguous
    }

    private func runClaimCase(_ benchmark: ClaimBenchmarkCase) -> BenchmarkCaseResult {
        let claim = Claim(id: benchmark.id, text: benchmark.claimText, type: benchmark.claimType)
        let verdict = verifier.verify(claim: claim, against: benchmark.evidence)
        return BenchmarkCaseResult(
            id: benchmark.id,
            category: benchmark.category,
            expected: benchmark.expectedStatus,
            predicted: verdict.status,
            confidence: verdict.confidence,
            passed: verdict.status == benchmark.expectedStatus,
            dangerouslyApproved: isApproved(verdict.status) && !isApproved(benchmark.expectedStatus)
        )
    }

    private func runExtractionCase(_ benchmark: ExtractionBenchmarkCase) -> ExtractionCaseResult {
        let expected = Set(benchmark.expectedClaims.map(canonicalClaim))
        let predictedClaims = extractor.extract(from: benchmark.document).map(\.text)
        let predicted = Set(predictedClaims.map(canonicalClaim))
        return ExtractionCaseResult(
            id: benchmark.id,
            expected: benchmark.expectedClaims,
            predicted: predictedClaims,
            truePositiveCount: expected.intersection(predicted).count,
            falsePositiveCount: predicted.subtracting(expected).count,
            falseNegativeCount: expected.subtracting(predicted).count
        )
    }

    private func canonicalClaim(_ text: String) -> String {
        text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined(separator: " ")
    }

    private func isApproved(_ status: SupportStatus) -> Bool {
        status == .directlySupported || status == .supportedByInference
    }

    private func ratio(_ numerator: Int, _ denominator: Int) -> Double {
        denominator == 0 ? 1 : Double(numerator) / Double(denominator)
    }
}
