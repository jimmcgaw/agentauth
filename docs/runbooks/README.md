# Runbooks

Operational runbooks for incident response and recurring procedures.

> **Status:** Placeholder. Runbooks will be added as the platform matures.

## Planned runbooks

- `spire-server-down.md` — recovery when the SPIRE Server is unreachable
- `opa-unreachable.md` — operating with PEP fail-closed behavior in effect
- `policy-rollback.md` — rolling back a bad policy push via OPAL
- `svid-revocation.md` — revoking a compromised workload identity
- `audit-pipeline-degradation.md` — handling audit-log shipping failures

Each runbook should follow the format: **Symptoms → Triage → Mitigation →
Resolution → Postmortem hooks.**
