# Top-level developer convenience targets.
#
# All commands operate against the local Docker Compose stack defined in
# deploy/docker-compose.yml. Production deployment lives elsewhere.

COMPOSE     := docker compose -f deploy/docker-compose.yml
COMPOSE_PROJECT := agentauth-dev

.PHONY: help build start stop down clean \
        verify-identity test-agent-up test-agent-logs

help:
	@echo "Targets:"
	@echo "  build             Build all Compose images."
	@echo "  start             Start the full local stack."
	@echo "  stop              Stop running containers (volumes preserved)."
	@echo "  down              Tear down the stack (volumes preserved)."
	@echo "  clean             Tear down the stack and remove volumes."
	@echo "  verify-identity   Phase 1a smoke test — prove SPIRE issues SVIDs."
	@echo "  test-agent-up     Build + start the test-agent reference workload."
	@echo "  test-agent-logs   Tail the test-agent's structured JSON logs."

build:
	$(COMPOSE) build

start:
	$(COMPOSE) up

stop:
	$(COMPOSE) stop

down:
	$(COMPOSE) down --remove-orphans

clean:
	$(COMPOSE) down --remove-orphans --volumes

# Phase 1a checkpoint: SPIRE Server + Agent come up, the dev workload entry
# is registered, and we successfully fetch an X.509 SVID for it via the
# Workload API. Set KEEP_STACK=1 to leave the stack running for follow-up
# inspection.
verify-identity:
	./scripts/verify-spire.sh

# Phase 1b: bring up the reference test-agent service. Assumes the identity
# layer is already running (e.g. via `make verify-identity KEEP_STACK=1`).
test-agent-up:
	$(COMPOSE) up -d --build test-agent

test-agent-logs:
	$(COMPOSE) logs -f test-agent
