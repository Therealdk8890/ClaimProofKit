# Legal evidence annotation policy v1

This policy governs human gold labels for ClaimProofKit's evidence-bound legal
benchmark. It evaluates only whether the supplied record supports a claim. It
does not ask whether the claim is good legal advice or ultimately true outside
the supplied record.

## Independence and reviewer qualifications

- Two primary reviewers label every claim independently.
- A third, distinct reviewer labels detailed disagreements without seeing the
  engine prediction or either primary reviewer's answer.
- Reviewers must be able to read the document type and jurisdiction presented.
  Legal-rule and legal-conclusion claims require a lawyer, supervised law
  student, paralegal, or other reviewer whose qualification is documented by
  the corpus coordinator.
- Reviewers may consult this policy and the supplied evidence packet only. They
  must not compare answers or see benchmark/model output before submission.
- A reviewer must disclose conflicts involving a party or matter and skip the
  assignment. The coordinator replaces that reviewer; skipped assignments are
  not treated as labels.

## Load-bearing binary decision

Set `approvalEligible` to `true` only for `directlySupported` or
`supportedByInference`. Every other detailed status is non-approvable.

| Status | Meaning |
| --- | --- |
| `directlySupported` | The supplied record expressly supports every material element. |
| `supportedByInference` | Every material element follows from a short, necessary, defensible inference with no material conflict. |
| `partiallySupported` | Some material elements are supported, but at least one is absent or overclaimed. |
| `contradicted` | Reliable supplied evidence conflicts with at least one material element. |
| `ambiguous` | The supplied record reasonably supports more than one material reading. |
| `unsupported` | The record does not establish the claim and does not affirmatively contradict it. |
| `notVerifiable` | The claim is advice, prediction, opinion, or otherwise not decidable from the supplied evidence. |

Material elements include actor, entity, event, amount, date, duration,
location, negation, modality, condition, procedural disposition, quotation,
and every component of a compound claim. A legal-rule claim also requires the
right authority, jurisdiction, effective date, and procedural context.

When in doubt between an approvable and non-approvable label, select the most
specific non-approvable status and explain the missing or conflicting element.
This is not permission to reject everything: a fully grounded claim must be
marked approvable.

## Evidence spans and rationale

- `directlySupported`, `supportedByInference`, and `contradicted` require at
  least one evidence span.
- `exactQuote` must be copied exactly from the identified passage. Do not fix
  spelling, whitespace, OCR, or punctuation in the quote.
- Include all spans needed to understand a cross-reference, definition,
  exception, condition, or multi-document inference. Prefer the shortest set
  that remains self-contained.
- For `unsupported`, an empty span list is normal. Do not cite an irrelevant
  passage merely to fill the field.
- The rationale must identify the load-bearing supported, absent, ambiguous, or
  conflicting element. It must not mention an engine prediction.

## Compound claims and source authority

A compound claim is approvable only when every material component is
approvable. If one component conflicts, use `contradicted`; if one component is
merely absent, use `partiallySupported`.

Party statements may support that the party made a statement, but not
necessarily that the statement's contents are true. A docket entry may support
that a filing occurred; it does not establish the filing's allegations. Use
the controlling source for legal rules and the operative order for procedural
dispositions.

## Adjudication and audit

The coordinator calculates Cohen's kappa on the two primary reviewers'
pre-adjudication binary decisions. Raw percent agreement is not a substitute.
All detailed-status disagreements go to the third reviewer. Original
submissions and the coordinator manifest remain in the private audit ledger;
only the finalized gold corpus is supplied to the benchmark runner.
