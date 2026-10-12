[CmdletBinding()]
param(
    [string]$LlvmSource,
    [string]$Llc
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$backend = Join-Path $repo 'backend\llvm-c28x'
$failures = [System.Collections.Generic.List[string]]::new()

$runtimeCandidates = @(
    'D:\c28x-toolchain\llvm-mingw\llvm-mingw-20260602-ucrt-x86_64\bin',
    (Join-Path $env:USERPROFILE 'llvm-mingw\bin')
)
foreach ($candidate in $runtimeCandidates) {
    if ((Test-Path $candidate) -and (($env:PATH -split ';') -notcontains $candidate)) {
        $env:PATH = "$candidate;$env:PATH"
    }
}

function Require-Text {
    param([string]$Path, [string]$Pattern, [string]$Message)
    if (-not (Select-String -LiteralPath $Path -Pattern $Pattern -Quiet)) {
        $failures.Add($Message)
    }
}

Require-Text (Join-Path $backend 'rustc-patches/c28x_none_elf_1_100.rs') `
    'arch: Arch::Other\("c28x"\.into\(\)\)' 'rustc target must use the registered C28x architecture string.'
Require-Text (Join-Path $backend 'rustc-patches/c28x_none_elf_1_100.rs') `
    'max_atomic_width: Some\(0\)' 'C28x must not expose unsupported atomics.'
Require-Text (Join-Path $repo 'tools/build-rustc-c28x.ps1') `
    'compiler/rustc' 'rustc bootstrap helper must build stage1 rustc.'
Require-Text (Join-Path $repo 'tools/build-rustc-c28x.ps1') `
    'library/std' 'rustc bootstrap helper must support building host std.'
Require-Text (Join-Path $backend 'llvm-patches/0001-llvm23-register-c28x-triple.patch') `
    'TargetDataLayout.cpp' 'LLVM Triple/DataLayout patch must be versioned.'
Require-Text (Join-Path $backend 'rustc-patches/compiler_builtins_c28x.md') `
    'physical_word = logical_byte >> 1' 'compiler_builtins memory intrinsics must document logical-byte address mapping.'
Require-Text (Join-Path $backend 'rustc-patches/memcpy_c28x.asm') `
    'NOT the frozen Rust ABI implementation' 'old memcpy prototype must be marked non-production.'
Require-Text (Join-Path $backend 'TargetInfo/C28xTargetInfo.cpp') `
    'RegisterTarget<Triple::c28x>' 'LLVM target must use Triple::c28x.'
Require-Text (Join-Path $backend 'C28xRegisterInfo.td') `
    'def RPC' 'The C28x return program counter must be modeled.'
Require-Text (Join-Path $backend 'C28xRegisterInfo.cpp') `
    'CSR_C28x_RegMask' 'Call-preserved masks must come from TableGen.'

$generatedInSource = Get-ChildItem -LiteralPath $backend -Filter 'C28xGen*.inc' -File
if ($generatedInSource) {
    $failures.Add('Generated TableGen includes must not be stored in the source tree.')
}

$duplicateRegistration = rg -l 'LLVMInitializeC28xTargetInfo' $backend -g '*.cpp'
if (($duplicateRegistration | Measure-Object).Count -ne 1) {
    $failures.Add('Exactly one C28x TargetInfo registration is required.')
}

if ($LlvmSource) {
    $tripleHeader = Join-Path $LlvmSource 'llvm/include/llvm/TargetParser/Triple.h'
    if (-not (Test-Path -LiteralPath $tripleHeader)) {
        $failures.Add("LLVM source tree is invalid: $LlvmSource")
    } elseif (-not (Select-String -LiteralPath $tripleHeader -Pattern '\bc28x\b' -Quiet)) {
        $failures.Add('LLVM Triple has not been patched with c28x.')
    }

    Require-Text (Join-Path $backend 'TargetInfo/C28xTargetInfo.cpp') `
        'RegisterTarget<Triple::c28x>' 'LLVM target must use Triple::c28x.'
    Require-Text (Join-Path $backend 'C28xTargetMachine.h') `
        'CodeGenTargetMachineImpl' 'TargetMachine must use the LLVM 23 codegen base.'
}

if ($Llc) {
    if (-not (Test-Path -LiteralPath $Llc)) {
        $failures.Add("llc was not found: $Llc")
    } else {
        $output = & $Llc -mtriple=c28x-ti-none -mcpu=c28x `
            (Join-Path $backend 'test/CodeGen/hello.ll') -o - 2>&1
        if ($LASTEXITCODE -ne 0) {
            $failures.Add("llc smoke test failed:`n$output")
        }
    }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host 'C28x port checks passed.'
