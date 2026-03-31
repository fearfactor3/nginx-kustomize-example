# Kyverno Policies

Reference for the four ClusterPolicies in this repository.

> **Source of truth:** `kyverno/policies/` in this repo. Policies are fetched
> directly from `main` by `argocd-eks-terraform/stacks/kyverno/policies.tf`
> via `data "http"` + `yamldecode()` and applied to both EKS clusters via
> Spacelift. To update a policy: edit the YAML here, merge to `main`, then
> trigger a Spacelift run on the kyverno stack.

## Policy Overview

All policies run in `Enforce` mode and target `Pod` resources. Targeting Pods (rather than Deployments) ensures enforcement across all workload types — Deployments, DaemonSets, StatefulSets, Jobs, and manual pod creation.

Most `foreach` rules cover `containers`, `initContainers`, and `ephemeralContainers`, preventing policy bypass via `kubectl debug`. The exception is `require-probes` — probes are not valid on ephemeral containers and that policy intentionally targets `containers` only.

| Policy | File | What it enforces |
| --- | --- | --- |
| `require-image-tag` | `require-image-tag.yaml` | Images must have a specific tag (not `:latest`, not untagged) |
| `require-resource-limits` | `require-resource-limits.yaml` | All containers must define CPU and memory limits |
| `require-non-root` | `require-non-root.yaml` | Pod-level `runAsNonRoot: true`; no container-level root override; `drop: [ALL]` on every container |
| `require-probes` | `require-probes.yaml` | All containers must define `livenessProbe` and `readinessProbe` |

## Why nginx/nginx-unprivileged

The standard `nginx` Docker image runs as `root` (uid 0) and binds to port 80. The `require-non-root` policy in `Enforce` mode would block it.

`nginx/nginx-unprivileged` is the official rootless variant:

| | `nginx` | `nginx/nginx-unprivileged` |
| --- | --- | --- |
| User | root (uid 0) | nginx (uid 101) |
| Port | 80 | 8080 |
| Kyverno compatible | No | Yes |

This repository uses `nginx/nginx-unprivileged:1.27.4`. The `containerPort` and all probes target port `8080`. The Service `port: 80` is unchanged — only `targetPort` points to `8080`.

## Policy Details

### require-image-tag

Denies pods where any container uses `:latest` or has no tag at all.

Violation example:

```yaml
image: nginx/nginx-unprivileged:latest  # denied
image: nginx/nginx-unprivileged         # denied (no tag)
image: nginx/nginx-unprivileged:1.27.4  # allowed
```

### require-resource-limits

Denies pods where any container is missing `resources.limits.cpu` or `resources.limits.memory`.

Violation example:

```yaml
containers:
  - name: nginx
    image: nginx/nginx-unprivileged:1.27.4
    # no resources block — denied
```

### require-non-root

Three rules:

1. `require-run-as-non-root` — pod-level `securityContext.runAsNonRoot` must be `true`
2. `deny-container-run-as-root` — no container may set `runAsNonRoot: false` or `runAsUser: 0` at the container level (prevents pod-level bypass)
3. `require-drop-all` — every container's `securityContext.capabilities.drop` must include `ALL`

Rules 2 and 3 iterate `containers + initContainers + ephemeralContainers`.

Violation examples:

```yaml
# Rule 1 — pod-level non-root not set
spec:
  securityContext:
    runAsNonRoot: false   # denied

# Rule 2 — container-level override bypasses pod-level check
spec:
  securityContext:
    runAsNonRoot: true    # passes rule 1...
  containers:
    - securityContext:
        runAsUser: 0      # ...but denied by rule 2

# Rule 3 — capabilities not dropped
  containers:
    - securityContext:
        capabilities:
          drop: []        # denied
```

### require-probes

Two rules: `require-liveness-probe` and `require-readiness-probe`. Both must be present on every container.

## Running the Test Suite

```shell
kyverno test kyverno/tests/
# or
make test
```

Expected output:

```text
Executing nginx-policy-tests...
pass: 10, fail: 0, skip: 0, error: 0
```

## Adding a New Policy

1. Create `kyverno/policies/<policy-name>.yaml` as a `ClusterPolicy` targeting `Pod`
2. Add a `data "http"` + `kubernetes_manifest` block to `stacks/kyverno/policies.tf`
   in [argocd-eks-terraform](https://github.com/fearfactor3/argocd-eks-terraform)
   pointing at the new file URL
3. Add a failing test fixture to `kyverno/tests/resources/fail-<violation>.yaml`
4. Update `kyverno/tests/kyverno-test.yaml` with the expected result
5. Run `make test` locally to validate before opening a PR
6. Merge to `main` — Spacelift picks up the new URL and applies the policy

Use `validationFailureAction: Audit` during development to observe violations
without blocking pods, then switch to `Enforce` once validated.
