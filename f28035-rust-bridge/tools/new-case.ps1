param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-z][a-z0-9_]*$')]
    [string]$Category,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-z][a-z0-9_]*$')]
    [string]$Name,

    [ValidateSet('scaffold', 'translated', 'compiled', 'verified')]
    [string]$Status = 'scaffold'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$caseRoot = Join-Path $projectRoot "app\hardware-tests\$Category\$Name"
$sourceDirectory = Join-Path $caseRoot 'src'
$includeDirectory = Join-Path $caseRoot 'include'

if (Test-Path -LiteralPath $caseRoot) {
    throw "Case already exists: $caseRoot"
}

New-Item -ItemType Directory -Path $sourceDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $includeDirectory -Force | Out-Null

$mainTemplate = @'
use f28035_safe_hal::{Peripherals, system_init};

/// Hardware-test entry point. Replace the loop body with this case's checks.
#[unsafe(no_mangle)]
pub extern "C" fn rust_main() -> ! {
    system_init();
    let _peripherals = Peripherals::take().unwrap();

    loop {
        core::hint::spin_loop();
    }
}

/// Required by the current C bridge even when this case does not use Timer0.
#[unsafe(no_mangle)]
pub extern "C" fn rust_timer0_interrupt() {
    unsafe {
        f28035_safe_hal::pac::ffi::f28035_timer0_ack();
    }
}
'@

$caseManifest = @"
name = "$Name"
category = "$Category"
entry = "src/main.rs"
status = "$Status"
requires = []
"@

$includeReadme = @"
# $Name case-local definitions

Put constants and configuration used only by this hardware case here.
Shared register definitions and C ABI declarations belong in the framework.
"@

Set-Content -LiteralPath (Join-Path $sourceDirectory 'main.rs') -Value $mainTemplate -Encoding utf8
Set-Content -LiteralPath (Join-Path $caseRoot 'case.toml') -Value $caseManifest -Encoding ascii
Set-Content -LiteralPath (Join-Path $includeDirectory 'README.md') -Value $includeReadme -Encoding utf8

Write-Output $caseRoot
