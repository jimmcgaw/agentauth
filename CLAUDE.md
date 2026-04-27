# CLAUDE.md — AI Agent AuthN/AuthZ Governance Platform

## Project Identity

This is an infrastructure platform providing **authentication and authorization for AI agents** using SPIFFE/SPIRE for identity and OPA/Rego for policy. It is designed as general-purpose infrastructure that serves most agentic AI use cases, with extension points for special cases.

**Do not** treat this as a typical web application. This is security infrastructure. Every design decision must prioritize correctness, auditability, and defense-in-depth over convenience or velocity.

---

## Architecture — Non-Negotiable Invariants

These are load-bearing architectural decisions. Do not deviate from them without an ADR.

### Identity Layer (AuthN)

- **SPIFFE/SPIRE is the sole identity provider.** No API keys, static tokens, shared secrets, or ambient credentials anywhere in this system. If a workload needs an identity, it gets an SVID.
- **SVID format:** X.509-SVID for service-to-service mTLS. JWT-SVID only when X.509 is impractical (browser contexts, cross-domain federation).
- **Workload API only.** Agents obtain SVIDs exclusively via the SPIRE Workload API (Unix Domain Socket). Never read or write SVID private keys to disk, environment variables, or config files. The sole exception is `spiffe-helper` for legacy/non-SDK workloads, and that must be explicitly documented per-service.
- **SPIFFE ID hierarchy:**
  ```
  spiffe://ai-agents.example.org/spire/server
  spiffe://ai-agents.example.org/spire/agent/{node-id}
  spiffe://ai-agents.example.org/agent/{team}/{agent-name}
  spiffe://ai-agents.example.org/agent/{team}/{agent-name}/sub/{task}
  spiffe://ai-agents.example.org/service/{service-name}
  spiffe://ai-agents.example.org/gateway/ingress
  spiffe://ai-agents.example.org/human/{idp-subject}
  ```
  New workloads must fit this hierarchy. If a new path segment is needed, write an ADR first.
- **Trust domain:** `ai-agents.example.org` (placeholder — substitute the real domain). One trust domain per environment (dev/staging/prod). Cross-environment communication uses SPIFFE Federation.
- **SVID TTL:** Default 1 hour. Never exceed 4 hours. Sub-30-minute TTLs for high-sensitivity workloads.

### Authorization Layer (AuthZ)

- **OPA is the sole PDP.** All authorization decisions go through OPA evaluating Rego policies. No authorization logic in application code — application code calls OPA (or is fronted by a PEP that calls OPA). No exceptions.
- **Default deny.** Every Rego policy file must start with `default allow := false`. If you find yourself writing a default-allow policy, stop and reconsider.
- **PEP placement:** Every service boundary has a Policy Enforcement Point. The PEP validates the caller's SVID, constructs an OPA query (SPIFFE ID + action + resource + context), and enforces the decision. Three valid PEP patterns:
  1. **Envoy sidecar** with `ext_authz` filter → preferred for most services
  2. **OPA Envoy Plugin** (combined PEP+PDP sidecar) → for latency-sensitive paths
  3. **SDK interceptor** (go-spiffe/py-spiffe middleware) → for services where Envoy is impractical
- **OPAL for policy distribution.** Use OPAL (not vanilla OPA bundle polling) for syncing policies and data to OPA instances. This gives us real-time push on policy/data changes, which is critical for capability revocation.
- **Policy source of truth:** Git. All Rego lives in `policies/` at the repo root. Changes require PR review and must pass `conftest verify` and `opa test` in CI before merge.

### Decoupling Principle

AuthN (SPIFFE/SPIRE) and AuthZ (OPA/Rego) are **strictly decoupled**. SPIRE answers "who is this workload?" and OPA answers "is this workload allowed to do this thing?" They never share a process, a deployment, or a data store. The only coupling point is the SPIFFE ID string, which flows from SPIRE → PEP → OPA input.

### Audit & Observability

