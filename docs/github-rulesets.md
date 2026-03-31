# GitHub Rulesets

This repository uses one GitHub Ruleset to protect `main`.
Rulesets are configured via the GitHub API and documented here for auditability.

## main-branch-protection

**Target:** `refs/heads/main`
**Enforcement:** Active

| Rule | Setting |
| --- | --- |
| Block deletion | Enabled |
| Block force pushes | Enabled (non-fast-forward) |
| Require linear history | Enabled — squash or rebase only, no merge commits |
| Require pull request | 1 required approving review; stale reviews dismissed on push |
| Require status checks | All 5 checks must pass; branch must be up to date |

### Required Status Checks

All of the following must be green before a PR can merge:

| Check | Workflow | What it validates |
| --- | --- | --- |
| `YAML Lint` | `validate.yaml` | yamllint style check |
| `Schema Validation (dev)` | `validate.yaml` | kubeconform K8s 1.32 schema — dev overlay |
| `Schema Validation (prod)` | `validate.yaml` | kubeconform K8s 1.32 schema — prod overlay |
| `Kyverno Policy Tests` | `validate.yaml` | kyverno CLI policy test suite |
| `MegaLinter` | `mega-linter.yml` | actionlint, gitleaks, trufflehog, trivy, cspell, yamllint, markdownlint |

### Why These Rules

- **Linear history** keeps `git log` readable and makes bisect/revert straightforward
- **Status checks + up-to-date branch** prevents a situation where a PR passes CI on a
  stale base but the merged result would fail
- **Stale review dismissal** ensures a fresh approval after any post-review push

## Bypass Actors

Repository **Admins** can bypass the ruleset (`bypass_mode: always`). This allows
emergency hotfixes to land without waiting for CI when necessary.

All other users — including maintainers — are subject to the full ruleset.

## Re-applying Rulesets

If rulesets need to be recreated (e.g. after a repo transfer), use the GitHub API:

```shell
# List current rulesets
gh api repos/fearfactor3/nginx-kustomize-example/rulesets

# View ruleset detail
gh api repos/fearfactor3/nginx-kustomize-example/rulesets/<id>
```

The ruleset configuration is captured in this document. Recreate via the GitHub UI
or API using the settings above.
