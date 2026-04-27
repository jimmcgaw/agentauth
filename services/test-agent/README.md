# test-agent

Reference SPIFFE workload — the canonical example of how every Python
service in this platform integrates with SPIRE.

> **Phase:** 1b (Identity Layer). This service does not yet make any
> outbound calls; it exists to prove the identity layer works from inside
> a Docker workload and to establish the integration pattern future
> services will copy.

## What it does

1. Connects to the SPIRE Agent's Workload API socket
   (`unix:///run/spire/agent/sock/api.sock` by default).
2. Fetches its initial X.509 SVID and logs the SPIFFE ID + expiry.
3. Opens a streaming connection that delivers every subsequent SVID
   rotation; each rotation is logged.
4. Runs as a long-lived process; exits cleanly on `SIGINT`/`SIGTERM`.

## SPIFFE identity

| Field         | Value                                                        |
|---------------|--------------------------------------------------------------|
| Trust domain  | `ai-agents.example.org`                                      |
| SPIFFE ID     | `spiffe://ai-agents.example.org/agent/dev/test-agent`        |
| Selector      | `unix:uid:1000`                                              |
| Container UID | `1000:1000`                                                  |

The registration entry is created by
[`scripts/register-test-agent.sh`](../../scripts/register-test-agent.sh).
Re-running that script is idempotent.

## Conventions illustrated

This service deliberately demonstrates the patterns CLAUDE.md mandates for
every Python workload:

- **No ambient credentials.** Identity comes from the Workload API only.
  No API keys, env tokens, or certs on disk.
- **No manual SVID caching.** The `spiffe` SDK auto-rotates in the
  background; we never inspect expiry by hand.
- **Structured JSON logs.** All output goes through `structlog`. SPIFFE
  IDs are logged; cert/key bytes never are.
- **Fail closed.** If `SPIFFE_ENDPOINT_SOCKET` is unset or the socket is
  unreachable, the SDK raises and the process exits non-zero — the
  correct behavior for a workload that cannot prove its identity.

## Running locally

```bash
# 1. Start the identity layer and register this workload.
make verify-identity   # or: ./scripts/verify-spire.sh

# 2. Start the test-agent container.
docker compose -f deploy/docker-compose.yml up -d test-agent

# 3. Watch its structured logs.
docker compose -f deploy/docker-compose.yml logs -f test-agent
```

You should see a `svid_initial` event followed by periodic `svid_rotated`
events as the SDK rotates the SVID before its expiry.

## Environment

| Variable                  | Default                                       | Purpose                            |
|---------------------------|-----------------------------------------------|------------------------------------|
| `SPIFFE_ENDPOINT_SOCKET`  | `unix:///run/spire/agent/sock/api.sock`       | Workload API UDS to dial.          |
