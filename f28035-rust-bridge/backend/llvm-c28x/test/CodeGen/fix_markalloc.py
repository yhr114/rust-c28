#!/usr/bin/env python3
"""Fix: replace MarkAllocated (private) with AllocateReg (public)."""
path = r"D:\c28x-toolchain\llvm-project-23.1.1.src\llvm\lib\Target\C28x\C28xISelLowering.cpp"
with open(path, "r", encoding="utf-8") as f:
    src = f.read()

# Fix i32 path
old1 = """      C28xCCState.ACCTaken = true;
      State.MarkAllocated(C28x::ACC);
      State.addLoc(
          CCValAssign::getReg(ValNo, ValVT, C28x::ACC, LocVT, LocInfo));"""
new1 = """      C28xCCState.ACCTaken = true;
      State.AllocateReg(C28x::ACC); // marks ACC + aliases AL/AH
      State.addLoc(
          CCValAssign::getReg(ValNo, ValVT, C28x::ACC, LocVT, LocInfo));"""
assert old1 in src, "i32 MarkAllocated not found"
src = src.replace(old1, new1, 1)

# Fix i16 path
old2 = """      MCPhysReg Reg = C28x16Slots[C28xCCState.Next16Slot++];
      State.MarkAllocated(Reg);
      State.addLoc(
          CCValAssign::getReg(ValNo, ValVT, Reg, LocVT, LocInfo));"""
new2 = """      MCPhysReg Reg = C28x16Slots[C28xCCState.Next16Slot++];
      State.AllocateReg(Reg); // marks Reg + aliases
      State.addLoc(
          CCValAssign::getReg(ValNo, ValVT, Reg, LocVT, LocInfo));"""
assert old2 in src, "i16 MarkAllocated not found"
src = src.replace(old2, new2, 1)

with open(path, "w", encoding="utf-8") as f:
    f.write(src)
print("Fixed: MarkAllocated -> AllocateReg")
