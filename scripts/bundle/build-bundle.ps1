# build-bundle.ps1
# ─────────────────────────────────────────────────────────────────────────────
# Assembles the portable SchoolMove bundle: a copy of R (with the
# already-restored renv library), the repo's r/ + config.yaml + dummy example
# data, and the .bat launchers — everything Veerle needs, with no install
# step and no network access required at runtime.
#
# Assumes R has already been set up and renv::restore() has already run
# (e.g. via the setup-r-env composite action) before this script is called.
#
# Usage:
#   pwsh scripts/bundle/build-bundle.ps1 -RepoRoot <repo root> -OutputDir <assembly dir>
# ─────────────────────────────────────────────────────────────────────────────

param(
  [Parameter(Mandatory = $true)][string]$RepoRoot,
  [Parameter(Mandatory = $true)][string]$OutputDir
)

$ErrorActionPreference = "Stop"

if (Test-Path $OutputDir) {
  Remove-Item -Recurse -Force $OutputDir
}
New-Item -ItemType Directory -Path $OutputDir | Out-Null

# ── 1. Copy the just-restored R installation ────────────────────────────────
Write-Host "Locating R installation ..."
$rHomeLines = & Rscript -e "cat(normalizePath(R.home()))"
$rHome = ($rHomeLines | Select-Object -Last 1).Trim()
if (-not (Test-Path $rHome)) {
  throw "Could not locate R.home() at '$rHome'"
}
Write-Host "Copying R from $rHome ..."
$rDestPortable = Join-Path $OutputDir "R-portable"
New-Item -ItemType Directory -Path $rDestPortable | Out-Null
Copy-Item -Recurse -Force (Join-Path $rHome "*") $rDestPortable

# ── 2. Copy the repo code (r/), excluding local/throwaway artifacts ────────
# NOTE: Copy-Item -Recurse nests the source folder itself under the
# destination unless the destination already exists AND the source path ends
# in "/*" (copy contents, not the folder) — hence New-Item first, then "/*".
$rDest = Join-Path $OutputDir "r"
New-Item -ItemType Directory -Path $rDest | Out-Null
Write-Host "Copying r/ ..."
Copy-Item -Recurse -Force (Join-Path $RepoRoot "r/*") $rDest
foreach ($stale in @("renv/staging", "renv/sandbox", ".Rproj.user", ".Rhistory", ".RData")) {
  $p = Join-Path $rDest $stale
  if (Test-Path $p) { Remove-Item -Recurse -Force $p }
}

# ── 3. Config + dummy example data only — never real/GDPR data ─────────────
Copy-Item -Force (Join-Path $RepoRoot "config.yaml") (Join-Path $OutputDir "config.yaml")

$dataDest = Join-Path $OutputDir "data"
New-Item -ItemType Directory -Path (Join-Path $dataDest "example") -Force | Out-Null
Copy-Item -Recurse -Force (Join-Path $RepoRoot "data/example/*") (Join-Path $dataDest "example")

foreach ($m in @("meting_1", "meting_2")) {
  $rawDir = Join-Path $dataDest "raw/$m"
  New-Item -ItemType Directory -Path $rawDir -Force | Out-Null
  $readme = Join-Path $RepoRoot "data/raw/$m/README.txt"
  if (Test-Path $readme) {
    Copy-Item -Force $readme (Join-Path $rawDir "README.txt")
  }
}

# ── 4. Launchers ─────────────────────────────────────────────────────────────
$templates = Join-Path $RepoRoot "scripts/bundle/templates"
Copy-Item -Force (Join-Path $templates "1 - Pipeline uitvoeren.bat") $OutputDir
Copy-Item -Force (Join-Path $templates "2 - Dashboard starten.bat") $OutputDir
Copy-Item -Force (Join-Path $templates "LEES MIJ.txt") $OutputDir

Write-Host "Bundle assembled at $OutputDir"