- **Every OPA decision is logged.** OPA Decision Logs are enabled on all instances and shipped to the audit collector. Decision logs include full input context (SPIFFE ID, action, resource, timestamp) and the result.
- **Every SVID lifecycle event is logged.** SPIRE Server emits events for issuance, renewal, and revocation.
- **OpenTelemetry for tracing.** All services propagate OTLP trace context. Agent-to-agent delegation chains must be traceable end-to-end.
- **Immutable audit logs.** The audit pipeline writes to append-only storage. No delete operations on audit data.

---

## Technology Stack

| Layer | Technology | Package/Binary |
|-------|-----------|----------------|
| Identity server | SPIRE Server | `spire-server` (Go) |
| Node agent | SPIRE Agent | `spire-agent` (Go) |
| Workload SDK (Python) | py-spiffe | `pip install py-spiffe` |
| Workload SDK (Go) | go-spiffe v2 | `go get github.com/spiffe/go-spiffe/v2` |
| Policy engine | OPA | `opa` (Go binary) |
| Policy language | Rego | v1 syntax (`import rego.v1`) |
| Policy distribution | OPAL | `opal-server`, `opal-client` |
| Policy testing | Conftest + OPA test | `conftest`, `opa test` |
| Policy linting | Regal | `regal lint` |
| PEP (sidecar) | Envoy + ext_authz | `envoyproxy/envoy` |
| PEP (combined) | OPA Envoy Plugin | `openpolicyagent/opa:latest-envoy` |
| Observability | OpenTelemetry | OTLP exporters per language |
| Audit log shipping | Fluent Bit / OPA Decision Logs | — |
| Metrics | Prometheus + Grafana | — |

**Python version:** 3.11+ (for all Python components).
**Go version:** 1.22+ (for any custom Go components).
**Rego:** Always use `import rego.v1` (the v1 syntax). Never use deprecated unification syntax.

---

## Project Structure

```
/
├── CLAUDE.md                        # This file
├── docs/
│   ├── architecture.md              # Architecture reference (from initial design)
│   ├── adr/                         # Architecture Decision Records
│   │   └── 000-template.md
│   └── runbooks/                    # Operational runbooks
├── policies/                        # Rego policies (OPA source of truth)
│   ├── ai/agent/authz.rego          # Core agent authorization
│   ├── ai/agent/authz_test.rego     # Tests for above
│   ├── data/                        # Static policy data (role maps, capabilities)
│   └── lib/                         # Shared Rego helper rules
├── spire/
│   ├── server/
│   │   └── server.conf              # SPIRE Server config
│   ├── agent/
│   │   └── agent.conf               # SPIRE Agent config
│   └── entries/                     # Registration entry definitions
├── envoy/
│   └── config/                      # Envoy proxy + ext_authz configs
├── opal/
│   ├── opal-server.env              # OPAL Server configuration
│   └── opal-client.env              # OPAL Client configuration
├── services/                        # Service implementations
│   ├── audit-collector/             # Audit log ingestion service
│   └── ...                          # Individual tool/agent services
├── deploy/
│   ├── docker-compose.yml           # Local development environment
│   ├── k8s/                         # Kubernetes manifests
│   └── helm/                        # Helm charts (if applicable)
├── scripts/                         # Dev tooling, CI helpers
├── tests/
│   ├── integration/                 # Cross-component integration tests
│   └── e2e/                         # End-to-end auth flow tests
└── .github/
    └── workflows/                   # CI/CD pipelines
```

---

## Code Conventions

### Python

- Type hints on all function signatures. Use `typing` or built-in generics (3.11+).
- Async by default for I/O-bound code. Use `asyncio` with `grpclib` or `grpcio` for gRPC clients.
- Structured logging only — `structlog` or stdlib `logging` with JSON formatter. No `print()` statements.
- All SPIFFE interactions go through `py-spiffe` `WorkloadApiClient`. Never construct TLS contexts manually.

### Rego

