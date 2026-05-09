param(
  [string]$BaseUrl = "https://scmdb.net",
  [string]$OutputPath = "api/SCMDBSnapshot/scmdb-fabricator-snapshot.json"
)

$ErrorActionPreference = "Stop"

function Get-Json($Url) {
  Invoke-RestMethod -Method Get -Uri $Url
}

$normalizedBase = $BaseUrl.TrimEnd("/")
$versions = Get-Json "$normalizedBase/data/versions.json"
if (-not $versions -or $versions.Count -eq 0) {
  throw "SCMDB versions.json lieferte keine Versionen."
}

$selectedVersion = $versions[0]
$version = $selectedVersion.version
Write-Host "Nutze SCMDB-Version $version"

$craftingBlueprints = Get-Json "$normalizedBase/data/crafting_blueprints-$version.json"
$craftingItems = Get-Json "$normalizedBase/data/crafting_items-$version.json"

$targetDir = Split-Path -Parent $OutputPath
if ($targetDir -and !(Test-Path $targetDir)) {
  New-Item -ItemType Directory -Path $targetDir | Out-Null
}

$snapshot = [ordered]@{
  sourceBaseURL = $normalizedBase
  version = $version
  fetchedAt = [DateTime]::UtcNow.ToString("o")
  craftingBlueprints = $craftingBlueprints
  craftingItems = $craftingItems
}

$snapshot | ConvertTo-Json -Depth 100 | Set-Content -Path $OutputPath -Encoding UTF8
Write-Host "SCMDB-Snapshot geschrieben nach $OutputPath"
