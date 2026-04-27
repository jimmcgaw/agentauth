# Prompting Guide: Building the AI Agent AuthN/AuthZ Platform with Claude Code

## Philosophy

The CLAUDE.md establishes *what* the system is and the invariants Claude Code must respect. The prompts below establish *how* to build it incrementally. The key insight is sequencing: you need identity before authorization, authorization before enforcement, and enforcement before any agent workloads.

The approach is bottom-up infrastructure, then a thin vertical slice that proves the whole stack works end-to-end, then iterative expansion.

---

## Phase 0: Project Scaffold

Start here. This gets the directory structure, tooling, and local dev environment in place before any real implementation.

### Prompt 0a — Scaffold

```
Read CLAUDE.md thoroughly. Then scaffold the full project directory structure 
exactly as specified — create all directories, placeholder READMEs, and the 
ADR template. Don't implement anything yet, just create the skeleton. 

For the ADR template at docs/adr/000-template.md, use the format from CLAUDE.md. 
Create ADR-001 documenting the foundational architecture decision: "Use SPIFFE/SPIRE 
for agent identity and OPA/Rego for authorization, with Envoy PEPs at all service 
boundaries."
```

### Prompt 0b — Docker Compose Foundation

```
Create deploy/docker-compose.yml for the local development stack. Include:

1. SPIRE Server container (spiffe/spire-server) with a minimal server.conf 
   that uses the trust domain from CLAUDE.md, an in-memory datastore for dev, 
   and a self-signed upstream CA.
2. SPIRE Agent container (spiffe/spire-agent) with join_token node attestation 
   for local dev, configured to talk to the SPIRE Server, and exposing the 
   Workload API socket via a shared volume.
3. OPA container (openpolicyagent/opa) with decision logging enabled, 
   loading policies from a bind-mounted ./policies/ directory.
4. OPAL Server container configured to watch the local policies/ directory.
5. OPAL Client container connected to OPA and the OPAL server.

Write the corresponding spire/server/server.conf and spire/agent/agent.conf. 
Keep it minimal — just enough to get SVID issuance working locally. Add a 
scripts/register-test-agent.sh that registers a test workload entry with 
SPIFFE ID spiffe://ai-agents.example.org/agent/dev/test-agent using unix 
workload attestation (uid-based for local dev).

Don't start on any services yet.
```

### Prompt 0c — CI Pipeline

```
Create .github/workflows/ci.yml that runs on every PR:

1. opa test policies/ -v
2. regal lint policies/
3. Python type checking and tests (pytest) for anything under services/
4. A step that validates all SPIRE configs parse correctly

Use GitHub Actions. Keep it simple — no deployment steps yet, just validation.
```

---

## Phase 1: Identity Layer (SPIRE)

Get SVID issuance working end-to-end before touching authorization.

### Prompt 1a — Verify SPIRE Stack

```
Write a scripts/verify-spire.sh script that:

1. Starts the docker compose stack (just spire-server and spire-agent services)
2. Waits for the SPIRE Server to be healthy
3. Generates a join token and restarts the agent with it
4. Runs the register-test-agent.sh script
5. Uses `docker compose exec` to call `spire-agent api fetch x509` and 
   verifies an SVID is returned
6. Prints the SPIFFE ID from the fetched SVID
7. Exits 0 on success, 1 on failure with clear error messages

This is our first integration test — it proves the identity layer works.
```

### Prompt 1b — Python SVID Client

```
Create services/test-agent/main.py — a minimal Python service that:

1. Uses py-spiffe WorkloadApiClient to connect to the Workload API socket
2. Fetches an X.509 SVID
3. Logs (using structlog, JSON format) the SPIFFE ID and SVID expiration
4. Sets up a watch that logs each SVID rotation
5. Runs as a long-lived process

Add a Dockerfile and add this service to docker-compose.yml. It should 
mount the SPIRE Agent's Workload API socket. Create a registration entry 
for it.

Include type hints on all functions. Follow the Python conventions in CLAUDE.md.
This service is our reference implementation for how all future Python agent 
services interact with SPIRE.
```

---

## Phase 2: Authorization Layer (OPA + Rego)

Build the policy foundation. Don't connect it to enforcement yet — get the policies right and tested in isolation first.

### Prompt 2a — Core Policy

