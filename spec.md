# AI Agent AuthN/AuthZ Infrastructure

**SPIFFE/SPIRE Identity Plane · OPA/Rego Policy Engine · Distributed PEP Enforcement · Zero-Trust Agent-to-Agent & Agent-to-Tool Authentication**

---

## Architectural Principles

**Zero Trust** — Every agent-to-agent and agent-to-service call is authenticated (mTLS via SVID) and authorized (OPA). No implicit trust based on network position.

**Short-lived Credentials** — SVIDs are auto-rotated (default 1-hour TTL). No long-lived API keys or static secrets. Compromise blast radius is bounded by SVID lifetime.

**Decoupled AuthN/AuthZ** — SPIFFE/SPIRE handles identity ("who are you?"). OPA handles authorization ("what can you do?"). Separation enables independent scaling and evolution.

**Policy as Code** — All authorization logic is versioned Rego in Git. Changes go through PR review, automated testing (Conftest), and staged rollout via OPAL.

---

## Components

### Control Plane

#### SPIRE Server

Central identity authority. Issues SVIDs (X.509 and JWT) to workloads. Manages registration entries mapping workload selectors to SPIFFE IDs.

**Purpose:** Root of trust for all agent identities. Maintains the trust bundle, signs SVIDs, and manages workload registration entries that bind selectors (k8s pod labels, Docker image hashes, process attributes) to SPIFFE IDs.

| Attribute | Value |
|---|---|
| **SPIFFE ID** | `spiffe://ai-agents.example.org/spire/server` |
| **Datastore** | SQLite (dev) / PostgreSQL (prod) for registration entries & CA state |
| **Protocols** | gRPC (Node Attestation API, Registration API); mTLS for all inter-component traffic |
| **HA Strategy** | Upstream authority mode or shared datastore for multi-server HA |

**Recommended Libraries / Frameworks:**

- `spire` (Go binary — github.com/spiffe/spire)
- `spire-plugin-sdk` for custom attestation plugins
- `spire-controller-manager` for Kubernetes CRD integration

---

#### Policy & Data Store

Git repo or bundle server holding Rego policies and contextual data (role mappings, capability lists). Synced to OPA instances via OPAL or OPA bundle protocol.

**Purpose:** Source of truth for all Rego policies and authorization data. Policies define what each agent identity can do (RBAC, ABAC, capability-based). Data includes role→permission mappings, agent capability manifests, resource sensitivity labels, and delegation chains. Synced to all OPA instances via the OPA bundle protocol or OPAL for real-time updates.

| Attribute | Value |
|---|---|
| **SPIFFE ID** | N/A (accessed by OPA, not by agents directly) |
| **Datastore** | Git + object storage (S3/GCS) for bundles |
| **Protocols** | OPA Bundle Protocol (HTTP polling); OPAL WebSocket for real-time push; Git webhooks for CI/CD triggers |
| **HA Strategy** | Standard Git HA; bundle server behind CDN/LB |

**Recommended Libraries / Frameworks:**

- Git (policy source of truth)
- OPAL server — github.com/permitio/opal
- OPA bundle server (S3, GCS, or custom HTTP)
- Conftest / OPA test for CI/CD policy validation
- Regal linter for Rego style enforcement

---

### Node Layer

#### SPIRE Agent

Runs on every node. Attests workloads, fetches SVIDs from SPIRE Server, and serves them via the Workload API (Unix domain socket).

**Purpose:** Per-node daemon that performs node attestation with the SPIRE Server, then attests local workloads using kernel/container metadata. Exposes the SPIFFE Workload API over a UDS for local processes to obtain SVIDs and trust bundles.

| Attribute | Value |
|---|---|
| **SPIFFE ID** | `spiffe://ai-agents.example.org/spire/agent/{node-id}` |
| **Datastore** | In-memory SVID cache + on-disk trust bundle |
| **Protocols** | gRPC to SPIRE Server (Node API); Unix Domain Socket — Workload API (default: `/tmp/spire-agent/public/api.sock`) |
| **HA Strategy** | One agent per node; agent crash = workloads can't renew SVIDs (use short-lived certs + grace period) |

**Recommended Libraries / Frameworks:**

