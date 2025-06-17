# nginx-kustomize-example
A simple Nginx application with kustomize

## How to run
### dev
```shell
kubectl apply -k overlays/dev
kubectl get all -n nginx-dev
```

### prod
```shell
kubectl apply -k overlays/prod
kubectl get all -n nginx-prod
```
