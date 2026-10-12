#Requires -Version 5.1
param(
    [switch]$SkipBuild,
    [string]$Compiler = '',
    [string]$Dss = '',
    [string]$TargetConfig = 'C:\Users\61987\Desktop\28035\f28035-rust-bridge\targetConfigs\TMS320F28035_XDS100v1.ccxml'
)

& (Join-Path $PSScriptRoot 'verify-mir-safe-hal-basic-ram.ps1') `
    -Name 'timer0_periodic_basic' `
    -Harness 'timer0_periodic_basic_test.c' `
    -VerifyJs 'verify-mir-timer0-periodic-basic.js' `
    -PassToken 'TIMER0_PERIODIC_BASIC_TARGET_TEST=PASS' `
    -SkipBuild:$SkipBuild `
    -Compiler $Compiler `
    -Dss $Dss `
    -TargetConfig $TargetConfig
