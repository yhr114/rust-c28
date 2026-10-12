# prepare-rustc-c28x.ps1 - Prepare a rustc checkout for the C28x target.
#
# This is the reproducible setup step before the expensive x.py build:
#   1. clone or reuse rust-lang/rust at the pinned nightly date;
#   2. apply llvm-c28x/rustc-patches/0001-add-c28x-target.patch idempotently;
#   3. mount llvm-c28x as src/llvm-project/llvm/lib/Target/C28x;
#   4. apply the LLVM Triple/DataLayout patch idempotently;
#   5. write bootstrap.toml for the pinned GNU-host stage1 build.
#
# Usage:
#   powershell -File tools\prepare-rustc-c28x.ps1
#   powershell -File tools\prepare-rustc-c28x.ps1 -RustSource D:\c28x-toolchain\rust-c28x -SkipClone
param(
    [string]$RustSource = '',
    [string]$RustRev = '',
    [switch]$SkipClone,
    [switch]$ForceConfig
)

. (Join-Path $PSScriptRoot 'toolchain.ps1')
if (-not $RustSource) { $RustSource = $Toolchain.RustSource }

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$c28xBackend = Join-Path $root 'backend\llvm-c28x'
$rustcPatch = Join-Path $c28xBackend 'rustc-patches\0001-add-c28x-target.patch'
$llvmPatch = Join-Path $c28xBackend 'llvm-patches\0001-llvm23-register-c28x-triple.patch'

function Step([string]$msg) { Write-Host "==> $msg" }

function RequireTool([string]$name) {
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
        throw "Required tool not found: $name"
    }
}

function ApplyPatchIdempotent([string]$Repo, [string]$PatchPath, [string]$Name) {
    git -C $Repo apply --check $PatchPath 2>$null
    if ($LASTEXITCODE -eq 0) {
        git -C $Repo apply $PatchPath
        if ($LASTEXITCODE -ne 0) { throw "git apply failed: $Name" }
        Write-Host "  applied $Name"
        return
    }

    git -C $Repo apply --reverse --check $PatchPath 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  already applied $Name"
        return
    }

    throw "patch does not apply cleanly: $Name"
}

RequireTool git

if ([string]::IsNullOrWhiteSpace($RustRev)) {
    $version = (& rustc -Vv | Out-String)
    $m = [regex]::Match($version, '(?m)^commit-hash:\s+([0-9a-f]{40})$')
    if ($m.Success) {
        $RustRev = $m.Groups[1].Value
    } else {
        $RustRev = '4b6d04e706108ccfeafe2547fbe857dfe8972bad'
    }
}

Step "1/6 Prepare rust source at $RustSource"
if (-not (Test-Path (Join-Path $RustSource 'x.py'))) {
    if ($SkipClone) {
        throw "Rust source not found at $RustSource and -SkipClone is set"
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $RustSource) -Force | Out-Null
    git clone https://github.com/rust-lang/rust.git $RustSource
    if ($LASTEXITCODE -ne 0) { throw 'git clone rust failed' }
}

git -C $RustSource fetch --depth 1 origin $RustRev
if ($LASTEXITCODE -ne 0) {
    Write-Host "  WARN: could not fetch $RustRev; using existing checkout" -ForegroundColor Yellow
} else {
    git -C $RustSource checkout FETCH_HEAD
    if ($LASTEXITCODE -ne 0) { throw "git checkout $RustRev failed" }
}

Step '2/6 Apply rustc C28x target patch'
ApplyPatchIdempotent $RustSource $rustcPatch '0001-add-c28x-target.patch'

Step '3/6 Initialize rust submodules needed by bootstrap'
git -C $RustSource submodule update --init --recursive src/llvm-project
if ($LASTEXITCODE -ne 0) { throw 'rust src/llvm-project submodule update failed' }

Step '4/6 Mount LLVM C28x backend'
$targetDir = Join-Path $RustSource 'src\llvm-project\llvm\lib\Target\C28x'
if (-not (Test-Path $targetDir)) {
    New-Item -ItemType Junction -Path $targetDir -Target $c28xBackend | Out-Null
    Write-Host "  junction created: $targetDir -> $c28xBackend"
} else {
    Write-Host "  mount exists: $targetDir"
}

Step '5/6 Apply LLVM Triple/DataLayout patch inside rust LLVM'
$llvmRepo = Join-Path $RustSource 'src\llvm-project'
ApplyPatchIdempotent $llvmRepo $llvmPatch '0001-llvm23-register-c28x-triple.patch'

Step '6/6 Write bootstrap.toml for the working GNU host build'
$configPath = Join-Path $RustSource 'bootstrap.toml'
if ((Test-Path $configPath) -and -not $ForceConfig) {
    Write-Host "  bootstrap.toml exists, leaving it unchanged: $configPath"
} else {
    $template = Join-Path $c28xBackend 'rustc-patches\bootstrap-windows-gnu.toml'
    Copy-Item -LiteralPath $template -Destination $configPath -Force
    Write-Host "  wrote $configPath"
}

Write-Host ''
Write-Host 'Prepared rustc checkout.' -ForegroundColor Green
Write-Host "Next:"
Write-Host "  powershell -File tools\build-rustc-c28x.ps1 -RustSource $RustSource"
