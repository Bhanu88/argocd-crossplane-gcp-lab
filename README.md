# ArgoCD with kind — Learning Project

A hands-on project for learning [ArgoCD](https://argo-cd.readthedocs.io/) using a local [kind](https://kind.sigs.k8s.io/) (Kubernetes IN Docker) cluster.

---

## Project Structure

```
argoCD/
├── kind-cluster/
│   └── cluster-config.yaml     ← kind cluster definition (ports exposed)
├── sample-app/
│   ├── namespace.yaml           ← Namespace: guestbook
│   ├── deployment.yaml          ← Deployment: guestbook-ui (2 replicas)
│   ├── service.yaml             ← NodePort Service on port 30081
│   └── kustomization.yaml       ← Kustomize entrypoint
├── argocd/
│   ├── application.yaml         ← ArgoCD Application CR (the core object)
│   └── project.yaml             ← ArgoCD AppProject CR (RBAC/scope)
└── scripts/
    ├── setup.ps1                ← Windows one-shot setup script
    ├── setup.sh                 ← Linux/macOS/WSL one-shot setup script
    └── teardown.ps1             ← Delete the cluster
```

---

## Prerequisites

| Tool | Install |
|------|---------|
| Docker Desktop | https://www.docker.com/products/docker-desktop/ |
| kind | `winget install Kubernetes.kind` |
| kubectl | `winget install Kubernetes.kubectl` |
| helm *(optional)* | `winget install Helm.Helm` |

> On Linux/macOS use your package manager or the official install scripts linked above.

---

## Quick Start (Windows)

```powershell
# from repo root
.\scripts\setup.ps1
```

That single script will:
1. Create a kind cluster named **argocd-demo**
2. Install ArgoCD into the `argocd` namespace
3. Patch the ArgoCD server to be reachable on **https://localhost:30080**
4. Print the initial **admin password**
5. Apply the `argocd/application.yaml` so ArgoCD immediately starts syncing the guestbook app

---

## Step-by-Step (manual — great for learning)

### 1 — Create the kind cluster

```powershell
kind create cluster --config kind-cluster\cluster-config.yaml
kubectl cluster-info --context kind-argocd-demo
```

### 2 — Install ArgoCD

```powershell
kubectl create namespace argocd
kubectl apply -n argocd `
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait until the server pod is Running
kubectl get pods -n argocd -w
```

### 3 — Expose the ArgoCD UI

The kind cluster config already maps container port **30080 → localhost:30080**.  
Patch the service to use a NodePort:

```powershell
kubectl patch svc argocd-server -n argocd `
  -p '{"spec":{"type":"NodePort","ports":[{"port":443,"targetPort":8080,"nodePort":30080}]}}'
```

### 4 — Get the admin password

```powershell
$b64 = kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}"
[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($b64))
```

Open **https://localhost:30080** → username `admin` → paste the password.

> The browser will warn about a self-signed certificate — click **Advanced → Proceed**.

### 5 — Deploy the guestbook app via ArgoCD

```powershell
kubectl apply -f argocd\application.yaml
```

Go back to the ArgoCD UI. You will see the **guestbook** application appear and transition through:

```
Missing → OutOfSync → Syncing → Synced (Healthy)
```

The guestbook UI will be available at **http://localhost:30081**.

---

## Key ArgoCD Concepts Demonstrated

| Concept | Where |
|---------|-------|
| **Application** CR | `argocd/application.yaml` |
| **AppProject** CR (scoping/RBAC) | `argocd/project.yaml` |
| **Automated sync** (`automated.prune`, `selfHeal`) | `argocd/application.yaml` → `syncPolicy` |
| **Declarative setup** (no UI clicks needed) | `kubectl apply -f argocd/application.yaml` |
| **GitOps loop** (Git is the source of truth) | Any change to `sample-app/` is auto-applied |

---

## Experimenting with GitOps

1. **Push `sample-app/` to your own GitHub repo**
2. Update `argocd/application.yaml` → `spec.source.repoURL` and `path` to point at it
3. `kubectl apply -f argocd/application.yaml`
4. Now edit `sample-app/deployment.yaml` (e.g. change `replicas: 2` → `replicas: 3`), commit & push
5. Watch ArgoCD detect the drift and auto-sync within ~3 minutes (or click **Sync** in the UI)

---

## Useful Commands

```powershell
# Watch ArgoCD application status
kubectl get application -n argocd -w

# Describe an app for events/errors
kubectl describe application guestbook -n argocd

# Force a manual sync
kubectl patch application guestbook -n argocd \
  --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{}}}'

# Get all ArgoCD resources
kubectl get all -n argocd

# Delete a specific app (respects the finalizer — cleans up deployed resources too)
kubectl delete application guestbook -n argocd

# Tear down everything
.\scripts\teardown.ps1
```

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────┐
│  Your Machine                                           │
│                                                         │
│  Git Repo (GitHub)                                      │
│  └── sample-app/  ◄──────────────────────┐             │
│                                           │ poll / webhook
│  ┌──────────────────────────────────────┐ │             │
│  │  kind cluster (Docker)               │ │             │
│  │                                      │ │             │
│  │  argocd namespace                    │ │             │
│  │  └── argocd-server ──────────────────┘ │             │
│  │      (syncs manifests from Git)        │             │
│  │                                        │             │
│  │  guestbook namespace                   │             │
│  │  └── Deployment: guestbook-ui (2 pods) │             │
│  │  └── Service: NodePort 30081           │             │
│  └────────────────────────────────────────┘             │
│                                                         │
│  localhost:30080 → ArgoCD UI                            │
│  localhost:30081 → Guestbook App                        │
└─────────────────────────────────────────────────────────┘
```
