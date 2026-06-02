# teardown.ps1 — Delete the kind cluster and clean up
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "`n==> Deleting kind cluster 'argocd-demo'" -ForegroundColor Cyan
kind delete cluster --name argocd-demo
Write-Host "Cluster deleted." -ForegroundColor Green
