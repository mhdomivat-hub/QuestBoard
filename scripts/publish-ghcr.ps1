param(
  [string]$Tag = "",
  [string]$Namespace = "mhdomivat-hub",
  [string]$Username = "mhdomivat-hub",
  [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"

if (-not $Tag) {
  $Tag = Get-Date -Format "yyyyMMdd-HHmmss"
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$apiImage = "ghcr.io/$Namespace/questboard-api:$Tag"
$webImage = "ghcr.io/$Namespace/questboard-web:$Tag"

Write-Host "Publishing QuestBoard images to GHCR"
Write-Host "  Namespace: $Namespace"
Write-Host "  Tag:       $Tag"
Write-Host "  API:       $apiImage"
Write-Host "  Web:       $webImage"

$token = $env:GHCR_TOKEN
if (-not $token) {
  throw "GHCR_TOKEN is not set. Create a GitHub token with write:packages and set it in the current shell."
}

$token | docker login ghcr.io -u $Username --password-stdin | Out-Host

if (-not $SkipBuild) {
  docker build -t $apiImage "$repoRoot\api"
  docker build -t $webImage "$repoRoot\web"
}

docker push $apiImage
docker push $webImage

Write-Host ""
Write-Host "Done."
Write-Host "Server deploy example:"
Write-Host "  GHCR_NAMESPACE=$Namespace GHCR_IMAGE_TAG=$Tag docker compose -f docker-compose.ghcr.yml pull"
Write-Host "  GHCR_NAMESPACE=$Namespace GHCR_IMAGE_TAG=$Tag docker compose -f docker-compose.ghcr.yml up -d"
