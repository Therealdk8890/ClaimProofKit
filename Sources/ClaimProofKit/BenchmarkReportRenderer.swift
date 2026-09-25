// Copyright 2026 Daniel Kissel
// SPDX-License-Identifier: Apache-2.0

import Foundation

public struct BenchmarkReportRenderer: Sendable {
    public init() {}

    public func markdown(_ report: BenchmarkReport) -> String {
        let failures = report.claimResults.filter { !$0.passed }
        let dangerous = report.claimResults.filter(\.dangerouslyApproved)
        var lines = [
            "# ClaimProofKit Benchmark \(report.corpusVersion)",
            "",
            "**Safety gate:** \(report.passesSafetyGate ? "PASS" : "FAIL")",
            "**Corpus:** \(report.corpusName)",
            "",
            "| Metric | Result | Required |",
            "| --- | ---: | ---: |",
            row("Verdict accuracy", report.verdictAccuracy, minimum: report.thresholds.minimumVerdictAccuracy),
            row("False-supported rate", report.falseSupportedRate, maximum: report.thresholds.maximumFalseSupportedRate),
            row("Contradiction recall", report.contradictionRecall, minimum: report.thresholds.minimumContradictionRecall),
            row("Extraction precision", report.extractionPrecision, minimum: report.thresholds.minimumExtractionPrecision),
            row("Extraction recall", report.extractionRecall, minimum: report.thresholds.minimumExtractionRecall),
            "",
            "Cases: \(report.claimResults.count) verdict · \(report.extractionResults.count) extraction · \(failures.count) exact-verdict failures · \(dangerous.count) dangerous approvals",
            "",
            "## Ship criteria",
            "",
            "**Ship criteria:** \(report.meetsShipCriteria ? "MET" : "NOT MET") — necessary on this development corpus, sufficient only on independently labeled realistic documents.",
            "",
            "| Metric | Result | Required |",
            "| --- | ---: | ---: |",
            row("Supported-claim precision", report.supportedPrecision, minimum: report.thresholds.minimumSupportedPrecision),
            row("Unsupported/contradicted recall", report.unsupportedRecall, minimum: report.thresholds.minimumUnsupportedRecall),
            "",
            "| Diagnostic (report-only) | Result |",
            "| --- | ---: |",
            "| Warning precision | \(percent(report.warningPrecision)) |",
            "| Abstention precision | \(percent(report.abstentionPrecision)) |",
            "| Abstention recall | \(percent(report.abstentionRecall)) |",
            "| Expected calibration error | \(fixed(report.calibration.expectedCalibrationError, decimals: 3)) |",
            "",
            "## Production release gate",
            "",
            "**Production release gate:** \(report.passesProductionReleaseGate ? "PASS" : "NOT READY") — run with `claimproof benchmark <corpus> --release` to enforce this gate.",
            "",
            corpusProfile(report),
            "",
            "| Metric | Result | Required |",
            "| --- | ---: | ---: |",
            countRow("Independent legal matters", report.matterCount, minimum: report.releaseThresholds.minimumMatterCount),
            countRow("Non-approvable gold claims", report.unsafeCaseCount, minimum: report.releaseThresholds.minimumUnsafeCaseCount),
            countRow("Approval-eligible gold claims", report.approvalEligibleCaseCount, minimum: report.releaseThresholds.minimumApprovalEligibleCaseCount),
            countRow("Dangerous approvals", report.dangerousApprovalCount, maximum: 0),
            row("False-supported one-sided 95% upper bound", report.falseSupportedUpperBound95, maximum: report.releaseThresholds.maximumFalseSupportedUpperBound95),
            row("Approval recall", report.approvalRecall, minimum: report.releaseThresholds.minimumApprovalRecall),
            row("Contradiction recall", report.contradictionRecall, minimum: report.releaseThresholds.minimumContradictionRecall),
            row("Extraction recall", report.extractionRecall, minimum: report.releaseThresholds.minimumExtractionRecall),
            row("Warning precision", report.warningPrecision, minimum: report.releaseThresholds.minimumWarningPrecision),
            "",
            "Required challenge coverage: \(report.releaseThresholds.minimumCasesPerChallengeTag)+ cases each for \(report.releaseThresholds.requiredChallengeTags.sorted().joined(separator: ", ")).",
            "",
            "Release blockers:",
            report.productionReleaseGateFailures.isEmpty
                ? "- None."
                : report.productionReleaseGateFailures.map { "- \($0)" }.joined(separator: "\n"),
            "",
            "## Per-category outcomes",
            "",
            "| Category | Cases | Exact | Dangerous approvals |",
            "| --- | ---: | ---: | ---: |"
        ]
        for key in report.categoryBreakdown.keys.sorted() {
            guard let metric = report.categoryBreakdown[key] else { continue }
            lines.append("| \(key) | \(metric.caseCount) | \(metric.exactMatchCount) (\(percent(metric.exactMatchRate))) | \(metric.dangerousApprovalCount) |")
        }

        lines.append(contentsOf: ["", "## Calibration", "", "| Confidence | Cases | Avg confidence | Exact-match rate |", "| --- | ---: | ---: | ---: |"])
        for bin in report.calibration.bins where bin.caseCount > 0 {
            lines.append("| \(fixed(bin.lowerBound, decimals: 1))–\(fixed(bin.upperBound, decimals: 1)) | \(bin.caseCount) | \(fixed(bin.averageConfidence, decimals: 2)) | \(percent(bin.exactMatchRate)) |")
        }

        if !failures.isEmpty {
            lines.append(contentsOf: ["", "## Verdict mismatches", ""])
            for failure in failures {
                lines.append("- `\(failure.id)` [\(failure.category.rawValue)]: expected `\(failure.expected.rawValue)`, predicted `\(failure.predicted.rawValue)`")
            }
        }

        let extractionFailures = report.extractionResults.filter {
            $0.falsePositiveCount > 0 || $0.falseNegativeCount > 0
        }
        if !extractionFailures.isEmpty {
            lines.append(contentsOf: ["", "## Extraction mismatches", ""])
            for failure in extractionFailures {
                lines.append("- `\(failure.id)`: \(failure.falsePositiveCount) extra, \(failure.falseNegativeCount) missed")
            }
        }

        return lines.joined(separator: "\n")
    }

