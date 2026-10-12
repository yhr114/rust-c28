# LLVM C28x Backend (Skeleton)

From-scratch LLVM backend skeleton for TI TMS320C28x, modeled after MSP430.

## Status

**End-to-end pipeline wired, 32 instructions, 34 files.**  Ready to symlink
into an LLVM source tree and run TableGen.

## Files

```
backend/llvm-c28x/
├── C28x.td                  # Root TableGen
├── C28xRegisterInfo.td       # 24 registers
├── C28xInstrFormats.td       # Operand types
├── C28xInstrInfo.td          # 32 instructions (MOV/ADD/SUB/AND/OR/XOR/LSL/LSR/MPY/B/LCR/PUSH/POP)
├── C28xCallingConv.td        # ABI
├── C28x.h / C28x.cpp         # Target registration
├── C28xTargetMachine.h/.cpp  # TargetMachine
├── C28xPassConfig.h/.cpp     # Full pipeline hooks (addPreRegAlloc/addPostRegAlloc/...)
├── C28xSubtarget.h/.cpp      # Subtarget
├── C28xISelLowering.h/.cpp   # DAG lowering
├── C28xISelDAGToDAG.h/.cpp   # DAG selector
├── C28xFrameLowering.h/.cpp  # Prologue/epilogue
├── C28xRegisterInfo.h/.cpp   # Reg alloc
├── C28xInstrInfo.h/.cpp      # Instr info
├── C28xMCInstLower.h/.cpp    # MI → MCI
├── C28xAsmPrinter.cpp         # MCI → text
├── CMakeLists.txt
├── build.sh                   # One-shot build + test script
├── test/CodeGen/hello.ll      # End-to-end test
└── MCTargetDesc/
    ├── CMakeLists.txt
    ├── C28xMCTargetDesc.cpp
    ├── C28xMCAsmInfo.h/.cpp    # Assembly syntax properties
    └── C28xMCCodeEmitter.cpp   # MCI → bytes
```

## What's done

- ✅ Target registration + data layout
- ✅ 24 registers, 32 instructions
- ✅ Full pass pipeline (addPreRegAlloc / addPostRegAlloc / addPreSched2 / addPreEmitPass)
- ✅ ISelLowering / ISelDAGToDAG
- ✅ FrameLowering (PUSH ACC / SUB SP / POP ACC)
- ✅ MCInstLower / AsmPrinter / MCCodeEmitter
- ✅ MCAsmInfo (`;` comment, TI dialect)
- ✅ hello world test case
- ✅ build.sh one-shot script

## What's missing

1. **Run TableGen** — generate `C28xGen*.inc` from `.td` files
2. **Real MCCodeEmitter encodings** — currently emits 0x0000
3. **Run `llvm-lit`** — actually run hello.ll through llc
4. **More instructions** — multiply with accumulator, branch-and-link

## Quick start

```bash
LLVM_SRC=/path/to/llvm-project ./build.sh
```
