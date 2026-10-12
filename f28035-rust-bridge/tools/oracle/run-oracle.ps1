# run-oracle.ps1 — PATH A（MIR 模式匹配，真机验证）作为 LLVM 后端正确性 oracle
#
# 对每个用例：
#   mir      : 用 dump-c28x-mir 重新生成参考汇编，与 golden 做规范化序列对比
#   ll       : 用 llc（若已构建）生成汇编/对象，做 contains 检查 + 对象字节检查
#   contract : 契约型用例，校验 fixture 与 checks 完整；后端落地后自动启用
#
# 用法:
#   powershell -File tools\oracle\run-oracle.ps1                      # 自动探测 llc
#   powershell -File tools\oracle\run-oracle.ps1 -Llc <llc.exe> -Objdump <llvm-objdump.exe>
#   powershell -File tools\oracle\run-oracle.ps1 -Strict             # ll 用例要求 golden 完全一致
param(
    [string]$Llc = '',
    [string]$Objdump = '',
    [string]$Cargo = 'C:\Users\61987\.cargo\bin\cargo.exe',
    [switch]$Strict
)

$ErrorActionPreference = 'Stop'

# UCRT forwarders must be on PATH or llc/llvm-objdump die with 0xC0000135 before
# printing anything, and every `ll` case reports FAIL for the wrong reason.
# Dot-sourcing also gives us Invoke-NativeCapture (raw rc/stdout/stderr).
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'llvm-c28x-env.ps1')

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$oracleDir = Join-Path $root 'tools\oracle'
$casesPath = Join-Path $oracleDir 'cases.json'
$cases = ([System.IO.File]::ReadAllText($casesPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json).cases

if (-not $Llc) {
    $cands = @(
        $C28xToolchain.Llc,
        'D:\c28x-toolchain\build-c28x-clang\bin\llc.exe',
        'D:\llvm-project-llvmorg-23.1.1\build-c28x\bin\llc.exe',
        (Join-Path $env:USERPROFILE 'llvm-project\build\bin\llc.exe'),
        (Join-Path $env:USERPROFILE 'llvm-project\build-c28x\bin\llc.exe')
    )
    $hit = $cands | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
    if ($hit) {
        $Llc = $hit
        $Objdump = $hit -replace 'llc\.exe$', 'llvm-objdump.exe'
    }
}
if (-not $Objdump -and $Llc) { $Objdump = $Llc -replace 'llc\.exe$', 'llvm-objdump.exe' }
$hasLlc = (-not [string]::IsNullOrWhiteSpace($Llc)) -and (Test-Path $Llc)

function Normalize-Asm([string]$path) {
    $out = @()
    foreach ($l in [System.IO.File]::ReadAllLines($path, [System.Text.Encoding]::UTF8)) {
        $t = $l
        $ci = $t.IndexOf(';')
        if ($ci -ge 0) { $t = $t.Substring(0, $ci) }
        $t = $t.Trim().ToLowerInvariant()
        if ($t -eq '') { continue }
        if ($t -match '^\.') { continue }                 # directives
        if ($t -match '^[a-z0-9_$.]+:$') { continue }     # labels
        $out += $t
    }
    return $out
}

function Test-Contains([string[]]$seq, [string[]]$checks) {
    $joined = $seq -join "`n"
    foreach ($c in $checks) {
        if ($joined -notmatch [regex]::Escape($c.ToLowerInvariant())) { return $false, $c }
    }
    return $true, ''
}

$passCount = 0; $failCount = 0; $skipCount = 0
$failDetails = @()

foreach ($case in $cases) {
    $id = $case.id
    $kind = $case.kind
    Write-Host "==> $id ($kind)" -ForegroundColor Cyan

    if ($kind -eq 'mir') {
        $src = Join-Path $root ($case.src -replace '/', '\')
        $golden = Join-Path $oracleDir ($case.golden -replace '/', '\')
        $tmpDir = Join-Path $env:TEMP ("c28x-oracle-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
        try {
            $asm = Join-Path $tmpDir 'case.asm'
            $mir = Join-Path $tmpDir 'case.mir.txt'
            & (Join-Path $root 'tools\dump-c28x-mir.ps1') -InputFile $src -OutputFile $mir -AssemblyFile $asm -Cargo $Cargo -RustcArguments '-Zmir-opt-level=4'
            if ($LASTEXITCODE -ne 0) { throw 'dump-c28x-mir failed' }
            $gen = Normalize-Asm $asm
            $ref = Normalize-Asm $golden
            $ok, $miss = Test-Contains $gen @($case.checks)
            if ($ok -and $gen.Count -eq $ref.Count) {
                $diff = @($null) * 0
                for ($i = 0; $i -lt $ref.Count; $i++) {
                    if ($gen[$i] -ne $ref[$i]) { $diff += "L$i golden: $($ref[$i])  generated: $($gen[$i])" }
                }
                if ($diff.Count -eq 0) {
                    Write-Host '  PASS: 序列与 golden 一致' -ForegroundColor Green
                    $passCount++
                } else {
                    Write-Host "  FAIL: 序列差异 $($diff.Count) 处" -ForegroundColor Red
                    $diff | Select-Object -First 10 | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
                    $failCount++; $failDetails += $id
                }
            } elseif (-not $ok) {
                Write-Host "  FAIL: checks 未全中 (miss: $miss)" -ForegroundColor Red
                $failCount++; $failDetails += $id
            } else {
                Write-Host "  FAIL: 序列行数与已验证 golden 不一致（golden=$($ref.Count) generated=$($gen.Count)）" -ForegroundColor Red
                Write-Host '    说明：当前 PATH A 输出与真机验证基线存在漂移。' -ForegroundColor Yellow
                Write-Host '    若源（rust-api/src/lib.rs）或驱动（c28x-mir）在真机验证后变更，' -ForegroundColor Yellow
                Write-Host '    需重新 flash+verify（tools\flash-and-verify-mir-control-loop.ps1）后才能更新 golden。' -ForegroundColor Yellow
                $max = [Math]::Max($ref.Count, $gen.Count)
                for ($i = 0; $i -lt $max; $i++) {
                    $gl = if ($i -lt $ref.Count) { $ref[$i] } else { '<none>' }
                    $dl = if ($i -lt $gen.Count) { $gen[$i] } else { '<none>' }
                    if ($gl -ne $dl) {
                        Write-Host "    L$i golden: $gl" -ForegroundColor Red
                        Write-Host "    L$i gen   : $dl" -ForegroundColor Red
                        $shown = 0; $shown++
                        if ($shown -ge 12) { break }
                    }
                }
                $failCount++; $failDetails += $id
            }
        } catch {
            Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red
            $failCount++; $failDetails += $id
        } finally {
            Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue
        }
        continue
    }

    if ($kind -eq 'll') {
        if (-not $hasLlc) {
            Write-Host '  SKIP: llc 未构建（先运行 tools\build-c28x-backend.ps1）；golden 已就绪' -ForegroundColor Yellow
            $skipCount++
            continue
        }
        $src = Join-Path $root ($case.src -replace '/', '\')
        $golden = Join-Path $oracleDir ($case.golden -replace '/', '\')
        $tmpDir = Join-Path $env:TEMP ("c28x-oracle-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
        try {
            $asm = Join-Path $tmpDir 'case.s'
            $asmRes = Invoke-Llc -Llc $Llc -Arguments @($src, '-o', $asm)
            if ($asmRes.ExitCode -ne 0) {
                throw "llc asm emission failed ($(Format-Rc $asmRes.ExitCode)): $($asmRes.StdErr.Trim())"
            }
            $gen = Normalize-Asm $asm
            $ok, $miss = Test-Contains $gen @($case.checks)
            $strictOk = $true
            if ($Strict -and $ok) {
                $ref = Normalize-Asm $golden
                if ($gen.Count -ne $ref.Count) { $strictOk = $false }
                else { for ($i = 0; $i -lt $ref.Count; $i++) { if ($gen[$i] -ne $ref[$i]) { $strictOk = $false; break } } }
            }
            $bytesOk = $true
            if ($case.objbytes) {
                $obj = Join-Path $tmpDir 'case.o'
                $objRes = Invoke-Llc -Llc $Llc -Arguments @('-filetype=obj', $src, '-o', $obj)
                if ($objRes.ExitCode -ne 0) {
                    throw "llc object emission failed ($(Format-Rc $objRes.ExitCode)): $($objRes.StdErr.Trim())"
                }
                $dump = Invoke-NativeCapture $Objdump @('-s', '-j', '.text', $obj)
                if ($dump.ExitCode -ne 0) {
                    throw "llvm-objdump failed ($(Format-Rc $dump.ExitCode)): $($dump.StdErr.Trim())"
                }
                $hex = ($dump.StdOut -replace '[^0-9a-fA-F]', '').ToLowerInvariant()
                $bytesOk = $hex.Contains($case.objbytes.ToLowerInvariant())
            }
            if ($ok -and $bytesOk -and $strictOk) {
                Write-Host '  PASS: checks + 字节回归通过' -ForegroundColor Green
                $passCount++
            } else {
                $why = @()
                if (-not $ok) { $why += "checks miss: $miss" }
                if (-not $bytesOk) { $why += "objbytes 不匹配" }
                if (-not $strictOk) { $why += 'Strict 模式 golden 不一致' }
                Write-Host "  FAIL: $($why -join '; ')" -ForegroundColor Red
                $failCount++; $failDetails += $id
            }
        } catch {
            Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red
            $failCount++; $failDetails += $id
        } finally {
            Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue
        }
        continue
    }

    if ($kind -eq 'contract') {
        $src = Join-Path $oracleDir ($case.src -replace '/', '\')
        $valid = (Test-Path $src) -and ($case.checks.Count -gt 0)
        if ($valid) {
            Write-Host '  CONTRACT: fixture 与 checks 就绪（后端落地后由同脚本自动启用）' -ForegroundColor DarkYellow
        } else {
            Write-Host '  FAIL: contract fixture 缺失或不完整' -ForegroundColor Red
            $failCount++; $failDetails += $id
        }
        continue
    }

    Write-Host "  FAIL: 未知 kind '$kind'" -ForegroundColor Red
    $failCount++; $failDetails += $id
}

Write-Host ''
Write-Host "ORACLE SUMMARY: pass=$passCount fail=$failCount skip=$skipCount"
if ($failDetails.Count -gt 0) {
    Write-Host "  failed: $($failDetails -join ', ')" -ForegroundColor Red
    exit 1
}
exit 0
