#!/usr/bin/env bash
# Copyright 2026 Daniel Kissel
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

required_license_lines=(
    'Apache License'
    'Version 2.0, January 2004'
    'Copyright 2026 Daniel Kissel'
)

for line in "${required_license_lines[@]}"; do
    if ! grep -Fqx "$line" LICENSE; then
        printf 'license surface check failed: LICENSE is missing: %s\n' "$line" >&2
        exit 1
    fi
done

missing_header=0
while IFS= read -r path; do
    if ! grep -Fq 'SPDX-License-Identifier: Apache-2.0' "$path"; then
        printf 'license surface check failed: missing Apache-2.0 header: %s\n' "$path" >&2
        missing_header=1
    fi
done < <(
    find Package.swift Sources Tests scripts         ConformanceHarness/Package.swift         ConformanceHarness/Sources         ConformanceHarness/regenerate-vectors.sh         -type f \( -name '*.swift' -o -name '*.sh' \) -print | sort
)

if [[ "$missing_header" -ne 0 ]]; then
    exit 1
fi

stale_matches=$(grep -RInE     --exclude-dir=.git     --exclude-dir=.build     --exclude=LICENSE     --exclude=check-license-surface.sh     'BUSL-1.1|Business Source License|source-available under'     . || true)

if [[ -n "$stale_matches" ]]; then
    printf '%s\n' "$stale_matches" >&2
    printf 'license surface check failed: stale BUSL/source-available wording found\n' >&2
    exit 1
fi

if ! grep -Fq 'open source under the [Apache License 2.0](LICENSE)' README.md; then
    printf 'license surface check failed: README does not identify Apache-2.0\n' >&2
    exit 1
fi

printf 'Apache-2.0 license surface check passed.\n'
