# ADR-001: SPIFFE/SPIRE + OPA/Rego + Envoy PEPs as the foundation

## Status

Accepted

## Context

This platform's purpose is to authenticate and authorize AI agents and the
services they call. Two architectural questions had to be answered before any
implementation could begin:

1. **How do workloads obtain and present identity?** AI agents are highly
   dynamic — many short-lived processes, frequently scaled, often delegating
   tasks to sub-agents. Static credentials (API keys, shared secrets, bearer
   tokens) are operationally expensive to rotate and have unbounded blast
   radius on compromise. Ambient authority (network position, hostname, k8s
   namespace) does not extend cleanly to multi-tenant or cross-cluster
   deployments and is the source of a long history of confused-deputy and
   SSRF-class incidents.

2. **How is authorization expressed and enforced?** Hard-coding permission
   checks into agent and service code is unmaintainable, untestable in
   isolation, and makes capability revocation a code-deploy-shaped problem
   instead of a config-shaped one. We need a declarative policy language with
   a real testing story, a real distribution story, and a clean separation
   from application code.

The constraints from `CLAUDE.md` are:

- Zero trust — no implicit trust based on network position.
- Short-lived credentials — bounded compromise blast radius.
- Strict decoupling of AuthN and AuthZ — the identity layer and policy layer
  must scale, evolve, and be reasoned about independently.
- Default deny + fail closed — if any layer is unavailable, requests are
  rejected.
- Auditable — every identity event and every authorization decision must be
  recorded to immutable storage.

Alternatives considered:

- **mTLS with a private CA + RBAC in application code.** Rejected: no
  declarative policy, no real revocation story for short-lived agent
  identities, and re-introduces ambient authority because the cert-to-identity
  mapping is ad hoc.
- **Service-mesh-native identity (Istio / Linkerd) + RBAC CRDs.** Rejected as
  the foundation: ties identity to a specific mesh, makes federation across
  environments harder, and the mesh's RBAC is intentionally coarse-grained
  (not suitable for capability-based agent authorization). A mesh may still be
  layered *on top of* SPIFFE/SPIRE later.
- **OAuth 2.0 / OIDC bearer tokens for agent-to-agent.** Rejected: bearer
  tokens are stealable, their distribution requires another secret, and there
  is no clean way to attest a workload's identity without re-introducing
  static credentials at bootstrap.
- **Cedar or AWS-IAM-style policy.** Rejected for now: less mature open-source
  ecosystem for our use case, fewer integrations with the workload-identity
  ecosystem we are committing to, and weaker testing tooling than OPA's
  `opa test` + Conftest + Regal.

## Decision

We will use **SPIFFE/SPIRE** as the sole identity provider for all workloads
in this platform, and **OPA evaluating Rego** as the sole policy decision
point for all authorization. **Envoy sidecars with the `ext_authz` filter**
will be the default Policy Enforcement Point at every service boundary.

Concretely:

1. Every workload — every AI agent, every tool, every internal service —
   obtains an X.509-SVID from the local SPIRE Agent via the Workload API
   (Unix Domain Socket). JWT-SVIDs are used only where mTLS is impractical
   (browser, cross-domain federation).

2. The SPIFFE ID hierarchy is fixed:
   ```
   spiffe://<trust-domain>/spire/server
   spiffe://<trust-domain>/spire/agent/{node-id}
   spiffe://<trust-domain>/agent/{team}/{agent-name}
   spiffe://<trust-domain>/agent/{team}/{agent-name}/sub/{task}
   spiffe://<trust-domain>/service/{service-name}
   spiffe://<trust-domain>/gateway/ingress
   spiffe://<trust-domain>/human/{idp-subject}
   ```
   New path segments require an ADR.

3. All authorization decisions are made by OPA evaluating Rego policies that
   live in `policies/` in this repository. Every policy file starts with
   `default allow := false`. Application code never makes authorization
   decisions itself — it calls OPA, or it sits behind a PEP that calls OPA.

4. Policies and supporting data are distributed to OPA instances via **OPAL**
   (rather than vanilla bundle polling) so that policy and capability changes
   — including capability revocations — take effect in near-real-time.

5. The default PEP is an **Envoy sidecar with `ext_authz`** querying OPA. Two
   alternative PEP patterns are permitted: the OPA Envoy Plugin (combined
   PEP+PDP sidecar) for latency-sensitive paths, and SDK interceptors built
   on `go-spiffe` / `py-spiffe` for services where Envoy is impractical.

6. SPIRE and OPA are strictly decoupled: separate processes, separate
   deployments, separate datastores. The only coupling point is the SPIFFE ID
   string flowing from SPIRE → PEP → OPA input.

7. Every OPA decision is logged with full input context, and every SVID
   lifecycle event is logged. Both streams are shipped to an append-only
   audit collector.

## Consequences

**What becomes easier**

- Workload identity is uniform and attestation-based across Docker, Kubernetes,
  and bare-metal — no per-environment credential plumbing.
- Authorization changes are PR-shaped: write Rego, write tests, merge, OPAL
  pushes the update. Revocation is just a data change.
- Capability and revocation testing is fast (`opa test`) and runs in CI without
  needing the rest of the stack.
- The audit story is built-in: OPA decision logs and SPIRE event hooks give us
  end-to-end visibility for free.
- Federation across environments works through SPIFFE Federation rather than
  bespoke trust plumbing.

**What becomes harder**

- Operational complexity is higher up front. We must run SPIRE Server, SPIRE
  Agents, OPA, OPAL, and Envoy proxies as core infrastructure — every
  environment, every cluster.
- Onboarding cost: contributors need at least passing familiarity with SPIFFE
  IDs, SVIDs, the Workload API, Rego syntax, and Envoy `ext_authz`.
- Latency: every cross-service request now goes through an Envoy hop and an
  OPA call. Mitigated by sidecar locality and (for hot paths) the combined
  OPA Envoy Plugin, but it is real and must be measured.
- Failure modes are *failure-to-deny*: if SPIRE Agent crashes, workloads can't
  renew SVIDs and stop being able to authenticate. If OPA is unreachable, PEPs
  deny all requests. This is correct behavior but requires good runbooks and
  alerting.
- Local development requires running the full stack (SPIRE + OPA + OPAL +
  Envoy) via Docker Compose, which is heavier than a typical app dev loop.

**What we are explicitly accepting**

- A hard dependency on the SPIFFE/OPA ecosystem. If either project's direction
  diverged sharply from ours, migration would be expensive. We accept this in
  exchange for the operational and security benefits, and we mitigate by
  isolating ecosystem-specific code behind SDK boundaries (`py-spiffe`,
  `go-spiffe`, OPA REST clients) so that, in the worst case, a future ADR
  could swap one component without rewriting application logic.
