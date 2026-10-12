param(
    [string]$InputFile = (Join-Path (Split-Path -Parent $PSScriptRoot) 'crates\rust-targets\native-arithmetic\src\lib.rs'),
    [string]$OutputFile = (Join-Path (Split-Path -Parent $PSScriptRoot) 'build\mir\native-arithmetic.mir.txt'),
    [string]$AssemblyFile = (Join-Path (Split-Path -Parent $PSScriptRoot) 'build\mir\native-arithmetic-from-mir.asm'),
    [string]$Cargo = '',
    [string]$OnlyExport = '',
    [string[]]$RustcArguments = @()
)

. (Join-Path $PSScriptRoot 'toolchain.ps1')
if (-not $Cargo) { $Cargo = $Toolchain.Cargo }

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$manifest = Join-Path $projectRoot 'backend\c28x-mir\Cargo.toml'
$InputFile = (Resolve-Path -LiteralPath $InputFile).Path
$OutputFile = [System.IO.Path]::GetFullPath($OutputFile)
$AssemblyFile = [System.IO.Path]::GetFullPath($AssemblyFile)
$outputDirectory = Split-Path -Parent $OutputFile
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
New-Item -ItemType Directory -Path (Split-Path -Parent $AssemblyFile) -Force | Out-Null

$env:C28X_MIR_OUTPUT = $OutputFile
$env:C28X_MIR_ASM_OUTPUT = $AssemblyFile
if ($OnlyExport) { $env:C28X_MIR_ONLY_EXPORT = $OnlyExport }
try {
    # c28x-mir 是宿主工具，不得被仓库根 .cargo/config.toml 的
    # [build] target = c28x-none-elf.json 误伤（否则宿主构建会失败）。
    # cargo 的配置发现从 CWD 向上直到文件系统根，仓库内任何位置都会命中根配置，
    # 因此把 CWD 切到仓库外的临时目录；并用 rustc-dev 的宿主库路径链接
    # rustc_driver 等 crate，运行时把 toolchain bin 加入 PATH 以解析 DLL。
    $cargoDir = Split-Path -Parent $Cargo
    $rustcPath = Join-Path $cargoDir 'rustc.exe'
    $sysroot = (& $rustcPath --print sysroot).Trim()
    $hostTarget = ((& $rustcPath -vV | Select-String '^host:').ToString().Substring(6)).Trim()
    $hostLib = Join-Path $sysroot ("lib\rustlib\{0}\lib" -f $hostTarget)
    $env:PATH = (Join-Path $sysroot 'bin') + ';' + $env:PATH
    $env:RUSTFLAGS = $env:RUSTFLAGS + ' ' + ('-L ' + $hostLib)
    Push-Location $env:TEMP
    try {
        # PS5.1 promotes cargo's normal stderr progress lines to
        # NativeCommandError records; capture with Continue and judge by
        # $LASTEXITCODE.
        $ErrorActionPreference = 'Continue'
        $mirOut = @(& $Cargo run --manifest-path $manifest -- $InputFile --edition=2024 @RustcArguments 2>&1 | ForEach-Object { "$_" })
        $mirExit = $LASTEXITCODE
        $ErrorActionPreference = 'Stop'
        if ($mirExit -ne 0) {
            $mirOut | Select-Object -Last 120 | ForEach-Object { Write-Output $_ }
            throw 'C28x MIR driver failed.'
        }
    } finally {
        Pop-Location
    }
} finally {
    Remove-Item Env:RUSTFLAGS -ErrorAction SilentlyContinue
    Remove-Item Env:C28X_MIR_OUTPUT -ErrorAction SilentlyContinue
    Remove-Item Env:C28X_MIR_ASM_OUTPUT -ErrorAction SilentlyContinue
    if ($OnlyExport) { Remove-Item Env:C28X_MIR_ONLY_EXPORT -ErrorAction SilentlyContinue }
}

Write-Output "MIR $OutputFile"
Write-Output "ASM $AssemblyFile"
