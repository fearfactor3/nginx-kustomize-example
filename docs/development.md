# Development

Daily workflow for contributing to this repository.

## Three-Layer Feedback System

Changes are validated at three points before reaching the cluster:

| Layer | Tool | When | What it checks |
|---|---|---|---|
| 1 — Pre-commit | check-yaml, commitlint, kustomize-build | Every local commit | YAML syntax, commit message format, overlay renders |
| 2 — CI | yamllint, kustomize build, kubeconform, kyverno test | Every PR | Style, schema, Kyverno policy correctness |
| 3 — MegaLinter | actionlint, gitleaks, trivy, yamllint, markdownlint | Every PR + weekly | Secrets, CVEs, workflow syntax, Markdown quality |

Fix failures at the lowest layer first — a pre-commit failure means the issue would also fail CI.

## Local Validation

Run all checks locally before pushing:

```shell
make all
```

Or individually:

```shell
make lint      # yamllint style check
make build     # kustomize build for dev + prod overlays
make validate  # kubeconform K8s 1.32 schema validation
make test      # kyverno CLI policy tests — expect pass:11 fail:0
```

## Minikube Workflow

Test against a real Kubernetes cluster before pushing:

```shell
# 1. Start cluster with metrics-server (required for HPA)
minikube start
minikube addons enable metrics-server

# 2. Install Kyverno (pinned to match EKS clusters)
helm repo add kyverno https://kyverno.github.io/kyverno/
helm install kyverno kyverno/kyverno --version 3.3.7 -n kyverno --create-namespace

# 3. Apply policies and ArgoCD AppProject
kubectl apply -f kyverno/policies/
kubectl apply -f argocd/project.yaml

# 4. Deploy and verify
kubectl apply -k overlays/dev
kubectl get pods -n nginx-dev

# 5. Confirm a policy violation is blocked (all four policies)
kubectl apply -f kyverno/tests/resources/fail-latest-tag.yaml
kubectl apply -f kyverno/tests/resources/fail-root-container.yaml
kubectl apply -f kyverno/tests/resources/fail-no-limits.yaml
kubectl apply -f kyverno/tests/resources/fail-no-probes.yaml
# Expected: Error from server — admission webhook denied the request

# 6. Test prod overlay (HPA, PDB, topology spread, ResourceQuota)
kubectl apply -k overlays/prod
kubectl get hpa,pdb -n nginx-prod
kubectl get resourcequota -n nginx-prod
```

## VPA Recommendations (dev only)

The dev overlay deploys a VPA in recommendation-only mode (`updateMode: Off`). After 7+ days of traffic, query collected recommendations to validate or further tune the resource requests in both overlays:

```shell
kubectl get vpa nginx-vpa -n nginx-dev -o json | jq '.status.recommendation'
```

The output shows `lowerBound`, `target`, and `upperBound` for CPU and memory. Update `overlays/dev/deployment.yaml` and `overlays/prod/deployment.yaml` resource values accordingly, then update `overlays/prod/resource-quota.yaml` in lockstep.

## Commit Message Format

Commits must follow the [Conventional Commits](https://www.conventionalcommits.org/) format:

```text
type(scope): short description
```

Enforced by commitlint at `commit-msg` hook time.

**Allowed types:** `fix`, `feat`, `docs`, `style`, `refactor`, `test`, `chore`, `ci`

**Allowed scopes:** `base`, `overlays`, `kyverno`, `argocd`, `ci`, `deps`, `docs`

Examples:

```text
feat(base): add startupProbe to nginx deployment
fix(overlays): right-size prod CPU and memory requests
feat(kyverno): add ephemeralContainers to require-non-root foreach
chore(ci): pin kyverno CLI to v1.13.6
docs(readme): update repository structure tree
```

## Branch Strategy

- Work on feature branches (`feat/`, `fix/`, `chore/`, etc.)
- Open a PR against `main`
- `main` is protected — direct commits are blocked by the `no-commit-to-branch` pre-commit hook
- All CI and MegaLinter checks must pass before merge
- Merging to `main` automatically syncs **dev only** — prod requires a manual `argocd app sync nginx-prod`
