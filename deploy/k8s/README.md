# deploy/k8s — Kubernetes manifests

> **Status:** Placeholder. Manifests are added after the Docker Compose stack
> and the end-to-end auth flow are proven (post Phase 3).

## Planned layout

- `spire/` — `StatefulSet` for SPIRE Server, `DaemonSet` for SPIRE Agent,
  `ServiceAccount` plumbing for k8s workload attestation.
- `opa/` — OPA `Deployment`, OPAL Server `Deployment`, OPAL Client sidecar
  pattern.
- `services/` — per-service manifests with Envoy sidecar templates.
- `crds/` — `spire-controller-manager` `ClusterSPIFFEID` CRDs replacing the
  shell-script registration entries used in Docker Compose.
