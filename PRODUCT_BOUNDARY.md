# Product boundary

ClaimProofKit is the source-available verification foundation. It is licensed under BUSL-1.1 for non-production use and under separate commercial terms for production use until the applicable Change Date. It may contain:

- Claim and evidence schemas
- Extraction and verification interfaces
- Basic local extraction and claim-to-passage matching
- Local TrustReport generation
- CLI and CI primitives
- Integration adapters

Hosted and enterprise operational features belong in the separate proprietary `ClaimProofCloud` repository. This repository must not contain implementations of:

- Hosted verification services or managed evidence storage
- Team dashboards, review queues, or approval workflows
- Advanced or domain-trained verification models
- Enterprise proof-policy engines
- Long-term report retention or immutable audit-package signing
- Billing, subscriptions, entitlements, or usage metering
- SSO, SAML, SCIM, or enterprise role-based access control
- Private-cloud or on-premises management planes
- Enterprise support or SLA automation

Package interfaces may permit commercially licensed integrations to implement these capabilities. ClaimProofCloud's implementations, deployment machinery, models, and operational workflows remain outside this repository.

The boundary check at `scripts/check-product-boundary.sh` runs in CI and rejects common ClaimProofCloud-only modules or symbols under package source paths. It is a guardrail, not a substitute for architectural or licensing review.
