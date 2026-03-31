# GitOps

How ArgoCD manages deployments from this repository to EKS.

## How It Works

ArgoCD polls this repository's `main` branch and reconciles the cluster state against the rendered Kustomize output. Two Applications are registered — one per environment:

| Application | Overlay path | Cluster namespace | Cluster |
|---|---|---|---|
| `nginx-dev` | `overlays/dev` | `nginx-dev` | `argocd-dev` |
| `nginx-prod` | `overlays/prod` | `nginx-prod` | `argocd-prod` |

Sync behaviour differs by environment:

| | `nginx-dev` | `nginx-prod` |
|---|---|---|
| Sync mode | Automated | **Manual** |
| `prune` | `true` | — |
| `selfHeal` | `true` | — |
| How to deploy | Merge to `main` | `argocd app sync nginx-prod` |

Both Applications share:

- **`CreateNamespace=true`** — ArgoCD creates the target namespace if it doesn't exist
- **`PrunePropagationPolicy=foreground`** — dependent resources are cleaned up before parents
- **Retry** — up to 5 attempts with exponential backoff (max 3 min)

## AppProject

Both Applications belong to the `nginx` AppProject ([argocd/project.yaml](../argocd/project.yaml)), which enforces:

- **Source restriction** — only this repository's URL is permitted
- **Destination restriction** — deployments only to `nginx-dev` and `nginx-prod` namespaces on the in-cluster server
- **Resource whitelist** — only the resource types used by this repo can be managed (Deployment, Service, ServiceAccount, HPA, PDB, NetworkPolicy, ResourceQuota, LimitRange, Namespace)

Apply the AppProject before the Applications:

```shell
kubectl apply -f argocd/project.yaml
kubectl apply -f argocd/app-dev.yaml
kubectl apply -f argocd/app-prod.yaml
```

## Viewing Sync Status

```shell
# List all Applications
kubectl get applications -n argocd

# Watch sync in real time
kubectl get applications -n argocd -w

# Get detailed status for a specific app
kubectl describe application nginx-dev -n argocd
```

## Deploying to Prod

Prod requires a manual sync — changes merged to `main` are **not** automatically promoted to `nginx-prod`.

```shell
# Via argocd CLI (requires argocd login)
argocd app sync nginx-prod

# Via kubectl
kubectl patch application nginx-prod -n argocd \
  --type merge -p '{"operation":{"initiatedBy":{"username":"manual"},"sync":{"revision":"HEAD"}}}'
```

## Triggering a Dev Sync Manually

Dev syncs automatically on merge, but you can force an immediate sync:

```shell
argocd app sync nginx-dev
```

## Applying the Applications

Before applying, update `repoURL` in [argocd/app-dev.yaml](../argocd/app-dev.yaml) and [argocd/app-prod.yaml](../argocd/app-prod.yaml) with the actual GitHub URL of this repository.

```shell
kubectl apply -f argocd/project.yaml
kubectl apply -f argocd/app-dev.yaml
kubectl apply -f argocd/app-prod.yaml
```

## NetworkPolicy — Granting Namespace Access

The prod NetworkPolicy only allows ingress from namespaces explicitly labelled `nginx-access: "true"`. Apply this label to any namespace that needs to reach nginx (ingress controller, monitoring):

```shell
kubectl label namespace ingress-nginx nginx-access=true
kubectl label namespace monitoring nginx-access=true
```

The dev NetworkPolicy allows any pod within the `nginx-dev` namespace (port 8080 only).

## Connecting This Repo to argocd-eks-terraform

The `argocd-eks-terraform` stack has an `argocd_source_repo` variable (currently `"*"`) that controls which repositories ArgoCD is permitted to sync from. Once this repo is wired up, restrict it to this repo's URL:

In `argocd-eks-terraform/stacks/argo-cd/dev.tfvars` and `prod.tfvars`:

```hcl
argocd_source_repo = "https://github.com/YOUR_ORG/nginx-kustomize-example.git"
```

Apply via Spacelift or `tofu apply` in the `stacks/argo-cd/` directory.

## Namespace Isolation

Each environment gets its own namespace with Pod Security Standards `restricted` enforcement:

| Namespace | Replicas | HPA | PDB | ResourceQuota |
| --- | --- | --- | --- | --- |
| `nginx-dev` | 1 | — | — | — |
| `nginx-prod` | 3 (min) | 3–10 | minAvailable: 2 | 12 pods, 1500m CPU, 1280Mi memory |

Namespaces are created by the `namespace.yaml` resources in each overlay. ArgoCD's `CreateNamespace=true` also creates them on first sync if applied before the namespace manifests.
