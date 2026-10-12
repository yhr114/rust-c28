param([switch]$Trace)
$ErrorActionPreference='Stop'
& (Join-Path $PSScriptRoot 'build.ps1')
$stage='C:\Users\61987\AppData\Local\Temp\can_mask_28035_20260904'
$label=if($Trace){'trace'}else{'baseline'}
$previous=$env:CAN_TRACE
try {
    $env:CAN_TRACE=if($Trace){'1'}else{'0'}
    & C:\ti\ccs2101\ccs\scripting\run.bat (Join-Path $stage 'run.js') 2>&1 | Tee-Object (Join-Path $PSScriptRoot ($label+'_run.log'))
    $runExit=$LASTEXITCODE
    if(Test-Path (Join-Path $stage 'results.json')) {
        Copy-Item (Join-Path $stage 'results.json') (Join-Path $PSScriptRoot ($label+'_results.json'))
    }
    if($runExit -ne 0){ throw "Validation failed, exit code $runExit; inspect $label`_run.log" }
} finally {
    if($null -eq $previous){Remove-Item Env:\CAN_TRACE -ErrorAction SilentlyContinue}
    else {$env:CAN_TRACE=$previous}
}
