# opal — OPAL configuration

OPAL (Open Policy Administration Layer) distributes policies and data to OPA
instances in near-real-time. It is preferred over vanilla OPA bundle polling
because capability revocations need to take effect quickly.

| File | Purpose |
|------|---------|
| `opal-server.env` | OPAL Server config — watches the `policies/` directory in this repo |
| `opal-client.env` | OPAL Client config — runs as a sidecar to OPA, applies updates |

## Topology

```
policies/ (Git)
    │
    ▼
OPAL Server  ──────────►  OPAL Client(s)  ──►  OPA instance(s)
   (push)                    (sidecar)
```

## Local development

For Docker Compose, the OPAL Server watches a bind-mounted copy of the local
`policies/` directory rather than a remote Git repo. This gives the same
real-time feedback loop without needing to push commits.

## Conventions

- No secrets in `.env` files. OPAL JWT signing keys (when used in non-dev
  environments) come from a secret store, not from these files.
- Authorization data — the `data/` JSON files — is distributed alongside
  policy. Treat data changes with the same review rigor as policy changes.
