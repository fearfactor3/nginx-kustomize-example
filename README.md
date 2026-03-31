# nginx-kustomize-example

A production-ready nginx application deployed to Amazon EKS using Kustomize and ArgoCD GitOps.

> **Before you begin:** Replace `YOUR_ORG` throughout this repository with your actual GitHub organization or username. Search with `grep -r YOUR_ORG .`

[![validate](https://github.com/YOUR_ORG/nginx-kustomize-example/actions/workflows/validate.yaml/badge.svg)](https://github.com/YOUR_ORG/nginx-kustomize-example/actions/workflows/validate.yaml)
[![MegaLinter](https://github.com/YOUR_ORG/nginx-kustomize-example/actions/workflows/mega-linter.yml/badge.svg)](https://github.com/YOUR_ORG/nginx-kustomize-example/actions/workflows/mega-linter.yml)

## Overview

This repository manages the deployment of an nginx application to two isolated EKS environments (`dev` and `prod`) provisioned by [argocd-eks-terraform](https://github.com/YOUR_ORG/argocd-eks-terraform). Dev deploys automatically on every merge to `main`; prod requires a manual `argocd app sync nginx-prod`.

## Architecture

```text
GitHub repo (source of truth)
        │
        ▼
  GitHub Actions CI
  ┌─────────────────────────────────────┐
  │  yamllint → kustomize build         │
  │  kubeconform → kyverno test         │
  └─────────────────────────────────────┘
        │
        ▼
  ArgoCD (in-cluster, watches main branch)
  ┌──────────────────┐  ┌──────────────────┐
  │  nginx-dev app   │  │  nginx-prod app   │
  │  overlays/dev    │  │  overlays/prod    │
  └────────┬─────────┘  └────────┬──────────┘
           ▼                     ▼
     EKS argocd-dev        EKS argocd-prod
     namespace: nginx-dev  namespace: nginx-prod
```

Kyverno ClusterPolicies enforce security standards at admission time on both clusters.

## Repository Structure

```text
.
├── .github/
│   ├── linters/              # Linter configs (.yamllint, .commitlintrc.yaml, .markdownlint.json)
│   └── workflows/
│       ├── validate.yaml     # YAML lint, kustomize build, kubeconform, kyverno test
│       └── mega-linter.yml   # MegaLinter (cupcake flavor) — YAML, Markdown, Trivy, Gitleaks
├── argocd/
│   ├── app-dev.yaml          # ArgoCD Application — dev (automated sync)
│   ├── app-prod.yaml         # ArgoCD Application — prod (manual sync)
│   └── project.yaml          # ArgoCD AppProject — source/destination restrictions
├── base/
│   ├── deployment.yaml       # nginx/nginx-unprivileged:1.27.4, port 8080, securityContext, probes
│   ├── kustomization.yaml
│   ├── network-policy.yaml   # Base NetworkPolicy — intra-namespace ingress on port 8080, DNS egress
│   ├── service.yaml          # ClusterIP, port 80 → targetPort 8080
│   └── serviceaccount.yaml   # Dedicated SA, automountServiceAccountToken: false
├── kyverno/
│   ├── policies/             # 4 ClusterPolicies (Enforce mode, covers ephemeralContainers)
│   └── tests/                # kyverno CLI test suite (passing + failing fixtures)
├── overlays/
│   ├── dev/
│   │   ├── deployment.yaml   # 1 replica, right-sized resources (50m CPU / 64Mi memory)
│   │   ├── kustomization.yaml
│   │   ├── namespace.yaml    # PSS restricted enforcement labels
│   │   └── vpa.yaml          # VPA recommendation-only (updateMode: Off)
│   └── prod/
│       ├── deployment.yaml   # 3 replicas, topology spread, right-sized resources
│       ├── hpa.yaml          # HPA autoscaling/v2, min 3 / max 10, CPU + memory
│       ├── kustomization.yaml
│       ├── namespace.yaml    # PSS restricted enforcement labels
│       ├── network-policy.yaml  # Prod override — label-gated ingress (nginx-access: "true")
│       ├── pdb.yaml          # PodDisruptionBudget, minAvailable: 2
│       └── resource-quota.yaml  # ResourceQuota + LimitRange
├── docs/
│   ├── setup.md              # Prerequisites and developer setup
│   ├── development.md        # Daily workflow and three-layer feedback system
│   ├── gitops.md             # ArgoCD GitOps workflow
│   └── kyverno-policies.md   # Policy reference and test guide
├── .mega-linter.yml          # MegaLinter configuration (cupcake flavor)
├── .pre-commit-config.yaml   # Pre-commit hooks (Layer 1 feedback)
└── Makefile                  # Local development targets
```

## Quick Start

### Prerequisites

See [docs/setup.md](docs/setup.md) for full tool installation instructions.

Required: `kubectl`, `kustomize`, `kyverno` CLI, `yamllint`, `pre-commit`

### Local validation (no cluster required)

```shell
# Install pre-commit hooks
pre-commit install --install-hooks

# Run all checks
make all
```

### Minikube (local cluster testing)

```shell
minikube start
minikube addons enable metrics-server

helm repo add kyverno https://kyverno.github.io/kyverno/
helm install kyverno kyverno/kyverno --version 3.3.7 -n kyverno --create-namespace

kubectl apply -f kyverno/policies/
kubectl apply -f argocd/project.yaml
kubectl apply -k overlays/dev
kubectl get pods -n nginx-dev
```

See [docs/development.md](docs/development.md) for the full minikube workflow.

### EKS (via ArgoCD)

Update `repoURL` in [argocd/app-dev.yaml](argocd/app-dev.yaml) and [argocd/app-prod.yaml](argocd/app-prod.yaml), then:

```shell
kubectl apply -f kyverno/policies/
kubectl apply -f argocd/project.yaml
kubectl apply -f argocd/app-dev.yaml
kubectl apply -f argocd/app-prod.yaml

# Label namespaces that need access to nginx (ingress controller, monitoring)
kubectl label namespace ingress-nginx nginx-access=true
kubectl label namespace monitoring nginx-access=true

kubectl get applications -n argocd -w
```

See [docs/gitops.md](docs/gitops.md) for the full GitOps workflow.

## Kyverno Policies

Four ClusterPolicies run in `Enforce` mode on both clusters:

| Policy | Enforcement |
|---|---|
| `require-image-tag` | Blocks pods using `:latest` or untagged images |
| `require-resource-limits` | Blocks pods missing CPU or memory limits |
| `require-non-root` | Blocks pods running as root, container-level root overrides, or missing `drop: ALL` |
| `require-probes` | Blocks pods missing liveness or readiness probes |

See [docs/kyverno-policies.md](docs/kyverno-policies.md) for the full policy reference.

## CI/CD

Three-layer feedback system:

| Layer | Tool | Trigger |
|---|---|---|
| 1 — Pre-commit | check-yaml, commitlint, kustomize-build | On every local commit |
| 2 — CI | yamllint, kustomize build, kubeconform, kyverno test | On every PR |
| 3 — MegaLinter | actionlint, gitleaks, trivy, yamllint, markdownlint | On every PR + weekly |
