# tools/_internal/standalone-image-keys.ps1
#
# 独立构建三件套（gpio30/gpio39 上板、native-arithmetic 上板）的映像指纹。
# 被 build-gpio30-low.ps1 / build-gpio39-low.ps1 / build-native-arithmetic.ps1
# （链接成功后写戳）和 flash-and-verify-*.ps1（上板前断言）共用。

function Get-GpioTargetImageKey {
    param(
        [Parameter(Mandatory = $true)][string]$Compiler,
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][ValidateSet('gpio30', 'gpio39')][string]$Target
    )
    $vendorRoot = Join-Path $ProjectRoot 'platform\vendor\ti\f2803x'
    $translatorRoot = Join-Path $ProjectRoot 'tools\rust-to-ti-c'
    $translatorSources = @(Get-ChildItem -LiteralPath (Join-Path $translatorRoot 'src') -Filter '*.rs' -File |
        ForEach-Object { $_.FullName } | Sort-Object)
    $files = @(
        (Join-Path $ProjectRoot "crates\rust-targets\${Target}_low.rs"),
        (Join-Path $ProjectRoot "platform\firmware\${Target}_low_test.c"),
        (Join-Path $ProjectRoot 'sdk\c-abi\f28035_bridge.c'),
        (Join-Path $ProjectRoot 'sdk\c-abi\f28035_bridge.h'),
        (Join-Path $ProjectRoot 'build\c28x\f28035_bridge.obj'),
        (Join-Path $vendorRoot 'common\source\DSP2803x_CodeStartBranch.asm'),
        (Join-Path $vendorRoot 'headers\source\DSP2803x_GlobalVariableDefs.c'),
        (Join-Path $vendorRoot 'common\cmd\F28035.cmd'),
        (Join-Path $ProjectRoot 'platform\firmware\F28035_EABI_sections.cmd'),
        (Join-Path $vendorRoot 'headers\cmd\DSP2803x_Headers_nonBIOS.cmd'),
        (Join-Path $translatorRoot 'Cargo.toml')
    ) + $translatorSources
    return New-ImageKey -Label "gpio-target/$Target" `
        -Tags @{ float = 'fpu32'; tool = 'rust-to-ti-c' } `
        -Files $files -Compiler $Compiler
}

function Get-NativeArithmeticImageKey {
    param(
        [Parameter(Mandatory = $true)][string]$Compiler,
        [Parameter(Mandatory = $true)][string]$ProjectRoot
    )
    $vendorRoot = Join-Path $ProjectRoot 'platform\vendor\ti\f2803x'
    $targetsRoot = Join-Path $ProjectRoot 'crates\rust-targets'
    function Get-TreeSources([string]$Root) {
        @(Get-ChildItem -LiteralPath (Join-Path $Root 'src') -Filter '*.rs' -File -ErrorAction SilentlyContinue |
            ForEach-Object { $_.FullName } | Sort-Object)
    }
    $files = @(
        (Join-Path $targetsRoot 'native-arithmetic\Cargo.toml'),
        (Join-Path $targetsRoot 'c28x-memory-model\Cargo.toml'),
        (Join-Path $targetsRoot 'mir-call-chain.rs'),
        (Join-Path $ProjectRoot 'platform\firmware\native_arithmetic_test.c'),
        (Join-Path $ProjectRoot 'platform\firmware\mir_arithmetic_test.c'),
        (Join-Path $ProjectRoot 'platform\runtime\c28x_byte_runtime.asm'),
        (Join-Path $vendorRoot 'common\source\DSP2803x_CodeStartBranch.asm'),
        (Join-Path $vendorRoot 'common\cmd\F28035.cmd'),
        (Join-Path $ProjectRoot 'platform\firmware\F28035_EABI_sections.cmd'),
        (Join-Path $targetsRoot 'native-arithmetic\Cargo.toml')
    ) + (Get-TreeSources (Join-Path $targetsRoot 'native-arithmetic')) +
        (Get-TreeSources (Join-Path $targetsRoot 'c28x-memory-model'))
    return New-ImageKey -Label 'native-arithmetic' `
        -Tags @{ float = 'fpu32'; tool = 'c28x-mir + native subset' } `
        -Files $files -Compiler $Compiler
}
