# docs

Project documentation.

| File / Directory | Purpose |
|------------------|---------|
| `architecture.md` | Reference architecture and component overview (sourced from the initial design) |
| `adr/` | Architecture Decision Records — one per non-trivial design decision |
| `runbooks/` | Operational runbooks for incident response and recurring procedures |

## Architecture Decision Records

Every change to the architectural invariants in `CLAUDE.md` requires an ADR.
Use `adr/000-template.md` as the starting point. ADRs are numbered sequentially
and never deleted — superseded ADRs are marked `Superseded by ADR-{NNN}` rather
than removed.
