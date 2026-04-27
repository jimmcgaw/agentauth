# Architecture Reference

This document is the architectural reference for the AI Agent AuthN/AuthZ
platform. It is the long-form companion to [`../CLAUDE.md`](../CLAUDE.md), which
captures the invariants in a form suitable for AI coding agents.

> **Status:** Placeholder. The initial-design content from `spec.md` will be
> migrated into this document as the system is built. Until then, treat
> `spec.md` and `CLAUDE.md` at the repository root as the authoritative
> references.

## Index (to be written)

- Identity Plane — SPIRE Server, SPIRE Agent, SVID lifecycle
- Authorization Plane — OPA, Rego, OPAL distribution
- Enforcement Plane — Envoy PEP patterns, SDK interceptors
- Audit Plane — Decision logs, OpenTelemetry tracing
- SPIFFE ID hierarchy and trust domain strategy
- Federation across environments
