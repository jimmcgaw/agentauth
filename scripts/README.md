# scripts — Dev tooling and CI helpers

Operational scripts for local development and CI. Each script should be:

- POSIX `sh` or `bash` (`#!/usr/bin/env bash` with `set -euo pipefail`).
- Self-documenting: a header comment describing what it does and what it
  expects (env vars, working directory, etc.).
- Idempotent where possible.

## Planned scripts

| Script | Purpose | Phase |
|--------|---------|-------|
| `register-test-agent.sh` | Creates the dev SPIRE registration entry for the test agent | 0b |
| `verify-spire.sh` | Smoke test: brings up SPIRE, fetches an SVID, prints the SPIFFE ID | 1a |
| `validate-spire-configs.sh` | Runs `spire-server validate` / `spire-agent validate` against the configs in `spire/` (used by CI) | 0c |
