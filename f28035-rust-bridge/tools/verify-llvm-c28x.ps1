# verify-llvm-c28x.ps1 鈥?C28x 鍚庣 MC 灞傞獙璇侊紙Windows锛?#
# 妫€鏌ラ」锛堝绾?L1-2锛宒ocs/ABI_FREEZE.md锛夛細
#   1. llc / llvm-objdump 瀛樺湪锛宭lc 鍒楀嚭 c28x target
#   2. 姝ｅ悜锛氫竴缁?.ll 鐨勫璞?.text 瀛楄妭蹇呴』涓?TI oracle 閫愬瓧鑺備竴鑷?#   3. 璐熷悜锛氭棤娉曠紪鐮佺殑杈撳叆蹇呴』琚嫆缁濓紙fail-closed锛夛紝涓嶅緱闈欓粯鎴柇鍦板潃
#   4. asm 閫氶亾搴忓垪妫€鏌ワ細core-ops.ll锛圫UB/CMP/鍒嗘敮/璁垮瓨/璋冪敤/鏍堝抚锛?#      浠ュ強 frame.ll锛堢湡姝ｇ殑灞€閮ㄦ爤甯э細ADDB_SP / SUBB_SP锛?#
# 璐熷悜鐢ㄤ緥闄や簡鏍￠獙 fail-closed锛岃繕鏍￠獙鎷掔粷蹇呴』鏄?鏁呮剰鐨?report_fatal_error"锛?# 鑰屼笉鏄?assertion abort 鈥斺€?llc 瀵逛袱鑰呴€€鍑虹爜鍚屼负 0xC000001D锛屽彧鑳介潬 stderr 鍒ゅ埆銆?#
# 鐢ㄤ緥琛紙OBJBS 鍧囨潵鑷?TI asm2000 -v28 + dis2000 浜ゅ弶鏍稿锛岃 ABI_FREEZE.md锛夛細
#   hello.ll        ADD AL,@AR0 ; LRETR
#   const3.ll       MOVB AL,#3 ; LRETR
#   const255.ll     MOVB AL,#255 ; LRETR锛坕mm8 涓婅竟鐣岋級
#   branch.ll       鍗曟潯涓ゅ瓧鍒嗘敮 + 鐩爣 fixup
#   branch-multi.ll 鍚屼竴 fragment 鍐呬袱鏉″垎鏀紙鍥炲綊锛?applyFixup 鍙岄噸鍋忕Щ" bug锛?#   alu-acc.ll      绱姞鍣?dst 绾︽潫锛圓DD 鍙兘钀藉埌 AL/AH锛?#   mmio-const.ll   瑁?i32 甯搁噺鍦板潃锛坕nttoptr锛夎惤鎴?MOVL XARn,#22bit + 闂存帴瀛樺彇
#
# core-ops.ll 鍜?frame.ll 鐜板湪鐩存帴鐢熸垚瀵硅薄鏂囦欢锛涘墠鑰呰繕鏍搁獙绗﹀彿閲嶅畾浣嶃€?# 璐熷悜琛細mmio-oor.ll 鐨?22 浣嶅湴鍧€瓒婄晫蹇呴』鍦?ISel 闃舵琚嫆銆?#
# 鐢ㄦ硶:  powershell -File tools\verify-llvm-c28x.ps1 [-LlvmBin <dir>]
param(
    [string]$LlvmBin = ''
)

$ErrorActionPreference = 'Stop'

# UCRT forwarders + llvm-mingw runtime must be on PATH or every llc/objdump
# invocation dies with 0xC0000135 before printing anything useful.
. (Join-Path $PSScriptRoot 'llvm-c28x-env.ps1')

$root = Split-Path -Parent $PSScriptRoot
$codegen = Join-Path $root 'backend\llvm-c28x\test\CodeGen'

if ([string]::IsNullOrWhiteSpace($LlvmBin)) {
    $candidates = @(
        (Join-Path $C28xToolchain.Build 'bin'),
        'D:\c28x-toolchain\build-c28x-clang\bin',
        (Join-Path $env:USERPROFILE 'llvm-project\build\bin'),
        (Join-Path $env:USERPROFILE 'llvm-project\build-c28x\bin')
    )
    $LlvmBin = $candidates |
        Where-Object { $_ -and (Test-Path (Join-Path $_ 'llc.exe')) } |
        Select-Object -First 1
    if (-not $LlvmBin) { $LlvmBin = '' }
}
if ([string]::IsNullOrWhiteSpace($LlvmBin) -or -not (Test-Path (Join-Path $LlvmBin 'llc.exe'))) {
    throw "llc.exe not found. Run tools\sync-and-build-c28x.ps1 first, or pass -LlvmBin <dir>."
}

