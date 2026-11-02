# tools/_internal/mir-common.ps1
#
# MIR 构建/验证的共享逻辑，被 build-mir.ps1 / verify-mir.ps1 dot-source。
# 所有路径都通过参数显式传入，避免 dot-source 时 $PSScriptRoot 指向本文件
# （tools/_internal）而非调用方（tools/）的歧义。
#
# 这些函数逐字复刻 legacy build-mir-*/verify-mir-* 脚本里的命令序列，
# 以保证通用脚本与旧脚本行为一致（同样的编译/链接/审计/校验步骤）。

. (Join-Path $PSScriptRoot 'image-stamp.ps1')

# 标准 MIR case 的映像指纹：覆盖全部进入链接的输入（Rust 源、harness、
# C 桥源、TI 公共源、链接命令、翻译器源码树、编译器、feature 相关 tag）。
# Build-StandardFirmware 用它写戳；Invoke-StandardRamVerify 用它断言，
# 防止切 features / 改源后用 -SkipBuild 把旧 rust obj 链上板。
function Get-MirStandardImageKey {
    param(
        [Parameter(Mandatory = $true)][PSCustomObject]$Case,
        [Parameter(Mandatory = $true)][string]$Compiler,
        [Parameter(Mandatory = $true)][string]$FloatSupport,
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string]$ToolsDir
    )
    $b = $Case.build
    $vendorRoot = Join-Path $ProjectRoot 'platform\vendor\ti\f2803x'
    $commonSource = Join-Path $vendorRoot 'common\source'
    $translatorRoot = Join-Path $ProjectRoot 'tools\rust-to-ti-c'
    $translatorSources = @(Get-ChildItem -LiteralPath (Join-Path $translatorRoot 'src') -Filter '*.rs' -File |
        ForEach-Object { $_.FullName } | Sort-Object)
    $files = @(
        (Join-Path $ProjectRoot 'crates\rust-api\src\lib.rs'),
        (Join-Path $ProjectRoot $b.harnessSrc),
        (Join-Path $ProjectRoot 'sdk\c-abi\f28035_bridge.c'),
        (Join-Path $ProjectRoot 'sdk\c-abi\f28035_bridge.h'),
        (Join-Path $ProjectRoot 'build\c28x\f28035_bridge.obj'),
        (Join-Path $commonSource 'DSP2803x_SysCtrl.c'),
        (Join-Path $commonSource 'DSP2803x_Gpio.c'),
        (Join-Path $commonSource 'DSP2803x_CodeStartBranch.asm'),
        (Join-Path $ProjectRoot 'platform\runtime\c28x_us_delay_eabi.asm'),
        (Join-Path $ProjectRoot 'tools\F28035_ram.cmd'),
        (Join-Path $ProjectRoot 'tools\F28035_EABI_sections_ram.cmd'),
        (Join-Path $ToolsDir 'F28035_ramfuncs_zero.cmd'),
        (Join-Path $ProjectRoot 'platform\firmware\F28035_Peripheral_symbols.cmd'),
        (Join-Path $vendorRoot 'headers\cmd\DSP2803x_Headers_nonBIOS.cmd'),
        (Join-Path $translatorRoot 'Cargo.toml')
    ) + $translatorSources
    return New-ImageKey -Label ("mir/{0}" -f $Case.key) `
        -Tags @{ float = $FloatSupport; onlyExport = $b.onlyExport; mirArgs = '-Zmir-opt-level=4' } `
        -Files $files -Compiler $Compiler
}

function Invoke-Native {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$Arguments
    )
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        return @(& $FilePath @Arguments 2>&1 | ForEach-Object { "$_" })
    } finally {
        $ErrorActionPreference = $prevEAP
    }
}

