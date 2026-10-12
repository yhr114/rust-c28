# llvm-c28x-env.ps1
#
# Dot-source this before running llc.exe / llvm-objdump.exe from the C28x build.
#
# Why: the C28x llc/llvm-objdump binaries are MinGW/UCRT builds that import the
# api-ms-win-crt-* forwarder DLLs. On this machine the forwarders are NOT in
# C:\Windows\System32 (only ucrtbase.dll is), so a plain shell fails with
#   "error while loading shared libraries: api-ms-win-crt-time-l1-1-0.dll"
# (exit 0xC0000135 / -1073741515). The Windows SDK redist directory provides
# them, and the vendor LLVM helper `add_llvm_tool_symlink`-style wrappers are not
# used here, so we prepend it ourselves.
#
# Usage:
#   . $PSScriptRoot\llvm-c28x-env.ps1
#   & $C28xToolchain.Llc -mtriple=c28x-ti-none -mcpu=c28x -filetype=obj in.ll -o out.o

$C28xRoot = 'D:\c28x-toolchain'

# UCRT forwarders (api-ms-win-crt-*.dll). Prefer the arch-specific redist copied
# next to the SDK version, fall back to the generic redist folder.
$ucrtCandidates = @(
    'C:\Program Files (x86)\Windows Kits\10\Redist\ucrt\DLLs\x64',
    'C:\Program Files (x86)\Windows Kits\10\Redist\10.0.26100.0\ucrt\DLLs\x64'
)
foreach ($dir in $ucrtCandidates) {
    if (Test-Path (Join-Path $dir 'api-ms-win-crt-time-l1-1-0.dll')) {
        $env:PATH = "$dir;$env:PATH"
        break
    }
}

# llvm-mingw host runtime (libc++ / libunwind / winpthread as needed).
$mingwBin = Join-Path $C28xRoot 'llvm-mingw\llvm-mingw-20260602-ucrt-x86_64\bin'
if (Test-Path $mingwBin) { $env:PATH = "$mingwBin;$env:PATH" }

# Vendor (TI) toolchain: asm2000 / dis2000 / ofd2000 / cl2000.
$tiBin = 'C:\ti\ccs2101\ccs\tools\compiler\ti-cgt-c2000_25.11.1.LTS\bin'
if (Test-Path $tiBin) { $env:PATH = "$tiBin;$env:PATH" }

$C28xToolchain = [pscustomobject]@{
    Root    = $C28xRoot
    Build   = Join-Path $C28xRoot 'build-c28x-clang'
    Llc     = Join-Path $C28xRoot 'build-c28x-clang\bin\llc.exe'
    Objdump = Join-Path $C28xRoot 'build-c28x-clang\bin\llvm-objdump.exe'
    Asm2000 = Join-Path $tiBin 'asm2000.exe'
    Dis2000 = Join-Path $tiBin 'dis2000.exe'
    Cl2000  = Join-Path $tiBin 'cl2000.exe'
    Ofd2000 = Join-Path $tiBin 'ofd2000.exe'
    Ninja   = 'E:\Qt\Tools\Ninja\ninja.exe'
    LlvmSrc = Join-Path $C28xRoot 'llvm-project-23.1.1.src'
    SrcTree = Join-Path $C28xRoot 'llvm-project-23.1.1.src\llvm\lib\Target\C28x'
}

# Quick sanity check so callers get a clear message instead of 0xC0000135.
if (-not (Test-Path $C28xToolchain.Llc)) {
    Write-Warning "llc.exe not found at $($C28xToolchain.Llc)"
}

#===------------------------------------------------------------------------===#
# Native-process helpers
#
# NEVER capture a native command's stderr with `& $exe ... 2> $file`.
#
# PowerShell converts each stderr line into an ErrorRecord, and `2>` writes the
# *formatted* record back out: prefixed with the exe name, decorated with the
# localized "所在位置 ... / At line ..." context block, given a BOM, and
# **hard-wrapped to the console width** (80 columns in a non-interactive host).
#
# That wrap destroys diagnostic matching. The C28x fail-closed message
#   "...needs an absolute relocation..."
# comes back as
#   llc.exe : LLVM ERROR: ... needs an absolu<CR><LF>te relocation, ...
# so the CRLF lands *inside a word* and no substring or \s+ regex can match it.
#
# Running the child through System.Diagnostics.Process with redirected streams
# returns the untouched bytes. Use Invoke-NativeCapture for everything.
#===------------------------------------------------------------------------===#

# Windows CRT command-line quoting (the rules CommandLineToArgvW parses with).
# ProcessStartInfo.Arguments is a single string, so each argv element has to be
# quoted by hand.
function Quote-CmdArg([string]$Value) {
    if ($Value.Length -eq 0) { return '""' }
    if ($Value -notmatch '[\s"]') { return $Value }
    $sb = New-Object System.Text.StringBuilder
    $null = $sb.Append('"')
    $backslashes = 0
    foreach ($ch in $Value.ToCharArray()) {
        if ($ch -eq '\') { $backslashes++; continue }
        if ($ch -eq '"') {
            # 2n+1 backslashes emit n backslashes then a literal quote.
            $null = $sb.Append('\', ($backslashes * 2) + 1)
            $null = $sb.Append('"')
            $backslashes = 0
            continue
        }
        if ($backslashes -gt 0) { $null = $sb.Append('\', $backslashes); $backslashes = 0 }
        $null = $sb.Append($ch)
    }
    # Trailing backslashes must be doubled or they escape the closing quote.
    if ($backslashes -gt 0) { $null = $sb.Append('\', $backslashes * 2) }
    $null = $sb.Append('"')
    return $sb.ToString()
}

# Run $Exe and return @{ ExitCode; StdOut; StdErr } with both streams raw.
function Invoke-NativeCapture {
    param([string]$Exe, [string[]]$Arguments = @())
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe
    $psi.Arguments = (($Arguments | ForEach-Object { Quote-CmdArg ([string]$_) }) -join ' ')
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    $null = $proc.Start()
    # Drain stderr on a worker thread: reading one pipe to completion before the
    # other deadlocks as soon as the child fills the unread pipe's buffer.
    $errTask = $proc.StandardError.ReadToEndAsync()
    $out = $proc.StandardOutput.ReadToEnd()
    $err = $errTask.GetAwaiter().GetResult()
    $proc.WaitForExit()
    $rc = $proc.ExitCode
    $proc.Dispose()
    return [pscustomobject]@{ ExitCode = $rc; StdOut = $out; StdErr = $err }
}

# A crashing LLVM tool exits with an NTSTATUS (e.g. 0xC000001D for abort), which
# reads as a large negative int. "0x........" is the only sane rendering.
function Format-Rc([int]$Code) { return ('0x{0:X8}' -f $Code) }

# llc with the C28x triple already filled in.
function Invoke-Llc {
    param([string[]]$Arguments = @(), [string]$Llc = '')
    if (-not $Llc) { $Llc = $C28xToolchain.Llc }
    return Invoke-NativeCapture $Llc (@('-mtriple=c28x-ti-none', '-mcpu=c28x') + $Arguments)
}
