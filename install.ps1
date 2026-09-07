param(
  [string]$Repo = $env:AVOCADO_REPO,
  [string]$Ref = $env:AVOCADO_REF
)

$ErrorActionPreference = "Stop"

if (-not $Repo) { $Repo = "ProtonKicker/Avocado" }
if (-not $Ref) { $Ref = "main" }

$zipUrl = $env:AVOCADO_ZIP_URL
if (-not $zipUrl) { $zipUrl = "https://codeload.github.com/$Repo/zip/refs/heads/$Ref" }

$baseDir = $env:AVOCADO_HOME
if (-not $baseDir) { $baseDir = Join-Path ([Environment]::GetFolderPath("LocalApplicationData")) "avocado" }

$venvDir = $env:AVOCADO_VENV_DIR
if (-not $venvDir) { $venvDir = Join-Path $baseDir "venv" }

$binDir = $env:AVOCADO_BIN_DIR
if (-not $binDir) { $binDir = Join-Path $baseDir "bin" }

$launcherPath = $env:AVOCADO_LAUNCHER_PATH
if (-not $launcherPath) { $launcherPath = Join-Path $binDir "avocado.ps1" }

$cmdPath = $env:AVOCADO_CMD_PATH
if (-not $cmdPath) { $cmdPath = Join-Path $binDir "avocado.cmd" }

$usePyLauncher = $null -ne (Get-Command py -ErrorAction SilentlyContinue)
$usePython = $null -ne (Get-Command python -ErrorAction SilentlyContinue)

if (-not $usePyLauncher -and -not $usePython) {
  Write-Host "error: Python not found (need Python 3.10+)"
  exit 1
}

$pyCmd = $null
if ($usePyLauncher) {
  & py -3 -c "import sys; raise SystemExit(0 if sys.version_info >= (3,10) else 1)" | Out-Null
  $pyCmd = @("py", "-3")
} else {
  & python -c "import sys; raise SystemExit(0 if sys.version_info >= (3,10) else 1)" | Out-Null
  $pyCmd = @("python")
}

$workDir = Join-Path ([System.IO.Path]::GetTempPath()) ("avocado-" + [System.Guid]::NewGuid().ToString("N"))
$zipPath = Join-Path $workDir "avocado.zip"
$extractDir = Join-Path $workDir "extract"
New-Item -ItemType Directory -Path $workDir | Out-Null
New-Item -ItemType Directory -Path $extractDir | Out-Null

try {
  Write-Host "downloading: $zipUrl"
  Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath

  Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force
  $pyproject = Get-ChildItem -Path $extractDir -Recurse -Filter "pyproject.toml" -File | Select-Object -First 1
  if (-not $pyproject) {
    Write-Host "error: pyproject.toml not found in downloaded zip"
    exit 1
  }

  New-Item -ItemType Directory -Force -Path $baseDir | Out-Null
  New-Item -ItemType Directory -Force -Path $binDir | Out-Null

  & $pyCmd -m venv $venvDir | Out-Null
  $venvPy = Join-Path $venvDir "Scripts\python.exe"
  & $venvPy -m pip install -U pip | Out-Null
  & $venvPy -m pip install -U $pyproject.DirectoryName | Out-Null

  @"
param([Parameter(ValueFromRemainingArguments=\$true)][string[]]\$Args)
\$venvPy = `"$venvPy`"
& \$venvPy -B -m avocado_tui.__main__ @Args
"@ | Set-Content -Path $launcherPath -Encoding UTF8

  "@`"$venvPy`" -B -m avocado_tui.__main__ %*" | Set-Content -Path $cmdPath -Encoding ASCII
} finally {
  if (Test-Path $workDir) { Remove-Item -Recurse -Force $workDir }
}

if (Get-Command avocado -ErrorAction SilentlyContinue) {
  avocado --help | Out-Null
  Write-Host "ok: avocado is installed"
  exit 0
}

Write-Host "installed, but 'avocado' is not on PATH in this shell"
Write-Host "add $binDir to PATH, open a new terminal, then run: avocado --help"
