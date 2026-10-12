@echo off
rem No-op linker for cargo: cargo expects a linker program for bin crates,
rem but for c28x-none-elf we do the real link later with cl2000.
rem This stub just exits 0 so cargo leaves the compiled .rcgu.o on disk.
exit /b 0