- `spire-agent` (Go binary, part of SPIRE distro)
- Workload attestors: k8s, docker, unix, systemd

---

### Workload Layer

#### AI Agent Runtime

The AI agent process itself. Uses a SPIFFE SDK sidecar or library to obtain its SVID and authenticate to other services.

**Purpose:** The actual AI agent workload (e.g., LangChain agent, AutoGen, CrewAI, custom). Obtains an SVID from the local SPIRE Agent via the Workload API. Uses the SVID to authenticate to tool services, other agents, and the PDP. The SVID's SPIFFE ID encodes the agent's identity: `spiffe://ai-agents.example.org/agent/{team}/{agent-name}`.

| Attribute | Value |
|---|---|
| **SPIFFE ID** | `spiffe://ai-agents.example.org/agent/{team}/{agent-name}` |
| **Datastore** | None (stateless identity consumer) |
| **Protocols** | UDS to SPIRE Agent (Workload API); mTLS or JWT-SVID to downstream services |
| **HA Strategy** | Horizontal scaling; each replica gets its own SVID with the same SPIFFE ID |

**Recommended Libraries / Frameworks:**

- `go-spiffe` v2 (Go) — github.com/spiffe/go-spiffe/v2
- `py-spiffe` (Python) — github.com/spiffe/py-spiffe
- `java-spiffe` (JVM) — github.com/spiffe/java-spiffe
- `spiffe-helper` for non-SDK workloads (writes certs to disk)

---

#### PEP (Policy Enforcement Point)

Distributed enforcement points (Envoy sidecars, API gateway middleware, SDK interceptors). Intercepts requests, extracts SVID, queries OPA, enforces decision.

**Purpose:** Sits in the request path — as an Envoy sidecar, an API gateway plugin, or an SDK middleware/interceptor. Extracts the caller's SVID (X.509 from mTLS or JWT-SVID from Authorization header), validates it against the SPIFFE trust bundle, then sends an authorization query to the OPA PDP. Enforces the decision (allow, deny, or conditional).

| Attribute | Value |
|---|---|
| **SPIFFE ID** | Inherits the workload's SPIFFE ID or has its own if standalone |
| **Datastore** | Optional local OPA instance with cached policies for low-latency decisions |
| **Protocols** | Envoy ext_authz gRPC/HTTP; Direct OPA REST query; mTLS for upstream/downstream |
| **HA Strategy** | One per workload (sidecar) or shared per-node; stateless |

**Recommended Libraries / Frameworks:**

- Envoy proxy + ext_authz filter (for sidecar PEP)
- OPA Envoy Plugin (built-in PEP+PDP in one sidecar)
- Rego-based local evaluation for latency-sensitive paths
- Custom gRPC/HTTP interceptors using go-spiffe or py-spiffe
- SPIFFE Helper for non-SDK certificate rotation

---

#### Tool / Resource Services

External tools, APIs, databases, and resources that agents call. Each has a PEP that validates the calling agent's SVID and enforces authorization.

**Purpose:** Any downstream service an AI agent might invoke: web search APIs, code execution sandboxes, database connections, file storage, email systems, third-party SaaS. Each service has its own SVID and a PEP that authenticates incoming agent requests (verifying their SVID) and authorizes the action via OPA.

| Attribute | Value |
|---|---|
| **SPIFFE ID** | `spiffe://ai-agents.example.org/service/{service-name}` |
| **Datastore** | Service-specific (Postgres, Redis, S3, etc.) |
| **Protocols** | mTLS (X.509-SVID) or JWT-SVID for inbound auth; Envoy ext_authz to OPA for authorization |
| **HA Strategy** | Standard service HA patterns; SVID rotation is transparent |

**Recommended Libraries / Frameworks:**

- go-spiffe / py-spiffe / java-spiffe for mTLS termination
- Envoy sidecar with ext_authz for transparent PEP
- SPIFFE Federation for cross-domain tool access

---

### Authorization Plane

#### OPA Policy Decision Point (PDP)

Centrally-managed OPA instance(s) evaluating Rego policies. Receives authorization queries from PEPs with agent identity + action context, returns allow/deny.

