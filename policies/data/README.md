# policies/data — Static policy data

JSON data files loaded into OPA alongside the Rego policies. These files are
the source of truth for capability assignments, resource sensitivity labels,
role mappings, and other policy-adjacent facts.

OPA loads each `.json` file under this directory at the same path within
`data.*`. For example, `policies/data/agents.json` becomes available to Rego
as `data.agents`.

> **Status:** Placeholder. Concrete data fixtures are added in Phase 2.

## Planned files

| File | Rego path | Contents |
|------|-----------|----------|
| `agents.json` | `data.agents` | SPIFFE-ID → capability set, tier, status |
| `resource_permissions.json` | `data.resource_permissions` | resource-type → action → required capability |
| `resources.json` | `data.resources` | resource-id → sensitivity label, owner |
| `config.json` | `data.config` | global tunables (e.g., `max_delegation_depth`) |

## Conventions

- Never put secrets here. Capability names and SPIFFE IDs only.
- Treat changes here as policy changes — they go through the same PR review,
  CI, and OPAL distribution path.
