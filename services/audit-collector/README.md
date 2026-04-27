# services/audit-collector

The audit collector receives:

1. **OPA Decision Logs** — pushed via HTTP POST by the OPA decision-log
   plugin. Every allow/deny with full input context.
2. **SPIRE event hooks** — SVID issuance, renewal, and revocation events.

It validates each entry has the required fields (SPIFFE ID, action, resource,
decision, timestamp), persists it to append-only structured storage, and
exposes Prometheus metrics for dashboards and alerting.

| Attribute | Value |
|-----------|-------|
| **SPIFFE ID** | `spiffe://ai-agents.example.org/service/audit-collector` |
| **Inbound auth** | mTLS with X.509-SVID |
| **Storage (dev)** | Append-only structured JSON files |
| **Storage (prod)** | TBD — Elasticsearch / S3 / cloud-native log service |

> **Status:** Placeholder. Implementation lands in Phase 4a per
> [`prompt.md`](../../prompt.md).
