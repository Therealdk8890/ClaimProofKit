#!/usr/bin/env bash
# Copyright 2026 Daniel Kissel
# SPDX-License-Identifier: BUSL-1.1

set -euo pipefail

repo_root="${1:-$(dirname "$0")/..}"
cd "$repo_root"

readonly scan_paths=(Sources Tests Package.swift)
readonly forbidden_path_pattern='(^|/)(Billing|CloudService|Dashboard|Enterprise|Hosted|Monetization|OnPrem|PolicyEngine|PrivateCloud|ReviewWorkflow|SSO|UsageAnalytics)(/|\.|$)'
readonly forbidden_code_pattern='(ApprovalWorkflow|EnterprisePolicyEngine|HostedEvidenceStore|ImmutableAuditSigner|MeteredUsage|PrivateCloudManager|ReportSigner|SAMLProvider|SCIMProvider|Stripe|SubscriptionManager|UsageAnalyticsService)'

failed=0

while IFS= read -r path; do
    if [[ "$path" =~ $forbidden_path_pattern ]]; then
        printf 'product boundary violation: ClaimProofCloud-only path: %s\n' "$path" >&2
        failed=1
    fi
done < <(find Sources Tests -type f -print | sort)

# Portable grep (BSD and GNU) rather than ripgrep: CI runners don't have rg,
# and a missing tool inside an `if` reads as "no matches" — a vacuous pass the
# guard self-test exists to catch. A scan error must fail loudly, not pass.
scan_status=0
scan_matches=$(grep -rnE --include='*.swift' "$forbidden_code_pattern" "${scan_paths[@]}" 2>&1) || scan_status=$?
if [[ "$scan_status" -eq 0 ]]; then
    printf '%s\n' "$scan_matches"
    printf 'product boundary violation: ClaimProofCloud-only capability found in ClaimProofKit\n' >&2
    failed=1
elif [[ "$scan_status" -ge 2 ]]; then
    printf 'boundary check could not scan the package: %s\n' "$scan_matches" >&2
    exit 2
fi

if [[ "$failed" -ne 0 ]]; then
    printf 'Move the implementation to the sibling ClaimProofCloud repository.\n' >&2
    exit 1
fi

printf 'Product boundary check passed.\n'
