@echo off
rem No-op linker for cargo that captures the .o files for later cl2000 linking.
set CAPTURE_DIR=C:\Users\61987\Desktop\28035\f28035-rust-bridge\build\c28x-gpio-blink\link-objs
if not exist "%CAPTURE_DIR%" mkdir "%CAPTURE_DIR%"
echo %* > "%CAPTURE_DIR%\link-args.txt"
for %%A in (%*) do (
    if /I "%%~xA"==".o" copy /Y "%%~fA" "%CAPTURE_DIR%\" >nul 2>&1
    if /I "%%~xA"==".rlib" copy /Y "%%~fA" "%CAPTURE_DIR%\" >nul 2>&1
)
exit /b 0
