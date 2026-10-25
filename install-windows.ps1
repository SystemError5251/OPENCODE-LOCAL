<#
.SYNOPSIS
  Install OPENCODE-LOCAL on Windows.

.DESCRIPTION
  -Mode Wsl (default, recommended): installs into WSL2 (Debian) with install-linux.sh, exactly like
  on Linux (everything built from pinned sources), and adds an "opencode-local" command for cmd/PowerShell.

  -Mode Native: OpenCode from the pinned official release zip (SHA-256 checked), llama.cpp via winget,
  config + MCP tools in %USERPROFILE%\.config\opencode. Needs Python 3 for the MCP tools.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\install-windows.ps1 -DryRun
  powershell -ExecutionPolicy Bypass -File .\install-windows.ps1
  powershell -ExecutionPolicy Bypass -File .\install-windows.ps1 -Mode Native
  powershell -ExecutionPolicy Bypass -File .\install-windows.ps1 -Mode Native -FetchModel qwen3-1.7b
#>
[CmdletBinding()]
param(
  [ValidateSet('Wsl', 'Native')] [string] $Mode = 'Wsl',
  [string] $Distro = 'Debian',
  [string] $FetchModel = '',
  [switch] $ConfigOnly,
  [switch] $DryRun
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# --- Pins (keep in sync with lib/common.sh) ---------------------------------------------
$OpenCodeTag = 'v1.19.4'
$OpenCodeSha256 = @{
  'opencode-windows-x64.zip'          = '93b899277bd6f68803009e32bf71772ce43c34b18adf1e93b9b4d8780fdf62e5'
  'opencode-windows-x64-baseline.zip' = '21cac96abb146b0f6e770680ea7855fc4f354c7966aab39f5be9859b0df1deac'
  'opencode-windows-arm64.zip'        = '36e696fd1d275b469ab02a1ccc00d161bfdcc0a4ffa93c2b7a4e57399f3ff347'
}

$RepoRoot = $PSScriptRoot
$UserHome = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
$AppData = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { Join-Path $UserHome '.local/share' }
$OclHome = Join-Path $AppData 'opencode-local'
$OclBin = Join-Path $OclHome 'bin'
$OclModels = Join-Path $OclHome 'models'
$ConfigDir = Join-Path $UserHome '.config/opencode'

function Log([string] $msg) { Write-Host "[ocl] $msg" -ForegroundColor Cyan }
function Warn([string] $msg) { Write-Host "[ocl] warning: $msg" -ForegroundColor Yellow }
function Fail([string] $msg) { Write-Host "[ocl] error: $msg" -ForegroundColor Red; exit 1 }

# Run a script block, or only describe it in dry-run mode.
function Step([string] $what, [scriptblock] $action) {
  if ($DryRun) { Write-Host "[dry-run] $what" -ForegroundColor DarkGray; return }
  & $action
}

function Get-Sha256([string] $path) { (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant() }

function Save-Url([string] $url, [string] $dest) {
  if (-not $url.StartsWith('https://')) { Fail "refusing non-HTTPS download: $url" }
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $dest
}

# --- Config ---------------------------------------------------------------------------
function Install-Config([string] $python) {
  if (Test-Path (Join-Path $ConfigDir 'opencode.json')) {
    $bak = "$ConfigDir.bak-" + (Get-Date -Format 'yyyyMMdd-HHmmss')
    Step "back up $ConfigDir to $bak" { Copy-Item -Recurse $ConfigDir $bak }
  }
  Step "write config to $ConfigDir" {
    New-Item -ItemType Directory -Force (Join-Path $ConfigDir 'agents') | Out-Null
    Copy-Item (Join-Path $RepoRoot 'ki-config/AGENTS.md') $ConfigDir -Force
    Copy-Item (Join-Path $RepoRoot 'ki-config/agents/*.md') (Join-Path $ConfigDir 'agents') -Force
    # MCP servers: point to this machine's Python and tool folder (no {env:HOME} on Windows).
    $tools = Join-Path $OclHome 'tools'
    New-Item -ItemType Directory -Force $tools | Out-Null
    Copy-Item (Join-Path $RepoRoot 'ki-tools/*.py') $tools -Force
    $cfg = Get-Content -Raw (Join-Path $RepoRoot 'ki-config/opencode.json') | ConvertFrom-Json
    foreach ($p in $cfg.mcp.PSObject.Properties) {
      $script = Split-Path -Leaf $p.Value.command[-1]
      if ($python) {
        $p.Value.command = @($python, '-I', (Join-Path $tools $script))
      } else {
        $p.Value | Add-Member -NotePropertyName enabled -NotePropertyValue $false -Force
      }
    }
    $json = $cfg | ConvertTo-Json -Depth 20
    [IO.File]::WriteAllText((Join-Path $ConfigDir 'opencode.json'), $json, (New-Object Text.UTF8Encoding $false))
  }
  if (-not $python) { Warn 'Python 3 not found - MCP tools are disabled. Install it (winget install Python.Python.3.12) and rerun -ConfigOnly.' }
}

function Find-Python {
  foreach ($name in @('python3', 'python')) {
    $c = Get-Command $name -ErrorAction SilentlyContinue
    # Skip the Microsoft Store placeholder in WindowsApps.
    if ($c -and $c.Source -notmatch 'WindowsApps') { return $c.Source }
  }
  return $null
}

# --- Model download (native mode) -------------------------------------------------------
function Get-Model([string] $id) {
  $models = (Get-Content -Raw (Join-Path $RepoRoot 'ki-models/models.json') | ConvertFrom-Json).models
  $m = $models | Where-Object { $_.id -eq $id }
  if (-not $m) { Fail "unknown model id: $id. Known: $(($models | ForEach-Object { $_.id }) -join ', ')" }
  $sha = $m.sha256
  if (-not $sha) {
    Log 'no pinned sha256 in models.json, reading it from the Hugging Face API'
    $tree = Invoke-RestMethod -UseBasicParsing "https://huggingface.co/api/models/$($m.repo)/tree/$($m.revision)"
    $sha = ($tree | Where-Object { $_.path -eq $m.file }).lfs.oid
    if ($sha -notmatch '^[0-9a-f]{64}$') { Fail "could not read the sha256 for $($m.file)" }
    Log "official sha256: $sha  (pin it in ki-models/models.json)"
  }
  $dest = Join-Path $OclModels $m.file
  Step "download $($m.file) ($($m.size_gb) GB) and verify SHA-256" {
    New-Item -ItemType Directory -Force $OclModels | Out-Null
    Save-Url "https://huggingface.co/$($m.repo)/resolve/$($m.revision)/$($m.file)" "$dest.part"
    if ((Get-Sha256 "$dest.part") -ne $sha) { Remove-Item "$dest.part"; Fail 'checksum mismatch - download deleted' }
    Move-Item -Force "$dest.part" $dest
    Log "ready: $dest"
  }
}

# --- Launcher ---------------------------------------------------------------------------
function Write-Launcher([string] $body) {
  Step "write $OclBin\opencode-local.cmd" {
    New-Item -ItemType Directory -Force $OclBin | Out-Null
    [IO.File]::WriteAllText((Join-Path $OclBin 'opencode-local.cmd'), $body, (New-Object Text.ASCIIEncoding))
  }
  $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
  if (-not $userPath -or ($userPath -split ';') -notcontains $OclBin) {
    Step "add $OclBin to the user PATH" {
      [Environment]::SetEnvironmentVariable('Path', ((@($userPath, $OclBin) | Where-Object { $_ }) -join ';'), 'User')
    }
    Log 'open a new terminal so the PATH change takes effect'
  }
}

# --- WSL2 -------------------------------------------------------------------------------
function Install-Wsl {
  if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    Fail 'WSL is not available. Run "wsl --install" as administrator, reboot, then rerun this script.'
  }
  $distros = (& wsl.exe -l -q) -replace "`0", '' | Where-Object { $_.Trim() }
  if ($distros -notcontains $Distro) {
    Step "wsl --install -d $Distro" { & wsl.exe --install -d $Distro }
    Log "Finish the $Distro setup (create a user) in the window that opened, then rerun this script."
    if (-not $DryRun) { exit 0 }
  }
  $wslRepo = if ($DryRun) { '/mnt/c/path/to/opencode-local' } else { (& wsl.exe -d $Distro -- wslpath -a ($RepoRoot -replace '\\', '/')).Trim() }
  $instArgs = if ($ConfigOnly) { '--config-only' } else { '' }
  if ($DryRun) { $instArgs = "$instArgs --dry-run" }
  Step "run install-linux.sh $instArgs inside $Distro" {
    & wsl.exe -d $Distro -- bash "$wslRepo/install-linux.sh" $instArgs.Trim().Split(' ', [StringSplitOptions]::RemoveEmptyEntries)
    if ($LASTEXITCODE -ne 0) { Fail 'install-linux.sh failed inside WSL' }
  }
  Write-Launcher @"
@echo off
rem Generated by install-windows.ps1: runs OpenCode inside WSL ($Distro) in the current folder.
wsl.exe -d $Distro --cd "%CD%" -- bash -lc "'$wslRepo/scripts/ensure-llama.sh' && exec ~/.local/bin/opencode-local %*"
"@
  Log "Next: wsl -d $Distro -- bash $wslRepo/scripts/fetch-model.sh qwen3-1.7b"
  Log 'Then cd into a project folder and run: opencode-local'
}

# --- Native -----------------------------------------------------------------------------
function Install-Native {
  if (-not $ConfigOnly) {
    $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }
    $asset = "opencode-windows-$arch.zip"
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("ocl-" + [Guid]::NewGuid())
    Step "download OpenCode $OpenCodeTag ($asset), verify SHA-256, extract to $OclBin" {
      New-Item -ItemType Directory -Force $tmp, $OclBin | Out-Null
      $zip = Join-Path $tmp $asset
      Save-Url "https://github.com/sst/opencode/releases/download/$OpenCodeTag/$asset" $zip
      if ((Get-Sha256 $zip) -ne $OpenCodeSha256[$asset]) { Remove-Item -Recurse $tmp; Fail "checksum mismatch for $asset" }
      Expand-Archive -Force $zip $OclBin
      Remove-Item -Recurse $tmp
    }
    if (-not (Get-Command llama-server -ErrorAction SilentlyContinue)) {
      Warn 'llama.cpp comes from winget (package ggml.llamacpp); its version is not pinned like in WSL mode.'
      Step 'winget install ggml.llamacpp' {
        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { Fail 'winget not found - install llama.cpp manually (llama-server.exe on PATH)' }
        & winget install --id ggml.llamacpp -e --accept-source-agreements --accept-package-agreements
      }
    }
  }
  Install-Config (Find-Python)
  Write-Launcher @"
@echo off
rem Generated by install-windows.ps1: offline environment + local llama-server + OpenCode.
setlocal
if /I "%CD%"=="%USERPROFILE%" (echo [ocl] cd into a project directory first & exit /b 1)
set OPENCODE_DISABLE_AUTOUPDATE=1
set OPENCODE_DISABLE_MODELS_FETCH=1
set OPENCODE_DISABLE_LSP_DOWNLOAD=1
set OPENCODE_DISABLE_DEFAULT_PLUGINS=1
set OPENCODE_DISABLE_CLAUDE_CODE=1
set OPENCODE_AUTO_SHARE=false
set NO_PROXY=localhost,127.0.0.1
if not defined OCL_LLAMA_API_KEY set OCL_LLAMA_API_KEY=local-no-key
curl.exe --silent --fail --max-time 2 http://127.0.0.1:8080/health >nul 2>&1
if errorlevel 1 (
  for %%M in ("$OclModels\*.gguf") do (
    start "llama-server" /min llama-server --model "%%~fM" --host 127.0.0.1 --port 8080 --ctx-size 16384 --jinja --alias local --no-webui --parallel 1
    goto :wait
  )
  echo [ocl] no model in $OclModels - run install-windows.ps1 -Mode Native -FetchModel qwen3-1.7b
  exit /b 1
)
:wait
for /L %%i in (1,1,120) do (
  curl.exe --silent --fail --max-time 2 http://127.0.0.1:8080/health >nul 2>&1 && goto :run
  timeout /t 1 /nobreak >nul
)
echo [ocl] llama-server did not become ready
exit /b 1
:run
"$OclBin\opencode.exe" %*
"@
  Log 'Next: install-windows.ps1 -Mode Native -FetchModel qwen3-1.7b, then cd into a project and run: opencode-local'
}

# --- Main -------------------------------------------------------------------------------
if ($DryRun) { Log "OPENCODE-LOCAL installer (windows, $Mode) [dry run]" } else { Log "OPENCODE-LOCAL installer (windows, $Mode)" }
if ($FetchModel) {
  if ($Mode -ne 'Native') { Fail 'in WSL mode download models inside WSL: wsl -- bash <repo>/scripts/fetch-model.sh <id>' }
  Get-Model $FetchModel
  exit 0
}
if ($Mode -eq 'Wsl') { Install-Wsl } else { Install-Native }
Log 'done'
