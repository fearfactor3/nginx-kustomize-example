# Setup

Prerequisites and one-time developer setup for working with this repository.

## Required Tools

| Tool | Version | Install |
| --- | --- | --- |
| `kubectl` | >= 1.29 | [docs](https://kubernetes.io/docs/tasks/tools/) |
| `kustomize` | >= 5.4 | `brew install kustomize` |
| `kyverno` CLI | v1.13.6 | See below |
| `kubeconform` | v0.6.7 | See below |
| `yamllint` | >= 1.35 | `pip install yamllint` |
| `pre-commit` | >= 3.x | `pip install pre-commit` |
| `argocd` CLI | >= 2.x | `brew install argocd` (EKS prod sync only) |
| `helm` | >= 3.x | `brew install helm` (minikube testing only) |
| `minikube` | >= 1.33 | `brew install minikube` (optional) |

### Install kyverno CLI

```shell
# macOS (arm64)
curl -sSL https://github.com/kyverno/kyverno/releases/download/v1.13.6/kyverno-cli_v1.13.6_darwin_arm64.tar.gz \
  | tar -xz -C /usr/local/bin kyverno

# macOS (x86_64)
curl -sSL https://github.com/kyverno/kyverno/releases/download/v1.13.6/kyverno-cli_v1.13.6_darwin_x86_64.tar.gz \
  | tar -xz -C /usr/local/bin kyverno

# Or via Makefile (Linux/macOS auto-detects arch)
make install-tools
```

### Install kubeconform (for schema validation)

```shell
# macOS
brew install kubeconform

# Or via Makefile
make install-tools
```

## Pre-commit Hooks

Install hooks after cloning:

```shell
pre-commit install --install-hooks
```

This installs two hook types:

- `pre-commit` — runs on every `git commit`: YAML syntax check, whitespace cleanup, large-file guard, no-commit-to-main, kustomize build validation
- `commit-msg` — runs on every commit message: enforces conventional commit format (see [development.md](development.md))

## EKS Cluster Access

The clusters are provisioned by [argocd-eks-terraform](https://github.com/YOUR_ORG/argocd-eks-terraform). To configure kubectl:

```shell
# Dev cluster
aws eks update-kubeconfig --name argocd-dev --region <your-region>

# Prod cluster
aws eks update-kubeconfig --name argocd-prod --region <your-region>
```

Confirm access:

```shell
kubectl get nodes
kubectl get applications -n argocd
```

## First-Time Cluster Bootstrap

Kyverno and its ClusterPolicies are managed by the `stacks/kyverno` stack in
[argocd-eks-terraform](https://github.com/fearfactor3/argocd-eks-terraform) and are
applied automatically via Spacelift. The policy YAML files in `kyverno/policies/`
are the source of truth — Terraform fetches them from `main` at apply time.
No manual policy steps are required here.

After gaining cluster access, apply the ArgoCD AppProject and Applications once per
cluster. ArgoCD will manage all subsequent changes via GitOps.

```shell
# 1. Create the ArgoCD AppProject (restricts sources, destinations, and resource types)
kubectl apply -f argocd/project.yaml

# 2. Register the ArgoCD Applications
kubectl apply -f argocd/app-dev.yaml
kubectl apply -f argocd/app-prod.yaml

# 3. Label namespaces that need HTTP access to nginx
#    (ingress controller, monitoring — adjust to match your cluster)
kubectl label namespace ingress-nginx nginx-access=true
kubectl label namespace monitoring nginx-access=true

# 4. Watch initial sync
kubectl get applications -n argocd -w
```

> **Note:** Prod does not auto-sync. After the initial `kubectl apply`, subsequent deployments require `argocd app sync nginx-prod`. See [gitops.md](gitops.md) for details.
