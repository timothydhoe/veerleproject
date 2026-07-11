# smoke_test_shiny.ps1
# ─────────────────────────────────────────────────────────────────────────────
# Launches the Shiny dashboard in the background, polls it for a healthy HTTP
# response, then tears it down. Exits non-zero if it never responds within
# the timeout. Reused by both windows-verify.yml (against the CI checkout's
# ambient R) and build-windows-bundle.yml (against the bundled R.exe, to
# actually test what Veerle will run).
#
# Usage:
#   pwsh scripts/ci/smoke_test_shiny.ps1 -RDir <path to r/> `
#     [-RscriptPath <path to Rscript.exe>] [-Port 7488] [-TimeoutSeconds 90]
# ─────────────────────────────────────────────────────────────────────────────

param(
  [Parameter(Mandatory = $true)][string]$RDir,
  [string]$RscriptPath = "Rscript",
  [int]$Port = 7488,
  [int]$TimeoutSeconds = 90
)

$tempDir = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [System.IO.Path]::GetTempPath() }
$logOut  = Join-Path $tempDir "shiny_stdout.log"
$logErr  = Join-Path $tempDir "shiny_stderr.log"

Write-Host "Launching Shiny from $RDir on port $Port using $RscriptPath ..."

$proc = Start-Process -FilePath $RscriptPath `
  -ArgumentList "-e", "shiny::runApp('shiny', port=$Port, launch.browser=FALSE, host='127.0.0.1')" `
  -WorkingDirectory $RDir `
  -PassThru -RedirectStandardOutput $logOut -RedirectStandardError $logErr

try {
  $elapsed = 0
  $ok = $false
  while ($elapsed -lt $TimeoutSeconds) {
    Start-Sleep -Seconds 5
    $elapsed += 5
    try {
      $response = Invoke-WebRequest -Uri "http://127.0.0.1:$Port" -UseBasicParsing -TimeoutSec 5
      if ($response.StatusCode -eq 200) { $ok = $true; break }
    } catch {
      # Not up yet, or still starting (package loading / data loading) — keep polling.
    }
  }

  if (-not $ok) {
    Write-Host "::error::Shiny dashboard did not respond with HTTP 200 within $TimeoutSeconds seconds"
    Write-Host "--- stdout ---"
    Get-Content $logOut -ErrorAction SilentlyContinue
    Write-Host "--- stderr ---"
    Get-Content $logErr -ErrorAction SilentlyContinue
    exit 1
  }

  Write-Host "OK: Shiny dashboard responded with HTTP 200 after $elapsed seconds"
} finally {
  if ($proc -and -not $proc.HasExited) {
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
  }
}
