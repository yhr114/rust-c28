#Requires -Version 5.1
# build-cargo-gpio-blink.ps1
#
# End-to-end build of the cargo-based F28035 GPIO34 blink:
#   1. cargo rustc (patched rustc + custom sysroot) -> gpio-blink.o
#   2. assemble RAM startup stub (cargo_blink_start.asm)
#   3. TI cl2000 --run_linker with rts2800_ml_eabi.lib + RAM cmd files -> .out
#
# Prereqs already built by gap1-4 scripts:
#   build/c28x-std/libcore.rlib, libcompiler_builtins.rlib
#   build/c28x-sysroot/lib/rustlib/c28x-none-elf/lib/{libcore,libcompiler_builtins}.rlib
#   build/c28x-std/objs/{core,builtins}-cgu.0.rcgu.o (extracted from rlibs)

. (Join-Path $PSScriptRoot 'llvm-c28x-env.ps1')
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

$rustc   = 'D:\c28x-toolchain\rust-build-gcc14fix\host\stage1\bin\rustc.exe'
$cargo   = 'C:\Users\61987\.cargo\bin\cargo.exe'
$crate   = Join-Path $root 'crates\c28x-gpio-blink'
$build   = Join-Path $root 'build\c28x-gpio-blink'
$stdObjs = Join-Path $root 'build\c28x-std\objs'
$rts     = 'C:\ti\ccs2101\ccs\tools\compiler\ti-cgt-c2000_25.11.1.LTS\lib\rts2800_ml_eabi.lib'
$ramCmd  = Join-Path $root 'tools\F28035_ram.cmd'
$eabiCmd = Join-Path $root 'tools\F28035_EABI_sections_ram.cmd'

foreach ($p in @($rustc,$cargo,$rts,$ramCmd,$eabiCmd)) {
    if (-not (Test-Path $p)) { throw "Missing $p" }
}
New-Item -ItemType Directory -Force -Path $build | Out-Null
$env:RUSTC_BOOTSTRAP = '1'
$env:CARGO_TERM_COLOR = 'never'

# --- 1. cargo build (release: unoptimized dev profile hits a C28x backend
#      relocation-expansion bug inside the TI linker; release codegen avoids it)
Set-Location $crate
$obj = Join-Path $crate 'gpio-blink.o'
Remove-Item $obj -ErrorAction SilentlyContinue
$prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
& $cargo rustc --release --target c28x-none-elf -- --emit=obj -o $obj 2>&1 | Out-Host
$cargoRc = $LASTEXITCODE
$ErrorActionPreference = $prev
if ($cargoRc -ne 0) { throw "cargo rustc failed (rc=$cargoRc)" }
if (-not (Test-Path $obj)) { throw "cargo did not produce $obj" }
Write-Host "OK: cargo -> $obj ($((Get-Item $obj).Length) bytes)"

# --- 2. assemble startup stub
$startAsm = Join-Path $crate 'cargo_blink_start.asm'
$startObj = Join-Path $build 'cargo_blink_start.obj'
$ErrorActionPreference = 'Continue'
& $C28xToolchain.Cl2000 --silicon_version=28 --float_support=softlib --abi=eabi --compile_only "--output_file=$startObj" $startAsm 2>&1 | Out-Host
$asmRc = $LASTEXITCODE
$ErrorActionPreference = $prev
if ($asmRc -ne 0) { throw 'asm startup failed' }
Write-Host "OK: startup -> $startObj"

# --- 3. TI link
$out = Join-Path $build 'gpio_blink.out'
$map = Join-Path $build 'gpio_blink.map'
Remove-Item $out,$map -ErrorAction SilentlyContinue
$prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
& $C28xToolchain.Cl2000 --silicon_version=28 --float_support=softlib --abi=eabi --run_linker `
    --rom_model --stack_size=0x100 --unused_section_elimination=on --entry_point=code_start `
    "--map_file=$map" "--output_file=$out" `
    $obj $startObj (Join-Path $stdObjs 'core-cgu.0.rcgu.o') (Join-Path $stdObjs 'builtins-cgu.0.rcgu.o') $rts `
    $ramCmd $eabiCmd
$linkRc = $LASTEXITCODE
$ErrorActionPreference = $prev
if ($linkRc -ne 0 -or -not (Test-Path $out)) { throw "TI link failed (rc=$linkRc)" }
Write-Host "OK: linked -> $out ($((Get-Item $out).Length) bytes)"
Write-Host ""
Write-Host "CARGO_GPIO_BLINK_BUILD=PASS $out"
Write-Host "Next: dss.bat verify-cargo-gpio-blink-ram.js targetConfigs\TMS320F28035_XDS100v1.ccxml $out"
