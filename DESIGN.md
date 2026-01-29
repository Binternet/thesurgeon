# GitOps & Multi-Cluster Deployment — Design Document

## 1. Overview

This document outlines the design for a GitOps-based deployment system that supports deploying a microservice across multiple Kubernetes clusters (Staging, Production EU, Production US) using **ArgoCD**, **Helm**, and **GitHub Actions**. The goal is to treat Git as the single source of truth: desired state lives in Git, and ArgoCD continuously reconciles cluster state against it.

---

## 2. Architecture

### 2.1 High-Level Flow

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐     ┌─────────────────┐
│   Developer │────▶│ GitHub Repo  │────▶│   ArgoCD    │────▶│ K8s Clusters    │
│   (PR/Main) │     │ (Manifests,  │     │ (Reconcile) │     │ stg / prd-eu /  │
└─────────────┘     │  Helm, App)  │     └─────────────┘     │ prd-us          │
                    └──────────────┘            │            └─────────────────┘
                           ▲                    │
                           │                    │  pull
                    ┌──────┴──────┐             │
                    │ GitHub      │             │
                    │ Actions CI  │─────────────┘
                    │ (build &    │   (optional: update
                    │  push img)  │    image tag in Git)
                    └─────────────┘
```

- **Git** holds: application source, Dockerfile, Helm chart, ArgoCD `Application` manifests, and environment-specific values.
- **CI (GitHub Actions)** builds the container image and pushes it to a registry (e.g. GHCR). Optionally, it can update the image tag in the Helm values and commit back (or use Argo CD Image Updater).
- **ArgoCD** watches the Git repo (and optionally the container registry), compares desired vs. live state, and applies changes to each target cluster.

### 2.2 Git Repository Layout (Recommended)

```
repo/
├── app/                    # Application source & Dockerfile
├── charts/
│   └── hcomp-app/           # Helm chart
│       ├── Chart.yaml
│       ├── values.yaml     # Defaults
│       └── values-*.yaml   # Per-environment overrides (optional)
├── argocd/
│   ├── applications/       # ArgoCD Application manifests
│   │   ├── stg.yaml
│   │   ├── prd-eu.yaml
│   │   └── prd-us.yaml
│   └── projects/           # ArgoCD AppProjects (optional)
├── .github/workflows/      # CI pipeline
├── DESIGN.md
└── README.md
```

- **Single repo** for app + Helm + ArgoCD keeps the POC simple. In production, you might split into app repo, config repo, and chart repo.
- **Helm** templates the Kubernetes manifests; **ArgoCD** points each `Application` at the chart path and injects environment-specific values.

### 2.3 Multi-Cluster Topology

| Environment | Cluster       | Purpose                |
|------------|---------------|------------------------|
| Staging    | `stg-cluster` | Development & testing  |
| Prod EU    | `prd-eu-cluster` | EU production      |
| Prod US    | `prd-us-cluster` | US production      |

**Options for ArgoCD:**

1. **Centralised ArgoCD**: One ArgoCD instance (e.g. in a dedicated admin cluster or in `stg-cluster`) managing all three clusters. Each cluster is registered via `argocd cluster add`. Applications target different clusters via `destination.name` or `destination.server`.
2. **Hub-and-spoke**: One “hub” cluster runs ArgoCD; other clusters are spokes. Same idea as above, with clear network/rbac boundaries.
3. **Argo CD ApplicationSet**: Use an `ApplicationSet` controller to generate `Application` resources per cluster from a template (cluster generator or list), reducing duplication.

For the POC we use a **single cluster** (Minikube) and one ArgoCD `Application`. The design naturally extends to multiple clusters by adding more `Application` manifests (or an ApplicationSet) that point to the same Helm chart with different `destination` and values.

---

## 3. Configuration Management Across Environments

### 3.1 Strategy

- **Helm values** drive environment-specific config: image tag, replicas, resources, env vars, ingress, etc.
- **Options**:
  - **A. Value files per env**: `values-stg.yaml`, `values-prd-eu.yaml`, `values-prd-us.yaml` in the chart or a config directory. Each ArgoCD `Application` references the appropriate `valueFiles` and `destination`.
  - **B. valuesObject in Application**: Environment-specific overrides live directly in the `Application` manifest. Good for small diffs; less so for large config.
  - **C. Layered approach**: `values.yaml` (defaults) + `values-<env>.yaml` (overrides). ArgoCD uses `valueFiles: [values.yaml, values-stg.yaml]` for staging, etc.

We use **layered value files** (C) for clarity and reuse.

### 3.2 What Varies Per Environment

- **Image tag**: e.g. `latest` or `sha-abc123` in staging; explicit tags in production.
- **Replicas**: e.g. 1 in staging, 2+ in production.
- **Resources**: Staging can be minimal; production sized appropriately.
- **Environment variables**: Feature flags, API endpoints, log levels.
- **Ingress / DNS**: Different hosts or TLS per env.

All of this is represented in values and optionally in a small set of env-specific value files.

### 3.3 Secrets

- **Avoid storing secrets in Git.** Use external secret management (e.g. Sealed Secrets, External Secrets Operator, Vault) and inject them into the cluster. The Helm chart expects a secret (e.g. name override) or env from a secret; ArgoCD deploys the chart, secrets come from the operator.
- For the **POC**, we use non-sensitive config only (no real secrets).

---

## 4. Deployment Flow: Development → Production

### 4.1 Stages

1. **Develop**: Feature branch, local or CI tests. No deployment yet.
2. **Build**: On merge to `main` (or on tag), GitHub Actions builds the image, tags it (e.g. `git sha`, `semver`), and pushes to the registry.
3. **Staging**: ArgoCD deploys from `main` (or a `staging` branch) to `stg-cluster` using `values-stg.yaml`. Optionally, CI updates the image tag in the staging values and commits, or Argo CD Image Updater does it. ArgoCD syncs and deploys.
4. **Production**: After validation in staging, promote the same **immutable image tag** to production:
   - **Option A (manual)**: Update `values-prd-eu.yaml` and `values-prd-us.yaml` (or the corresponding ArgoCD `valuesObject`) with the new tag, commit, PR, merge. ArgoCD syncs to each prod cluster.
   - **Option B (automated)**: Promotion pipeline (e.g. GitHub Actions) updates prod value files and opens a PR; humans approve and merge.
   - **Option C**: Use Argo CD Image Updater or similar to update prod when a new tag is promoted.

We favour **Option A** for the POC: explicit, auditable changes in Git.

### 4.2 GitOps Principles Applied

- **Declarative**: All desired state (Helm values, Application specs) in Git.
- **Versioned / immutable**: Git history tracks who changed what and when; container images are tagged immutably.
- **Pulled automatically**: ArgoCD pulls from Git (and optionally registry) and reconciles; no ad-hoc `kubectl apply` from laptops.
- **Continuously reconciled**: ArgoCD periodically compares Git vs cluster and corrects drift.

---

## 5. POC Scope vs. Production Extensions

### 5.1 In Scope for POC

- Single cluster (Minikube), one ArgoCD `Application`.
- Simple app with a `/version` (and optionally `/health`) endpoint.
- CI builds and pushes the image; Helm chart deploys it; ArgoCD syncs from Git.
- README with local setup and validation steps.

### 5.2 Future Extensions

- **Multi-cluster**: Additional `Application` manifests (or ApplicationSet) for `stg-cluster`, `prd-eu-cluster`, `prd-us-cluster`.
- **Image updater**: Automate image tag updates in Git (e.g. Argo CD Image Updater) for staging or canary.
- **App-of-Apps**: Root `Application` that points to a directory of child `Application` manifests for multi-service or multi-cluster.
- **Secrets**: Integrate External Secrets / Sealed Secrets and wire them into the chart.
- **Promotion pipelines**: Automated PRs to update prod values with promoted image tags.
- **Observability**: Dashboards and alerts on sync status, rollout status, and app metrics.

---

## 6. Summary

| Aspect | Choice |
|--------|--------|
| **Source of truth** | Git (app, Helm, ArgoCD config) |
| **Templating** | Helm |
| **CD** | ArgoCD |
| **CI** | GitHub Actions (build & push image) |
| **Config per env** | Layered Helm value files |
| **Clusters** | POC: single (Minikube); design supports stg, prd-eu, prd-us |

This design keeps the POC minimal while remaining consistent with GitOps practices and scalable to multi-cluster, multi-environment production deployments.