```
Create the core authorization policy at policies/ai/agent/authz.rego 
with the following rules:

1. default allow := false
2. Allow if the caller's SPIFFE ID maps to an agent with the required 
   capability for the requested action on the requested resource type
3. Deny with reason if the SVID is near expiry (< 5 minutes)
4. Allow delegation if the delegation chain is valid (each delegator has 
   delegate permission, chain depth <= max_delegation_depth from config)

Use import rego.v1. Reference capabilities from data.agents[spiffe_id], 
resource permissions from data.resource_permissions[resource_type][action], 
and delegation config from data.config.

Then create policies/ai/agent/authz_test.rego with tests covering:
- Agent with correct capability → allowed
- Agent missing capability → denied
- Expired SVID → deny_reason includes "svid_near_expiry"
- Valid 2-hop delegation chain → allowed
- Delegation chain exceeding max depth → denied
- Unknown SPIFFE ID → denied (default deny)

Also create policies/data/agents.json and policies/data/resource_permissions.json 
with test fixture data matching the test cases. Include at least 3 agent 
identities with different capability sets.

Run opa test and regal lint and fix any issues.
```

### Prompt 2b — Shared Policy Library

```
Create policies/lib/spiffe.rego with helper rules for working with SPIFFE IDs:

1. parse_spiffe_id(id) — extracts trust_domain, path segments, and full path
2. is_agent(id) — true if path starts with /agent/
3. is_service(id) — true if path starts with /service/
4. is_sub_agent(id) — true if path contains /sub/
5. agent_team(id) — extracts the team segment from an agent SPIFFE ID
6. same_trust_domain(id1, id2) — true if both IDs share a trust domain

Write tests in policies/lib/spiffe_test.rego covering each helper with 
the SPIFFE ID patterns from CLAUDE.md.

Then refactor policies/ai/agent/authz.rego to use these helpers where appropriate.
Re-run opa test to confirm nothing broke.
```

### Prompt 2c — Obligation & Constraint Policies

```
Extend the authorization policy to return structured obligations and 
constraints alongside allow/deny. Add these rules to authz.rego:

1. obligations[obj] — returns objects like {"type": "audit_enhanced", 
   "reason": "high_sensitivity_resource"} when an agent accesses a 
   resource with sensitivity_label "high" in data.resources
2. constraints[c] — returns rate limiting constraints like 
   {"type": "rate_limit", "max_requests": 10, "window_seconds": 60} 
   based on agent tier from data.agents
3. deny_reason[msg] — extend with reasons: "agent_suspended" when 
   agent status is "suspended", "outside_operating_hours" when 
   time-based restrictions apply

Create policies/data/resources.json with sample resources at different 
sensitivity levels. Add tests for each new rule. Run opa test and 
regal lint.
```

---

## Phase 3: Enforcement Layer (PEP + Integration)

Connect identity to authorization. This is where the system comes alive.

### Prompt 3a — Envoy PEP Configuration

```
Create envoy/config/envoy.yaml — an Envoy proxy configuration that:

1. Listens on port 8080 for inbound requests
2. Terminates mTLS using the workload's SVID (X.509) obtained from SPIRE — 
   configure SDS (Secret Discovery Service) via the SPIRE Agent's Workload API
3. Has an ext_authz HTTP filter that sends authorization checks to OPA at 
   the OPA container's address, POST to /v1/data/ai/agent/authz
4. Passes the caller's SPIFFE ID (extracted from the validated client cert) 
   to OPA in the authorization request
5. Routes allowed requests to an upstream cluster on port 8081

Add this Envoy sidecar to docker-compose.yml as a generic template that can 
be placed in front of any service. Document in a README how to pair it with 
a new service.

Create envoy/config/ext_authz_request.lua or equivalent filter config that 
constructs the OPA input payload: {caller: {spiffe_id, svid_expiry}, 
action: <from HTTP method>, resource: {type: <from path>, id: <from path>}}.
```

### Prompt 3b — End-to-End Vertical Slice

```
Build the first end-to-end integration test that proves the full 
auth stack works. Create tests/e2e/test_full_auth_flow.py that:

1. Starts the full docker compose stack (SPIRE Server, Agent, OPA, 
   OPAL, Envoy PEP, test-agent service)
2. The test-agent service fetches its SVID from SPIRE
3. The test-agent makes an mTLS request through the Envoy PEP to a 
   simple echo service behind it
4. Asserts: request with valid SVID + matching capability → 200
5. Asserts: request with valid SVID but missing capability → 403
6. Asserts: request from unregistered workload (no SVID) → 401
7. Checks that OPA decision logs contain entries for each request

This is the critical milestone. When this test passes, the core 
architecture is proven. Use pytest, structlog, and py-spiffe. 
Add a Makefile target: `make test-e2e` that runs this.
```

---

## Phase 4: Audit & Observability

### Prompt 4a — Audit Collector Service

