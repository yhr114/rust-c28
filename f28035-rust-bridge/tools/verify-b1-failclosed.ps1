# Verify the released rustc, in addition to the llc/MIR backend gate.
param([string]$BundleRoot = '', [string]$OutputDirectory = '')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'llvm-c28x-env.ps1')
$main = Split-Path -Parent $PSScriptRoot
. (Join-Path (Split-Path -Parent $main) 'f28035-rust-bridge-b1\tools\toolchain-release.ps1')
$bundle = Get-C28xBundle -Root $BundleRoot
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $main ("build\failclosed-" + $bundle.Id) }
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
$savedBootstrap = $env:RUSTC_BOOTSTRAP
$env:RUSTC_BOOTSTRAP = '1'
try {
    $source = Join-Path $main 'backend\llvm-c28x\test\Rust\b1-failclosed.rs'
    $common = @('--target=c28x-none-elf', '--crate-type=lib', '--edition=2024',
        "--sysroot=$($bundle.Root)", '-Cpanic=abort', '-Copt-level=0',
        '-Ccodegen-units=1', '-Zub-checks=no', $source)
    $object = Join-Path $OutputDirectory 'positive.o'
    $asm = Join-Path $OutputDirectory 'positive.s'
    foreach ($emit in @(@('--emit=obj', $object), @('--emit=asm', $asm))) {
        $r = Invoke-NativeCapture $bundle.Rustc ($common + @($emit[0], '-o', $emit[1]))
        [IO.File]::WriteAllText(($emit[1] + '.log'), $r.StdErr)
        if ($r.ExitCode -ne 0) { throw "Positive compilation failed: $($r.StdErr)" }
    }
    if ([IO.File]::ReadAllText($asm) -notmatch '(?m)^\s*b\s+\$,\s*unc') {
        throw 'Published rustc does not emit an instruction-local trap loop'
    }
    $negative = Join-Path $OutputDirectory ('refused-' + [guid]::NewGuid().ToString('N') + '.o')
    $r = Invoke-NativeCapture $bundle.Rustc ($common + @('--emit=obj',
        '-Cllvm-args=-basic-block-sections=all', '-o', $negative))
    [IO.File]::WriteAllText((Join-Path $OutputDirectory 'refused.log'), $r.StdErr)
    if ($r.ExitCode -eq 0 -or $r.StdErr -notmatch 'C28x: BRANCH to unresolved target' -or
        $r.StdErr -match 'Assertion failed') { throw "Expected a deliberate branch refusal: $($r.StdErr)" }
    if (Test-Path -LiteralPath $negative) { throw 'Refused compile left an output object' }
    [ordered]@{ bundle=$bundle.Id; manifestSha256=Get-C28xSha $bundle.Manifest;
        normalObject='PASS'; trapInstructionLocal='PASS'; unresolvedBranchRefused='PASS';
        sourceSha256=Get-C28xSha $source; hardware='NOT_RUN' } |
        ConvertTo-Json | Set-Content (Join-Path $OutputDirectory 'report.json') -Encoding utf8
    Write-Host "B1_FAILCLOSED=PASS bundle=$($bundle.Id)"
} finally {
    if ($null -eq $savedBootstrap) { Remove-Item Env:RUSTC_BOOTSTRAP -ErrorAction SilentlyContinue }
    else { $env:RUSTC_BOOTSTRAP = $savedBootstrap }
}
