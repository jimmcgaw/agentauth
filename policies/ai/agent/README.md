# policies/ai/agent — Core agent authorization

Rego package: `ai.agent.authz`.

This package is queried by every PEP for every agent action. The OPA REST
endpoint is `POST /v1/data/ai/agent/authz`.

> **Status:** Placeholder. The actual `authz.rego` and `authz_test.rego` files
> are added in Phase 2 of the build plan (see `prompt.md`).

## Inputs (planned)

```json
{
  "caller": {
    "spiffe_id": "spiffe://ai-agents.example.org/agent/<team>/<agent>",
    "svid_expiry": 1714761600000000000
  },
  "action": "read",
  "resource": {
    "type": "document",
    "id": "doc-123"
  },
  "delegation_chain": []
}
```

## Outputs (planned)

- `allow` — boolean, default `false`
- `deny_reason[msg]` — set of human-readable deny reasons
- `obligations[obj]` — structured obligations the PEP must enforce
- `constraints[c]` — rate limits and similar runtime constraints
