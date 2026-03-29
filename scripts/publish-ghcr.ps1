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
$apiLatestImage = "ghcr.io/$Namespace/questboard-api:latest"
$webLatestImage = "ghcr.io/$Namespace/questboard-web:latest"

Write-Host "Publishing QuestBoard images to GHCR"
Write-Host "  Namespace: $Namespace"
Write-Host "  Tag:       $Tag"
Write-Host "  API:       $apiImage"
Write-Host "  Web:       $webImage"
Write-Host "  API latest: $apiLatestImage"
Write-Host "  Web latest: $webLatestImage"

$token = $env:GHCR_TOKEN
if (-not $token) {
  throw "GHCR_TOKEN is not set. Create a GitHub token with write:packages and set it in the current shell."
}

$token | docker login ghcr.io -u $Username --password-stdin | Out-Host

if (-not $SkipBuild) {
  docker build -t $apiImage "$repoRoot\api"
  docker build -t $webImage "$repoRoot\web"
}

if ($Tag -ne "latest") {
  docker tag $apiImage $apiLatestImage
  docker tag $webImage $webLatestImage
}

docker push $apiImage
docker push $webImage

if ($Tag -ne "latest") {
  docker push $apiLatestImage
  docker push $webLatestImage
}

Write-Host ""
Write-Host "Done."
Write-Host "Server deploy example:"
Write-Host "  GHCR_NAMESPACE=$Namespace GHCR_IMAGE_TAG=$Tag docker compose -f docker-compose.ghcr.yml pull"
Write-Host "  GHCR_NAMESPACE=$Namespace GHCR_IMAGE_TAG=$Tag docker compose -f docker-compose.ghcr.yml up -d"
if ($Tag -ne "latest") {
  Write-Host ""
  Write-Host "Default deploy script compatibility:"
  Write-Host "  'latest' was updated as well, so deploy-ghcr.sh without GHCR_IMAGE_TAG will pick up this build."
}
