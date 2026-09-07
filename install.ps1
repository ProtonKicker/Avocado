param(
  [string]$Repo = $env:AVOCADO_REPO,
  [string]$Ref = $env:AVOCADO_REF
)

$ErrorActionPreference = "Stop"

if (-not $Repo) { $Repo = "ProtonKicker/Avocado" }
if (-not $Ref) { $Ref = "main" }

$zipUrl = "https://github.com/$Repo/archive/refs/heads/$Ref.zip"

$usePyLauncher = $null -ne (Get-Command py -ErrorAction SilentlyContinue)
$usePython = $null -ne (Get-Command python -ErrorAction SilentlyContinue)

if (-not $usePyLauncher -and -not $usePython) {
  Write-Host "error: Python not found (need Python 3.10+)"
  exit 1
}

if ($usePyLauncher) {
  & py -3 -c "import sys; raise SystemExit(0 if sys.version_info >= (3,10) else 1)" | Out-Null
  & py -3 -m pip install --user -U pip | Out-Null
  & py -3 -m pip install --user -U pipx | Out-Null
  Write-Host "installing avocado from: $zipUrl"
  & py -3 -m pipx install --force $zipUrl
  & py -3 -m pipx ensurepath | Out-Null
} else {
  & python -c "import sys; raise SystemExit(0 if sys.version_info >= (3,10) else 1)" | Out-Null
  & python -m pip install --user -U pip | Out-Null
  & python -m pip install --user -U pipx | Out-Null
  Write-Host "installing avocado from: $zipUrl"
  & python -m pipx install --force $zipUrl
  & python -m pipx ensurepath | Out-Null
}

if (Get-Command avocado -ErrorAction SilentlyContinue) {
  avocado --help | Out-Null
  Write-Host "ok: avocado is installed"
  exit 0
}

Write-Host "installed, but 'avocado' is not on PATH in this shell"
Write-Host "open a new terminal, then run: avocado --help"
