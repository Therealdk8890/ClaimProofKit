// Copyright 2026 Daniel Kissel
// SPDX-License-Identifier: BUSL-1.1

import Foundation

public struct ReportRenderer: Sendable {
    public init() {}

    public func markdown(_ report: ProofReport) -> String {
        let percent = Int((report.supportRate * 100).rounded())
        var lines = [
            "# ClaimProof Report",
            "",
            "**Publish status:** \(report.isSafeToPublish ? "PASS" : "BLOCKED")",
            "**Supported claims:** \(percent)% (\(report.verdicts.filter { $0.status == .directlySupported || $0.status == .supportedByInference }.count)/\(report.verdicts.count))",
            ""
        ]

        for verdict in report.verdicts {
            lines.append("## [\(verdict.status.rawValue.uppercased())] \(verdict.claim.text)")
            lines.append("")
            lines.append("Type: `\(verdict.claim.type.rawValue)` · Fingerprint: `\(verdict.claim.fingerprint)`")
            lines.append("")
            lines.append(verdict.explanation)
            for match in verdict.evidence {
                lines.append("- `\(match.passage.id)` \(match.passage.source) — \(Int((match.score * 100).rounded()))% term coverage")
                lines.append("  > \(match.passage.text.replacingOccurrences(of: "\n", with: " "))")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}
