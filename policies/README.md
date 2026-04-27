# policies — Rego policy source of truth

This directory is the authoritative source for all authorization policy in the
platform. OPA instances load these policies (via OPAL or the bundle protocol)
and evaluate them on every authorization query.

Per [`CLAUDE.md`](../CLAUDE.md):

- All `.rego` files use `import rego.v1` (the v1 syntax).
- Every `.rego` file has a corresponding `_test.rego` file.
- Every policy starts with `default allow := false`.
- Authorization data (capability lists, role maps, sensitivity labels) lives
  in `data/` as JSON. **No hardcoded values inside Rego rules.**
- Application code never duplicates these rules — services call OPA.

## Layout

| Path | Contents |
|------|----------|
| `ai/agent/` | Core agent authorization policy and tests |
| `data/` | Static policy data (agents, resource permissions, config) |
| `lib/` | Shared Rego helper rules (e.g., SPIFFE ID parsing) |

## Local workflow

```bash
opa test policies/ -v       # run all policy tests
regal lint policies/        # lint
conftest verify             # validate policy structure
```

CI runs all three on every PR. Failures block merge.

## Adding a new policy

1. Create the `.rego` file under the appropriate package directory.
2. Create the matching `_test.rego` file with at least one test per rule.
3. If the policy reads new data, add the data fixture under `data/`.
4. If the policy changes authorization semantics for existing agents, write
   an ADR under `docs/adr/`.
