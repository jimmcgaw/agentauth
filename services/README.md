# services — Service implementations

Each subdirectory is one service that runs in the platform. Every service
follows the same structural conventions:

- Has a SPIFFE ID from the hierarchy in [`CLAUDE.md`](../CLAUDE.md).
- Obtains its SVID via the Workload API (using `py-spiffe` or `go-spiffe`).
  **Never** reads SVIDs from disk or env vars.
- Sits behind an Envoy PEP (or uses an SDK PEP interceptor) — application
  code does not contain authorization logic.
- Emits structured JSON logs (no `print()`).
- Emits OpenTelemetry traces with the SPIFFE ID in the span attributes.
- Has a `Dockerfile` and is registered in `deploy/docker-compose.yml`.
- Has unit tests; integration tests live under `tests/integration/`.

## Subdirectories

| Path | Purpose | Phase |
|------|---------|-------|
| `audit-collector/` | Receives OPA decision logs and SPIRE events, persists immutable audit trail | Phase 4a |
| `test-agent/` | Reference implementation: minimal Python agent that fetches and rotates an SVID | Phase 1b |
| `common/` | Shared Python modules (logging setup, OTEL bootstrap) | Phase 4b |

> **Status:** Placeholder. Concrete services land in later phases per
> [`prompt.md`](../prompt.md).
