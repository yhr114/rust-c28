@echo off
call "D:\VSBuildTools\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1
set "PATH=D:\c28x-toolchain\llvm-mingw\llvm-mingw-20260602-ucrt-x86_64\bin;%PATH%"
set SRC=C:\Users\61987\Desktop\28035\f28035-rust-bridge\backend\llvm-c28x
set DST=D:\c28x-toolchain\llvm-project-23.1.1.src\llvm\lib\Target\C28x
copy /Y "%SRC%\C28xISelLowering.cpp" "%DST%\C28xISelLowering.cpp" >nul
copy /Y "%SRC%\C28xISelLowering.h"   "%DST%\C28xISelLowering.h" >nul
copy /Y "%SRC%\C28xInstrInfo.td"    "%DST%\C28xInstrInfo.td" >nul
copy /Y "%SRC%\C28xInstrInfo.cpp"   "%DST%\C28xInstrInfo.cpp" >nul
copy /Y "%SRC%\C28xInstrInfo.h"    "%DST%\C28xInstrInfo.h" >nul
copy /Y "%SRC%\C28xISelDAGToDAG.cpp" "%DST%\C28xISelDAGToDAG.cpp" >nul
cd /d D:\c28x-toolchain\build-c28x-clang
"E:\Qt\Tools\Ninja\ninja.exe" llc 2>&1
echo exit: %ERRORLEVEL%