**Purpose:** Evaluates fine-grained authorization policies written in Rego. Each query includes the agent's SPIFFE ID (from the verified SVID), the requested action, the target resource, and environmental context (time, parent chain, session metadata). Returns structured decisions: allow/deny + conditions/obligations.

| Attribute | Value |
|---|---|
| **SPIFFE ID** | `spiffe://ai-agents.example.org/service/opa-pdp` |
| **Datastore** | In-memory policy + data cache; bundles from S3/GCS/Git |
| **Protocols** | REST API (`POST /v1/data/{policy_path}`); gRPC (Envoy ext_authz); Bundle API for policy distribution |
| **HA Strategy** | Stateless — horizontally scale behind load balancer; each replica loads identical bundles |

**Recommended Libraries / Frameworks:**

- OPA (Go binary) — github.com/open-policy-agent/opa
- OPA Envoy Plugin for sidecar mode
- Rego for policy authoring
- Conftest for policy testing
- OPAL (Open Policy Administration Layer) for real-time policy & data sync

---

### Observability Plane

#### Audit & Observability

Centralized audit logging for all authentication and authorization events. Captures SVID issuance, policy decisions, and enforcement actions.

**Purpose:** Immutable record of every identity and authorization event across the system. Captures: SVID issuance/renewal/revocation events from SPIRE, OPA decision logs (every allow/deny with full input context), PEP enforcement actions, and agent-to-agent delegation chains. Essential for compliance, forensics, and anomaly detection.

| Attribute | Value |
|---|---|
| **SPIFFE ID** | `spiffe://ai-agents.example.org/service/audit-collector` |
| **Datastore** | Elasticsearch, S3 (long-term), or cloud-native log service |
| **Protocols** | OPA Decision Log API (HTTP POST); OTLP (OpenTelemetry Protocol); Fluentd/Fluent Bit for log shipping |
| **HA Strategy** | Standard log pipeline HA (buffering, retry, multi-writer) |

**Recommended Libraries / Frameworks:**

- OPA Decision Logs (built-in, push to HTTP endpoint)
- SPIRE event hooks / audit plugin
- OpenTelemetry for distributed tracing across agent chains
- Elastic / Loki / CloudWatch for log aggregation
- Prometheus + Grafana for metrics dashboards

---

## Data Flows

The numbered flow below shows the end-to-end lifecycle of an AI agent request — from identity bootstrapping through authorization enforcement and audit logging.

| Step | From | To | Description |
|------|------|----|-------------|
| 1 | SPIRE Agent | SPIRE Server | Node attestation + SVID signing (gRPC/mTLS) |
| 2 | AI Agent Runtime | SPIRE Agent | Workload API — fetch X.509/JWT SVID (UDS) |
| 3 | AI Agent Runtime | PEP (Sidecar) | Agent request intercepted by PEP |
| 4 | PEP (Sidecar) | OPA PDP | AuthZ query: SPIFFE ID + action + resource (REST/gRPC) |
| 5 | OPA PDP | Policy & Data Store | Policy & data bundle sync (HTTP/OPAL) |
| 6 | PEP (Sidecar) | Tool / Resource Services | Allowed request forwarded with mTLS (SVID) |
| 7 | OPA PDP | Audit & Observability | Decision logs shipped (every allow/deny) |
| 8 | SPIRE Server | Audit & Observability | SVID lifecycle events |

### Request Lifecycle Summary

**Bootstrap (Steps 1–2):** SPIRE Agent attests to the Server and obtains node-level trust. AI agent workloads fetch their SVIDs from the local Agent via the Workload API (Unix Domain Socket). No secrets are ever stored on disk — SVIDs are short-lived and auto-rotated.

**Request (Steps 3–4):** When an agent makes a request (to a tool, another agent, or any service), the PEP intercepts it, extracts the SVID, and queries OPA with the agent's SPIFFE ID, the action, and the target resource.

**Decision (Steps 5–6):** OPA evaluates Rego policies (synced from the policy store) and returns allow/deny with optional conditions. The PEP enforces the decision — forwarding the request over mTLS if allowed, or rejecting it.

**Audit (Steps 7–8):** Every OPA decision and every SVID lifecycle event is shipped to centralized audit logging for compliance, forensics, and anomaly detection.

---

## SPIFFE ID Scheme