    private func row(_ name: String, _ value: Double, minimum: Double) -> String {
        "| \(name) | \(percent(value)) | ≥ \(percent(minimum)) |"
    }

    private func row(_ name: String, _ value: Double, maximum: Double) -> String {
        "| \(name) | \(percent(value)) | ≤ \(percent(maximum)) |"
    }

    private func countRow(_ name: String, _ value: Int, minimum: Int) -> String {
        "| \(name) | \(value) | ≥ \(minimum) |"
    }

    private func countRow(_ name: String, _ value: Int, maximum: Int) -> String {
        "| \(name) | \(value) | ≤ \(maximum) |"
    }

    private func corpusProfile(_ report: BenchmarkReport) -> String {
        guard let metadata = report.corpusMetadata else {
            return "Corpus profile: unspecified synthetic/development metadata."
        }
        return "Corpus profile: \(metadata.origin.rawValue) · \(metadata.split.rawValue) · \(metadata.annotatorsPerClaim) annotator(s)/claim · binary agreement \(fixed(metadata.binaryLabelAgreement, decimals: 2))."
    }

    private func percent(_ value: Double) -> String {
        fixed(value * 100, decimals: 1) + "%"
    }

    /// Fixed-decimal rendering without `String(format:)`, which is unavailable in
    /// FoundationEssentials-only environments (e.g. the wasm32-wasi SDK).
    ///
    /// `printf` rounds the *exact* decimal expansion of the binary value, so a
    /// naive multiply-by-scale loses the sub-ulp excess that decides cases like
    /// 0.025 → "0.03". The fused multiply-add recovers the product's exact
    /// residual, letting the half-point comparison match printf digit-for-digit;
    /// parity is locked by `BenchmarkRendererFormattingTests` and the committed
    /// report drift check in CI. Internal (not private) for those tests.
    /// Parity holds for finite values with `|value| * scale < 2^53` — far above
    /// anything a benchmark report emits (ratios and percentages). Outside that
    /// domain the value falls back to Swift's own rendering instead of trapping;
    /// 64-bit arithmetic keeps the path safe on 32-bit `Int` platforms (wasm32).
    func fixed(_ value: Double, decimals: Int) -> String {
        precondition((0...3).contains(decimals))
        let sign = value.sign == .minus ? "-" : ""
        let magnitude = value.magnitude
        let scale = [1.0, 10.0, 100.0, 1000.0][decimals]

        let product = magnitude * scale
        guard product.isFinite, product < 0x1p53 else {
            return String(describing: value)
        }
        let residual = (-product).addingProduct(magnitude, scale) // exact: fma(m, s, -p)
        let floorValue = product.rounded(.down)
        var units = Int64(floorValue)
        let remainderMinusHalf = (product - floorValue) - 0.5
        if remainderMinusHalf > -residual {
            units += 1
        } else if remainderMinusHalf == -residual, units % 2 != 0 {
            units += 1 // exactly halfway: ties to even, like printf
        }

        let intScale = Int64(scale)
        let whole = units / intScale
        guard decimals > 0 else { return sign + String(whole) }
        var fraction = String(units % intScale)
        while fraction.count < decimals { fraction = "0" + fraction }
        return "\(sign)\(whole).\(fraction)"
    }
}
