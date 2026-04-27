# Architecture Decision Records

This directory holds Architecture Decision Records (ADRs) for the platform.

## When to write an ADR

Per [`CLAUDE.md`](../../CLAUDE.md), an ADR is **required** for any change to the
architectural invariants — the identity provider, the policy engine, the PEP
placement model, the SPIFFE ID hierarchy, the trust-domain strategy, or any
fail-open / fail-closed behavior.

ADRs are also valuable (but optional) for non-invariant decisions that future
contributors should understand: choice of bundle distribution mechanism,
choice of audit storage backend, etc.

## Format

1. Copy `000-template.md` to `NNN-short-title.md` where `NNN` is the next
   sequential number (zero-padded to 3 digits).
2. Fill in **Status**, **Context**, **Decision**, **Consequences**.
3. Open a PR. Discussion happens in PR review.
4. On merge, status moves from `Proposed` to `Accepted`.
5. If a later ADR replaces this one, mark this one
   `Superseded by ADR-{NNN}` — never delete it.

## Index

| ID | Title | Status |
|----|-------|--------|
| [000](./000-template.md) | Template | n/a |
| [001](./001-spiffe-spire-and-opa-rego-foundation.md) | SPIFFE/SPIRE + OPA/Rego + Envoy PEPs as the foundation | Accepted |
