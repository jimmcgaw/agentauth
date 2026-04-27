# spire/entries — Workload registration entries

Each file in this directory describes one (or a few related) SPIRE
registration entries — the binding from workload selectors to SPIFFE IDs.

> **Status:** Placeholder. The first entry — for the dev test agent — is
> created by `scripts/register-test-agent.sh` in Phase 0b.

## Format

Entries are checked into Git as either:

- Shell scripts wrapping `spire-server entry create ...` (used for local dev),
  **or**
- YAML manifests for `spire-controller-manager` (used for Kubernetes).

Both formats reference the SPIFFE ID hierarchy from [`CLAUDE.md`](../../CLAUDE.md).

## Conventions

- One file per logical workload (or tightly related group).
- Filename matches the leaf SPIFFE-ID segment, e.g. `dev-test-agent.sh` for
  `spiffe://ai-agents.example.org/agent/dev/test-agent`.
- Selectors must be specific enough that a different process / image cannot
  inadvertently match them.
