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

# Some installs may miss this CRD due to annotation-size apply issues.
if ! kubectl get crd applicationsets.argoproj.io >/dev/null 2>&1; then
    warn "applicationsets.argoproj.io CRD missing, creating it explicitly..."
    kubectl create -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/crds/applicationset-crd.yaml
    kubectl rollout restart deployment/argocd-applicationset-controller -n argocd
fi

warn "Waiting for ArgoCD pods to be ready (~2 minutes)..."
kubectl wait --for=condition=Available deployment/argocd-server -n argocd --timeout=300s

# ─── 3. Expose ArgoCD server via NodePort ────────────────────────────────────
step "Exposing ArgoCD server on NodePort 30080"
kubectl patch svc argocd-server -n argocd \
    -p '{"spec":{"type":"NodePort","ports":[{"name":"https","port":443,"protocol":"TCP","targetPort":8080,"nodePort":30080},{"name":"http","port":80,"protocol":"TCP","targetPort":8080,"nodePort":30082}]}}'

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

# ─── 6. Deploy Crossplane applications (optional but recommended for this lab)
step "Deploying Crossplane apps via ArgoCD"
kubectl apply -f argocd/crossplane-install-app.yaml
kubectl apply -f argocd/crossplane-gcp-free-resource-app.yaml

# If a local key exists, bootstrap gcp-creds so Crossplane can reconcile.
if [ -f "./your-service-account.json" ]; then
    warn "Found your-service-account.json, creating/updating gcp-creds secret..."
    kubectl create secret generic gcp-creds -n crossplane-system --from-file=creds.json=./your-service-account.json --dry-run=client -o yaml | kubectl apply -f -
    kubectl annotate application crossplane-gcp-free-resource -n argocd argocd.argoproj.io/refresh=hard --overwrite
else
    warn "No your-service-account.json found. Crossplane GCP app may stay Degraded until gcp-creds is created."
fi

echo ""
echo "Current ArgoCD applications:"
kubectl get applications -n argocd

echo ""
ok "Done! ArgoCD will auto-sync the guestbook app."
echo "  UI  → https://localhost:30080  (accept self-signed cert)"
echo "  App → http://localhost:30081   (once synced)"
