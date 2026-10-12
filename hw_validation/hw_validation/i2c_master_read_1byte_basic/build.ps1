$ErrorActionPreference='Stop'
$stage='C:\Users\61987\AppData\Local\Temp\i2c_read1_28035_20260904'
$compiler='C:\ti\ccs2101\ccs\tools\compiler\ti-cgt-c2000_25.11.1.LTS'
$support='D:\ti\c2000\C2000Ware_5_02_00_00\device_support\f2803x'
$original='C:\Users\61987\Desktop\28035\fpga_delivery_28035\case_src\i2c\i2c_master_read_1byte_basic'
New-Item -ItemType Directory -Force -Path $stage | Out-Null
Copy-Item -LiteralPath (Join-Path $original 'src\main.c'),(Join-Path $original 'include\case_config.h') -Destination $stage
foreach($file in @('board_i2c_case.h','test_runtime.h','runtime.c','run.js','target.ccxml')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination $stage
}
Push-Location $stage
try {
    & "$compiler\bin\cl2000.exe" -v28 -ml -g --abi=coffabi --include_path="$compiler\include" --include_path="$support\headers\include" --include_path="$support\common\include" --include_path=. -c main.c runtime.c "$support\headers\source\DSP2803x_GlobalVariableDefs.c" "$support\common\source\DSP2803x_CodeStartBranch.asm" "$support\common\source\DSP2803x_SysCtrl.c" "$support\common\source\DSP2803x_usDelay.asm"
    if($LASTEXITCODE -ne 0){throw 'Compile failed'}
    & "$compiler\bin\cl2000.exe" -v28 -ml --abi=coffabi -z --rom_model --stack_size=0x200 --entry_point=code_start --output_file=case.out --map_file=case.map main.obj runtime.obj DSP2803x_GlobalVariableDefs.obj DSP2803x_CodeStartBranch.obj DSP2803x_SysCtrl.obj DSP2803x_usDelay.obj "$support\common\cmd\28035_RAM_lnk.cmd" "$support\headers\cmd\DSP2803x_Headers_nonBIOS.cmd" --search_path="$compiler\lib" --library=rts2800_ml.lib
    if($LASTEXITCODE -ne 0){throw 'Link failed'}
    Get-FileHash main.c
    Copy-Item case.out,case.map -Destination $PSScriptRoot
} finally {Pop-Location}


