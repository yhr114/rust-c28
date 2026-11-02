param(
    [string]$Compiler = '',
    [string]$Cargo = ''
)

. (Join-Path $PSScriptRoot 'toolchain.ps1')
. (Join-Path $PSScriptRoot '_internal\image-stamp.ps1')
. (Join-Path $PSScriptRoot '_internal\standalone-image-keys.ps1')
if (-not $Compiler) { $Compiler = $Toolchain.Compiler }
if (-not $Cargo) { $Cargo = $Toolchain.Cargo }

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$outputDirectory = Join-Path $projectRoot 'build\native-arithmetic'
$rustManifest = Join-Path $projectRoot 'crates\rust-targets\native-arithmetic\Cargo.toml'
$memoryModelManifest = Join-Path $projectRoot 'crates\rust-targets\c28x-memory-model\Cargo.toml'
$rustSource = Join-Path $projectRoot 'crates\rust-targets\native-arithmetic\src\lib.rs'
$callChainSource = Join-Path $projectRoot 'crates\rust-targets\mir-call-chain.rs'
$generatedAssembly = Join-Path $outputDirectory 'native_arithmetic_from_rs.asm'
$mirAssembly = Join-Path $projectRoot 'build\mir\native-arithmetic-from-mir.asm'
$callChainAssembly = Join-Path $projectRoot 'build\mir\call-chain.asm'
$harnessSource = Join-Path $projectRoot 'platform\firmware\native_arithmetic_test.c'
$mirHarnessSource = Join-Path $projectRoot 'platform\firmware\mir_arithmetic_test.c'
$startupSource = Join-Path $projectRoot 'platform\vendor\ti\f2803x\common\source\DSP2803x_CodeStartBranch.asm'
$byteRuntimeSource = Join-Path $projectRoot 'platform\runtime\c28x_byte_runtime.asm'
$linkerCommand = Join-Path $projectRoot 'platform\vendor\ti\f2803x\common\cmd\F28035.cmd'
$eabiSections = Join-Path $projectRoot 'platform\firmware\F28035_EABI_sections.cmd'
$compilerRoot = Split-Path -Parent (Split-Path -Parent $Compiler)
$runtimeLibrary = Join-Path $compilerRoot 'lib\rts2800_fpu32_eabi.lib'
$compilerInclude = Join-Path $compilerRoot 'include'
$hexConverter = Join-Path (Split-Path -Parent $Compiler) 'hex2000.exe'
$nativeObject = Join-Path $outputDirectory 'native_arithmetic_from_rs.obj'
$mirObject = Join-Path $outputDirectory 'native_arithmetic_from_mir.obj'
$callChainObject = Join-Path $outputDirectory 'call_chain_from_mir.obj'
$harnessObject = Join-Path $outputDirectory 'native_arithmetic_test.obj'
$mirHarnessObject = Join-Path $outputDirectory 'mir_arithmetic_test.obj'
$startupObject = Join-Path $outputDirectory 'codestart.obj'
$byteRuntimeObject = Join-Path $outputDirectory 'c28x_byte_runtime.obj'
$firmwareOut = Join-Path $outputDirectory 'native_arithmetic_test.out'
$mirFirmwareOut = Join-Path $outputDirectory 'mir_arithmetic_test.out'
$firmwareHex = Join-Path $outputDirectory 'native_arithmetic_test.hex'
$mapFile = Join-Path $outputDirectory 'native_arithmetic_test.map'

New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null

& $Toolchain.HostTestCargo test --manifest-path $rustManifest --target $Toolchain.HostTestTarget
if ($LASTEXITCODE -ne 0) { throw 'Native arithmetic Rust tests failed.' }
& $Toolchain.HostTestCargo test --manifest-path $memoryModelManifest --target $Toolchain.HostTestTarget
if ($LASTEXITCODE -ne 0) { throw 'C28x logical-byte memory model tests failed.' }
& $Toolchain.HostTestCargo test --manifest-path (Join-Path $PSScriptRoot 'rust-to-ti-c\Cargo.toml') --target $Toolchain.HostTestTarget
if ($LASTEXITCODE -ne 0) { throw 'Native subset backend tests failed.' }
& (Join-Path $PSScriptRoot 'dump-c28x-mir.ps1') -InputFile $rustSource -Cargo $Toolchain.MirCargo
if ($LASTEXITCODE -ne 0) { throw 'rustc MIR extraction failed.' }
& (Join-Path $PSScriptRoot 'dump-c28x-mir.ps1') `
    -InputFile $callChainSource `
    -OutputFile (Join-Path $projectRoot 'build\mir\call-chain.mir.txt') `
    -AssemblyFile $callChainAssembly `
    -Cargo $Cargo
