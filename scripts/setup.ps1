# setup.ps1 — Full ArgoCD + kind demo setup (Windows PowerShell)
# Run from the repo root: .\scripts\setup.ps1

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Step($msg) {
    Write-Host "`n==> $msg" -ForegroundColor Cyan
}

# ─── 0. Prerequisites check ────────────────────────────────────────────────────
Write-Step "Checking prerequisites"

$missing = @()
foreach ($cmd in @("kind", "kubectl", "helm")) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        $missing += $cmd
    }
}
if ($missing.Count -gt 0) {
    Write-Host "Missing tools: $($missing -join ', ')" -ForegroundColor Red
    Write-Host "Install them with:"
    Write-Host "  winget install Kubernetes.kind"
    Write-Host "  winget install Kubernetes.kubectl"
    Write-Host "  winget install Helm.Helm"
    exit 1
}
Write-Host "All prerequisites found." -ForegroundColor Green

# ─── 1. Create kind cluster ─────────────────────────────────────────────────────
Write-Step "Creating kind cluster 'argocd-demo'"

$clusterExists = kind get clusters 2>&1 | Select-String "argocd-demo"
if ($clusterExists) {
    Write-Host "Cluster 'argocd-demo' already exists, skipping creation." -ForegroundColor Yellow
} else {
    kind create cluster --config kind-cluster/cluster-config.yaml
    Write-Host "Cluster created." -ForegroundColor Green
}

# ─── 2. Install ArgoCD ─────────────────────────────────────────────────────────
Write-Step "Installing ArgoCD"

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Some installs may miss this CRD due to annotation-size apply issues.
$appSetCrd = kubectl get crd applicationsets.argoproj.io --ignore-not-found
if (-not $appSetCrd) {
    Write-Host "applicationsets.argoproj.io CRD missing, creating it explicitly..." -ForegroundColor Yellow
    kubectl create -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/crds/applicationset-crd.yaml
    kubectl rollout restart deployment/argocd-applicationset-controller -n argocd
}

Write-Host "Waiting for ArgoCD pods to be ready (this takes ~2 minutes)..." -ForegroundColor Yellow
kubectl wait --for=condition=Available deployment/argocd-server -n argocd --timeout=300s

# ─── 3. Patch ArgoCD server to NodePort so we can reach it on localhost:30080 ──
Write-Step "Exposing ArgoCD server on NodePort 30080"

kubectl patch svc argocd-server -n argocd -p '{\"spec\":{\"type\":\"NodePort\",\"ports\":[{\"name\":\"https\",\"port\":443,\"protocol\":\"TCP\",\"targetPort\":8080,\"nodePort\":30080},{\"name\":\"http\",\"port\":80,\"protocol\":\"TCP\",\"targetPort\":8080,\"nodePort\":30082}]}}'

# ─── 4. Fetch the initial admin password ───────────────────────────────────────
Write-Step "Retrieving initial ArgoCD admin password"

$b64pass = kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}"
$password = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($b64pass))

Write-Host ""
Write-Host "╔══════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║  ArgoCD is ready!                            ║" -ForegroundColor Green
Write-Host "║  URL      : https://localhost:30080          ║" -ForegroundColor Green
Write-Host "║  Username : admin                            ║" -ForegroundColor Green
Write-Host "║  Password : $password" -ForegroundColor Green
Write-Host "╚══════════════════════════════════════════════╝" -ForegroundColor Green

# ─── 5. Apply the ArgoCD Application ──────────────────────────────────────────
Write-Step "Deploying guestbook Application via ArgoCD"

kubectl apply -f argocd/application.yaml

# ─── 6. Deploy Crossplane applications (optional but recommended for this lab) ─
Write-Step "Deploying Crossplane apps via ArgoCD"

kubectl apply -f argocd/crossplane-install-app.yaml
kubectl apply -f argocd/crossplane-gcp-free-resource-app.yaml

# If a local key exists, bootstrap gcp-creds so Crossplane can reconcile.
$credsFile = ".\your-service-account.json"
if (Test-Path $credsFile) {
    Write-Host "Found your-service-account.json, creating/updating gcp-creds secret..." -ForegroundColor Yellow
    kubectl create secret generic gcp-creds -n crossplane-system --from-file=creds.json=$credsFile --dry-run=client -o yaml | kubectl apply -f -
    kubectl annotate application crossplane-gcp-free-resource -n argocd argocd.argoproj.io/refresh=hard --overwrite
} else {
    Write-Host "No your-service-account.json found. Crossplane GCP app may stay Degraded until gcp-creds is created." -ForegroundColor Yellow
}

Write-Host "Current ArgoCD applications:" -ForegroundColor Cyan
kubectl get applications -n argocd

Write-Host ""
Write-Host "Application deployed. ArgoCD will sync the guestbook app automatically." -ForegroundColor Green
Write-Host "Open https://localhost:30080 and log in to watch the sync." -ForegroundColor Cyan
Write-Host "Guestbook app will be available at http://localhost:30081 once synced." -ForegroundColor Cyan
