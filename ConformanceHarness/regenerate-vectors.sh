#!/usr/bin/env bash
# Copyright 2026 Daniel Kissel
# SPDX-License-Identifier: Apache-2.0
#
# Re-lock the Claim Proof Specification vectors from the live implementation,
# then show what changed. Regenerating is an intentional act: any diff below
# is a behavior change that requires a spec-version review before commit
# (see Docs/PROOF_SPEC_V1.md).
set -euo pipefail
cd "$(dirname "$0")"
swift run ConformanceHarness --regenerate
echo
echo "Vector diff (every hunk below is locked behavior changing):"
git --no-pager diff --stat -- vectors 2>/dev/null || true
git status --short -- vectors 2>/dev/null || true
echo
echo "If any vector changed, bump ClaimProofSpec.version (or verifierVersion)"
echo "in Sources/ClaimProofKit/ProofIdentity.swift before committing."
