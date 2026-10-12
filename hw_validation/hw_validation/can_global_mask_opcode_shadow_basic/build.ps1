$ErrorActionPreference = 'Stop'
# cl2000 writes harmless warnings (e.g. entry-point "code_start") to stderr;
# with EAP=Stop PowerShell 5.1 wraps stderr as NativeCommandError and kills the
# script even when the tool exits 0.  Invoke-Native keeps warnings visible but
# judges success by $LASTEXITCODE only (same pattern as verify-case-ram.ps1).
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
$stage = 'C:\Users\61987\AppData\Local\Temp\can_mask_28035_20260904'
$compiler = 'C:\ti\ccs2101\ccs\tools\compiler\ti-cgt-c2000_25.11.1.LTS'
$support = 'D:\ti\c2000\C2000Ware_5_02_00_00\device_support\f2803x'
$original = 'C:\Users\61987\Desktop\28035\fpga_delivery_28035\case_src\can\can_global_mask_opcode_shadow_basic'
New-Item -ItemType Directory -Force -Path $stage | Out-Null
Copy-Item -LiteralPath (Join-Path $original 'src\main.c') -Destination $stage
Copy-Item -Path (Join-Path $original 'include\*.h') -Destination $stage
Copy-Item -Path (Join-Path $PSScriptRoot 'board_can_case.h'),(Join-Path $PSScriptRoot 'runtime.c') -Destination $stage
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'test_runtime.h'),(Join-Path $PSScriptRoot 'target.ccxml'),(Join-Path $PSScriptRoot 'run.js') -Destination $stage
Push-Location $stage
try {
    $cOut = @(Invoke-Native -FilePath "$compiler\bin\cl2000.exe" -Arguments @('-v28','-ml','-g','--abi=coffabi',"--include_path=$compiler\include","--include_path=$support\headers\include","--include_path=$support\common\include",'--include_path=.','-c','main.c','runtime.c',"$support\headers\source\DSP2803x_GlobalVariableDefs.c","$support\common\source\DSP2803x_CodeStartBranch.asm"))
    $cOut | ForEach-Object { Write-Output $_ }
    if ($LASTEXITCODE -ne 0) { throw 'Compile failed' }
    $lOut = @(Invoke-Native -FilePath "$compiler\bin\cl2000.exe" -Arguments @('-v28','-ml','--abi=coffabi','-z','--rom_model','--stack_size=0x200','--entry_point=code_start','--output_file=case.out','--map_file=case.map','main.obj','runtime.obj','DSP2803x_GlobalVariableDefs.obj','DSP2803x_CodeStartBranch.obj',"$support\common\cmd\28035_RAM_lnk.cmd","$support\headers\cmd\DSP2803x_Headers_nonBIOS.cmd","--search_path=$compiler\lib",'--library=rts2800_ml.lib'))
    $lOut | ForEach-Object { Write-Output $_ }
    if ($LASTEXITCODE -ne 0) { throw 'Link failed' }
    Get-FileHash main.c
    Copy-Item case.out,case.map -Destination $PSScriptRoot
} finally { Pop-Location }

