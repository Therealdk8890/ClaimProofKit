# Public legal corpus source assessment

Public datasets can reduce evidence-collection cost, but their published labels
must not be described as ClaimProofKit's independent human holdout unless their
annotation procedure satisfies this repository's policy.

## ContractNLI: development bootstrap only

- Official sources: [dataset site](https://stanfordnlp.github.io/contract-nli/),
  [paper](https://aclanthology.org/2021.findings-emnlp.164/), and
  [repository](https://github.com/stanfordnlp/contract-nli).
- Coverage: 607 non-disclosure agreements, 17 fixed hypotheses, three-way NLI
  labels, and evidence spans.
- License: CC BY 4.0, with terms presented on the official download page.
- Useful mapping: entailment can seed an approvable candidate; contradiction
  can seed `contradicted`; not-mentioned can seed `unsupported`.
- Release limitation: the paper says two Mechanical Turk workers redundantly
  annotated with an emphasis on coverage, their spans were merged, and a
  primary annotator reviewed/adjusted the result. Most development and some
  test material were labeled only by the primary annotator. The paper does not
  publish the pre-adjudication binary Cohen's kappa required here.

Therefore ContractNLI may be imported into `development`, with its original
attribution, but must set `independentlyLabeled` to `false` until two new
qualified ClaimProofKit reviewers label the cases blindly under this policy.
It is NDA-only and cannot establish performance across pro se litigation
workflows.

## CUAD: extraction bootstrap only

- Official sources: [dataset site](https://www.atticusprojectai.org/cuad/) and
  [paper](https://arxiv.org/abs/2103.06268).
- Coverage: 510 commercial contracts, more than 13,000 labels, and 41 clause
  categories.
- Annotation: trained law-student annotators; the paper reports 70-100 hours of
  contract-review training and three additional verifications per annotation.
- License: CC BY 4.0, subject to the official site's terms/disclaimer.
- Release limitation: CUAD is a clause-extraction/review dataset, not an
  evidence-bound approval/contradiction/unsupported verdict task. Its expert
  spans do not supply the binary gold decision or Cohen's kappa required by the
  ClaimProofKit release gate.

CUAD is suitable for extraction development, realistic contract passages, and
distractor construction. It must not be converted into verdict gold by an AI or
simple label mapping.

## Recommended collection order

1. Use ContractNLI and CUAD only for development and workflow calibration after
   the operator reviews and accepts their current terms.
2. Collect a matter-disjoint public/de-identified pilot across landlord-tenant,
   consumer debt, contract, employment, personal injury, family procedure, and
   motion/order workflows.
3. Run two new blind primary reviews plus third-reviewer adjudication with the
   executable workflow in this repository.
4. Freeze the final holdout outside the repository and record a digest before
   any release-gate run.
