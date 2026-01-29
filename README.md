# Hcomp — GitOps POC

Minimal app that returns a random phrase and version (/, /version, /health), plus Helm chart and ArgoCD config for GitOps-style deployment.

## Prerequisites

- **Docker** (for building the image)
- **Minikube** (+ kubectl): [install](https://minikube.sigs.k8s.io/docs/start/)
- **Helm 3**: [install](https://helm.sh/docs/intro/install/)
- **Node.js 18+** (optional; only for running the app without Docker/K8s)

---

## Option 1: Run the app locally (no Docker/K8s)

```bash
cd app
npm install   # optional, no deps
VERSION=0.1.0-local node server.js
```

Then open http://localhost:8080 or http://localhost:8080/version.

---

## Option 2: Deploy to Minikube with Helm (quickest K8s run)

This gets the app running on Kubernetes **without** ArgoCD. Good for a quick local deploy.

```bash
# 1. Start Minikube
minikube start

# 2. Build the image and load it into Minikube
docker build -t hcomp-app:latest .
minikube image load hcomp-app:latest

# 3. Install the chart (defaults + values-local)
helm upgrade --install hcomp-app ./charts/hcomp-app \
  -f charts/hcomp-app/values.yaml \
  -f charts/hcomp-app/values-local.yaml \
  -n hcomp-app \
  --create-namespace

# 4. Port-forward to access the app
kubectl port-forward -n hcomp-app svc/hcomp-app 8080:80
```

Open http://localhost:8080 or http://localhost:8080/version. You should see `{"message":"…","version":"0.1.0-local"}` (message is a random phrase: "I Love Sabich", "Kama Lasim Bapita?", or "Ein al falafel").

---

## Option 3: Full GitOps flow with ArgoCD (Minikube)

This uses ArgoCD to sync from Git and deploy the Helm chart. The app still runs in Minikube.

### 3.1 One-time setup

```bash
minikube start
minikube addons enable ingress   # optional

# Install ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ArgoCD to be ready
kubectl wait -n argocd --for=condition=Available deployment/argocd-server --timeout=120s
kubectl wait -n argocd --for=condition=Available deployment/argocd-applicationset-controller --timeout=120s
```

### 3.2 Build and load the image

```bash
docker build -t hcomp-app:latest .
minikube image load hcomp-app:latest
```

### 3.3 Point ArgoCD at your repo and deploy

1. **Push this repo to GitHub** (if you haven’t already).

2. **Use the local ArgoCD Application**  
   Edit `argocd/applications/hcomp-app-local.yaml` and set `repoURL` to your repo, e.g.:
   ```yaml
   repoURL: https://github.com/Binternet/thesurgeon.git
   ```

3. **Apply the Application**
   ```bash
   kubectl apply -f argocd/applications/hcomp-app-local.yaml
   ```
   To use the **staging** Application (`hcomp-app-staging`) instead, create the `staging` branch first (`./scripts/ensure-staging-branch.sh`), then `kubectl apply -f argocd/applications/hcomp-app-staging.yaml`.

4. **Sync**  
   ArgoCD will create the `hcomp-app` namespace and deploy the chart with `values-local.yaml`.  
   If sync doesn’t start automatically:
   ```bash
   argocd app sync hcomp-app-local
   ```
   (Install the [ArgoCD CLI](https://argo-cd.readthedocs.io/en/stable/cli_installation/) if you use this.)

5. **Access the app**
   ```bash
   kubectl port-forward -n hcomp-app svc/hcomp-app 8080:80
   ```
   Then open http://localhost:8080 or http://localhost:8080/version.

### 3.4 ArgoCD UI (optional)

```bash
kubectl port-forward -n argocd svc/argocd-server 8443:443
```

- URL: https://localhost:8443  
- Login: user `admin`, password from:
  ```bash
  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d && echo
  ```

---

## CI (GitHub Actions)

On push to `main`, the workflow in `.github/workflows/ci.yaml` builds the image and pushes it to **GitHub Container Registry** as `ghcr.io/<owner>/hcomp-app` (tags: `latest`, git SHA).

To use that image instead of a local one, point your Helm values (or ArgoCD `valueFiles`) at that image and tag.

---

## Layout

```
├── app/                 # Node app (/, /version, /health)
├── charts/hcomp-app/     # Helm chart
│   ├── values.yaml      # defaults
│   ├── values-local.yaml
│   ├── values-stg.yaml
│   ├── values-prd-eu.yaml
│   └── values-prd-us.yaml
├── argocd/applications/ # ArgoCD Application manifests
├── scripts/             # ensure-staging-branch.sh, etc.
├── .github/workflows/   # CI (build & push image)
├── DESIGN.md
└── README.md
```

---

## Branch-per-environment

All ArgoCD Applications use the **same repo** (`repoURL`) but different **branches** via `targetRevision`:

| Application | Branch | Value files |
|-------------|--------|-------------|
| `hcomp-app-local` | `main` | values-local |
| `hcomp-app-staging` | `staging` | values-stg |
| `hcomp-app-prd-eu` | `main` | values-prd-eu |
| `hcomp-app-prd-us` | `main` | values-prd-us |

Staging tracks `staging`; local and production track `main`. Use tags (e.g. `v1.2.3`) or other branch names if you prefer.

**Staging branch:** The staging Application (`hcomp-app-staging`) watches the `staging` branch and uses `values-stg.yaml`. Create and push it so ArgoCD has something to watch:

```bash
./scripts/ensure-staging-branch.sh
```

That creates `staging` from your current branch (including `charts/hcomp-app` and `values-stg.yaml`) and pushes it. Ensure `staging` exists and contains the chart before applying the staging Application.

---

## Summary

| Goal | Use |
|------|-----|
| Run app on your machine only | Option 1 (Node) |
| Run on Minikube quickly, no GitOps | Option 2 (Helm) |
| Run on Minikube with GitOps (ArgoCD) | Option 3 (ArgoCD + Helm) |