```
# Trust domain
spiffe://ai-agents.example.org/

# Hierarchy
/spire/server                          # SPIRE Server
/spire/agent/{node-id}                 # SPIRE Agents
/agent/{team}/{agent-name}             # AI Agent workloads
/agent/{team}/{agent-name}/sub/{task}  # Sub-agent / delegated task
/service/{service-name}                # Backend services & tools
/gateway/ingress                       # API Gateway / Ingress
/human/{idp-subject}                   # Human users (via OIDC federation)
```

### Design Notes

**Trust domain** — One per environment (dev, staging, prod). Use SPIFFE Federation for cross-domain trust when agents span organizational boundaries.

**Agent paths** — Encode team ownership and agent name. Sub-agent tasks get a `/sub/` segment, enabling wildcard policies like "allow all sub-agents of agent X to access tool Y."

**Human identity bridging** — Use OIDC Federation to map human IdP subjects into the SPIFFE trust domain. This enables unified policies that span human-initiated and autonomous agent actions.

**Registration entries** — Map workload selectors (k8s namespace + service account, Docker labels, process UID) to SPIFFE IDs. This is how SPIRE knows "this container running in k8s namespace 'ml-team' with service account 'research-agent' gets SPIFFE ID `spiffe://ai-agents.example.org/agent/ml-team/research-agent`."

---

## Policy Example (Rego)

Example Rego policy for authorizing AI agent actions. This demonstrates capability-based access control with delegation chain validation — a common pattern for multi-agent systems where one agent may delegate tasks to sub-agents.

```rego
package ai.agent.authz

import rego.v1

# Default deny
default allow := false

# Allow if agent has required capability for the action
allow if {
    # Extract SPIFFE ID from input
    spiffe_id := input.caller.spiffe_id

    # Look up agent's capabilities from data
    agent := data.agents[spiffe_id]

    # Check agent has the required capability
    required := data.resource_permissions[input.resource.type][input.action]
    required_cap in agent.capabilities

    required_cap = required
}

# Allow agent-to-agent delegation if chain is valid
allow if {
    input.delegation_chain
    valid_chain(input.delegation_chain)
    leaf_agent := input.delegation_chain[count(input.delegation_chain) - 1]
    data.agents[leaf_agent.spiffe_id].allow_delegation
}

# Deny if agent's SVID is about to expire (< 5 min)
deny_reason["svid_near_expiry"] if {
    input.caller.svid_expiry - time.now_ns() < 300000000000
}

# Validate delegation chain: each delegator must have
# delegate permission and the chain depth <= max
valid_chain(chain) if {
    count(chain) <= data.config.max_delegation_depth
    every i, link in chain {
        i == 0  # root of chain is always valid
    }
}
valid_chain(chain) if {
    count(chain) <= data.config.max_delegation_depth
    every i, link in chain {
        i > 0
        parent := chain[i - 1]
        data.agents[parent.spiffe_id].can_delegate_to[link.spiffe_id]
    }
}
```

---

## Library & Framework Summary

| Function | Recommended Tool | Language/Runtime |
|---|---|---|
| Identity Server | SPIRE Server | Go binary |
| Node Agent | SPIRE Agent | Go binary |
| Workload SDK (Go) | go-spiffe v2 | Go |
| Workload SDK (Python) | py-spiffe | Python |
| Workload SDK (JVM) | java-spiffe | Java/Kotlin |
| Non-SDK cert rotation | spiffe-helper | Any (writes to disk) |
| Policy Decision Point | OPA | Go binary |
| Policy Language | Rego | OPA-native |
| Policy Distribution | OPAL | Python |
| Policy Testing | Conftest | Go binary |
| Policy Linting | Regal | Go binary |
| PEP (Sidecar) | Envoy + ext_authz | C++ (binary) |
| PEP (Combined) | OPA Envoy Plugin | Go |
| Service Mesh | Envoy / Istio (optional) | — |
| K8s Integration | spire-controller-manager | Go |
| Audit Logging | OPA Decision Logs + OpenTelemetry | — |
| Log Aggregation | Elastic / Loki / CloudWatch | — |
| Metrics | Prometheus + Grafana | — |
| Distributed Tracing | OpenTelemetry (OTLP) | Multi-language |