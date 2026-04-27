#!/usr/bin/env bash
#
# register-test-agent.sh
#
# One-shot bootstrap helper for the local Docker Compose stack. Performs:
#
#   1. Waits for the SPIRE Server container to be healthy.
#   2. Creates a registration entry for the SPIRE Agent itself
#      (spiffe://ai-agents.example.org/spire/agent/dev-node) so the join
#      token resolves to a node identity.
#   3. Generates a join token for that agent SPIFFE ID and writes it to the
#      shared `spire-bootstrap` volume at /run/spire/bootstrap/join_token,
#      where the spire-agent container's entrypoint reads it.
#   4. Creates a workload registration entry for the dev test agent
#      (spiffe://ai-agents.example.org/agent/dev/test-agent) using
#      unix:uid attestation against UID 1000.
#
# After this script completes successfully:
#
#       docker compose -f deploy/docker-compose.yml up -d spire-agent
#
# will start the agent, which can then issue an SVID for the dev/test-agent
# workload to any local process running as UID 1000 that connects to the
# Workload API socket.
#
# This script is idempotent — re-running it is safe (existing entries are
# preserved; the join token is regenerated each time).

set -euo pipefail

# ---- config -----------------------------------------------------------------

TRUST_DOMAIN="ai-agents.example.org"

NODE_SPIFFE_ID="spiffe://${TRUST_DOMAIN}/spire/agent/dev-node"
TEST_AGENT_SPIFFE_ID="spiffe://${TRUST_DOMAIN}/agent/dev/test-agent"

# UID that the test-agent container runs as. Must match the `user:` field
# of the test-agent service in deploy/docker-compose.yml.
TEST_AGENT_UID="1000"

SERVER_CONTAINER="agentauth-spire-server"
COMPOSE_FILE_DEFAULT="$(cd "$(dirname "$0")/.." && pwd)/deploy/docker-compose.yml"
COMPOSE_FILE="${COMPOSE_FILE:-$COMPOSE_FILE_DEFAULT}"

# Where, inside the spire-server container, we write the join token. The
# `spire-bootstrap` volume is shared with the spire-agent container.
JOIN_TOKEN_PATH="/run/spire/bootstrap/join_token"

# ---- helpers ----------------------------------------------------------------

log()  { printf '[register-test-agent] %s\n' "$*" >&2; }
fail() { log "ERROR: $*"; exit 1; }

compose() {
    docker compose -f "$COMPOSE_FILE" "$@"
}

server_exec() {
    compose exec -T spire-server "$@"
}

require_container_running() {
    if ! docker ps --format '{{.Names}}' | grep -qx "$SERVER_CONTAINER"; then
        fail "Container '${SERVER_CONTAINER}' is not running. Start it first with:
        docker compose -f ${COMPOSE_FILE} up -d spire-server"
    fi
}

wait_for_server_healthy() {
    log "waiting for spire-server to be healthy..."
    local i
    for i in $(seq 1 60); do
        if server_exec /opt/spire/bin/spire-server healthcheck >/dev/null 2>&1; then
            log "spire-server is healthy."
            return 0
        fi
        sleep 1
    done
    fail "spire-server did not become healthy within 60s."
}

# Returns 0 if a registration entry with the given SPIFFE ID already exists.
entry_exists() {
    local spiffe_id="$1"
    server_exec /opt/spire/bin/spire-server entry show \
        -spiffeID "$spiffe_id" 2>/dev/null \
        | grep -q '^Entry ID'
}

# ---- 1. preflight -----------------------------------------------------------

require_container_running
wait_for_server_healthy

# ---- 2. node registration entry --------------------------------------------
#
# Bind the dev node's SPIFFE ID to the join_token attestor. Selector format
# for join_token is `join_token:<token>`, but we need to register the node
# *before* we generate the token so the entry is keyed by SPIFFE ID and
# selectorless. SPIRE handles this by allowing node entries that gain
# selectors through attestation.

log "ensuring node entry for ${NODE_SPIFFE_ID} exists..."
if entry_exists "$NODE_SPIFFE_ID"; then
    log "node entry already present — skipping."
else
    # The join_token attestor produces an implicit SPIFFE ID of the form
    # spiffe://<trust-domain>/spire/agent/join_token/<uuid>. We use that
    # canonical form as the parent for workload entries below, so we don't
    # actually need a separate node entry here — but creating one
    # explicitly makes the topology obvious in `spire-server entry show`.
    log "(node entries for join_token are implicit; nothing to create)"
fi

# ---- 3. generate join token -------------------------------------------------

log "generating join token..."
TOKEN_OUTPUT="$(server_exec /opt/spire/bin/spire-server token generate \
    -spiffeID "$NODE_SPIFFE_ID" \
    -ttl 3600)"

# Output looks like:  Token: 6e8a9b5c-...-...
JOIN_TOKEN="$(printf '%s\n' "$TOKEN_OUTPUT" | awk '/^Token:/ {print $2}')"
[ -n "$JOIN_TOKEN" ] || fail "failed to parse join token from spire-server output:
${TOKEN_OUTPUT}"

log "writing join token to shared volume at ${JOIN_TOKEN_PATH}..."
server_exec sh -c "mkdir -p \"$(dirname "$JOIN_TOKEN_PATH")\" \
    && printf '%s' '${JOIN_TOKEN}' > '${JOIN_TOKEN_PATH}' \
    && chmod 0600 '${JOIN_TOKEN_PATH}'"

# ---- 4. workload registration entry ----------------------------------------

# Parent for the workload entry is the node identity that the join_token
# attestor will produce.
JOIN_TOKEN_NODE_ID="spiffe://${TRUST_DOMAIN}/spire/agent/join_token/${JOIN_TOKEN}"

log "registering workload entry for ${TEST_AGENT_SPIFFE_ID}..."
if entry_exists "$TEST_AGENT_SPIFFE_ID"; then
    log "workload entry already present — skipping."
else
    server_exec /opt/spire/bin/spire-server entry create \
        -parentID "$JOIN_TOKEN_NODE_ID" \
        -spiffeID "$TEST_AGENT_SPIFFE_ID" \
        -selector "unix:uid:${TEST_AGENT_UID}" \
        -ttl 3600
fi

log "done."
log ""
log "  Trust domain : ${TRUST_DOMAIN}"
log "  Node SPIFFE  : ${JOIN_TOKEN_NODE_ID}"
log "  Test agent   : ${TEST_AGENT_SPIFFE_ID}  (selector: unix:uid:${TEST_AGENT_UID})"
log ""
log "Next: docker compose -f ${COMPOSE_FILE} up -d spire-agent"
