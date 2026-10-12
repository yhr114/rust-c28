add_llvm_component_group(C28x)

set(LLVM_TARGET_DEFINITIONS C28x.td)

tablegen(LLVM C28xGenAsmMatcher.inc -gen-asm-matcher)
tablegen(LLVM C28xGenAsmWriter.inc -gen-asm-writer)
tablegen(LLVM C28xGenCallingConv.inc -gen-callingconv)
tablegen(LLVM C28xGenDAGISel.inc -gen-dag-isel)
tablegen(LLVM C28xGenInstrInfo.inc -gen-instr-info)
tablegen(LLVM C28xGenRegisterInfo.inc -gen-register-info)
tablegen(LLVM C28xGenSubtargetInfo.inc -gen-subtarget)

add_public_tablegen_target(C28xCommonTableGen)

add_llvm_target(C28xCodeGen
  C28xTargetMachine.cpp
  C28xSubtarget.cpp
  C28xPassConfig.cpp
  C28xISelLowering.cpp
  C28xISelDAGToDAG.cpp
  C28xFrameLowering.cpp
  C28xRegisterInfo.cpp
  C28xInstrInfo.cpp
  C28xAsmPrinter.cpp
  C28xMCInstLower.cpp

  LINK_COMPONENTS
  AsmPrinter
  CodeGen
  Core
  MC
  C28xDesc
  C28xInfo
  Support
  Target

  ADD_TO_COMPONENT
  C28x
  )

add_subdirectory(MCTargetDesc)
add_subdirectory(TargetInfo)
