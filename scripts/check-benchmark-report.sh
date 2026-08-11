#!/usr/bin/env bash
# Copyright 2026 Daniel Kissel
# SPDX-License-Identifier: BUSL-1.1

set -euo pipefail

cd "$(dirname "$0")/.."
generated="$(mktemp)"
trap 'rm -f "$generated"' EXIT

swift run claimproof benchmark Fixtures/benchmark-v0.1.json > "$generated"
diff -u Docs/BENCHMARK_V0.1.md "$generated"
printf 'Benchmark report is current.\n'