- Every `.rego` file in `policies/` must have a corresponding `_test.rego` file.
- Use `import rego.v1` at the top of every file.
- Rule naming: `allow`, `deny_reason[msg]`, `obligations[obj]`. No bare `true`/`false` assignments outside `default`.
- Data references always go through `data.*`, never hardcoded values. Role maps, capability lists, and resource sensitivity labels live in `policies/data/` as JSON.
- Comments explaining the "why" on every rule that isn't self-evident.

### Configuration

- No secrets in config files, env files, or source code. Ever.
- SPIRE configs go in `spire/` and reference the trust domain variable.
- Environment-specific overrides use `.env.{environment}` files with non-secret values only.

### Error Handling

- AuthN failures (invalid/expired SVID, untrusted CA) → reject immediately, log at WARN.
- AuthZ failures (OPA returns deny) → reject with 403 + structured error body including the deny reasons, log at INFO with full OPA input.
- OPA unreachable → **fail closed** (deny the request). Never fail open. Log at ERROR and alert.

---

## Security Boundaries — Hard Rules

1. **No secret material in logs.** SVIDs, private keys, trust bundles, and bearer tokens must never appear in log output. Log SPIFFE IDs (the URI string), not the certificate contents.
2. **No ambient authority.** A workload's permissions come from its SPIFFE ID + OPA policy, not from its network position, its hostname, its environment variables, or any other implicit signal.
3. **No policy bypass endpoints.** No `/health` or `/debug` or `/internal` routes that skip PEP enforcement. Health checks use a separate port or are handled by the PEP itself.
4. **Fail closed on all auth errors.** If SPIRE is down, agents can't get SVIDs and can't make authenticated calls — this is correct behavior. If OPA is down, PEPs deny all requests — this is correct behavior.
5. **Validate the full SVID chain.** PEPs must validate the SVID against the SPIFFE trust bundle, check expiration, and extract the SPIFFE ID. Never trust a SPIFFE ID claim without verifying the SVID.

---

## ADR Process

Any change to the invariants listed above requires an Architecture Decision Record in `docs/adr/`. Format:

```
# ADR-{NNN}: {Title}

## Status: Proposed | Accepted | Superseded by ADR-{NNN}

## Context
What is the issue or question?

## Decision
What are we doing and why?

## Consequences
What are the tradeoffs? What becomes easier/harder?
```

---

## Development Workflow

### Local Development

```bash
# Start the full local stack (SPIRE Server, SPIRE Agent, OPA, OPAL, Envoy)
docker compose -f deploy/docker-compose.yml up

# Register a test agent workload
./scripts/register-test-agent.sh

# Run Rego policy tests
opa test policies/ -v

# Lint Rego
regal lint policies/

# Run integration tests (requires local stack running)
pytest tests/integration/ -v
```

### CI Checks (must all pass before merge)

- `opa test policies/ -v` — all policy tests pass
- `regal lint policies/` — no linting violations
- `conftest verify` — policy structure validation
- `pytest tests/` — unit + integration tests
- Type checking (mypy/pyright for Python services)

---

## Common Pitfalls — Read Before Building

- **Don't cache SVIDs yourself.** The `py-spiffe` / `go-spiffe` SDK handles SVID rotation. If you're writing code that stores an SVID and checks expiry manually, you're doing it wrong — use the SDK's `WorkloadApiClient` which auto-rotates.
- **Don't put authorization logic in application code.** If you're writing an `if` statement that checks permissions in a Python service, extract it into a Rego rule and call OPA instead. The one exception is basic input validation (is this a well-formed request?), which is not authorization.
- **Don't use JWT-SVIDs where X.509 works.** JWT-SVIDs are for cases where mTLS is impossible (browser, cross-domain). Default to X.509-SVID + mTLS.
- **Don't conflate authentication and authorization errors.** A 401 means "I don't know who you are" (bad/missing SVID). A 403 means "I know who you are but you can't do this" (OPA denied). Never return 401 for an authorization failure.
- **Don't skip the PEP for "internal" calls.** Zero trust means zero exceptions. Agent-to-agent calls within the same namespace still go through a PEP.
