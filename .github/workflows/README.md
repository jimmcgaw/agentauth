# .github/workflows

GitHub Actions workflows.

| Workflow | Purpose |
|----------|---------|
| `ci.yml` | Runs on every PR — policy tests, Rego linting, SPIRE config validation, Python tests and type checks |

CI must stay fast and deterministic. No deployment steps run from this
directory — deployments are operated separately.
