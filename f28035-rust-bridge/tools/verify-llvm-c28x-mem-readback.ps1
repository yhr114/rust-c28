# verify-llvm-c28x-mem-readback.ps1
#
# TI C 读回测试（编译+链接级别）：
#   1. llc 把 mem-access.ll 编译为 C28x .obj
#   2. TI cl2000 编译一个 C 测试驱动，声明并调用所有访存函数
#   3. TI linker 链接 C 驱动 + LLVM .obj
#   4. ofd2000 验证输出为 EM_TI_C2000，符号正确解析
#
# 运行时行为验证（实际执行并读回内存）需要 C28x 仿真器或硬件，本脚本不覆盖。
# 但 ABI 兼容性（调用约定、符号名、参数传递）在此验证。

param(
    [string]$LlvmBin = ''
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'llvm-c28x-env.ps1')

$root = Split-Path -Parent $PSScriptRoot
$codegen = Join-Path $root 'backend\llvm-c28x\test\CodeGen'

if ([string]::IsNullOrWhiteSpace($LlvmBin)) {
    $LlvmBin = Join-Path $C28xToolchain.Build 'bin'
}
$llc = Join-Path $LlvmBin 'llc.exe'
if (-not (Test-Path $llc)) { throw "llc.exe not found at $llc" }

$tmp = Join-Path $env:TEMP ("c28x-mem-readback-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null

try {
    Write-Host '==> [1/4] llc: mem-access.ll -> C28x .obj'
    $llObj = Join-Path $tmp 'mem-access.obj'
    $llRes = Invoke-NativeCapture $llc @('-mtriple=c28x-ti-none', '-mcpu=c28x',
        '-filetype=obj', (Join-Path $codegen 'mem-access.ll'), '-o', $llObj)
    if ($llRes.ExitCode -ne 0) {
        throw "llc failed: $($llRes.StdErr)"
    }
    $ofd = Invoke-NativeCapture $C28xToolchain.Ofd2000 @('-x', $llObj)
    if ($ofd.StdOut -notmatch '<e_machine>EM_TI_C2000</e_machine>') {
        throw "ofd2000: not EM_TI_C2000`n$($ofd.StdOut)"
    }
    Write-Host '  OK: LLVM .obj is EM_TI_C2000' -ForegroundColor Green

    Write-Host '==> [2/4] TI C: compile test driver'
    $cSource = Join-Path $tmp 'mem_driver.c'
    # C driver declares the LLVM-generated functions and calls each one.
    # The globals bytes2/val32 are defined in the LLVM object; C only references them.
    [IO.File]::WriteAllText($cSource, @"
/* LLVM-generated functions (mem-access.ll) */
extern void store_byte1(unsigned char v);
extern unsigned char load_byte1(void);
extern unsigned char i8_stack(unsigned char a, unsigned char b);
extern void i32_store(unsigned long v);
extern unsigned long i32_load(void);

/* Globals defined in the LLVM object */
extern volatile unsigned char bytes2[2];
extern volatile unsigned long val32;

/* Exercise every memory-access path.  Returns a checksum so the linker
   cannot eliminate the calls as dead code. */
unsigned main(void) {
    unsigned checksum = 0;

    /* byte array: write second byte, read it back */
    store_byte1(0x5A);
    checksum += load_byte1();

    /* i8 stack roundtrip */
    checksum += i8_stack(0x10, 0x20);

    /* i32 store/load */
    i32_store(0x12345678ul);
    checksum += (unsigned)(i32_load() & 0xFFFF);
    checksum += (unsigned)(i32_load() >> 16);

    return checksum;
}
"@)
    $cObj = Join-Path $tmp 'mem_driver.obj'
    $cRes = Invoke-NativeCapture $C28xToolchain.Cl2000 @(
        '--silicon_version=28', '--float_support=softlib', '--abi=eabi',
        '--compile_only', "--output_file=$cObj", $cSource)
    if ($cRes.ExitCode -ne 0) {
        throw "TI C compile failed: $($cRes.StdOut)`n$($cRes.StdErr)"
    }
    Write-Host '  OK: TI C driver compiled' -ForegroundColor Green

    Write-Host '==> [3/4] TI linker: C driver + LLVM .obj -> .out'
    $out = Join-Path $tmp 'mem_test.out'
    $map = Join-Path $tmp 'mem_test.map'
    $ramCmd = Join-Path $root 'tools\F28035_ram.cmd'
    $sectionsCmd = Join-Path $root 'tools\F28035_EABI_sections_ram.cmd'
    $runtime = Join-Path (Split-Path -Parent (Split-Path -Parent $C28xToolchain.Cl2000)) 'lib\rts2800_ml_eabi.lib'
    $linkRes = Invoke-NativeCapture $C28xToolchain.Cl2000 @(
        '--silicon_version=28', '--float_support=softlib', '--abi=eabi',
        '--run_linker', '--rom_model', '--stack_size=0x100',
        '--unused_section_elimination=off',
        "--map_file=$map", "--output_file=$out",
        $cObj, $llObj, $runtime, $ramCmd, $sectionsCmd)
    if ($linkRes.ExitCode -ne 0 -or -not (Test-Path $out)) {
        throw "TI linker failed: $($linkRes.StdOut)`n$($linkRes.StdErr)"
    }
    Write-Host '  OK: linked .out produced' -ForegroundColor Green

    Write-Host '==> [4/4] Verify symbols resolved in .out'
    $ofdOut = Invoke-NativeCapture $C28xToolchain.Ofd2000 @('-x', $out)
    $symbols = @('store_byte1', 'load_byte1', 'i8_stack', 'i32_store',
                 'i32_load', 'bytes2', 'val32', 'main')
    $missing = @()
    foreach ($sym in $symbols) {
        if ($ofdOut.StdOut -notmatch [regex]::Escape($sym)) {
            $missing += $sym
        }
    }
    if ($missing.Count -gt 0) {
        throw "Missing symbols in .out: $($missing -join ', ')"
    }
    Write-Host "  OK: all $($symbols.Count) symbols resolved" -ForegroundColor Green

    Write-Host ''
    Write-Host 'PASS: LLVM mem-access functions link with TI C driver; all symbols resolved.' -ForegroundColor Green
    Write-Host '  (Runtime readback requires a C28x simulator or hardware.)'
}
finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