if ($LASTEXITCODE -ne 0) { throw 'Rust call-chain MIR extraction failed.' }
& (Join-Path $PSScriptRoot 'test-mir-rejections.ps1') -Cargo $Cargo
if ($LASTEXITCODE -ne 0) { throw 'MIR rejection tests failed.' }

& (Join-Path $PSScriptRoot 'rust-to-ti-asm.ps1') -InputFile $rustSource -OutputFile $generatedAssembly -Cargo $Cargo

$commonOptions = @('--silicon_version=28', '--float_support=fpu32', '--abi=eabi', '--compile_only')
& $Compiler @commonOptions --output_file=$nativeObject $generatedAssembly
if ($LASTEXITCODE -ne 0) { throw 'Failed to assemble native arithmetic.' }
& $Compiler @commonOptions --output_file=$mirObject $mirAssembly
if ($LASTEXITCODE -ne 0) { throw 'Failed to assemble MIR-generated arithmetic.' }
& $Compiler @commonOptions --output_file=$callChainObject $callChainAssembly
if ($LASTEXITCODE -ne 0) { throw 'Failed to assemble MIR-generated Rust call chain.' }
& $Compiler @commonOptions --opt_level=2 --include_path=$compilerInclude --output_file=$harnessObject $harnessSource
if ($LASTEXITCODE -ne 0) { throw 'Failed to compile native arithmetic harness.' }
& $Compiler @commonOptions --opt_level=2 --include_path=$compilerInclude --output_file=$mirHarnessObject $mirHarnessSource
if ($LASTEXITCODE -ne 0) { throw 'Failed to compile MIR arithmetic harness.' }
& $Compiler @commonOptions --output_file=$startupObject $startupSource
if ($LASTEXITCODE -ne 0) { throw 'Failed to compile startup.' }
& $Compiler @commonOptions --output_file=$byteRuntimeObject $byteRuntimeSource
if ($LASTEXITCODE -ne 0) { throw 'Failed to assemble packed-byte runtime.' }

& $Compiler `
    --silicon_version=28 --float_support=fpu32 --abi=eabi --run_linker `
    --entry_point=code_start --rom_model --stack_size=0x100 --warn_sections `
    --map_file=$mapFile --output_file=$firmwareOut `
    $startupObject $harnessObject $nativeObject $byteRuntimeObject $linkerCommand $eabiSections $runtimeLibrary
if ($LASTEXITCODE -ne 0) { throw 'Failed to link native arithmetic firmware.' }

& $Compiler `
    --silicon_version=28 --float_support=fpu32 --abi=eabi --run_linker `
    --entry_point=code_start --rom_model --stack_size=0x100 --warn_sections `
    --output_file=$mirFirmwareOut `
    $startupObject $mirHarnessObject $mirObject $callChainObject $linkerCommand $eabiSections $runtimeLibrary
if ($LASTEXITCODE -ne 0) { throw 'Failed to link MIR arithmetic firmware.' }

& $hexConverter --intel --byte --memwidth=16 --romwidth=16 --outfile=$firmwareHex $firmwareOut
if ($LASTEXITCODE -ne 0) { throw 'hex2000 failed.' }

Write-Output "Rust $rustSource"
Write-Output "Asm  $generatedAssembly"
Write-Output "Obj  $nativeObject"
Write-Output "Out  $firmwareOut"

# 新鲜度戳：两个映像（native + MIR）共用同一输入集，flash-and-verify-*.ps1 上板前断言
$arithKey = Get-NativeArithmeticImageKey -Compiler $Compiler -ProjectRoot $projectRoot
Set-ImageStamp -Image $firmwareOut -Key $arithKey
Set-ImageStamp -Image $mirFirmwareOut -Key $arithKey