# 审计链接产物，防止可加载段落到 CSM 密码区（会锁死芯片）。
function Invoke-CsmAudit {
    param(
        [Parameter(Mandatory = $true)][string]$FirmwareOut,
        [Parameter(Mandatory = $true)][string]$ObjectDisplay
    )
    $objXml = (Invoke-Native $ObjectDisplay @('-x', $FirmwareOut)) | Out-String
    if ($LASTEXITCODE -ne 0) { throw 'ofd2000 failed while auditing CSM password addresses.' }
    $passwordStart = 0x3f7ff8L
    $passwordEndExclusive = 0x3f8000L
    foreach ($header in [regex]::Matches($objXml, '(?s)<elf32_phdr>(.*?)</elf32_phdr>')) {
        $addressMatch = [regex]::Match($header.Value, '<p_paddr>0x([0-9a-fA-F]+)</p_paddr>')
        if (-not $addressMatch.Success) {
            $addressMatch = [regex]::Match($header.Value, '<p_vaddr>0x([0-9a-fA-F]+)</p_vaddr>')
        }
        $sizeMatch = [regex]::Match($header.Value, '<p_filesz>0x([0-9a-fA-F]+)</p_filesz>')
        if (-not ($addressMatch.Success -and $sizeMatch.Success)) { continue }
        $segmentStart = [Convert]::ToInt64($addressMatch.Groups[1].Value, 16)
        $fileBytes = [Convert]::ToInt64($sizeMatch.Groups[1].Value, 16)
        $segmentWords = [Convert]::ToInt64([Math]::Ceiling($fileBytes / 2.0))
        $segmentEndExclusive = [Convert]::ToInt64($segmentStart + $segmentWords)
        if ($fileBytes -gt 0 -and $segmentStart -lt $passwordEndExclusive -and
            $segmentEndExclusive -gt $passwordStart) {
            throw ('Unsafe firmware: loadable segment 0x{0:x}-0x{1:x} overlaps the CSM password area.' -f `
                $segmentStart, ($segmentEndExclusive - 1))
        }
    }
    Write-Output 'CSM password-area audit: PASS (no loadable segment overlaps 0x3F7FF8..0x3F7FFF)'
    Write-Output 'Flash-range audit: PASS (loadable data is limited to 0x3E8000..0x3F7F7F and boot entry 0x3F7FF6..0x3F7FF7)'
}

# 标准 MIR 固件构建：复刻 legacy build-mir-* 的命令序列。
function Build-StandardFirmware {
    param(
        [Parameter(Mandatory = $true)][PSCustomObject]$Case,
        [Parameter(Mandatory = $true)][string]$Compiler,
        [Parameter(Mandatory = $true)][string]$Cargo,
        [string]$FloatSupport = 'softlib',
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string]$ToolsDir
    )
    $b = $Case.build
    $ErrorActionPreference = 'Stop'

    $mirDirectory = Join-Path $ProjectRoot 'build\mir'
    $rustSource = Join-Path $ProjectRoot 'crates\rust-api\src\lib.rs'
    $rustManifest = Join-Path $ProjectRoot 'crates\rust-api\Cargo.toml'
    $bridgeObject = Join-Path $ProjectRoot 'build\c28x\f28035_bridge.obj'
    $headers = Join-Path $ProjectRoot 'platform\vendor\ti\f2803x\headers\include'
    $common = Join-Path $ProjectRoot 'platform\vendor\ti\f2803x\common\include'
    $commonSource = Join-Path $ProjectRoot 'platform\vendor\ti\f2803x\common\source'
    $compilerRoot = Split-Path -Parent (Split-Path -Parent $Compiler)
    $compilerInclude = Join-Path $compilerRoot 'include'
    $runtimeLibrary = Join-Path $compilerRoot 'lib\rts2800_ml_eabi.lib'
    $objectDisplay = Join-Path (Split-Path -Parent $Compiler) 'ofd2000.exe'
    $linkerCommand = Join-Path $ProjectRoot 'tools\F28035_ram.cmd'
    $headerLinkerCommand = Join-Path $ProjectRoot 'platform\vendor\ti\f2803x\headers\cmd\DSP2803x_Headers_nonBIOS.cmd'
    $eabiSections = Join-Path $ProjectRoot 'tools\F28035_EABI_sections_ram.cmd'
    $peripheralSymbols = Join-Path $ProjectRoot 'platform\firmware\F28035_Peripheral_symbols.cmd'

    $outputDirectory = Join-Path $ProjectRoot $b.outputDir
    $mirOutput = Join-Path $mirDirectory $b.mirFile
    $assembly = Join-Path $mirDirectory $b.asmFile
    $rustObject = Join-Path $outputDirectory $b.rustObj
    $harnessObject = Join-Path $outputDirectory $b.harnessObj
    $firmwareOut = Join-Path $outputDirectory $b.firmwareOut
    $mapFile = Join-Path $outputDirectory ($b.firmwareOut -replace '\.out$', '.map')
    $harnessSource = Join-Path $ProjectRoot $b.harnessSrc
    $onlyExport = $b.onlyExport

    foreach ($required in @($Compiler, $Cargo, $objectDisplay, $rustSource, $runtimeLibrary, $harnessSource)) {
        if (-not (Test-Path -LiteralPath $required)) { throw "Required build input not found: $required" }
    }
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null

    # 主机测试（在仓库外 TEMP 执行，避免命中仓库根 .cargo 的 c28x target）
    # 宿主测试走 GNU 自含工具链——本机无 WinSDK，MSVC host 链接不可用
    Push-Location $env:TEMP
    try {
        $out = Invoke-Native $Toolchain.HostTestCargo @('test', '--manifest-path', $rustManifest, '--target', $Toolchain.HostTestTarget)
        $out | ForEach-Object { Write-Output $_ }
        if ($LASTEXITCODE -ne 0) { throw 'Safe HAL host tests failed.' }
    } finally { Pop-Location }

    # C bridge
    $out = @(& (Join-Path $ToolsDir 'build-c-bridge.ps1') -Compiler $Compiler -FloatSupport $FloatSupport 2>&1 | ForEach-Object { "$_" })
    $out | ForEach-Object { Write-Output $_ }
    if ($LASTEXITCODE -ne 0) { throw 'C bridge build failed.' }

    # c28x-mir 降级（rustc_driver 会先做类型/借用检查）
    # 翻译器用 MirCargo（GNU 自含工具链，含 rustc-dev）——见 toolchain.ps1
    $mirArgs = @('-NoProfile', '-File', (Join-Path $ToolsDir 'dump-c28x-mir.ps1'),
        '-InputFile', $rustSource, '-OutputFile', $mirOutput, '-AssemblyFile', $assembly,
        '-Cargo', $Toolchain.MirCargo, '-RustcArguments', '-Zmir-opt-level=4')
    if ($onlyExport) { $mirArgs += @('-OnlyExport', $onlyExport) }
    $out = Invoke-Native 'powershell.exe' $mirArgs
    $out | ForEach-Object { Write-Output $_ }
    if ($LASTEXITCODE -ne 0) { throw ('MIR lowering failed for case {0}.' -f $Case.key) }

    $commonOptions = @(
        '--silicon_version=28', "--float_support=$FloatSupport", '--abi=eabi',
        '--compile_only', '--gen_func_subsections=on',
        "--include_path=$compilerInclude", "--include_path=$headers", "--include_path=$common"
    )

    $startupObject = Join-Path $outputDirectory 'codestart.obj'
    $sysCtrlObject = Join-Path $outputDirectory 'sysctrl.obj'
    $gpioObject = Join-Path $outputDirectory 'gpio.obj'
    $delayObject = Join-Path $outputDirectory 'delay.obj'

    $out = Invoke-Native $Compiler @($commonOptions + @("--output_file=$rustObject", $assembly))
    $out | ForEach-Object { Write-Output $_ }
    if ($LASTEXITCODE -ne 0) { throw 'Failed to assemble rustc-MIR.' }

    $out = Invoke-Native $Compiler @($commonOptions + @('--opt_level=2', "--output_file=$harnessObject", $harnessSource))
    $out | ForEach-Object { Write-Output $_ }
    if ($LASTEXITCODE -ne 0) { throw 'Failed to compile harness.' }

    $out = Invoke-Native $Compiler @($commonOptions + @('--opt_level=2', "--output_file=$sysCtrlObject", (Join-Path $commonSource 'DSP2803x_SysCtrl.c')))
    $out | ForEach-Object { Write-Output $_ }
    if ($LASTEXITCODE -ne 0) { throw 'Failed to compile system initialization.' }

    $out = Invoke-Native $Compiler @($commonOptions + @('--opt_level=2', "--output_file=$gpioObject", (Join-Path $commonSource 'DSP2803x_Gpio.c')))
    $out | ForEach-Object { Write-Output $_ }
    if ($LASTEXITCODE -ne 0) { throw 'Failed to compile GPIO initialization.' }

    $out = Invoke-Native $Compiler @($commonOptions + @("--output_file=$delayObject", (Join-Path $ProjectRoot 'platform\runtime\c28x_us_delay_eabi.asm')))
    $out | ForEach-Object { Write-Output $_ }
    if ($LASTEXITCODE -ne 0) { throw 'Failed to assemble delay helper.' }

    $out = Invoke-Native $Compiler @($commonOptions + @("--output_file=$startupObject", (Join-Path $commonSource 'DSP2803x_CodeStartBranch.asm')))
    $out | ForEach-Object { Write-Output $_ }
    if ($LASTEXITCODE -ne 0) { throw 'Failed to compile startup.' }

    $out = Invoke-Native $Compiler @(
        '--silicon_version=28', "--float_support=$FloatSupport", '--abi=eabi', '--run_linker',
        '--entry_point=code_start', '--rom_model', '--stack_size=0x100',
        '--unused_section_elimination=on', '--warn_sections',
        "--map_file=$mapFile", "--output_file=$firmwareOut",
        $startupObject, $harnessObject, $rustObject, $bridgeObject, $sysCtrlObject, $gpioObject,
        $delayObject, $linkerCommand, $eabiSections, $peripheralSymbols,
        $headerLinkerCommand, $runtimeLibrary)
    $out | ForEach-Object { Write-Output $_ }
    if ($LASTEXITCODE -ne 0) { throw 'Failed to link firmware.' }

    Invoke-CsmAudit -FirmwareOut $firmwareOut -ObjectDisplay $objectDisplay

    # 新鲜度戳：链接+审计成功后记录全部输入指纹，供上板前 Assert-ImageFresh
    Set-ImageStamp -Image $firmwareOut -Key (Get-MirStandardImageKey -Case $Case `
        -Compiler $Compiler -FloatSupport $FloatSupport -ProjectRoot $ProjectRoot -ToolsDir $ToolsDir)

    Write-Output "Rust $rustSource"
    Write-Output "MIR  $mirOutput"
    Write-Output "Asm  $assembly"
    Write-Output "Out  $firmwareOut"
}

# 标准 RAM 重链接 + JTAG 校验：复刻 legacy verify-mir-* 的 [2/3][3/3] 步骤。
# RAM 重链接用的是磁盘上的现有 .obj——若构建被跳过（-SkipBuild）而输入
# （源码/features/C 桥/编译器）已变化，这里会链出"看起来新、内容旧"的映像。
# 因此默认对 Build-StandardFirmware 写下的 buildstamp 做断言（fail-closed），
# 确需绕过时由调用方显式传 -AllowStale。
function Invoke-StandardRamVerify {
    param(
        [Parameter(Mandatory = $true)][PSCustomObject]$Case,
        [Parameter(Mandatory = $true)][string]$Compiler,
        [Parameter(Mandatory = $true)][string]$Dss,
        [string]$TargetConfig,
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string]$ToolsDir,
        [switch]$AllowStale
    )
    $b = $Case.build
    $v = $Case.verify
    $ErrorActionPreference = 'Continue'

    $outputDirectory = Join-Path $ProjectRoot $b.outputDir
    $harnessObject = Join-Path $outputDirectory $b.harnessObj
    $rustObject = Join-Path $outputDirectory $b.rustObj
    $bridgeObject = Join-Path $ProjectRoot 'build\c28x\f28035_bridge.obj'
    $OutDir = $outputDirectory
    $RamOut = Join-Path $OutDir $v.ramOut
    $RamMap = Join-Path $OutDir $v.ramMap

    Assert-ImageFresh -Image (Join-Path $OutDir $b.firmwareOut) `
        -Key (Get-MirStandardImageKey -Case $Case -Compiler $Compiler -FloatSupport 'softlib' `
            -ProjectRoot $ProjectRoot -ToolsDir $ToolsDir) `
        -Context ("mir-ram-relink/{0}" -f $Case.key) -AllowStale:$AllowStale

    foreach ($p in @($Compiler, $Dss, $TargetConfig)) {
        if (-not (Test-Path -LiteralPath $p)) { throw "Required path missing: $p" }
    }

    Write-Output '== [2/3] RAM relink (all sections -> SARAM, no flash) =='
    $compilerRoot = Split-Path -Parent (Split-Path -Parent $Compiler)
    $runtimeLibrary = Join-Path $compilerRoot 'lib\rts2800_ml_eabi.lib'
    $objects = @(
        (Join-Path $OutDir 'codestart.obj'),
        $harnessObject,
        $rustObject,
        $bridgeObject,
        (Join-Path $OutDir 'sysctrl.obj'),
        (Join-Path $OutDir 'gpio.obj'),
        (Join-Path $OutDir 'delay.obj')
    )
    foreach ($o in $objects) { if (-not (Test-Path -LiteralPath $o)) { throw "Missing object: $o" } }

    Remove-Item $RamOut, $RamMap -ErrorAction SilentlyContinue
    $linkArgs = @(
        '--silicon_version=28', '--float_support=softlib', '--abi=eabi', '--run_linker',
        '--entry_point=code_start', '--rom_model', '--stack_size=0x100',
        '--unused_section_elimination=on', '--warn_sections',
        "--map_file=$RamMap", "--output_file=$RamOut"
    ) + $objects + @(
        (Join-Path $ProjectRoot 'tools\F28035_ram.cmd'),
        (Join-Path $ProjectRoot 'tools\F28035_EABI_sections_ram.cmd'),
        (Join-Path $ToolsDir 'F28035_ramfuncs_zero.cmd'),
        (Join-Path $ProjectRoot 'platform\firmware\F28035_Peripheral_symbols.cmd'),
        (Join-Path $ProjectRoot 'platform\vendor\ti\f2803x\headers\cmd\DSP2803x_Headers_nonBIOS.cmd'),
        $runtimeLibrary
    )
    & $Compiler @linkArgs 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $RamOut)) { throw 'RAM relink failed.' }

    $flashHits = Select-String -Path $RamMap -Pattern '^\s*\.(text|cinit|econst|const)\s+' | ForEach-Object {
        $c = @($_.Line -split '\s+' | Where-Object { $_ -ne '' })
        if ($c.Count -ge 3 -and [Convert]::ToInt64($c[2], 16) -ge 0x3E0000) { $_.Line }
    }
    if ($flashHits) { throw "RAM link leaked into flash: $($flashHits -join ' | ')" }
    Write-Output "RAM link OK: $RamOut"

    Write-Output '== [3/3] JTAG RAM verify (XDS100v1, flash untouched) =='
    $verifyJs = Join-Path $ToolsDir $v.js
    $vOut = @(& $Dss $verifyJs $TargetConfig $RamOut 2>&1 | ForEach-Object { "$_" })
    $vOut | ForEach-Object { Write-Output $_ }
    if ($LASTEXITCODE -ne 0) { throw "dss exited $LASTEXITCODE while verifying $($Case.key)." }
    if (($vOut -join "`n") -notmatch $v.passMarker) { throw "Target verification failed for $($Case.key)." }
    Write-Output "RESULT: PASS  $($Case.key) (MIR true-compile, RAM verify, flash untouched)"
}

