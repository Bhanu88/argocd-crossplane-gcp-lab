#!/usr/bin/env bash
# setup.sh — Full ArgoCD + kind demo setup (Linux / macOS / WSL)
# Usage: bash scripts/setup.sh

set -euo pipefail

step() { echo -e "\n\033[36m==> $*\033[0m"; }
ok()   { echo -e "\033[32m$*\033[0m"; }
warn() { echo -e "\033[33m$*\033[0m"; }
err()  { echo -e "\033[31m$*\033[0m"; }

# ─── 0. Prerequisites check ──────────────────────────────────────────────────
step "Checking prerequisites"
missing=()
for cmd in kind kubectl helm; do
    command -v "$cmd" &>/dev/null || missing+=("$cmd")
done
if [ ${#missing[@]} -gt 0 ]; then
    err "Missing tools: ${missing[*]}"
    echo "Install guides:"
    echo "  kind   → https://kind.sigs.k8s.io/docs/user/quick-start/#installation"
    echo "  kubectl→ https://kubernetes.io/docs/tasks/tools/"
    echo "  helm   → https://helm.sh/docs/intro/install/"
    exit 1
fi
ok "All prerequisites found."

# ─── 1. Create kind cluster ──────────────────────────────────────────────────
step "Creating kind cluster 'argocd-demo'"
if kind get clusters 2>/dev/null | grep -q "argocd-demo"; then
    warn "Cluster 'argocd-demo' already exists, skipping."
else
    kind create cluster --config kind-cluster/cluster-config.yaml
    ok "Cluster created."
fi

# ─── 2. Install ArgoCD ───────────────────────────────────────────────────────
step "Installing ArgoCD"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

warn "Waiting for ArgoCD pods to be ready (~2 minutes)..."
kubectl wait --for=condition=Available deployment/argocd-server -n argocd --timeout=300s

# ─── 3. Expose ArgoCD server via NodePort ────────────────────────────────────
step "Exposing ArgoCD server on NodePort 30080"
kubectl patch svc argocd-server -n argocd \
    -p '{"spec":{"type":"NodePort","ports":[{"port":443,"targetPort":8080,"nodePort":30080}]}}'

# ─── 4. Get admin password ───────────────────────────────────────────────────
step "Retrieving initial ArgoCD admin password"
PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" | base64 -d)

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║  ArgoCD is ready!                            ║"
echo "║  URL      : https://localhost:30080          ║"
echo "║  Username : admin                            ║"
echo "║  Password : ${PASSWORD}"
echo "╚══════════════════════════════════════════════╝"

# ─── 5. Deploy the guestbook Application ─────────────────────────────────────
step "Deploying guestbook Application via ArgoCD"
kubectl apply -f argocd/application.yaml

echo ""
ok "Done! ArgoCD will auto-sync the guestbook app."
echo "  UI  → https://localhost:30080  (accept self-signed cert)"
echo "  App → http://localhost:30081   (once synced)"
