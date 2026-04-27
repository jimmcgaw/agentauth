# policies/lib — Shared Rego helpers

Reusable Rego helper rules. Other policy packages import from here.

> **Status:** Placeholder. The first helper module — `spiffe.rego` for parsing
> SPIFFE IDs — is added in Phase 2b.

## Conventions

- One helper module per concept (`spiffe.rego`, `time.rego`, etc.).
- Each module has a matching `_test.rego` with full coverage of the helpers.
- Helpers must be pure functions — no dependence on `input` or top-level
  `data` paths outside the helper's own package.
