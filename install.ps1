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

$repoDir = $env:AVOCADO_REPO_DIR
if (-not $repoDir) { $repoDir = Join-Path $baseDir "repo" }

$installDir = $env:AVOCADO_INSTALL_DIR
if (-not $installDir) { $installDir = Join-Path $baseDir "install" }

$binDir = $env:AVOCADO_BIN_DIR
if (-not $binDir) { $binDir = Join-Path $baseDir "bin" }

$launcherPath = $env:AVOCADO_LAUNCHER_PATH
if (-not $launcherPath) { $launcherPath = Join-Path $binDir "avocado.ps1" }

$cmdPath = $env:AVOCADO_CMD_PATH
if (-not $cmdPath) { $cmdPath = Join-Path $binDir "avocado.cmd" }

function Add-UserPathEntry {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Entry
  )

  $current = [Environment]::GetEnvironmentVariable("Path", "User")
  $parts = @()
  if ($current) {
    $parts = $current.Split(';', [System.StringSplitOptions]::RemoveEmptyEntries)
  }

  $normalizedEntry = [System.IO.Path]::GetFullPath($Entry).TrimEnd('\')
  foreach ($part in $parts) {
    if ([System.IO.Path]::GetFullPath($part).TrimEnd('\') -ieq $normalizedEntry) {
      return $false
    }
  }

  $newParts = @($normalizedEntry)
  $newParts += $parts
  $newValue = ($newParts -join ';')
  [Environment]::SetEnvironmentVariable("Path", $newValue, "User")
  $env:Path = $newValue + ";" + [Environment]::GetEnvironmentVariable("Path", "Machine")
  return $true
}

$scriptRoot = $null
if ($MyInvocation.MyCommand.Path) {
  $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
}

$sourceDir = $env:AVOCADO_SOURCE_DIR
if (-not $sourceDir -and $scriptRoot) {
  $localBuild = Join-Path $scriptRoot "build.zig"
  $localSrc = Join-Path $scriptRoot "src"
  if ((Test-Path $localBuild) -and (Test-Path $localSrc)) {
    $sourceDir = $scriptRoot
  }
}

$zigCmd = Get-Command zig -ErrorAction SilentlyContinue
if ($zigCmd) {
  $zigExe = $zigCmd.Source
} else {
  $zigPackageRoot = Join-Path $env:LOCALAPPDATA "Microsoft\\WinGet\\Packages\\zig.zig_Microsoft.Winget.Source_8wekyb3d8bbwe"
  $zigExe = Get-ChildItem -Path $zigPackageRoot -Recurse -Filter "zig.exe" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -ExpandProperty FullName -First 1
}

if (-not $zigExe) {
  Write-Host "error: zig.exe not found (need Zig 0.16+)"
  exit 1
}

$pathUpdated = $false

try {
  New-Item -ItemType Directory -Force -Path $baseDir | Out-Null
  New-Item -ItemType Directory -Force -Path $binDir | Out-Null

  if (Test-Path $installDir) { Remove-Item -Recurse -Force $installDir }

  if ($sourceDir) {
    Write-Host "installing from local source: $sourceDir"
    $repoBuildDir = $sourceDir
  } else {
    $workDir = Join-Path ([System.IO.Path]::GetTempPath()) ("avocado-" + [System.Guid]::NewGuid().ToString("N"))
    $zipPath = Join-Path $workDir "avocado.zip"
    $extractDir = Join-Path $workDir "extract"
    New-Item -ItemType Directory -Path $workDir | Out-Null
    New-Item -ItemType Directory -Path $extractDir | Out-Null

    Write-Host "downloading: $zipUrl"
    Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath

    Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force
    $buildFile = Get-ChildItem -Path $extractDir -Recurse -Filter "build.zig" -File | Select-Object -First 1
    if (-not $buildFile) {
      Write-Host "error: build.zig not found in downloaded zip"
      exit 1
    }

    Move-Item -Path $buildFile.DirectoryName -Destination $repoDir
    $repoBuildDir = $repoDir
  }

  Push-Location $repoBuildDir
  try {
    & $zigExe build -Doptimize=ReleaseSafe --prefix $installDir
    if ($LASTEXITCODE -ne 0) {
      throw "zig build failed"
    }
  } finally {
    Pop-Location
  }

  $installedExe = Join-Path $installDir "bin\\avocado.exe"
  if (-not (Test-Path $installedExe)) {
    throw "installed executable not found at $installedExe"
  }

  @"
param([Parameter(ValueFromRemainingArguments=`$true)][string[]]`$Args)
`$exe = `"$installedExe`"
& `$exe @Args
exit `$LASTEXITCODE
"@ | Set-Content -Path $launcherPath -Encoding UTF8

  "@`"$installedExe`" %*" | Set-Content -Path $cmdPath -Encoding ASCII

  $pathUpdated = Add-UserPathEntry -Entry $binDir
} finally {
  if ($workDir -and (Test-Path $workDir)) { Remove-Item -Recurse -Force $workDir }
}

if (Get-Command avocado -ErrorAction SilentlyContinue) {
  Write-Host "ok: avocado is installed"
  if ($pathUpdated) {
    Write-Host "added to PATH: $binDir"
  }
  Write-Host "run: avocado"
  exit 0
}

Write-Host "installed, but 'avocado' is not on PATH in this shell"
Write-Host "add $binDir to PATH, open a new terminal, then run: avocado"
