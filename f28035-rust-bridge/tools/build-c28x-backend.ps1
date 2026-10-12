# build-c28x-backend.ps1 — 在 Windows 上构建 C28x LLVM 后端（bootstrap.sh 的 PowerShell 移植）
# 步骤：
#   1. 准备 llvm-project 源码（默认 $env:USERPROFILE\llvm-project，可 -LlvmSource 指定）
#   2. 以目录联接（Junction，无需管理员）把 llvm-c28x 挂到 llvm\lib\Target\C28x
#   3. 应用 llvm-patches\*.patch（目前该目录只有 README，无补丁文件则跳过）
#   4. cmake + ninja 构建 llc、llvm-objdump
#   5. 运行 verify-llvm-c28x.ps1 完成 MC 层回归
#
# 注意：本机（无 LLVM 源码/无 llc 的机器）无法执行第 4-5 步；
#       请在具备 git/ninja/cmake 且联网的环境运行本脚本。
param(
    [string]$LlvmSource = (Join-Path $env:USERPROFILE 'llvm-project'),
    [string]$Branch = 'main',
    [string]$BuildDir = '',
    [switch]$SkipClone,
    [switch]$SkipVerify
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$c28xSrc = Join-Path $root 'backend\llvm-c28x'
if ([string]::IsNullOrWhiteSpace($BuildDir)) { $BuildDir = Join-Path $LlvmSource 'build-c28x' }

function Step([string]$msg) { Write-Host "==> $msg" }

foreach ($tool in @('git', 'ninja', 'cmake')) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "Required tool not found: $tool"
    }
}

$runtimeCandidates = @(
    'D:\c28x-toolchain\llvm-mingw\llvm-mingw-20260602-ucrt-x86_64\bin',
    (Join-Path $env:USERPROFILE 'llvm-mingw\bin')
)
foreach ($candidate in $runtimeCandidates) {
    if ((Test-Path $candidate) -and (($env:PATH -split ';') -notcontains $candidate)) {
        $env:PATH = "$candidate;$env:PATH"
    }
}

Step '1/5 准备 llvm-project 源码'
if (-not (Test-Path (Join-Path $LlvmSource 'llvm\CMakeLists.txt'))) {
    if ($SkipClone) { throw "LLVM source not found at $LlvmSource and -SkipClone is set" }
    New-Item -ItemType Directory -Path (Split-Path -Parent $LlvmSource) -Force | Out-Null
    git clone --depth 1 --branch $Branch https://github.com/llvm/llvm-project.git $LlvmSource
    if ($LASTEXITCODE -ne 0) { throw 'git clone llvm-project failed' }
} else {
    Write-Host "  using existing source: $LlvmSource"
}

Step '2/5 挂载 C28x 后端（Junction）'
$c28xMount = Join-Path $LlvmSource 'llvm\lib\Target\C28x'
if (-not (Test-Path $c28xMount)) {
    New-Item -ItemType Junction -Path $c28xMount -Target $c28xSrc | Out-Null
    Write-Host "  junction created: $c28xMount -> $c28xSrc"
} else {
    Write-Host "  junction exists: $c28xMount"
}

Step '3/5 应用 llvm-patches'
$patches = Get-ChildItem (Join-Path $c28xSrc 'llvm-patches') -Filter *.patch -ErrorAction SilentlyContinue
if ($patches) {
    foreach ($p in $patches) {
        $patchPath = Join-Path $c28xSrc 'llvm-patches' $p.Name
        git -C $LlvmSource apply --check $patchPath 2>$null
        if ($LASTEXITCODE -eq 0) {
            git -C $LlvmSource apply $patchPath
            if ($LASTEXITCODE -ne 0) { throw "git apply failed: $($p.Name)" }
            Write-Host "  applied $($p.Name)"
            continue
        }

        git -C $LlvmSource apply --reverse --check $patchPath 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  already applied $($p.Name)"
            continue
        }

        throw "patch does not apply cleanly: $($p.Name)"
    }
} else {
    Write-Host '  llvm-patches 目录无 .patch 文件（README 为手工修改说明），跳过'
}

Step '4/5 cmake + ninja 构建 llc / llvm-objdump'
if (-not (Test-Path (Join-Path $BuildDir 'build.ninja'))) {
    cmake -S (Join-Path $LlvmSource 'llvm') -B $BuildDir -G Ninja `
        -DCMAKE_BUILD_TYPE=Release `
        -DLLVM_TARGETS_TO_BUILD=X86 `
        -DLLVM_EXPERIMENTAL_TARGETS_TO_BUILD=C28x `
        -DLLVM_INCLUDE_TESTS=OFF `
        -DLLVM_INCLUDE_EXAMPLES=OFF `
        -DLLVM_INCLUDE_BENCHMARKS=OFF
    if ($LASTEXITCODE -ne 0) { throw 'cmake configure failed' }
}
ninja -C $BuildDir llc llvm-objdump
if ($LASTEXITCODE -ne 0) { throw 'ninja build failed' }

Step '5/5 MC 层回归'
if (-not $SkipVerify) {
    & (Join-Path $PSScriptRoot 'verify-llvm-c28x.ps1') -LlvmBin (Join-Path $BuildDir 'bin')
}
Write-Host 'DONE: build-c28x-backend.ps1 完成'
