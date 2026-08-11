# ClaimProofKit Benchmark v0.1

**Safety gate:** PASS
**Corpus:** Evidence-bound legal verification baseline

| Metric | Result | Required |
| --- | ---: | ---: |
| Verdict accuracy | 82.4% | ≥ 70.0% |
| False-supported rate | 0.0% | ≤ 0.0% |
| Contradiction recall | 100.0% | ≥ 80.0% |
| Extraction precision | 100.0% | ≥ 80.0% |
| Extraction recall | 100.0% | ≥ 80.0% |

Cases: 34 verdict · 10 extraction · 6 exact-verdict failures · 0 dangerous approvals

## Ship criteria

**Ship criteria:** MET — necessary on this development corpus, sufficient only on independently labeled realistic documents.

| Metric | Result | Required |
| --- | ---: | ---: |
| Supported-claim precision | 100.0% | ≥ 95.0% |
| Unsupported/contradicted recall | 100.0% | ≥ 90.0% |

| Diagnostic (report-only) | Result |
| --- | ---: |
| Warning precision | 92.3% |
| Abstention precision | 100.0% |
| Abstention recall | 100.0% |
| Expected calibration error | 0.061 |

## Production release gate

**Production release gate:** NOT READY — run with `claimproof benchmark <corpus> --release` to enforce this gate.

Corpus profile: unspecified synthetic/development metadata.

| Metric | Result | Required |
| --- | ---: | ---: |
| Independent legal matters | 0 | ≥ 50 |
| Non-approvable gold claims | 24 | ≥ 300 |
| Approval-eligible gold claims | 10 | ≥ 100 |
| Dangerous approvals | 0 | ≤ 0 |
| False-supported one-sided 95% upper bound | 11.7% | ≤ 1.0% |
| Approval recall | 80.0% | ≥ 80.0% |
| Contradiction recall | 100.0% | ≥ 95.0% |
| Extraction recall | 100.0% | ≥ 98.0% |
| Warning precision | 92.3% | ≥ 80.0% |

Required challenge coverage: 20+ cases each for actor, amount, compoundClaim, date, modality, negation, quotation, sourceAuthority.

Release blockers:
- realistic-corpus metadata is missing
- one or more claim cases have no matterID
- independent matter count 0 < 50
- non-approvable claim count 24 < 300
- approval-eligible claim count 10 < 100
- false-supported 95% upper bound exceeds the required maximum
- contradiction case count 9 < 50
- extraction case count 10 < 50
- challenge tag actor count 0 < 20
- challenge tag amount count 0 < 20
- challenge tag compoundClaim count 0 < 20
- challenge tag date count 0 < 20
- challenge tag modality count 0 < 20
- challenge tag negation count 0 < 20
- challenge tag quotation count 0 < 20
- challenge tag sourceAuthority count 0 < 20
- 19 approval-eligible/contradicted cases lack valid exact gold evidence spans

## Per-category outcomes

| Category | Cases | Exact | Dangerous approvals |
| --- | ---: | ---: | ---: |
| citationIntegrity | 3 | 2 (66.7%) | 0 |
| contradiction | 8 | 8 (100.0%) | 0 |
| directSupport | 8 | 8 (100.0%) | 0 |
| notVerifiable | 2 | 2 (100.0%) | 0 |
| partialSupport | 4 | 3 (75.0%) | 0 |
| reasonableInference | 2 | 0 (0.0%) | 0 |
| sourceAuthority | 3 | 3 (100.0%) | 0 |
| unsupported | 4 | 2 (50.0%) | 0 |

## Calibration

| Confidence | Cases | Avg confidence | Exact-match rate |
| --- | ---: | ---: | ---: |
| 0.4–0.6 | 4 | 0.46 | 25.0% |
| 0.6–0.8 | 13 | 0.69 | 76.9% |
| 0.8–1.0 | 17 | 0.99 | 100.0% |

## Verdict mismatches

- `inference-001` [reasonableInference]: expected `supportedByInference`, predicted `partiallySupported`
- `inference-002` [reasonableInference]: expected `supportedByInference`, predicted `partiallySupported`
- `partial-002` [partialSupport]: expected `partiallySupported`, predicted `contradicted`
- `unsupported-003` [unsupported]: expected `unsupported`, predicted `partiallySupported`
- `unsupported-004` [unsupported]: expected `unsupported`, predicted `partiallySupported`
- `citation-003` [citationIntegrity]: expected `unsupported`, predicted `partiallySupported`
