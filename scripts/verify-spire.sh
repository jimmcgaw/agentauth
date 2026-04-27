#!/usr/bin/env bash
#
# verify-spire.sh — Phase 1a integration test: prove the SPIRE identity layer
# works end-to-end against the local Docker Compose stack.
#
# Steps:
#   1. Bring up `spire-server` and wait for it to report healthy.
#   2. Run scripts/register-test-agent.sh, which:
#        - generates a join token for the dev node SPIFFE ID,
#        - writes it into the shared `spire-bootstrap` volume, and
#        - registers the dev test-agent workload entry
#          (spiffe://ai-agents.example.org/agent/dev/test-agent,
#           selector unix:uid:1000).
#   3. Bring up `spire-agent` and wait for it to report healthy.
#   4. Exec into the agent container as UID 1000 and call
#      `spire-agent api fetch x509` against the Workload API socket. Per
#      CLAUDE.md this is the *only* supported path for a workload to obtain
#      its identity — we never read SVIDs from disk or env.
#   5. Parse the SPIFFE ID from the output and assert it matches the expected
#      identity. Print it on success.
#
# Exit codes:
#   0  on success (SVID fetched, SPIFFE ID matches expected value)
#   1  on any failure (with a clear error message on stderr)
#
# Environment:
#   COMPOSE_FILE   override path to deploy/docker-compose.yml
#   KEEP_STACK=1   leave the stack running on exit (default: tear it down)
#
# This script is intentionally self-contained so it can run from a developer
# machine or from CI as the canonical "is the identity layer alive?" check.

set -euo pipefail

# ---- config -----------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE_FILE="${COMPOSE_FILE:-$REPO_ROOT/deploy/docker-compose.yml}"

TRUST_DOMAIN="ai-agents.example.org"
EXPECTED_SPIFFE_ID="spiffe://${TRUST_DOMAIN}/agent/dev/test-agent"

# Must match the unix:uid:<N> selector created by register-test-agent.sh and
# the `user:` directive on the test-agent compose service.
TEST_AGENT_UID="1000"

SERVER_CONTAINER="agentauth-spire-server"
AGENT_CONTAINER="agentauth-spire-agent"

# Path to the Workload API UDS inside the spire-agent container. Matches the
# `socket_path` setting in spire/agent/agent.conf.
WORKLOAD_SOCKET="/run/spire/agent/sock/api.sock"

HEALTH_TIMEOUT_SECONDS=60

# ---- helpers ----------------------------------------------------------------

log()  { printf '[verify-spire] %s\n' "$*" >&2; }
ok()   { printf '[verify-spire] \xe2\x9c\x93 %s\n' "$*" >&2; }
fail() { log "ERROR: $*"; exit 1; }

compose() {
    docker compose -f "$COMPOSE_FILE" "$@"
}

cleanup() {
    if [ "${KEEP_STACK:-0}" = "1" ]; then
        log "leaving stack running (KEEP_STACK=1)"
        return
    fi
    log "tearing down stack..."
    compose down --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT

# Block until the named container's healthcheck reports `healthy`. We poll
# `docker inspect` rather than `compose ps` because the latter's status
# strings are inconsistent across docker-compose versions.
wait_for_healthy() {
    local container="$1"
    local i state
    for i in $(seq 1 "$HEALTH_TIMEOUT_SECONDS"); do
        state="$(docker inspect -f '{{.State.Health.Status}}' "$container" 2>/dev/null || echo unknown)"
        if [ "$state" = "healthy" ]; then
            ok "$container is healthy"
            return 0
        fi
        sleep 1
    done
    state="$(docker inspect -f '{{.State.Health.Status}}' "$container" 2>/dev/null || echo unknown)"
    fail "$container did not become healthy within ${HEALTH_TIMEOUT_SECONDS}s (state=$state)"
}

# ---- 1. spire-server --------------------------------------------------------

log "starting spire-server..."
compose up -d spire-server >/dev/null
wait_for_healthy "$SERVER_CONTAINER"

# ---- 2. registration --------------------------------------------------------

log "running register-test-agent.sh (generates join token + workload entry)..."
COMPOSE_FILE="$COMPOSE_FILE" "$SCRIPT_DIR/register-test-agent.sh" \
    || fail "register-test-agent.sh failed"

# ---- 3. spire-agent ---------------------------------------------------------

log "starting spire-agent..."
compose up -d spire-agent >/dev/null
wait_for_healthy "$AGENT_CONTAINER"

# ---- 4. fetch X.509 SVID ----------------------------------------------------
#
# We exec into the spire-agent container as UID 1000. The unix workload
# attestor sees the calling process's UID via /proc/<pid>/status (the agent
# runs in the host PID namespace per the compose config), matches the
# `unix:uid:1000` selector on the test-agent registration entry, and issues
# the corresponding X.509 SVID.
#
# `-output json` gives us a stable, parseable representation that won't drift
# across SPIRE versions like the human-readable default does.

log "fetching X.509 SVID via Workload API as uid=${TEST_AGENT_UID}..."
SVID_JSON="$(compose exec -T --user "${TEST_AGENT_UID}:${TEST_AGENT_UID}" \
    spire-agent /opt/spire/bin/spire-agent api fetch x509 \
    -socketPath "$WORKLOAD_SOCKET" \
    -output json 2>&1)" \
    || fail "spire-agent api fetch x509 failed:
${SVID_JSON}"

# Newer spire CLIs emit `{"svids":[{"spiffe_id":"...", ...}]}`. Parse with a
# small Python one-liner so we don't take a hard `jq` dependency on the host.
SVID_ID="$(printf '%s' "$SVID_JSON" \
    | python3 -c '
import json, sys
try:
    payload = json.load(sys.stdin)
except Exception as e:
    sys.stderr.write(f"failed to parse JSON SVID payload: {e}\n")
    sys.exit(2)
svids = payload.get("svids") or []
if not svids:
    sys.stderr.write("no svids in payload\n")
    sys.exit(2)
print(svids[0].get("spiffe_id", ""))
' 2>/dev/null)" || true

if [ -z "${SVID_ID:-}" ]; then
    fail "could not extract SPIFFE ID from spire-agent response:
${SVID_JSON}"
fi

# ---- 5. assert --------------------------------------------------------------

if [ "$SVID_ID" != "$EXPECTED_SPIFFE_ID" ]; then
    fail "fetched SVID has unexpected SPIFFE ID
  expected: ${EXPECTED_SPIFFE_ID}
  actual  : ${SVID_ID}"
fi

ok "fetched SVID for ${SVID_ID}"
log ""
log "Phase 1a verified: SPIRE identity layer is issuing SVIDs end-to-end."
exit 0
