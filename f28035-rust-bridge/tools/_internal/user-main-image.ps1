# tools/_internal/user-main-image.ps1
#
# user_main（RAM / Flash 两条链）的映像指纹。
# 被 run-user-main.ps1（写戳）、build-user-main-flash.ps1（写戳）、
# verify-user-main-flash.ps1（上板前断言）共用，保证三条脚本对"新鲜"
# 的定义完全一致。
#
# 关键设计：key 同时覆盖源码（rust-api lib.rs + app/main.rs + harness +
# C 桥源 + TI 公共源 + 链接命令 + 翻译器源码树）和两个关键构建产物
# （C 桥 obj 的二进制哈希、MIR 翻译器源码树）。因此即使有人用
# run-user-main.ps1 -BridgeObject 传入预构建桥对象，key 也能反映
# 实际链入的桥内容；桥 obj 被其他构建刷新后，旧映像立即判定过期。

function Get-UserMainImageKey {
    param(
        [Parameter(Mandatory = $true)][string]$Compiler,
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][ValidateSet('ram', 'flash')][string]$Variant
    )
    $vendorRoot = Join-Path $ProjectRoot 'platform\vendor\ti\f2803x'
    $commonSource = Join-Path $vendorRoot 'common\source'
    $translatorRoot = Join-Path $ProjectRoot 'tools\rust-to-ti-c'
    $translatorSources = @(Get-ChildItem -LiteralPath (Join-Path $translatorRoot 'src') -Filter '*.rs' -File |
        ForEach-Object { $_.FullName } | Sort-Object)
    $files = @(
        (Join-Path $ProjectRoot 'crates\rust-api\src\lib.rs'),
        (Join-Path $ProjectRoot 'app\src\main.rs'),
        (Join-Path $ProjectRoot 'app\firmware\default_interrupts.c'),
        (Join-Path $ProjectRoot 'platform\firmware\user_main_test.c'),
        (Join-Path $ProjectRoot 'sdk\c-abi\f28035_bridge.c'),
        (Join-Path $ProjectRoot 'sdk\c-abi\f28035_bridge.h'),
        (Join-Path $ProjectRoot 'build\c28x\f28035_bridge.obj'),
        (Join-Path $commonSource 'DSP2803x_SysCtrl.c'),
        (Join-Path $commonSource 'DSP2803x_Gpio.c'),
        (Join-Path $commonSource 'DSP2803x_CodeStartBranch.asm'),
        (Join-Path $ProjectRoot 'platform\runtime\c28x_us_delay_eabi.asm'),
        (Join-Path $ProjectRoot 'tools\F28035_ram.cmd'),
        (Join-Path $ProjectRoot 'tools\F28035_EABI_sections_ram.cmd'),
        (Join-Path $ProjectRoot 'tools\F28035_ramfuncs_zero.cmd'),
        (Join-Path $ProjectRoot 'platform\firmware\F28035_Peripheral_symbols.cmd'),
        (Join-Path $vendorRoot 'headers\cmd\DSP2803x_Headers_nonBIOS.cmd'),
        (Join-Path $translatorRoot 'Cargo.toml')
    ) + $translatorSources
    $tags = @{ features = 'one-file-main'; mirArgs = '-Zmir-opt-level=4 -OnlyExport rust_user_main' }
    if ($Variant -eq 'flash') {
        $files += @(
            (Join-Path $ProjectRoot 'platform\firmware\user_main_flash_prepare.c'),
            (Join-Path $vendorRoot 'common\cmd\F28035.cmd'),
            (Join-Path $ProjectRoot 'platform\firmware\F28035_EABI_sections.cmd')
        )
        $tags['defines'] = 'F28035_FLASH_BOOT'
    }
    return New-ImageKey -Label "user_main/$Variant" -Tags $tags -Files $files -Compiler $Compiler
}
