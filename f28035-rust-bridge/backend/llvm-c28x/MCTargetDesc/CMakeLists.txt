add_llvm_component_library(LLVMC28xDesc
  C28xAsmBackend.cpp
  C28xInstPrinter.cpp
  C28xMCAsmInfo.cpp
  C28xMCCodeEmitter.cpp
  C28xMCTargetDesc.cpp

  LINK_COMPONENTS
  MC
  BinaryFormat
  C28xInfo
  Support

  ADD_TO_COMPONENT
  C28x
  )
