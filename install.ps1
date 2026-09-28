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

if ($usePyLauncher) {
  $pyExe = "py"
  $pyPreArgs = @("-3")
} else {
  $pyExe = "python"
  $pyPreArgs = @()
}

# The call operator takes a single command string, so keep the executable and
# its switches separate and pass the switches by array splatting.
$versionOk = $false
try {
  & $pyExe @pyPreArgs -c "import sys; raise SystemExit(0 if sys.version_info >= (3,10) else 1)" | Out-Null
  $versionOk = ($LASTEXITCODE -eq 0)
} catch {
  $versionOk = $false
}

if (-not $versionOk) {
  $detected = ""
  try { $detected = ((& $pyExe @pyPreArgs -V) 2>&1) -join " " } catch { $detected = "not runnable" }
  Write-Host "error: need Python 3.10+ (detected: $detected)"
  exit 1
}

$workDir = Join-Path ([System.IO.Path]::GetTempPath()) ("avocado-" + [System.Guid]::NewGuid().ToString("N"))
$zipPath = Join-Path $workDir "avocado.zip"
$extractDir = Join-Path $workDir "extract"
New-Item -ItemType Directory -Path $workDir | Out-Null
New-Item -ItemType Directory -Path $extractDir | Out-Null

try {
  Write-Host "downloading: $zipUrl"
  Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing

  Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force
  $pyproject = Get-ChildItem -Path $extractDir -Recurse -Filter "pyproject.toml" -File | Select-Object -First 1
  if (-not $pyproject) {
    Write-Host "error: pyproject.toml not found in downloaded zip"
    exit 1
  }

  New-Item -ItemType Directory -Force -Path $baseDir | Out-Null
  New-Item -ItemType Directory -Force -Path $binDir | Out-Null

  & $pyExe @pyPreArgs -m venv $venvDir | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "venv creation failed (exit code $LASTEXITCODE)" }

  $venvPy = Join-Path $venvDir "Scripts\python.exe"
  & $venvPy -m pip install -U pip | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "pip upgrade failed (exit code $LASTEXITCODE)" }

  & $venvPy -m pip install -U $pyproject.DirectoryName | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "package install failed (exit code $LASTEXITCODE)" }

  # Non-expanding here-string: the launcher body must keep its own $variables
  # literal, and backslash is not an escape character in PowerShell.
  $launcherBody = @'
param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$Rest
)

$ErrorActionPreference = "Stop"

$venvPy = "__VENV_PY__"
if ($env:AVOCADO_VENV_DIR) {
  $venvPy = Join-Path $env:AVOCADO_VENV_DIR "Scripts\python.exe"
}

& $venvPy -B -m avocado_tui.__main__ @Rest
'@
  $launcherBody = $launcherBody.Replace("__VENV_PY__", $venvPy)
  Set-Content -Path $launcherPath -Value $launcherBody -Encoding UTF8

  $cmdBody = '@"' + $venvPy + '" -B -m avocado_tui.__main__ %*'
  Set-Content -Path $cmdPath -Value $cmdBody -Encoding ASCII

  # Put the bin directory on PATH: persistently for the user, and right away
  # for this session. Read the User-scope value so the machine PATH is never
  # folded into the user PATH.
  $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
  if (-not $userPath) { $userPath = "" }
  if (($userPath -split ";") -notcontains $binDir) {
    $updated = (@($userPath.TrimEnd(";"), $binDir) -join ";").TrimStart(";")
    [Environment]::SetEnvironmentVariable("Path", $updated, "User")
    Write-Host "added $binDir to your user PATH (new terminals pick it up)"
  }
  if (($env:Path -split ";") -notcontains $binDir) {
    $env:Path = "$binDir;$env:Path"
  }
} finally {
  if (Test-Path $workDir) { Remove-Item -Recurse -Force $workDir }
}

# Application (PATHEXT) lookup, so this verifies the shim Windows will actually
# run rather than the .ps1, which is not executable by name from cmd.exe.
$shim = Get-Command avocado -CommandType Application -ErrorAction SilentlyContinue |
  Select-Object -First 1

if ($shim) {
  & $shim.Source --help | Out-Null
  if ($LASTEXITCODE -eq 0) {
    Write-Host "ok: avocado is installed ($($shim.Source))"
    exit 0
  }
  Write-Host "error: launcher check failed (exit code $LASTEXITCODE)"
  exit 1
}

Write-Host "installed, but 'avocado' was not found on PATH in this shell"
Write-Host "open a new terminal, then run: avocado --help"
Write-Host "if it is still missing, add $binDir to PATH"
