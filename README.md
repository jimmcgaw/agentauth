# agentauth — AI Agent AuthN/AuthZ Governance Platform

Infrastructure for authenticating and authorizing AI agents using **SPIFFE/SPIRE**
for workload identity and **OPA/Rego** for policy.

This repository is security infrastructure, not a typical web application. Read
[`CLAUDE.md`](./CLAUDE.md) before contributing — it defines the load-bearing
architectural invariants that every change must respect.

## What lives here

| Path | Purpose |
|------|---------|
| `docs/` | Architecture reference, Architecture Decision Records (ADRs), runbooks |
| `policies/` | Rego policies and supporting data (the OPA source of truth) |
| `spire/` | SPIRE Server / Agent configuration and registration entries |
| `envoy/` | Envoy proxy configuration for Policy Enforcement Points |
| `opal/` | OPAL Server / Client configuration for policy distribution |
| `services/` | Service implementations (audit collector, agent reference services) |
| `deploy/` | Local Docker Compose stack and Kubernetes / Helm manifests |
| `scripts/` | Dev tooling and CI helpers |
| `tests/` | Integration and end-to-end auth-flow tests |
| `.github/` | CI/CD workflows |

## Quickstart

The local development stack is brought up with Docker Compose. See
[`deploy/README.md`](./deploy/README.md) once the stack is implemented.

```bash
docker compose -f deploy/docker-compose.yml up
```

## Architectural invariants (summary)

- **SPIFFE/SPIRE is the sole identity provider.** No API keys or static secrets.
- **OPA is the sole Policy Decision Point.** All authorization goes through Rego.
- **Default deny.** Every Rego policy starts with `default allow := false`.
- **Fail closed.** If SPIRE or OPA is unreachable, requests are denied.
- **Decoupled AuthN/AuthZ.** SPIRE answers "who?", OPA answers "what can they do?"

See [`CLAUDE.md`](./CLAUDE.md) for the full set of invariants and the ADR
process for proposing changes.

## Development workflow

```bash
# Run policy tests
opa test policies/ -v

# Lint policies
regal lint policies/

# Run Python tests
pytest tests/
```

CI runs on every PR via `.github/workflows/ci.yml`.
