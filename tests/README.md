# tests — Integration and end-to-end tests

| Path | Purpose |
|------|---------|
| `integration/` | Cross-component tests — exercise two or three components together (e.g., SPIRE Agent + a service) |
| `e2e/` | End-to-end tests — bring up the full Docker Compose stack and exercise real auth flows |

Unit tests live next to the code they test (under `services/<name>/tests/`),
not here.

## Running

```bash
pytest tests/                   # all integration + e2e
pytest tests/integration/       # integration only (lighter — fewer containers)
pytest tests/e2e/               # e2e only (full stack required)
make test-e2e                   # the canonical "is the whole stack working?" command (added in Phase 3b)
```

## The pinned invariant test

Once Phase 3b lands, `tests/e2e/test_full_auth_flow.py` is the *invariant
test*: every PR after that point must keep it passing. It proves the entire
identity → policy → enforcement → audit chain still works end-to-end.