$llc = Join-Path $LlvmBin 'llc.exe'
$objdump = Join-Path $LlvmBin 'llvm-objdump.exe'
$tmp = Join-Path $env:TEMP ("c28x-verify-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null

$script:failures = @()

# ---------------------------------------------------------------------------
# Child processes
#
# All llc / llvm-objdump invocations go through Invoke-NativeCapture (defined in
# llvm-c28x-env.ps1, dot-sourced above). Never use `& $exe ... 2> $file` here:
# PowerShell writes the *formatted* ErrorRecord, hard-wrapped to the console
# width, which splits long diagnostics mid-word and makes every substring test
# fail. See the long comment in llvm-c28x-env.ps1.
# ---------------------------------------------------------------------------

function Assert-Text([string]$Path, [string]$Needle, [string]$What) {
    $text = Get-Content -Raw -LiteralPath $Path
    if ($text -notmatch $Needle) { throw "FAIL: $What 鈥?'$Needle' not found in $Path" }
    Write-Host "  OK: $What" -ForegroundColor Green
}

# Extract the hex column of `llvm-objdump -s -j .text` as one lowercase string.
# Only the section-content lines are parsed (the file header carries the temp
# path, which would otherwise leak hex-looking letters) and the ASCII rendering
# column is dropped (it can contain a-f letters for printable bytes).
# Layout of a content line: "<addr> <bytes...>   <ascii>" where the address and
# the first byte group are separated by a single space and the ASCII column is
# pushed out by two or more spaces.
function Get-TextHex([string]$ObjPath) {
    $res = Invoke-NativeCapture $objdump @('-s', '-j', '.text', $ObjPath)
    if ($res.ExitCode -ne 0) {
        throw "llvm-objdump failed ($(Format-Rc $res.ExitCode)) on $ObjPath`n$($res.StdErr.Trim())"
    }
    $hex = ''
    $inSection = $false
    foreach ($line in ($res.StdOut -split "`r?`n")) {
        if ($line -match 'Contents of section') { $inSection = $true; continue }
        if (-not $inSection) { continue }
        $head = ($line.TrimEnd() -split '\s{2,}')[0]
        $toks = @($head -split '\s+' | Where-Object { $_ -ne '' })
        if ($toks.Count -lt 2) { continue }
        $bytes = ($toks | Select-Object -Skip 1) -join ''
        if ($bytes -match '^[0-9a-fA-F]+$') { $hex += $bytes }
    }
    return $hex.ToLowerInvariant()
}

# Build one object and expect llc to REFUSE it, with a diagnostic matching one
# of the accepted substrings. A source that compiles here means the backend
# silently emitted bytes for something it has not verified.
function Test-Refused([string]$Name, [string[]]$Accept) {
    $src = Join-Path $codegen $Name
    $obj = Join-Path $tmp ("$Name.neg.o")
    $res = Invoke-NativeCapture $llc @('-mtriple=c28x-ti-none', '-mcpu=c28x',
                                       '-filetype=obj', $src, '-o', $obj)
    if ($res.ExitCode -eq 0) {
        $script:failures += "${Name}: object emission unexpectedly succeeded (expected a refusal)"
        return
    }
    # A refusal must be a *deliberate* report_fatal_error, never an assertion
    # abort. llc exits 0xC000001D for both, so the exit code cannot tell them
    # apart 鈥?only the message can. Caveat: report_fatal_error *also* prints
    # "PLEASE submit a bug report ... Stack dump: ...", so that string is
    # useless as a crash marker; "Assertion failed" is the real discriminator.
    # This is precisely how the "implicit operand" crash stayed hidden:
    # ADDB_SP/SUBB_SP and MOV_XAR7_AL carry TableGen Defs/Uses, so
    # getNumOperands() was never 1, and every function with a stack frame
    # aborted llc while all asm-only tests stayed green.
    if ($res.StdErr -cmatch 'Assertion failed') {
        $script:failures += ("${Name}: crashed with an assertion instead of refusing cleanly: " +
                             ($res.StdErr -split "`n" | Select-Object -First 1))
        return
    }
    # Whitespace-insensitive: the child may reflow the message and we do not
    # want the gate to hinge on where a line break lands.
    $flat = $res.StdErr -replace '\s', ''
    $hit = @($Accept | Where-Object { $flat -like ('*' + ($_ -replace '\s', '') + '*') })
    if ($hit.Count -eq 0) {
        $script:failures += ("${Name}: refusal did not mention any of [$($Accept -join ' | ')]; " +
                             "exit=$(Format-Rc $res.ExitCode); stderr: $($res.StdErr.Trim())")
        return
    }
    Write-Host "  OK: $Name refused ('$($hit[0])')" -ForegroundColor Green
}

# Build one object and compare its .text against the oracle byte string.
# A mismatch is recorded and reported at the end so one bad case does not hide
# the state of the others.
function Test-ObjBytes([string]$Name, [string]$Want, [string[]]$ExtraArgs = @()) {
    $src = Join-Path $codegen $Name
    $obj = Join-Path $tmp ("$Name.o")
    $res = Invoke-NativeCapture $llc (@('-mtriple=c28x-ti-none', '-mcpu=c28x', '-filetype=obj') +
                                     $ExtraArgs + @($src, '-o', $obj))
    if ($res.ExitCode -ne 0) {
        $script:failures += "${Name}: object emission failed ($(Format-Rc $res.ExitCode)): $($res.StdErr.Trim())"
        return
    }
    $got = Get-TextHex $obj
    if ($got -ne $Want) {
        $script:failures += "${Name}: .text = $got, want $Want"
        return
    }
    Write-Host "  OK: $Name -> $Want" -ForegroundColor Green
}

try {
    Write-Host '==> [1/4] Checking tools'
    if (-not (Test-Path $llc))     { throw "llc.exe not found at $llc" }
    if (-not (Test-Path $objdump)) { throw "llvm-objdump.exe not found at $objdump" }
    $ver = (Invoke-NativeCapture $llc @('--version')).StdOut
    if ($ver -match 'c28x') { Write-Host '  OK: llc lists c28x' -ForegroundColor Green }
    else                    { Write-Host '  WARN: llc --version does not list c28x (may still work)' -ForegroundColor Yellow }

    Write-Host '==> [2/4] Positive: object .text bytes must match the TI oracle'
    #                                                      expected .text bytes
    Test-ObjBytes 'hello.ll'        'a8940600'
    Test-ObjBytes 'const3.ll'       '039a0600'
    Test-ObjBytes 'const255.ll'     'ff9a0600'
    Test-ObjBytes 'branch.ll'       'a854e0ff0400019a0600009a0600'
    Test-ObjBytes 'branch-multi.ll' 'a854e0ff0800a892a454e0ff0600019a0600039a0600029a0600'
    Test-ObjBytes 'alu-acc.ll'      'bd1ea492a594a096be06a894a0940600a89ea4ce0600'
    Test-ObjBytes 'mmio-const.ll'   '008d4010a93a082952ffa9c5c7920600008d4010bd1ea93a082952ffa9c5be06c7960600'
    Test-ObjBytes 'core-ops.ll'     'a89e0600a854e0ff0400019a0600009a0600008d0000a93a082953ffa98ea93a082952ffa9c5c7920600008d0000a93a082953ffa98ebd1ea93a082952ffa9c5be06c796060040760000060001fead8081dfbd1ea9c3082953ffa9c5a78ebe06bd1ea93a082952ffa9c5be06c796a93a082952ffa9c5c79281fe0600'
    Test-ObjBytes 'frame.ll'        '01fead8081dfbd1ea9c3082953ffa9c5a78ebe06bd1ea93a082952ffa9c5be06c796019ba89481fe0600a096a22ba1280100a293a292a054e3ff0800a292a194a295a296effff8ffa8920600'
    # mem-access.ll: byte-array 2nd byte, i8 stack alloca, i32 store/load.
    # Guards the ABI L1-1 byte-address model: MOVB lane selection, odd-offset
    # frame index, and 32-bit store to adjacent words (PUSH/POP ACC + ADDB).
    Test-ObjBytes 'mem-access.ll'   '008d0000a93a082953ffa98ec03c0600008d0000a93a082953ffa98ec0c60600008d0000a93a082953ffa98ebd1ea93a0109a98ebe06c03c0600008d0000a93a082953ffa98ebd1ea93a0109a98ebe06c0c6060001fead8081dfbd1ea9c3083b53ffa9c5a78ebe06c03ca89481fe0600bd1e008d0400a93a082953ffa98ebe06bd1ebd1ea93a082952ffa9c5be06c79601dfc797be060600008d0400a93a082953ffa98ea93a082952ffa9c5c79201dfc7930600'

    $relocs = Invoke-NativeCapture $objdump @('-r', (Join-Path $tmp 'core-ops.ll.o'))
    if ($relocs.ExitCode -ne 0) { throw "llvm-objdump -r failed: $($relocs.StdErr)" }
    foreach ($symbol in @('word', 'callee')) {
        if ($relocs.StdOut -notmatch "(?m)^\s*[0-9a-f]+\s+\S+\s+$symbol\s*$") {
            $script:failures += "core-ops.ll: missing relocation for $symbol"
        }
    }

    Write-Host '==> [3/4] Negative: unverified / unencodable inputs must be refused'
    # Object emission has to fail loudly rather than silently writing wrong
    # bytes:
    #   mmio-oor.ll  uses a 2^24 word address, past the 22-bit field of
    #                MOVL XARn,#22bit. It must be rejected by the imm22 value
    #                predicate at ISel time, not truncated by the encoder into a
    #                pointer at some unrelated peripheral register.
    Test-Refused 'mmio-oor.ll' @('Cannot select')

    Write-Host '==> [4/4] core operations -> verified assembly'
    $coreAsm = Join-Path $tmp 'core-ops.s'
    $asmRes = Invoke-NativeCapture $llc @('-mtriple=c28x-ti-none', '-mcpu=c28x', '-verify-machineinstrs',
                                          (Join-Path $codegen 'core-ops.ll'), '-o', $coreAsm)
    if ($asmRes.ExitCode -ne 0) {
        throw ("core-ops.ll verified emission failed ($(Format-Rc $asmRes.ExitCode)):`n" +
               $asmRes.StdErr.Trim())
    }
    # 16-bit SUB/CMP must be emitted (not widened to 32-bit); the routed rhs
    # register is chosen post-RA (reserved AR7 scratch / AH), so wildcard it.
    Assert-Text $coreAsm 'sub al, (ar[0-7]|ah)' 'core-ops.s contains a 16-bit sub al'
    Assert-Text $coreAsm 'cmp al, (ar[0-7]|ah)' 'core-ops.s contains a 16-bit cmp al'
    foreach ($needle in @('movl xar0, #word',
                          'lcr callee', 'addb sp, #1', 'subb sp, #1')) {
        Assert-Text $coreAsm ([regex]::Escape($needle)) "core-ops.s contains $needle"
    }

    # Stack-frame path: a function owning an alloca must set up / tear down its
    # local frame while preserving AL across SP address materialization.
    $frameAsm = Join-Path $tmp 'frame.s'
    $frameRes = Invoke-NativeCapture $llc @('-mtriple=c28x-ti-none', '-mcpu=c28x',
                                            '-verify-machineinstrs',
                                            (Join-Path $codegen 'frame.ll'), '-o', $frameAsm)
    if ($frameRes.ExitCode -ne 0) {
        throw ("frame.ll verified emission failed ($(Format-Rc $frameRes.ExitCode)):`n" +
               $frameRes.StdErr.Trim())
    }
    foreach ($needle in @('addb sp, #', 'subb sp, #', 'movz ar7, sp', 'subb xar7, #1')) {
        Assert-Text $frameAsm ([regex]::Escape($needle)) "frame.s contains $needle"
    }

    # Memory-access model: byte lane, i8 stack, i32 adjacent words.
    $memAsm = Join-Path $tmp 'mem-access.s'
    $memRes = Invoke-NativeCapture $llc @('-mtriple=c28x-ti-none', '-mcpu=c28x',
                                           '-verify-machineinstrs',
                                           (Join-Path $codegen 'mem-access.ll'), '-o', $memAsm)
    if ($memRes.ExitCode -ne 0) {
        throw ("mem-access.ll verified emission failed ($(Format-Rc $memRes.ExitCode)):`n" +
               $memRes.StdErr.Trim())
    }
    foreach ($needle in @('movb *xar', 'movb al, *xar', 'push acc', 'pop acc',
                          'addb xar7, #1')) {
        Assert-Text $memAsm ([regex]::Escape($needle)) "mem-access.s contains $needle"
    }

    # Outgoing stack arguments must land at NEGATIVE offsets from the raised SP
    # (TI ABI: *-SP[k]), not above the allocation.  Guards the LowerCall signed
    # offset (w-StackWords) / STORE_STK16 expansion.
    $stkAsm = Join-Path $tmp 'stack-args-many.s'
    $stkRes = Invoke-NativeCapture $llc @('-mtriple=c28x-ti-none', '-mcpu=c28x',
                                           '-verify-machineinstrs',
                                           (Join-Path $codegen 'stack-args-many.ll'),
                                           '-o', $stkAsm)
    if ($stkRes.ExitCode -ne 0) {
        throw ("stack-args-many.ll verified emission failed ($(Format-Rc $stkRes.ExitCode)):`n" +
               $stkRes.StdErr.Trim())
    }
    Assert-Text $stkAsm 'addb sp, #2'        'stack-args-many.s allocates 2 words'
    Assert-Text $stkAsm 'subb xar7, #2'      'stack-args-many.s writes arg6 at SP-2'
    Assert-Text $stkAsm 'subb xar7, #1'      'stack-args-many.s writes arg7 at SP-1'
    Assert-Text $stkAsm 'subb sp, #2'        'stack-args-many.s releases the area'

    if ($script:failures.Count -gt 0) {
        Write-Host ''
        Write-Host "FAILED: $($script:failures.Count) object-byte mismatch(es)" -ForegroundColor Red
        $script:failures | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
        exit 1
    }
    Write-Host '==> MC layer self-check complete' -ForegroundColor Green
    exit 0
}
finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
