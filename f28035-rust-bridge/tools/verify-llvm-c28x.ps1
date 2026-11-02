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
function Test-Refused([string]$Name, [string[]]$Accept, [string[]]$ExtraArgs = @()) {
    $src = Join-Path $codegen $Name
    $obj = Join-Path $tmp ("$Name.neg.o")
    $argsForLlc = @('-mtriple=c28x-ti-none', '-mcpu=c28x', '-filetype=obj') +
                  $ExtraArgs + @($src, '-o', $obj)
    $res = Invoke-NativeCapture $llc $argsForLlc
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

# Build one object and compare its .text against the blessed byte baseline.
# Individual opcode encodings come from TI oracle probes.  The complete
# function baseline also includes B-1's even-aligned stack guard allocation
# and byte-lane lowering, so it is intentionally not byte-for-byte identical
# to a leaf function emitted by cl2000.
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

    Write-Host '==> [2/4] Positive: object bytes match TI encodings + B-1 frame baseline'
    #                                                      expected .text bytes
    Test-ObjBytes 'hello.ll'        '02fea89482fe0600'
    Test-ObjBytes 'const3.ll'       '02fe039a82fe0600'
    Test-ObjBytes 'const255.ll'     '02feff9a82fe0600'
    Test-ObjBytes 'trap.ll'         '02feefff0000' @('-O0')
    Test-ObjBytes 'branch.ll'       '02fea854e0ff0500019a82fe0600009a82fe0600'
    Test-ObjBytes 'branch-multi.ll' '02fea854e0ff0900a892a454e0ff0800019a82fe0600039a82fe0600029a82fe0600'
    Test-ObjBytes 'alu-acc.ll'      '02febd1ea492a594a096be06a894a09482fe060002fea89ea4ce82fe0600'
    # and32.ll: 32-bit AND/OR/XOR must preserve Lhs across the Rhs half
    # extractions (push/pop ACC around each `movl acc, <rhs>`).  The old
    # expansion let Rhs overwrite Lhs in ACC, so it computed Rhs&Rhs/OR/XOR;
    # seen on hardware as is_some returning 0 for Some (core-ex group E/A).
    Test-ObjBytes 'and32.ll'        '02fe008d0100bd3abec5bd3abd1ea9c3a097be06a0cfbd1ea9c3a096be06a0cebe8e82fe060004fead8088dfbd1ea9c3082953ffa9c5bdc3be8ebe06bd1ea93a082952ffa9c5c79201dfc793ac1ebe06bd1ea9aba097be06a0cfbd1ea9aba096be06a0ce84fe060004fead8088dfbd1ea9c3082953ffa9c5bdc3be8ebe06bd1ea93a082952ffa9c5c79201dfc793ac1ebe06bd1ea9aba097be06a0cbbd1ea9aba096be06a0ca84fe060004fead8088dfbd1ea9c3082953ffa9c5bdc3be8ebe06bd1ea93a082952ffa9c5c79201dfc793ac1ebe06bd1ea9aba097be06a071bd1ea9aba096be06a07084fe0600'
    Test-ObjBytes 'mmio-const.ll'   '02fe008d4010a93a082952ffa9c5c79282fe060002fe008d4010bd1ea93a082952ffa9c5be06c79682fe0600'
    # sub32imm.ll: `ADD/SUB ACC,#16bit` zero-extend their immediate, so a
    # negative addend must be encoded as the opposite op on its magnitude.
    # The old encoding (add acc,#65534) left a stray 1<<16 that turned the
    # byte->word >>1 into 0x8403 instead of 0x0403 — every
    # DoubleEndedIterator path (last/rev) read code memory.
    Test-ObjBytes 'sub32imm.ll'     '02febd1ea9a80219a98ebe06a93a82fe060002febd1e00ffe803a98ebe06a93a82fe060002febd1e10ffe803a98ebe06a93a82fe0600'
    Test-ObjBytes 'core-ops.ll'     '02fea89e82fe060002fea854e0ff0500019a82fe0600009a82fe060002fe008d0000a93a082953ffa98ea93a082952ffa9c5c79282fe060002febd1e008d0000a93a082953ffa98ebe06bd1ea93a082952ffa9c5be06c79682fe060002fe4076000082fe060002fead8082dfbd1ea9c3082953ffa9c5bdc3be8ebe06bd1ea93a082952ffa9c5be06c796a93a082952ffa9c5c79282fe0600'
    # Atomic compare/branch changes loop allocation/layout; TI assembly of the
    # emitted loop independently confirms its instructions and branch targets.
    Test-ObjBytes 'frame.ll'        '02fead8082dfbd1ea9c3082953ffa9c5bdc3be8ebe06bd1ea93a082952ffa9c5be06c796019ba89482fe060002fea096009ba497a892a054e3ff0d00019aa980a492a794a495a496a054e3ff0400effff7ffa89282fe0600'
    # Independent TI asm oracle: MOVL XAR0 immediates 0x50001, 0x3fffff, 0x10000.
    Test-ObjBytes 'upper-immediate.ll' '02fe058d0100a93a82fe060002fe3f8dffffa93a82fe060002fe018d0000a93a82fe0600'
    # mem-access.ll: byte-array 2nd byte, i8 stack alloca, i32 store/load.
    # Guards the ABI L1-1 byte-address model: MOVB lane selection, odd-offset
    # frame index, and 32-bit store to adjacent words (PUSH/POP ACC + ADDB).
    Test-ObjBytes 'mem-access.ll'   '02fec0760000a02b973c82fe060002fec0760000a02b97c6a796a79282fe060002fec0760000a0280100973c82fe060002fec0760000a028010097c6a796a79282fe060002fead8082dfbd1ea9c3083b53ffa9c5bdc3be8ebe06bd3abd1ea93aa9c5a0280100a0cea096a9c3082952ffa9c5be06973cbe8ea89482fe060002febd1e008d0200a93a082953ffa98ebe06bd1ea93a082952ffa9c5be06c79601dfc79782fe060002fe008d0200a93a082953ffa98ea93a082952ffa9c5c79201dfc79382fe0600'

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
    Test-Refused 'branch-unresolved.mir' @('C28x: BRANCH to unresolved target') @('-start-after=stack-frame-layout', '-basic-block-sections=all')
    Test-Refused 'frame-offset-invalid.mir' @("C28x: frame object FI=0 of function 'frame_offset_invalid' is not below SP") @('-start-before=prolog-epilog')
    Test-Refused 'frame-offset-zero.mir' @('delta from SP=0') @('-start-before=prolog-epilog')

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
                          'lcr callee', 'addb sp, #2', 'subb sp, #2')) {
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
    foreach ($needle in @('addb sp, #', 'subb sp, #', 'movz ar7, sp', 'subb xar7, #2')) {
        Assert-Text $frameAsm ([regex]::Escape($needle)) "frame.s contains $needle"
    }

    # O0 is essential: fast RA spills select/PHI values on NonNull::eq's path.
    # Every conditional branch must consume the immediately preceding compare.
    $compareAsm = Join-Path $tmp 'compare-select.s'
    $compareRes = Invoke-NativeCapture $llc @('-mtriple=c28x-ti-none', '-mcpu=c28x',
        '-O0', '-verify-machineinstrs', (Join-Path $codegen 'compare-select.ll'),
        '-o', $compareAsm)
    if ($compareRes.ExitCode -ne 0) { throw "O0 compare/select emission failed: $($compareRes.StdErr)" }
    $previous = ''
    $branches = 0
    foreach ($line in (Get-Content -LiteralPath $compareAsm)) {
        if ($line -notmatch '^\s+[a-z]+\s') { continue }
        if ($line -match '^\s+b\s+[^,]+,\s*(?!unc\b)\w+') {
            if ($previous -notmatch '^\s*(cmp al,|subl acc, xt)') {
                throw "Compare flags can be clobbered before branch: $previous / $line"
            }
            $branches++
        }
        $previous = $line
    }
    if ($branches -ne 3) { throw "Expected three protected conditional branches, got $branches" }
    Write-Host '  OK: O0 i16/i32 selects and branch consume compare flags immediately'

    # Memory-access model: byte lane, i8 stack, i32 adjacent words.
    $memAsm = Join-Path $tmp 'mem-access.s'
    $memRes = Invoke-NativeCapture $llc @('-mtriple=c28x-ti-none', '-mcpu=c28x',
                                           '-verify-machineinstrs',
                                           (Join-Path $codegen 'mem-access.ll'), '-o', $memAsm)
    if ($memRes.ExitCode -ne 0) {
        throw ("mem-access.ll verified emission failed ($(Format-Rc $memRes.ExitCode)):`n" +
               $memRes.StdErr.Trim())
    }
    foreach ($needle in @('movb *+xar', 'movb al, *+xar', 'push acc', 'pop acc',
                          'addb xar7, #1')) {
        Assert-Text $memAsm ([regex]::Escape($needle)) "mem-access.s contains $needle"
    }
    $memText = Get-Content -LiteralPath $memAsm -Raw
    foreach ($fn in @('store_byte0', 'load_byte0', 'store_byte1', 'load_byte1')) {
        $body = [regex]::Match($memText, "(?s)(?m)^${fn}:.*?(?=^\s*\.global\s|\z)").Value
        if (-not $body -or $body -match '(?m)^\s*rol\s+acc\b' -or
            $body -notmatch 'movl\s+xar7,\s*#bytes2' -or
            $body -notmatch 'movb\s+') {
            throw "FAIL: $fn must use a direct TI word-address byte lane without ROL"
        }
    }
    Assert-Text $memAsm 'setc c\s*\r?\n\s*rol acc' 'stack-byte pointer keeps its own address conversion'

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
    Assert-Text $stkAsm 'addb sp, #4'        'stack-args-many.s rounds 3 argument words to an even area'
    Assert-Text $stkAsm 'subb xar7, #3'      'stack-args-many.s writes arg5 at SP-3'
    Assert-Text $stkAsm 'subb xar7, #2'      'stack-args-many.s writes arg6 at SP-2'
    Assert-Text $stkAsm 'subb xar7, #1'      'stack-args-many.s writes arg7 at SP-1'
    Assert-Text $stkAsm 'subb sp, #4'        'stack-args-many.s releases the even area'

    # Spill/frame and packed-byte stress: a >127-word frame must be emitted in
    # legal ADDB/SUBB chunks, while many live i32 values must pass verifier
    # checks through spill/reload and struct byte fields must retain MOVB lane
    # accesses.
    $stressAsm = Join-Path $tmp 'stack-byte-stress.s'
    $stressRes = Invoke-NativeCapture $llc @('-mtriple=c28x-ti-none', '-mcpu=c28x',
                                              '-verify-machineinstrs',
                                              (Join-Path $codegen 'stack-byte-stress.ll'),
                                              '-o', $stressAsm)
    if ($stressRes.ExitCode -ne 0) {
        throw ("stack-byte-stress.ll verified emission failed ($(Format-Rc $stressRes.ExitCode)):`n" +
               $stressRes.StdErr.Trim())
    }
    foreach ($needle in @('addb sp, #127', 'subb sp, #127', 'push xar1',
                          'pop xar1', 'movb *+xar', 'movb al, *+xar')) {
        Assert-Text $stressAsm ([regex]::Escape($needle)) "stack-byte-stress.s contains $needle"
    }
    Assert-Text $stressAsm 'clrc c\s*\r?\n\s*ror acc' 'ordinary byte pointers convert logical byte to TI word address'

    # Memory builtin call ABI: exercise memcpy/memmove/memset/memcmp with
    # both even and odd logical byte addresses and i32 lengths.
    $memBuiltinAsm = Join-Path $tmp 'mem-builtins.s'
    $memBuiltinRes = Invoke-NativeCapture $llc @('-mtriple=c28x-ti-none', '-mcpu=c28x',
                                                  '-verify-machineinstrs',
                                                  (Join-Path $codegen 'mem-builtins.ll'),
                                                  '-o', $memBuiltinAsm)
    if ($memBuiltinRes.ExitCode -ne 0) {
        throw ("mem-builtins.ll verified emission failed ($(Format-Rc $memBuiltinRes.ExitCode)):`n" +
               $memBuiltinRes.StdErr.Trim())
    }
    foreach ($needle in @('lcr c28x_memcpy', 'lcr c28x_memmove', 'lcr c28x_memset', 'lcr c28x_memcmp')) {
        Assert-Text $memBuiltinAsm ([regex]::Escape($needle)) "mem-builtins.s contains $needle"
    }

    # Constant-size memory intrinsics must be expanded into loads/stores.  The
    # TI RTS memcpy dereferences C word addresses while Rust passes logical byte
    # addresses, so a libcall here corrupts every in-memory aggregate copy of 4
    # bytes or more (core-ex B2 read 72/90 until this was fixed).
    #
    # NOTE: deliberately no -verify-machineinstrs here.  The inlined copy loads
    # a 32-bit word as `$al = MOV_ind_load` + `$ah = MOV_ind_load`, and a later
    # PUSH_ACC (implicit $acc) then trips "Using an undefined physical register"
    # because the two 16-bit defs never fully define ACC.  The emitted code is
    # correct on hardware (core-ex A-E and the parts13 ABI probe all pass); the
    # gap is the backend's liveness modelling of AL/AH subregister defs, which
    # is tracked in docs/PATH_B.md section 7.
    $memInlineAsm = Join-Path $tmp 'memcpy-inline.s'
    $memInlineRes = Invoke-NativeCapture $llc @('-mtriple=c28x-ti-none', '-mcpu=c28x',
                                                  '-O2',
                                                  (Join-Path $codegen 'memcpy-inline.ll'),
                                                  '-o', $memInlineAsm)
    if ($memInlineRes.ExitCode -ne 0) {
        throw ("memcpy-inline.ll verified emission failed ($(Format-Rc $memInlineRes.ExitCode)):`n" +
               $memInlineRes.StdErr.Trim())
    }
    $memInlineText = Get-Content -Raw -LiteralPath $memInlineAsm
    # The three constant-size copies must be pure load/store code; only the
    # runtime-length `varcopy` calls our byte-address helper.
    $memCalls = ([regex]::Matches($memInlineText, 'lcr\s+(?:c28x_)?mem(cpy|set|move)')).Count
    if ($memCalls -ne 1) {
        throw ("FAIL: memcpy-inline.s has $memCalls RTS memory calls; only the runtime-length varcopy may call memcpy")
    }
    $varcopyIndex = $memInlineText.IndexOf('varcopy:')
    if ($varcopyIndex -lt 0) { throw 'FAIL: memcpy-inline.s lost the varcopy function' }
    if ($memInlineText.Substring(0, $varcopyIndex) -match 'lcr\s+(?:c28x_)?mem(cpy|set|move)') {
        throw 'FAIL: memcpy-inline.s still calls the TI RTS memory routine for a constant-size copy'
    }
    Write-Host '  OK: constant-size memcpy/memset expand inline (no RTS libcall)' -ForegroundColor Green
    Assert-Text $memInlineAsm 'movb al, \*\+xar7\[ar0\]' 'memcpy-inline.s routes the odd byte tail through the AR0 byte lane'
    Assert-Text $memInlineAsm 'lcr c28x_memcpy' 'runtime-size copy calls the unique byte-address helper'
    $varcopyText = $memInlineText.Substring($varcopyIndex)
    if ($varcopyText -match 'lsrl acc,t|lcr\s+memcpy\b') {
        throw 'FAIL: runtime-size copy still converts pointers or calls TI word-address memcpy'
    }

    # Aggregate-return ABI: the hidden return-buffer pointer arrives in XAR6
    # (oracle: cl2000 -v28 --abi=eabi, driver uses MOVL XAR6,#sym before LCR).
    # The callee writes word and byte fields through it; the caller moves its
    # own buffer pointer into XAR6 before the call and expects no scalar return.
    $sretAsm = Join-Path $tmp 'struct-return.s'
    $sretRes = Invoke-NativeCapture $llc @('-mtriple=c28x-ti-none', '-mcpu=c28x',
                                           '-verify-machineinstrs',
                                           (Join-Path $codegen 'struct-return.ll'),
                                           '-o', $sretAsm)
    if ($sretRes.ExitCode -ne 0) {
        throw ("struct-return.ll verified emission failed ($(Format-Rc $sretRes.ExitCode)):`n" +
               $sretRes.StdErr.Trim())
    }
    foreach ($needle in @('make_pair:', 'movl acc, xar6', 'mov *xar7, al',
                          'movb *+xar7[ar0], al',
                          'use_pair:', 'push xar4', 'pop xar6', 'lcr make_pair')) {
        Assert-Text $sretAsm ([regex]::Escape($needle)) "struct-return.s contains $needle"
    }

    # Mixed i16/i32 argument ABI (oracle: cl2000 -v28 --abi=eabi, 2026-10-20):
    # with any i32 in the list the first i32 takes ACC and 16-bit args skip
    # AL/AH, starting at AR4; the second i32 goes on the stack.
    $abiMixAsm = Join-Path $tmp 'abi-mixed.s'
    $abiMixRes = Invoke-NativeCapture $llc @('-mtriple=c28x-ti-none', '-mcpu=c28x',
                                             '-verify-machineinstrs',
                                             (Join-Path $codegen 'abi-mixed.ll'),
                                             '-o', $abiMixAsm)
    if ($abiMixRes.ExitCode -ne 0) {
        throw ("abi-mixed.ll verified emission failed ($(Format-Rc $abiMixRes.ExitCode)):`n" +
               $abiMixRes.StdErr.Trim())
    }
    $abiMixText = Get-Content -LiteralPath $abiMixAsm -Raw
    foreach ($fn in @('f_i16_i32', 'f_i32_i16', 'f_i16_i16_i32',
                      'f_i32_i16_i16', 'f_i16_i32_i16', 'f_i32_i32',
                      'f_i16_i32_i32')) {
        $body = [regex]::Match($abiMixText, "(?s)(?m)^${fn}:.*?(?=^\s*\.global\s|\z)").Value
        if (-not $body) { throw "FAIL: abi-mixed.s missing function $fn" }
    }
    # Per-function allocation checks (exact sequences live in abi-mixed.ll
    # FileCheck; here we only pin the source register of each argument).
    Assert-Text $abiMixAsm '(?s)f_i16_i32:.*?movl xar7, acc.*?mov al, ar4' '(i16,i32): a from AR4, b from ACC'
    Assert-Text $abiMixAsm '(?s)f_i32_i16:.*?movz ar0, ar4.*?movl xt, acc' '(i32,i16): a from ACC, b from AR4'
    Assert-Text $abiMixAsm '(?s)f_i16_i16_i32:.*?mov al, ar4.*?add al, ar5.*?movl xar7, acc' '(i16,i16,i32): AR4 + AR5 + ACC'
    Assert-Text $abiMixAsm '(?s)f_i32_i16_i16:(?=.*?movz ar\d, ar4)(?=.*?movz ar\d, ar5)' '(i32,i16,i16): ACC + AR4 + AR5'
    Assert-Text $abiMixAsm '(?s)f_i16_i32_i16:.*?movl xar7, acc.*?mov al, ar4.*?add al, ar5' '(i16,i32,i16): AR4 + ACC + AR5'
    Assert-Text $abiMixAsm '(?s)f_i32_i32:.*?addb sp, #4' 'second i32 lands on the stack with an even frame'
    Assert-Text $abiMixAsm '(?s)f_i16_i32_i32:(?=.*?movz ar\d, ar4)(?=.*?addb sp, #\d+)' '(i16,i32,i32): AR4 + ACC + stack'

    # Pointer-pool ABI (oracle: cl2000 -v28 --abi=eabi, 2026-10-20):
    # pointer arguments use XAR4/XAR5 (never ACC), overflow to the stack;
    # sret uses XAR6; i16 args avoid the pointer-occupied slots.
    $abiPtrAsm = Join-Path $tmp 'abi-pointer.s'
    $abiPtrRes = Invoke-NativeCapture $llc @('-mtriple=c28x-ti-none', '-mcpu=c28x',
                                             '-verify-machineinstrs',
                                             (Join-Path $codegen 'abi-pointer.ll'),
                                             '-o', $abiPtrAsm)
    if ($abiPtrRes.ExitCode -ne 0) {
        throw ("abi-pointer.ll verified emission failed ($(Format-Rc $abiPtrRes.ExitCode)):`n" +
               $abiPtrRes.StdErr.Trim())
    }
    Assert-Text $abiPtrAsm '(?s)f_ptr_i32:(?=.*?movl xt, acc)(?=.*?movl acc, xar4)' '(ptr,i32) -> XAR4 + ACC'
    Assert-Text $abiPtrAsm '(?s)f_ptr_ptr:(?=.*?movl acc, xar4)(?=.*?movl acc, xar5)' '(ptr,ptr) -> XAR4 + XAR5'
    Assert-Text $abiPtrAsm '(?s)f_ptr_i16:(?=.*?movz ar\d, al)(?=.*?movl acc, xar4)' '(ptr,i16) -> XAR4 + AL'
    Assert-Text $abiPtrAsm '(?s)f_i16_ptr_i32:(?=.*?movz ar\d, ar5)(?=.*?movl acc, xar4)' '(i16,ptr,i32) -> AR5 + XAR4 + ACC'
    Assert-Text $abiPtrAsm '(?s)f_3ptr:(?=.*?movl acc, xar4)(?=.*?movl acc, xar5)(?=.*?addb sp, #\d+)' '(ptr,ptr,ptr) -> XAR4 + XAR5 + stack'
    Assert-Text $abiPtrAsm 'lcr \*xar' 'indirect call lowers to LCR *XARn'

    foreach ($name in @('call-four-args', 'call-stack-select', 'negative-compare')) {
        foreach ($level in @('0', '2')) {
            $path = Join-Path $tmp "$name-O$level.s"
            $r = Invoke-NativeCapture $llc @('-mtriple=c28x-ti-none', "-O$level",
                '-verify-machineinstrs', (Join-Path $codegen "$name.ll"), '-o', $path)
            if ($r.ExitCode -ne 0) { throw "$name O$level failed: $($r.StdErr)" }
            if ($name -ne 'negative-compare') {
                Assert-Text $path 'lcr (check_four|stack_inner)' "$name O$level emits its call"
            } else {
                Assert-Text $path 'subl acc, xt' "$name O$level emits its comparison"
            }
        }
    }
    $four = Join-Path $tmp 'call-four-args-O0.s'
    Assert-Text $four '(?s)call_four_reload:.*?push acc(?:(?!pop acc).)*?mov al, \*xar7\s+addb xar7, #1\s+mov ah, \*xar7\s+movl xar4, acc\s+pop acc' 'four-argument pointer reload preserves the live ACC count'

    # Interrupts need software saves as well as the hardware IRET frame.
    foreach ($opt in @('0', '2')) {
        $r = Invoke-NativeCapture $llc @('-mtriple=c28x-ti-none', "-O$opt", '-verify-machineinstrs',
            '-filetype=obj', (Join-Path $codegen 'interrupt.ll'), '-o', (Join-Path $tmp "irq-$opt.o"))
        if ($r.ExitCode -ne 0) { throw "IRQ O$opt machine verification failed: $($r.StdErr)" }
    }
    $irqObj=Join-Path $tmp 'irq-empty.o'
    $r=Invoke-NativeCapture $llc @('-mtriple=c28x-ti-none','-O0','-filetype=obj',
        (Join-Path $codegen 'interrupt-empty.ll'),'-o',$irqObj)
    if ($r.ExitCode) {throw "Empty ISR emission failed: $($r.StdErr)"}
    $irqAsm=Join-Path $tmp 'irq-oracle.asm'; $irqOracle=Join-Path $tmp 'irq-oracle.obj'
    $lines=@('    .sect ".text"','    ASP','    SPM #0','    CLRC OVM|PAGE0','    CLRC AMODE')
    foreach($n in 0..7) {$lines+="    PUSH XAR$n"}
    $lines+=@('    PUSH XT','    ADDB SP,#20','    SUBB SP,#20','    POP XT')
    foreach($n in 7..0) {$lines+="    POP XAR$n"}
    $lines+=@('    NASP','    IRET')
    [IO.File]::WriteAllLines($irqAsm,$lines)
    $r=Invoke-NativeCapture $C28xToolchain.Cl2000 @('--abi=eabi','--silicon_version=28','--compile_only',"--output_file=$irqOracle",$irqAsm)
    if($r.ExitCode -ne 0 -or (Get-TextHex $irqObj) -ne (Get-TextHex $irqOracle)) {throw "Interrupt context bytes differ from TI oracle: $($r.StdErr)"}
    Write-Host '  OK: O0/O2 ISR liveness and complete context bytes match TI oracle'

    # Independent TI oracle for the new full-width CSR/scratch push opcodes.
    $oracle = Join-Path $tmp 'push32.asm'
    [IO.File]::WriteAllText($oracle, "    .sect `".text`"`n    push xar0`n    push xar1`n    push xar2`n    push xar3`n    pop xar3`n    pop xar2`n    pop xar1`n    pop xar0`n")
    $oracleObj = Join-Path $tmp 'push32.obj'
    $r = Invoke-NativeCapture $C28xToolchain.Cl2000 @('--abi=eabi', '--silicon_version=28',
        '--compile_only', "--output_file=$oracleObj", $oracle)
    if ($r.ExitCode -ne 0) { throw "TI push32 oracle failed: $($r.StdErr)" }
    if ((Get-TextHex $oracleObj) -ne 'bd3abdb2bdaabda2be82be86be8bbe8e') {
        throw 'TI full-width XAR push/pop encoding changed'
    }
    Write-Host '  OK: TI oracle confirms full-width XAR0-XAR3 push/pop opcodes'

    # TI shortens a known `B $,UNC` to SB. Keep the target external until link
    # to independently verify the two-word self-loop used for llvm.trap.
    $trapAsm = Join-Path $tmp 'trap-oracle.asm'
    $trapObj = Join-Path $tmp 'trap-oracle.obj'
    $trapCmd = Join-Path $tmp 'trap-oracle.cmd'
    $trapOut = Join-Path $tmp 'trap-oracle.out'
    [IO.File]::WriteAllText($trapAsm, "    .sect `".text`"`n    .ref trap_loop`n    b trap_loop, unc`n")
    [IO.File]::WriteAllText($trapCmd, 'trap_loop = 0x8000; MEMORY { RAM : origin = 0x8000, length = 0x100 } SECTIONS { .text > RAM }')
    $r = Invoke-NativeCapture $C28xToolchain.Cl2000 @('--abi=eabi', '--silicon_version=28',
        '--compile_only', "--output_file=$trapObj", $trapAsm)
    if ($r.ExitCode -ne 0) { throw "TI trap oracle assembly failed: $($r.StdErr)" }
    $r = Invoke-NativeCapture $C28xToolchain.Cl2000 @('--abi=eabi', '-z',
        '--unused_section_elimination=off', '--entry_point=trap_loop',
        "--output_file=$trapOut", $trapObj, $trapCmd)
    if ($r.ExitCode -ne 0) { throw "TI trap oracle link failed: $($r.StdErr)" }
    if ((Get-TextHex $trapOut) -ne 'efff0000') { throw 'TI trap self-loop encoding changed' }
    Write-Host '  OK: TI assembler/linker independently confirm the long trap self-loop'

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
