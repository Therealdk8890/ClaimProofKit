#!/usr/bin/env bash
# Copyright 2026 Daniel Kissel
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

mkdir -p "$fixture/Sources/Public" "$fixture/Tests"
printf '// public verification primitive\n' > "$fixture/Sources/Public/Verifier.swift"
printf '// swift-tools-version: 6.0\n' > "$fixture/Package.swift"

bash "$repo_root/scripts/check-product-boundary.sh" "$fixture" >/dev/null

printf 'struct SubscriptionManager {}\n' > "$fixture/Sources/Public/SubscriptionManager.swift"
if bash "$repo_root/scripts/check-product-boundary.sh" "$fixture" >/dev/null 2>&1; then
    printf 'boundary guard self-test failed: commercial capability was accepted\n' >&2
    exit 1
fi

printf 'Product boundary guard self-test passed.\n'
