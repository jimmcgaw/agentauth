# envoy — Policy Enforcement Point configuration

Envoy proxy configurations used as Policy Enforcement Points (PEPs) in front
of every service. The default PEP pattern in this platform is an Envoy
sidecar with the `ext_authz` HTTP filter calling OPA.

> **Status:** Placeholder. The first concrete `envoy.yaml` is added in
> Phase 3a.

## Layout

| Path | Purpose |
|------|---------|
| `config/envoy.yaml` | Generic sidecar template — used in front of any service |
| `config/ext_authz_request.lua` | (Optional) request-shaping filter that builds the OPA input payload |

## What the PEP does

1. Terminates inbound mTLS using its own X.509-SVID (delivered via SDS from
   the SPIRE Agent's Workload API).
2. Validates the caller's SVID against the SPIFFE trust bundle.
3. Extracts the caller's SPIFFE ID from the validated client certificate.
4. Constructs an OPA input payload — `{caller, action, resource, context}` —
   and POSTs it to OPA at `/v1/data/ai/agent/authz`.
5. Forwards allowed requests to the upstream cluster; rejects denied
   requests with 403 + structured deny reasons; rejects unauthenticated
   requests with 401.
6. Emits OpenTelemetry trace spans for each request.
