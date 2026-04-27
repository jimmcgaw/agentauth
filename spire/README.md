# spire — SPIRE Server / Agent configuration

Configuration files and registration entries for the SPIFFE Runtime
Environment (SPIRE).

| Path | Purpose |
|------|---------|
| `server/server.conf` | SPIRE Server configuration (datastore, CA, plugins) |
| `agent/agent.conf` | SPIRE Agent configuration (server address, attestors) |
| `entries/` | Workload registration entries (selector → SPIFFE ID) |

## Trust domain

All configurations use the trust domain `ai-agents.example.org` for local
development. Production / staging trust domains are environment-specific and
managed via overlay files (added in later phases).

## Local development notes

- Datastore is in-memory / SQLite — fine for dev, **not** for production.
- Node attestation uses `join_token` — this is a dev-only convenience. Real
  environments use k8s, AWS, GCP, or x509-pop attestors.
- Workload attestation uses the `unix` attestor (UID/GID/path) for Docker
  Compose.

## Registration entries

Entries under `entries/` are loaded by `scripts/register-test-agent.sh` and
similar helpers. Each entry maps workload selectors (process UID, container
labels, k8s service account, etc.) to a SPIFFE ID from the hierarchy defined
in [`CLAUDE.md`](../CLAUDE.md).
