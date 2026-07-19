param(
  [string]$BaseUrl = "https://scmdb.net",
  [string]$OutputPath = "api/SCMDBSnapshot/scmdb-fabricator-snapshot.json"
)

$ErrorActionPreference = "Stop"

function Get-Json($Url) {
  $tempFile = [System.IO.Path]::GetTempFileName()
  try {
    & curl.exe --fail --silent --show-error --location --retry 3 --retry-all-errors --connect-timeout 20 --max-time 180 -H "Accept: application/json" -A "QuestBoard-SCMDB-Fetch/1.0" $Url -o $tempFile
    if ($LASTEXITCODE -ne 0) {
      throw "curl fehlgeschlagen fuer $Url"
    }

    $raw = Get-Content -Path $tempFile -Raw -Encoding UTF8
    return $raw | ConvertFrom-Json
  }
  finally {
    Remove-Item -Path $tempFile -ErrorAction SilentlyContinue
  }
}

$normalizedBase = $BaseUrl.TrimEnd("/")
$versions = Get-Json "$normalizedBase/data/versions.json"
if (-not $versions -or $versions.Count -eq 0) {
  throw "SCMDB versions.json lieferte keine Versionen."
}

$selectedVersion = $versions[0]
$version = $selectedVersion.version
if (-not $version) {
  throw "SCMDB versions.json enthaelt keine gueltige Version."
}
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