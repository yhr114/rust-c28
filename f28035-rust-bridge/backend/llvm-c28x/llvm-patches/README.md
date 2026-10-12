# LLVM 23 integration points

The backend requires `c28x` to be a real LLVM architecture. Registering it as
`Triple::UnknownArch` is unsafe because every unrecognised triple can then
select the C28x backend.

## 实证状态（2026-09-16，本机构建通过）

LLVM 23.1.1 + gcc 16.2 (MinGW-w64 UCRT) 构建 llc 成功，`c28x - TI TMS320C28x
[experimental]` 注册，`verify-llvm-c28x.ps1` 7/7 通过（含对象字节契约
039a0600 / ff9a0600 与负向门禁）。

> 2026-09-28 更正：早先记录的 68037b00 / 68ff7b00 不是 C28x 指令。SPRU430F 中
> 8 位立即数形式是 `MOVB AX,#8bit` = `1001 101A`、`ADDB AX,#8bitSigned` =
> `1001 110A`，`LRETR` = `0000 0000 0000 0110`；且 TI 对象按小端存字（低字节
> 在前）。现基线由 TI cl2000 / asm2000 + dis2000 + ofd2000 逐字节交叉验证。

## 打补丁（幂等脚本，推荐）

```powershell
powershell -File tools\patch-llvm-triple-c28x.ps1 [-LlvmRoot <llvm-project 根>]
```

对 `llvm/include/llvm/TargetParser/Triple.h` 与 `llvm/lib/TargetParser/Triple.cpp`
做 7 处修改（已存在则跳过）：

1. `Triple::ArchType` 枚举加 `c28x`（Triple.h）
2. `getArchTypeName` 打印 `c28x`
3. `getArchTypePrefix` 返回 `c28x`
4. `getArchTypeForLLVMName` 映射 `"c28x" -> c28x`
5. `parseArch` 解析 `"c28x" -> Triple::c28x`
6. `getObjectFormat` 返回 ELF（实证发现：缺了 llc 在 triple 解析阶段
   `llvm_unreachable("unknown architecture")`）
7. `getArchPointerBitWidth` 返回 **32**（FROZEN ABI：32 位逻辑字节指针，
   见 ABI_FREEZE.md；缺了 llc 报 "Invalid architecture value"）

## 手工改动（与脚本等价）

- `llvm/include/llvm/TargetParser/Triple.h`：ArchType 枚举 csky 前加
  `c28x,        // C28x: TI C2000 C28x (experimental, out-of-tree backend)`
- `llvm/lib/TargetParser/Triple.cpp`：见脚本内锚点。

## 配置与构建（MinGW）

```powershell
$env:Path = "<mingw64>\bin;" + $env:Path
cmake -S <llvm>\llvm -B <build> -G "MinGW Makefiles" `
  -DCMAKE_C_COMPILER=<mingw64>\bin\gcc.exe `
  -DCMAKE_CXX_COMPILER=<mingw64>\bin\g++.exe `
  -DCMAKE_BUILD_TYPE=Release `
  -DLLVM_TARGETS_TO_BUILD=C28x `
  -DLLVM_EXPERIMENTAL_TARGETS_TO_BUILD=C28x `
  -DLLVM_INCLUDE_TESTS=OFF -DLLVM_INCLUDE_EXAMPLES=OFF -DLLVM_INCLUDE_BENCHMARKS=OFF
cd <build>; mingw32-make llc llvm-objdump -j8
```

注意：
- LLVM 23 用 C++20 语法，**gcc 8.1 无法编译**（APFloat.cpp CTAD 报错）；
  需 gcc 11+（实证用 winlibs gcc 16.2.0 UCRT）。
- 后端目录以 junction/复制挂到 `llvm/lib/Target/C28x`（本次实证用 junction，
  改工程代码即时生效）。
- 运行 llc/llvm-objdump 时 `mingw64\bin` 必须在 PATH（libstdc++-6.dll 等运行时）。

## 验证

```powershell
powershell -File tools\verify-llvm-c28x.ps1 -LlvmBin <build>\bin
powershell -File tools\oracle\run-oracle.ps1      # 自动探测 llc
```

The canonical triple used by rustc is `c28x-ti-none`.
