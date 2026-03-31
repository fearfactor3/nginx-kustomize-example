.DEFAULT_GOAL := help

KUSTOMIZE           ?= kustomize
KYVERNO             ?= kyverno
KUBECONFORM         ?= kubeconform
YAMLLINT            ?= yamllint
KUBECTL             ?= kubectl
K8S_VERSION         ?= 1.32.0
KYVERNO_VERSION     ?= v1.13.6
KUBECONFORM_VERSION ?= v0.6.7
KUSTOMIZE_VERSION   ?= 5.4.3

.PHONY: all lint build validate test \
        argocd-apply \
        apply-dev apply-prod diff-dev diff-prod \
        check-context install-tools help

## ── Validation ──────────────────────────────────────────────────────────────

all: lint build validate test ## Run all checks (lint → build → validate → test)

lint: ## YAML style check via yamllint
	$(YAMLLINT) -c .github/linters/.yamllint .

build: ## Render both overlays with kustomize (validates structure)
	@$(KUSTOMIZE) build overlays/dev  > /dev/null
	@$(KUSTOMIZE) build overlays/prod > /dev/null

validate: ## Schema validation against K8s $(K8S_VERSION) via kubeconform
	$(KUSTOMIZE) build overlays/dev  | $(KUBECONFORM) -strict -summary -ignore-missing-schemas -kubernetes-version $(K8S_VERSION) -schema-location default
	$(KUSTOMIZE) build overlays/prod | $(KUBECONFORM) -strict -summary -ignore-missing-schemas -kubernetes-version $(K8S_VERSION) -schema-location default

test: ## Kyverno CLI policy tests — expect pass:10 fail:0
	@if ! command -v $(KYVERNO) > /dev/null 2>&1; then \
		echo "warning: kyverno not found — skipping policy tests (run make install-tools)"; \
	else \
		$(KYVERNO) test kyverno/tests/; \
	fi

## ── Cluster bootstrap (one-time) ─────────────────────────────────────────────

argocd-apply: ## Apply ArgoCD AppProject + Applications to current kubectl context
	$(KUBECTL) apply -f argocd/project.yaml
	$(KUBECTL) apply -f argocd/app-dev.yaml
	$(KUBECTL) apply -f argocd/app-prod.yaml

## ── Per-environment operations ───────────────────────────────────────────────

apply-dev: ## Apply dev overlay (kubectl apply -k overlays/dev)
	$(KUBECTL) apply -k overlays/dev

apply-prod: check-context ## Apply prod overlay — confirms kubectl context first
	$(KUBECTL) apply -k overlays/prod

diff-dev: ## Show diff for dev overlay vs current cluster state
	$(KUBECTL) diff -k overlays/dev

diff-prod: ## Show diff for prod overlay vs current cluster state
	$(KUBECTL) diff -k overlays/prod

check-context:
	@echo "Current context: $$($(KUBECTL) config current-context)"
	@printf "Apply to prod? [y/N] " && read ans && [ "$${ans}" = "y" ]

## ── Local setup ──────────────────────────────────────────────────────────────

install-tools: ## Install kyverno CLI and kubeconform (Linux/macOS)
	@OS=$$(uname -s | tr '[:upper:]' '[:lower:]'); \
	ARCH=$$(uname -m | sed 's/x86_64/x86_64/;s/arm64/arm64/'); \
	curl -sSL "https://github.com/kyverno/kyverno/releases/download/$(KYVERNO_VERSION)/kyverno-cli_$(KYVERNO_VERSION)_$${OS}_$${ARCH}.tar.gz" \
		| tar -xz -C /usr/local/bin kyverno && echo "kyverno $(KYVERNO_VERSION) installed"
	@OS=$$(uname -s | tr '[:upper:]' '[:lower:]'); \
	ARCH=$$(uname -m | sed 's/x86_64/amd64/;s/arm64/arm64/'); \
	curl -sSL "https://github.com/yannh/kubeconform/releases/download/$(KUBECONFORM_VERSION)/kubeconform-$${OS}-$${ARCH}.tar.gz" \
		| tar -xz -C /usr/local/bin kubeconform && echo "kubeconform $(KUBECONFORM_VERSION) installed"

## ── Help ─────────────────────────────────────────────────────────────────────

help: ## Show this help message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  %-20s %s\n", $$1, $$2}'
