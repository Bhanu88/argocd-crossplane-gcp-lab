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

Write-Host "Waiting for ArgoCD pods to be ready (this takes ~2 minutes)..." -ForegroundColor Yellow
kubectl wait --for=condition=Available deployment/argocd-server -n argocd --timeout=300s

# ─── 3. Patch ArgoCD server to NodePort so we can reach it on localhost:30080 ──
Write-Step "Exposing ArgoCD server on NodePort 30080"

kubectl patch svc argocd-server -n argocd -p '{\"spec\":{\"type\":\"NodePort\",\"ports\":[{\"port\":443,\"targetPort\":8080,\"nodePort\":30080}]}}'

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

Write-Host ""
Write-Host "Application deployed. ArgoCD will sync the guestbook app automatically." -ForegroundColor Green
Write-Host "Open https://localhost:30080 and log in to watch the sync." -ForegroundColor Cyan
Write-Host "Guestbook app will be available at http://localhost:30081 once synced." -ForegroundColor Cyan
