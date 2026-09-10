param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$Args
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
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
  throw "zig.exe not found. Install Zig 0.16+ or add it to PATH."
}

Push-Location $repoRoot
try {
  & $zigExe build run -- @Args
  exit $LASTEXITCODE
} finally {
  Pop-Location
}
