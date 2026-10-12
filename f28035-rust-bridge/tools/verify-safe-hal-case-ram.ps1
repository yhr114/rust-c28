#Requires -Version 5.1
<#
.SYNOPSIS
  Verify an app hardware case through the Safe HAL MIR backend route.

.DESCRIPTION
  This is the bridge between the application case registry (`app/hardware-tests`)
  and the compiler-research route (`crates/rust-api` -> `backend/c28x-mir`).

  The ordinary `verify-case-ram.ps1` path still uses the restricted Rust-to-C
  translator.  This script is for cases whose `case.toml` has a `[mir_template]`
  section: the case is tracked as an app case, while the verified target object
  comes from rustc optimized MIR lowered by `backend/c28x-mir`.

  Initial supported cases (app symbol -> per-case verifier):
    gpio/gpio_output_basic        -> rust_gpio34_output_basic      -> verify-mir-gpio34.ps1
    gpio/gpio_output_readback_basic -> rust_gpio34_output_readback -> verify-mir-gpio34-readback.ps1
    gpio/gpio_toggle_basic        -> rust_gpio34_toggle_basic      -> verify-mir-gpio34-toggle.ps1
    gpio/gpio_direction_switch_basic -> rust_gpio34_direction_switch -> verify-mir-gpio34-dirswitch.ps1
    adc/adc_sample_basic          -> rust_adc_sample_basic         -> verify-mir-adc-sample-basic.ps1
    epwm/epwm_cmp_basic           -> rust_epwm_cmp_basic           -> verify-mir-epwm-cmp-basic.ps1
    timer/timer0_periodic_basic   -> rust_timer0_periodic_basic    -> verify-mir-timer0-periodic-basic.ps1
    integration/safe_hal_control_loop -> rust_main                 -> verify-mir-control-loop-ram.ps1
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$Case,

    [switch]$SkipBuild,
    [string]$Compiler = '',
    [string]$Dss = '',
    [string]$TargetConfig = ''
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$parts = $Case.Replace('/', '\').Split('\', [System.StringSplitOptions]::RemoveEmptyEntries)
if ($parts.Count -ne 2) {
    throw 'Case must use category/name, for example gpio/gpio_output_basic'
}

$category = $parts[0]
$name = $parts[1]
$caseRoot = Join-Path $projectRoot "app\hardware-tests\$category\$name"
$caseManifest = Join-Path $caseRoot 'case.toml'
if (-not (Test-Path -LiteralPath $caseManifest -PathType Leaf)) {
    throw "Case manifest not found: $caseManifest"
}

$manifestText = Get-Content -LiteralPath $caseManifest -Raw
if ($manifestText -notmatch '(?m)^\[mir_template\]\s*$') {
    throw "Case does not declare a [mir_template] Safe HAL route: $Case"
}

$appMatch = [regex]::Match($manifestText, '(?m)^app\s*=\s*"([^"]+)"\s*$')
if (-not $appMatch.Success) {
    throw "Case [mir_template] is missing app = ""..."" in $caseManifest"
}
$appSymbol = $appMatch.Groups[1].Value

# app symbol -> per-case MIR/RAM/JTAG verifier script
$verifierBySymbol = @{
    'rust_gpio34_output_basic'      = 'verify-mir-gpio34.ps1'
    'rust_gpio34_output_readback'   = 'verify-mir-gpio34-readback.ps1'
    'rust_gpio34_toggle_basic'      = 'verify-mir-gpio34-toggle.ps1'
    'rust_gpio2_3_low'              = 'verify-mir-gpio2-3.ps1'
    'rust_gpio30_low'               = 'verify-mir-gpio30.ps1'
    'rust_gpio34_direction_switch'  = 'verify-mir-gpio34-dirswitch.ps1'
    'rust_gpio0_mux_to_epwm1a'      = 'verify-mir-gpio0-mux.ps1'
    'rust_adc_sample_basic'         = 'verify-mir-adc-sample-basic.ps1'
    'rust_adc_eoc_irq_setup'        = 'verify-mir-adc-eoc-irq.ps1'
    'rust_adc_clkdiv2en_setup'      = 'verify-mir-adc_clkdiv2en.ps1'
    'rust_adc_single_soc_setup'     = 'verify-mir-adc_single_soc.ps1'
    'rust_epwm_cmp_basic'           = 'verify-mir-epwm-cmp-basic.ps1'
    'rust_timer0_periodic_basic'    = 'verify-mir-timer0-periodic-basic.ps1'
    'rust_main'                     = 'verify-mir-control-loop-ram.ps1'
}

if (-not $verifierBySymbol.ContainsKey($appSymbol)) {
    throw "No Safe HAL MIR verifier is registered for app symbol: $appSymbol"
}

$script = Join-Path $PSScriptRoot $verifierBySymbol[$appSymbol]
# Hashtable splatting: array splatting would bind '-SkipBuild' as a positional
# string (switch params cannot bind positionally), which the verifier scripts
# would then treat as a path and reject.
$forward = @{}
if ($SkipBuild) { $forward['SkipBuild'] = $true }
if ($Compiler) { $forward['Compiler'] = $Compiler }
if ($Dss) { $forward['Dss'] = $Dss }
if ($TargetConfig) { $forward['TargetConfig'] = $TargetConfig }

Write-Output "== Safe HAL app case: $Case =="
Write-Output "Route: app case -> crates/rust-api::$appSymbol -> c28x-mir -> RAM/JTAG"
$mutexName = 'Global\f28035-rust-bridge-xds100-dss'
$mutex = [System.Threading.Mutex]::new($false, $mutexName)
$lockTaken = $false
try {
    Write-Output "Waiting for exclusive XDS100/DSS access: $mutexName"
    $lockTaken = $mutex.WaitOne([TimeSpan]::FromMinutes(5))
    if (-not $lockTaken) {
        throw 'Timed out waiting for exclusive XDS100/DSS access.'
    }

    & $script @forward
    if ($LASTEXITCODE -ne 0) {
        throw "Safe HAL MIR verification failed for $Case"
    }
} finally {
    if ($lockTaken) {
        $mutex.ReleaseMutex()
    }
    $mutex.Dispose()
}
Write-Output "SAFE_HAL_CASE_TARGET_TEST=PASS"
Write-Output "RESULT: PASS  $Case (app registry, Safe HAL MIR route, RAM verify, flash untouched)"
