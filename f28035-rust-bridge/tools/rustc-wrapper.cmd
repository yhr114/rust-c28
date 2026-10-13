@echo off
rem rustc-wrapper.cmd - thin shim that hands off to rustc-wrapper.ps1.
rem cargo invokes:  rustc-wrapper.cmd <real-rustc-path> <rustc-args...>
rem PowerShell handles the long arg array (cmd.exe chokes at 8k chars once
compiler_builtins emits hundreds of --check-cfg flags).

powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\61987\Desktop\28035\f28035-rust-bridge\tools\rustc-wrapper.ps1" %*
exit /b %ERRORLEVEL%