```
Create services/audit-collector/ — a Python service that:

1. Receives OPA Decision Logs via HTTP POST (OPA pushes to this endpoint)
2. Receives SPIRE event hooks (SVID issuance/renewal/revocation)
3. Validates each log entry has required fields (SPIFFE ID, action, 
   resource, decision, timestamp)
4. Writes to append-only structured JSON log files (for now — we'll 
   add Elasticsearch later)
5. Exposes Prometheus metrics: decisions_total (by result), 
   svid_events_total (by event_type), decision_latency_histogram

Has its own SVID: spiffe://ai-agents.example.org/service/audit-collector. 
Uses mTLS for inbound connections. Add to docker-compose.yml. Configure 
OPA's decision log plugin to push to this service.

Follow all CLAUDE.md Python conventions. Include a Dockerfile. 
No secrets in config.
```

### Prompt 4b — OpenTelemetry Integration

```
Add OpenTelemetry tracing to the test-agent service:

1. pip install opentelemetry-api opentelemetry-sdk opentelemetry-exporter-otlp
2. Create a trace span for each outbound request that includes: 
   the agent's SPIFFE ID, the target service, the action, and the 
   OPA decision result
3. Propagate trace context through the Envoy PEP (Envoy already 
   supports this — just enable the tracing config)
4. Add a Jaeger container to docker-compose.yml as the trace backend

This establishes the tracing pattern all future services will follow.
Create a shared module at services/common/tracing.py with the 
initialization boilerplate so other services can import it.
```

---

## Phase 5: Expand

At this point the infrastructure is proven. Expansion prompts are more domain-specific, but here are the templates:

### Adding a New Agent Service

```
Create services/{agent-name}/ — a new AI agent service that:

1. Obtains its SVID via py-spiffe WorkloadApiClient
2. [describe what this agent does]
3. Calls [target service] through the Envoy PEP using mTLS with its SVID
4. Has SPIFFE ID: spiffe://ai-agents.example.org/agent/{team}/{agent-name}

Create a SPIRE registration entry in spire/entries/.
Add capability mappings in policies/data/agents.json.
Add to docker-compose.yml with the Envoy sidecar template.
Write integration tests. Follow CLAUDE.md conventions.
```

### Adding a New Rego Policy Rule

```
Add a new authorization rule to policies/ai/agent/authz.rego:

[describe the rule semantics]

Add corresponding test cases in authz_test.rego. Add any new data 
fixtures in policies/data/. Run opa test and regal lint. If this 
changes the authorization semantics for existing agents, create an 
ADR documenting the change.
```

### Adding Agent-to-Agent Delegation

```
Implement the delegation flow between two agent services:

1. Agent A (spiffe://ai-agents.example.org/agent/team-a/orchestrator) 
   delegates a subtask to Agent B 
   (spiffe://ai-agents.example.org/agent/team-a/worker)
2. Agent A includes a delegation token (JWT-SVID with delegation claims) 
   in the request to Agent B
3. Agent B presents both its own SVID and the delegation chain to the 
   PEP when calling downstream services
4. The PEP sends the full delegation chain to OPA
5. OPA validates the chain using the existing valid_chain rule

Update the Envoy config to pass delegation headers. Update the PEP's 
OPA input construction to include delegation_chain. Write e2e tests 
covering: valid delegation, delegation chain too deep, unauthorized 
delegator.
```

---

## Prompting Tips Specific to This Project

**Always reference CLAUDE.md.** Start complex prompts with "Read CLAUDE.md" or "Per CLAUDE.md conventions." Claude Code respects the CLAUDE.md as its primary instruction set, but an explicit reminder helps on longer sessions.

**One infrastructure layer per prompt.** Don't ask for "set up SPIRE and OPA and Envoy and write the agent service." Each layer has dependencies on the previous one. Prompt sequentially and verify each layer works before building on top of it.

**Demand tests before moving on.** End every implementation prompt with "Run the tests and fix any issues" or "Run opa test and regal lint and fix any issues." This forces Claude Code to validate its own output before you accept it.

**Use `make` targets as checkpoints.** Prompts like "add a Makefile target `make verify-identity` that runs the SPIRE verification script" give you one-command validation at each phase.

**Be explicit about what NOT to do.** For security infrastructure, anti-patterns matter as much as patterns. Phrases like "Do not cache the SVID manually" or "No authorization logic in the application code" prevent the most common drift.

**Request ADRs for deviations.** If you're exploring an alternative (e.g., "what if we use Istio's identity instead of SPIRE?"), prompt Claude Code to write the ADR first, not the implementation. This forces the tradeoff analysis to happen before code gets written.

**Pin the integration test as the invariant.** Once `test_full_auth_flow.py` passes, every subsequent prompt should end with "Run make test-e2e and confirm it still passes." This prevents later changes from silently breaking the core auth flow.
