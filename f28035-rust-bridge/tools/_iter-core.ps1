. C:\Users\61987\Desktop\28035\f28035-rust-bridge\tools\llvm-c28x-env.ps1
Set-Location 'D:\c28x-toolchain\build-c28x-clang'
& 'E:\Qt\Tools\Ninja\ninja.exe' llc 2>&1 | Select-Object -Last 4
"=== ninja exit: $LASTEXITCODE ==="
$ll = 'C:\Users\61987\Desktop\28035\f28035-rust-bridge\build\c28x-std\core.ll'
$obj = 'C:\Users\61987\Desktop\28035\f28035-rust-bridge\build\c28x-std\core.o'
$r = Invoke-Llc @('-filetype=obj','-o',$obj,$ll)
$code = $r.ExitCode -band 0xFFFFFFFF
"=== llc exit=0x{0:X8}, .o exists: {1} ===" -f $code, (Test-Path $obj)
$lines = $r.StdErr -split "`n"
$hit = $lines | Select-String 'LLVM ERROR' | Select-Object -First 1
if ($hit) {
  $i = $hit.LineNumber
  "=== next fatal (from line $i) ==="
  $end = [Math]::Min($i+10, $lines.Count-1)
  for ($k=$i-1; $k -le $end; $k++) { $lines[$k] }
} else {
  "=== no LLVM ERROR. tail: ==="
  $lines | Select-Object -Last 10
}
