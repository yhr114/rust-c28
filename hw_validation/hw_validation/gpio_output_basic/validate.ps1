$ErrorActionPreference='Stop'
& (Join-Path $PSScriptRoot 'build.ps1')
$stage='C:\Users\61987\AppData\Local\Temp\gpio_output_28035_20260904'
& C:\ti\ccs2101\ccs\scripting\run.bat (Join-Path $stage 'run.js') 2>&1 | Tee-Object (Join-Path $PSScriptRoot 'run.log')
$runExit=$LASTEXITCODE
if(Test-Path (Join-Path $stage 'results.json')) {Copy-Item (Join-Path $stage 'results.json') $PSScriptRoot}
if($runExit -ne 0){throw "Validation failed: exit $runExit"}

