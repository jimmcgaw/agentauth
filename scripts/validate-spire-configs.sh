#!/usr/bin/env bash
#
# validate-spire-configs.sh
#
# Parses every SPIRE config in spire/ using `spire-server validate` and
# `spire-agent validate`. Used by CI and pre-commit to catch config-syntax
# regressions without needing to bring up the full Docker stack.
#
# Requires the `spire-server` and `spire-agent` binaries (or the official
# container images) on PATH. CI uses the container images via `docker run`.

set -euo pipefail

SPIRE_VERSION="${SPIRE_VERSION:-1.9.6}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SERVER_CONF_DIR="$ROOT_DIR/spire/server"
AGENT_CONF_DIR="$ROOT_DIR/spire/agent"

log()  { printf '[validate-spire-configs] %s\n' "$*" >&2; }
fail() { log "ERROR: $*"; exit 1; }

# Pick local binary if available, else fall back to the container image.
have() { command -v "$1" >/dev/null 2>&1; }

validate_with_local_binary() {
    local binary="$1" conf="$2"
    log "validating $(basename "$conf") with local $binary"
    "$binary" validate -config "$conf"
}

validate_with_docker() {
    local image="$1" conf="$2" mount_dir
    mount_dir="$(dirname "$conf")"
    log "validating $(basename "$conf") with image $image"
    docker run --rm \
        -v "$mount_dir:/conf:ro" \
        --entrypoint "/opt/spire/bin/$(basename "$image" | cut -d: -f1 | sed 's|.*/||')" \
        "$image" \
        validate -config "/conf/$(basename "$conf")"
}

validate_server_conf() {
    local conf="$SERVER_CONF_DIR/server.conf"
    [ -f "$conf" ] || fail "missing $conf"
    if have spire-server; then
        validate_with_local_binary spire-server "$conf"
    else
        validate_with_docker "ghcr.io/spiffe/spire-server:${SPIRE_VERSION}" "$conf"
    fi
}

validate_agent_conf() {
    local conf="$AGENT_CONF_DIR/agent.conf"
    [ -f "$conf" ] || fail "missing $conf"
    if have spire-agent; then
        validate_with_local_binary spire-agent "$conf"
    else
        validate_with_docker "ghcr.io/spiffe/spire-agent:${SPIRE_VERSION}" "$conf"
    fi
}

validate_server_conf
validate_agent_conf

log "all SPIRE configs valid."
