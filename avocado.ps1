param(
  [Parameter(Position=0)]
  [string]$Path
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$venvPython = Join-Path $repoRoot ".venv\\Scripts\\python.exe"

if (-not (Test-Path $venvPython)) {
  python -m venv (Join-Path $repoRoot ".venv")
  & $venvPython -m pip install -U pip
  & $venvPython -m pip install -e $repoRoot
}

$env:PYTHONDONTWRITEBYTECODE = "1"
& $venvPython -B -m avocado_tui.__main__ $Path
