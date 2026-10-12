# verify-llvm-c28x-link.ps1
# End-to-end check: LLVM llc -filetype=obj -> TI linker -> .out
#
# Verifies that an LLVM-produced C28x ELF object with R_C28X_ABS22_BR
# relocations can be linked by TI's cl2000 --run_linker, and that the
# resulting .out has the external call resolved to the correct address.
#
# Usage:
#   . tools/llvm-c28x-env.ps1
#   . tools/verify-llvm-c28x-link.ps1

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

# --- Inputs ---------------------------------------------------------------
# Minimal IR: caller calls external callee; result discarded.
$callerLl = @'
declare i32 @callee()
define i32 @caller() {
  %1 = call i32 @callee()
  ret i32 %1
}
'@

# TI-side callee: just LRETR.
$calleeAsm = @'
    .sect ".text"
    .def callee; .globalsym; .endef
callee:
    lretr
'@

# TI-side main: calls caller, returns.
$mainAsm = @'
    .sect ".text"
    .def main; .globalsym; .endef
    .ref caller
main:
    lcr caller
    lretr
'@

# --- Work dir -------------------------------------------------------------
$work = Join-Path $env:TEMP 'c28x-link-verify'
New-Item -ItemType Directory -Force -Path $work | Out-Null

$callerLlPath = Join-Path $work 'caller.ll'
$calleeAsmPath = Join-Path $work 'callee.asm'
$mainAsmPath   = Join-Path $work 'main.asm'
$callerObjPath = Join-Path $work 'caller.obj'
$calleeObjPath = Join-Path $work 'callee.obj'
$mainObjPath   = Join-Path $work 'main.obj'
$outPath       = Join-Path $work 'linked.out'
$mapPath       = Join-Path $work 'linked.map'

Set-Content -Path $callerLlPath -Value $callerLl -Encoding ASCII
Set-Content -Path $calleeAsmPath -Value $calleeAsm -Encoding ASCII
Set-Content -Path $mainAsmPath   -Value $mainAsm -Encoding ASCII

Remove-Item $callerObjPath,$calleeObjPath,$mainObjPath,$outPath,$mapPath -ErrorAction SilentlyContinue

# --- Step 1: LLVM llc -> caller.obj ---------------------------------------
& $C28xToolchain.Llc -mtriple=c28x-ti-none -mcpu=c28x -filetype=obj $callerLlPath -o $callerObjPath
if ($LASTEXITCODE -ne 0) { throw "llc failed (exit $LASTEXITCODE)" }
if (-not (Test-Path $callerObjPath)) { throw "llc did not produce caller.obj" }
Write-Host "OK: llc produced caller.obj ($((Get-Item $callerObjPath).Length) bytes)"

# --- Step 2: TI assemble callee + main ------------------------------------
$compileFlags = @('--silicon_version=28','--abi=eabi','--compile_only','-v28')
& $C28xToolchain.Cl2000 @compileFlags --output_file=$calleeObjPath $calleeAsmPath
if ($LASTEXITCODE -ne 0) { throw "cl2000 assemble callee failed" }
& $C28xToolchain.Cl2000 @compileFlags --output_file=$mainObjPath $mainAsmPath
if ($LASTEXITCODE -ne 0) { throw "cl2000 assemble main failed" }
Write-Host "OK: TI assembled callee.obj and main.obj"

# --- Step 3: TI link ------------------------------------------------------
$runtime = Join-Path (Split-Path -Parent (Split-Path -Parent $C28xToolchain.Cl2000)) 'lib\rts2800_ml_eabi.lib'
$ramCmd   = Join-Path $root 'tools\F28035_ram.cmd'
$eabiCmd  = Join-Path $root 'tools\F28035_EABI_sections_ram.cmd'

& $C28xToolchain.Cl2000 `
    --silicon_version=28 --float_support=softlib --abi=eabi --run_linker `
    --rom_model --stack_size=0x100 --unused_section_elimination=off `
    --map_file=$mapPath --output_file=$outPath `
    $callerObjPath $calleeObjPath $mainObjPath $runtime $ramCmd $eabiCmd
if ($LASTEXITCODE -ne 0) { throw "TI link failed" }
if (-not (Test-Path $outPath)) { throw "TI link did not produce .out" }
Write-Host "OK: TI linker produced linked.out ($((Get-Item $outPath).Length) bytes)"

# --- Step 4: Verify call resolved -----------------------------------------
# Read map to get addresses of caller and callee.
$mapText = Get-Content $mapPath
$callerLine = $mapText | Select-String -Pattern '^\s*0\s+([0-9a-f]+)\s+caller\s*$' | Select-Object -First 1
$calleeLine = $mapText | Select-String -Pattern '^\s*0\s+([0-9a-f]+)\s+callee\s*$' | Select-Object -First 1
if (-not $callerLine -or -not $calleeLine) { throw "map does not contain caller/callee symbols" }

$callerAddr = [Convert]::ToInt32($callerLine.Matches[0].Groups[1].Value, 16)
$calleeAddr = [Convert]::ToInt32($calleeLine.Matches[0].Groups[1].Value, 16)
Write-Host ("OK: caller @ 0x{0:x}, callee @ 0x{1:x}" -f $callerAddr, $calleeAddr)

# Disassemble and check the LCR at caller points to callee.
$disasm = & $C28xToolchain.Dis2000 $outPath 2>&1 | Out-String
$expectedLcr = "LCR          0x{0:x6}" -f $calleeAddr
if ($disasm -match [regex]::Escape($expectedLcr)) {
    Write-Host "OK: LCR relocation resolved to $expectedLcr"
} else {
    throw "LCR relocation NOT resolved. Expected '$expectedLcr' in disasm."
}

Write-Host ""
Write-Host "=== ALL CHECKS PASSED ===" -ForegroundColor Green
Write-Host "LLVM .obj -> TI linker -> .out with R_C28X_ABS22_BR works end-to-end."
