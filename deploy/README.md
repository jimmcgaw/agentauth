# deploy — Deployment artifacts

| Path | Purpose |
|------|---------|
| `docker-compose.yml` | Local development stack — SPIRE Server, SPIRE Agent, OPA, OPAL, Envoy, services |
| `k8s/` | Kubernetes manifests (raw YAML) |
| `helm/` | Helm charts (when applicable) |

## Local development

```bash
# Bring up the full stack
docker compose -f deploy/docker-compose.yml up

# Bring up just the identity layer
docker compose -f deploy/docker-compose.yml up spire-server spire-agent

# Tear down (and remove volumes)
docker compose -f deploy/docker-compose.yml down -v
```

The compose file mounts the repository's `policies/`, `spire/`, `envoy/`,
and `opal/` directories into the relevant containers, so edits on the host
take effect with a container restart (or, for policies, automatically via
OPAL).

## Kubernetes

> **Status:** Placeholder. Production-shaped Kubernetes manifests are added
> after the local stack and the end-to-end vertical slice are proven.
