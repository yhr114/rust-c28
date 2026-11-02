#Requires -Version 5.1
param(
    [string]$Compiler = '',
    [string]$Cargo = ''
)

. (Join-Path $PSScriptRoot 'toolchain.ps1')
. (Join-Path $PSScriptRoot '_internal\image-stamp.ps1')
. (Join-Path $PSScriptRoot '_internal\user-main-image.ps1')
if (-not $Compiler) { $Compiler = $Toolchain.Compiler }
if (-not $Cargo) { $Cargo = $Toolchain.Cargo }
$ErrorActionPreference = 'Continue'

$root = Split-Path -Parent $PSScriptRoot
$ram = Join-Path $root 'build\user-main'
$flash = Join-Path $root 'build\user-main-flash'
$compilerRoot = Split-Path -Parent (Split-Path -Parent $Compiler)
$compilerInclude = Join-Path $compilerRoot 'include'
$headers = Join-Path $root 'platform\vendor\ti\f2803x\headers\include'
$common = Join-Path $root 'platform\vendor\ti\f2803x\common\include'
$runtime = Join-Path $compilerRoot 'lib\rts2800_ml_eabi.lib'
$ofd = Join-Path (Split-Path -Parent $Compiler) 'ofd2000.exe'
$out = Join-Path $flash 'user_main_flash.out'
$map = Join-Path $flash 'user_main_flash.map'
$harness = Join-Path $flash 'user_main_flash_test.obj'
$prepare = Join-Path $flash 'user_main_flash_prepare.obj'

foreach ($path in @($Compiler, $Cargo, $runtime, $ofd)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing build input: $path" }
}

# Always rebuild the RAM reference first, so the two images use the same Rust source.
& (Join-Path $PSScriptRoot 'run-user-main.ps1') -Compiler $Compiler -Cargo $Cargo
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath (Join-Path $ram 'user_main_ram.out'))) {
    throw 'RAM reference build failed.'
}
New-Item -ItemType Directory -Path $flash -Force | Out-Null

$compile = @(
    '--silicon_version=28', '--float_support=softlib', '--abi=eabi',
    '--compile_only', '--gen_func_subsections=on', '--opt_level=2',
    "--include_path=$compilerInclude", "--include_path=$headers", "--include_path=$common"
)
& $Compiler @compile --define=F28035_FLASH_BOOT "--output_file=$harness" (Join-Path $root 'platform\firmware\user_main_test.c')
if ($LASTEXITCODE -ne 0) { throw 'Failed to compile Flash harness.' }
& $Compiler @compile "--output_file=$prepare" (Join-Path $root 'platform\firmware\user_main_flash_prepare.c')
if ($LASTEXITCODE -ne 0) { throw 'Failed to compile Flash startup helper.' }

$objects = @(
    (Join-Path $ram 'codestart.obj'), $harness, $prepare,
    (Join-Path $ram 'default_interrupts.obj'),
    (Join-Path $ram 'user_main.obj'),
    (Join-Path $root 'build\c28x\f28035_bridge.obj'),
    (Join-Path $ram 'sysctrl.obj'), (Join-Path $ram 'gpio.obj'),
    (Join-Path $ram 'delay.obj')
)
foreach ($path in $objects) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing object: $path" }
}

Remove-Item -LiteralPath $out, $map -ErrorAction SilentlyContinue
& $Compiler --silicon_version=28 --float_support=softlib --abi=eabi --run_linker `
    --entry_point=code_start --rom_model --stack_size=0x100 `
    --unused_section_elimination=on --warn_sections `
    "--map_file=$map" "--output_file=$out" `
    @objects `
    (Join-Path $root 'platform\vendor\ti\f2803x\common\cmd\F28035.cmd') `
    (Join-Path $root 'platform\firmware\F28035_EABI_sections.cmd') `
    (Join-Path $root 'platform\firmware\F28035_Peripheral_symbols.cmd') `
    (Join-Path $root 'platform\vendor\ti\f2803x\headers\cmd\DSP2803x_Headers_nonBIOS.cmd') `
    $runtime
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $out -PathType Leaf)) {
    throw 'Failed to link Flash firmware.'
}

$xml = & $ofd -x $out | Out-String
if ($LASTEXITCODE -ne 0) { throw 'Failed to inspect Flash firmware.' }
$flashSegments = 0
$bootSegment = 0
foreach ($header in [regex]::Matches($xml, '(?s)<elf32_phdr>(.*?)</elf32_phdr>')) {
    $address = [regex]::Match($header.Value, '<p_paddr>0x([0-9a-fA-F]+)</p_paddr>')
    $size = [regex]::Match($header.Value, '<p_filesz>0x([0-9a-fA-F]+)</p_filesz>')
    if (-not ($address.Success -and $size.Success)) { throw 'Unparseable loadable segment.' }
    $start = [Convert]::ToInt64($address.Groups[1].Value, 16)
    $words = [long][Math]::Ceiling([Convert]::ToInt64($size.Groups[1].Value, 16) / 2.0)
    if ($words -eq 0) { continue }
    $end = $start + $words
    if ($start -ge 0x3f6000 -and $end -le 0x3f7f80) {
        $flashSegments++
    } elseif ($start -eq 0x3f7ff6 -and $end -le 0x3f7ff8) {
        $bootSegment++
    } else {
        throw ('Unsafe Flash load segment: 0x{0:x}-0x{1:x}' -f $start, ($end - 1))
    }
}
if ($flashSegments -eq 0 -or $bootSegment -ne 1) {
    throw "Flash image is missing code or the boot entry (code=$flashSegments boot=$bootSegment)."
}
Write-Output "FLASH_OUT=$out"
Write-Output 'FLASH_SEGMENTS_AUDIT=PASS'
Write-Output 'CSM_PASSWORD_AREA=PASS'

# 新鲜度戳：RAM 对象刚由 run-user-main.ps1 重建并写戳，这里再给 Flash
# 映像写独立戳（含 flash 专属输入：prepare.c、F28035.cmd、FLASH_BOOT define）。
Set-ImageStamp -Image $out -Key (Get-UserMainImageKey -Compiler $Compiler -ProjectRoot $root -Variant flash)

Write-Output 'FLASH_BUILD_ONLY=PASS'
