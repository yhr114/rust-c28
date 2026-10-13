#!/usr/bin/env python3
"""Patch C28xISelLowering.cpp to use the custom CC function."""
import sys

path = r"D:\c28x-toolchain\llvm-project-23.1.1.src\llvm\lib\Target\C28x\C28xISelLowering.cpp"
with open(path, "r", encoding="utf-8") as f:
    src = f.read()

# --- 1. Insert custom CC function before LowerCall ---
custom_cc = r'''
//===----------------------------------------------------------------------===//
// Custom C28x argument calling convention.
//
// The TI C28x EABI (verified against cl2000 -v28 --abi=eabi disassembly) uses a
// packed 16-bit slot model with a special rule for 32-bit arguments:
//
//   Slots:   0=AL   1=AH   2=AR4   3=AR5
//   i32 arg: occupies ACC (slots 0-1) -- the ONLY 32-bit register.
//
// The critical rule (confirmed by oracle): whenever the argument list contains
// ANY 32-bit argument, the first 32-bit argument takes ACC, and ALL 16-bit
// arguments skip slots 0-1 (AL/AH) entirely, starting at AR4.  This prevents a
// 16-bit argument from stealing AL/AH and overlapping ACC.
//
//   (i16 a, i32 b)          -> a=AR4, b=ACC
//   (i32 a, i16 b)          -> a=ACC, b=AR4
//   (i16 a, i16 b, i32 c)   -> a=AR4, b=AR5, c=ACC
//   (i32 a, i16 b, i16 c)   -> a=ACC, b=AR4, c=AR5
//   (i16 a, i32 b, i16 c)   -> a=AR4, b=ACC, c=AR5
//
// If the list has NO 32-bit argument, 16-bit args fill AL, AH, AR4, AR5.
// The second 32-bit argument (and beyond) goes on the stack (4 bytes).
//
// The generated CC_C28x from C28xCallingConv.td uses independent CCIfType
// lists, so a leading i16 allocates AL (marking ACC as an alias), which then
// blocks the later i32 from ACC and wrongly pushes it to the stack.  This
// custom function implements the correct slot model.
//===----------------------------------------------------------------------===//

namespace {
struct C28xCCAllocState {
  bool HasI32Arg = false;  // pre-scanned: does the arg list contain i32?
  bool ACCTaken = false;   // has ACC been handed to the first i32 arg?
  unsigned Next16Slot = 0;  // index into the 16-bit slot table (0..3, then stack)
};
static thread_local C28xCCAllocState C28xCCState;
} // namespace

// 16-bit argument slots in allocation order.  When HasI32Arg is true, the
// counter starts at slot 2 (AR4) so AL/AH stay reserved for ACC.
static const MCPhysReg C28x16Slots[] = {
  C28x::AL, C28x::AH, C28x::AR4, C28x::AR5
};

static bool CC_C28x_Custom(unsigned ValNo, MVT ValVT, MVT LocVT,
                           CCValAssign::LocInfo LocInfo,
                           ISD::ArgFlagsTy ArgFlags, Type *OrigTy,
                           CCState &State) {
  if (LocVT == MVT::i32) {
    if (!C28xCCState.ACCTaken) {
      C28xCCState.ACCTaken = true;
      State.MarkAllocated(C28x::ACC);
      State.addLoc(
          CCValAssign::getReg(ValNo, ValVT, C28x::ACC, LocVT, LocInfo));
      return false;
    }
    // Second+ 32-bit argument -> stack (4 bytes, 2-byte aligned).
    int64_t Off = State.AllocateStack(4, Align(2));
    State.addLoc(CCValAssign::getMem(ValNo, ValVT, Off, LocVT, LocInfo));
    return false;
  }

  if (LocVT == MVT::i16) {
    // If there's an i32 argument, AL/AH are reserved for ACC; start at AR4.
    if (C28xCCState.HasI32Arg && C28xCCState.Next16Slot < 2)
      C28xCCState.Next16Slot = 2;
    if (C28xCCState.Next16Slot < 4) {
      MCPhysReg Reg = C28x16Slots[C28xCCState.Next16Slot++];
      State.MarkAllocated(Reg);
      State.addLoc(
          CCValAssign::getReg(ValNo, ValVT, Reg, LocVT, LocInfo));
      return false;
    }
    // Out of 16-bit registers -> stack (2 bytes).
    int64_t Off = State.AllocateStack(2, Align(2));
    State.addLoc(CCValAssign::getMem(ValNo, ValVT, Off, LocVT, LocInfo));
    return false;
  }

  return true; // unhandled type
}

'''

marker = "SDValue C28xTargetLowering::LowerCall(CallLoweringInfo &CLI,"
assert marker in src, "LowerCall marker not found"
src = src.replace(marker, custom_cc + marker, 1)

# --- 2. Modify LowerCall pre-scan ---
old_call = "  CCInfo.AnalyzeCallOperands(Outs, CC_C28x);"
new_call = ("  // Pre-scan: if any outgoing argument is i32, reserve AL/AH for ACC.\n"
            "  C28xCCState = C28xCCAllocState();\n"
            "  for (const ISD::OutputArg &Out : Outs)\n"
            "    if (Out.VT == MVT::i32)\n"
            "      C28xCCState.HasI32Arg = true;\n"
            "  CCInfo.AnalyzeCallOperands(Outs, CC_C28x_Custom);")
assert old_call in src, "AnalyzeCallOperands line not found"
src = src.replace(old_call, new_call, 1)

# --- 3. Modify LowerFormalArguments pre-scan ---
old_formal = "  CCInfo.AnalyzeFormalArguments(Ins, CC_C28x);"
new_formal = ("  // Pre-scan: if any formal argument is i32, reserve AL/AH for ACC.\n"
              "  C28xCCState = C28xCCAllocState();\n"
              "  for (const ISD::InputArg &In : Ins)\n"
              "    if (In.VT == MVT::i32)\n"
              "      C28xCCState.HasI32Arg = true;\n"
              "  CCInfo.AnalyzeFormalArguments(Ins, CC_C28x_Custom);")
assert old_formal in src, "AnalyzeFormalArguments line not found"
src = src.replace(old_formal, new_formal, 1)

with open(path, "w", encoding="utf-8") as f:
    f.write(src)

print("Patch applied successfully")
print("Changes:")
print("  1. Inserted CC_C28x_Custom + C28xCCAllocState before LowerCall")
print("  2. LowerCall: pre-scan Outs for i32, use CC_C28x_Custom")
print("  3. LowerFormalArguments: pre-scan Ins for i32, use CC_C28x_Custom")
