# rustc 构建指南

## 为什么要编译 rustc

本项目使用**自定义 LLVM C28x 后端**，后端源码是 C++ 文件（`C28xISelLowering.cpp`、`C28xInstrInfo.td`、`C28xMCCodeEmitter.cpp` 等）。

修改这些 C++ 源码后，必须重新编译 rustc 才能让修改生效：

```
修改 C28x 后端 .cpp/.td 文件
    ↓
重编 rustc_llvm 库（C++ 编译）
    ↓
重链 rustc_driver.dll（链接）
    ↓
生成新的 rustc.exe（包含修改后的 C28x 后端）
    ↓
用新 rustc 编译你的 Rust 项目
```

**不编译 = 修改不生效**，rustc 还是用旧的后端。

## 编译完有什么用

编译产物是 `rustc.exe`，路径：
```
D:\c28x-toolchain\rust-build-gcc14fix\host\stage1\bin\rustc.exe
```

这个 rustc 内置了 C28x LLVM 后端，可以直接把 Rust 代码编译成 C28x 目标文件（`.o`），无需经过 C 编译器。

用它编译项目：
```powershell
cd crates/c28x-gpio-blink
cargo build -Zbuild-std=core,compiler_builtins --release --target c28x-none-elf
```

## 优化后的 config.toml

位置：`D:\c28x-toolchain\rust-src-unpacked\rust-4b6d04e706108ccfeafe2547fbe857dfe8972bad\config.toml`

```toml
[llvm]
download-ci-llvm = false

[build]
build = "x86_64-pc-windows-gnu"
host = ["x86_64-pc-windows-gnu"]
target = ["x86_64-pc-windows-gnu"]
docs = false

[target.x86_64-pc-windows-gnu]
linker = "E:/Qt/Tools/mingw810_64/bin/gcc.exe"
cc = "E:/Qt/Tools/mingw810_64/bin/gcc.exe"
cxx = "E:/Qt/Tools/mingw810_64/bin/g++.exe"

[rust]
codegen-backends = ["llvm"]
debug = false
optimize = true
debuginfo-level = 0
debuginfo-level-rustc = 0
debuginfo-level-std = 0
debuginfo-level-tools = 0
strip = true
lld = true
incremental = true
tools = []
```

### 各项优化说明

| 配置 | 作用 |
|------|------|
| `lld = true` | 用 rust 自带 lld 链接器，比 MinGW ld 快 3-5 倍 |
| `incremental = true` | 增量编译，改单文件只重编受影响的 crate |
| `tools = []` | 不编 rustdoc/clippy/rustfmt |
| `docs = false` | 不编文档 |
| `debuginfo-level = 0` | 无调试信息，DLL 体积最小 |
| `strip = true` | 剥离符号，进一步减小体积 |
| `optimize = true` | 优化编译，rustc 运行更快 |

## 构建命令

### 改了 LLVM 后端后（最常用，推荐用脚本）

```powershell
.\tools\build-rustc.ps1
```

脚本自动设置环境变量、只构建 `compiler/rustc`、计时、验证产物。

### 手动构建

```powershell
cd D:\c28x-toolchain\rust-src-unpacked\rust-4b6d04e706108ccfeafe2547fbe857dfe8972bad
python x.py build compiler/rustc --build-dir D:\c28x-toolchain\rust-build-gcc14fix -j 1
```

### 增量构建规则（默认行为）

`x.py build` **默认就是增量构建**，只会重编：
- 修改过的 `.cpp` / `.rs` 文件
- 依赖这些文件的库
- 最终重链 `rustc_driver.dll`

**不会**全量重编。不需要额外配置。`incremental = true` 进一步开启 Rust crate 级别的增量编译。

### 全量构建（仅首次或清理后）

```powershell
python x.py build --build-dir D:\c28x-toolchain\rust-build-gcc14fix -j 1
```

### 环境变量（构建前设置）

```powershell
$env:PATH = "D:\c28x-toolchain\.lingma\bin;D:\c28x-toolchain\rust-src-unpacked\rust-4b6d04e706108ccfeafe2547fbe857dfe8972bad\build\x86_64-pc-windows-gnu\llvm\bin;" + $env:PATH
$env:TEMP = "D:\c28x-toolchain\build-temp"
$env:TMP = "D:\c28x-toolchain\build-temp"
```

## 两个 LLVM 副本必须同步

修改 C28x 后端时，有两个副本必须同步修改：

1. **独立树**（用于 llc 验证）：
   `D:\c28x-toolchain\llvm-project-23.1.1.src\llvm\lib\Target\C28x\`

2. **rust 树内副本**（编译进 rustc）：
   `D:\c28x-toolchain\rust-src-unpacked\rust-4b6d04e706108ccfeafe2547fbe857dfe8972bad\src\llvm-project\llvm\lib\Target\C28x\`

独立树改完后用 ninja 重编 llc 快速验证：
```powershell
cd D:\c28x-toolchain\build-c28x-clang
ninja llc
```

验证通过后，把同样的修改复制到 rust 树内副本，再 `x.py build compiler/rustc`。

## 常见问题

### rustc_driver.dll 加载失败 (error 193)

DLL 体积过大（581MB），DWARF section VA 超出 SizeOfImage。已通过 `debuginfo-level=0` + `strip=true` 缓解。如果仍出现，尝试 `lld = true`（lld 处理大 DLL 更稳定）。

### 改了代码但行为没变

确认两个 LLVM 副本都改了，且执行了 `x.py build compiler/rustc`。只改独立树不会影响 rustc。

### 构建很慢

确认用的是 `build compiler/rustc` 而非全量 `build`。确认 `incremental = true` 和 `lld = true` 已开启。
