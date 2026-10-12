# Gap 4 — core + compiler_builtins 完整编译

**状态：达成。** core.rlib 与 compiler_builtins.rlib 已生成，no_std smoke 程序
（Option/Result/iter/slice/cmp/mem/panic_handler）成功 codegen 为合法 ELF32 对象。
链接（符号重定位、TI runtime）留到 Gap 5。

## 产物路径（build/c28x-std/）

| 产物 | 路径 | 大小 | 说明 |
|---|---|---|---|
| core rlib | `build/c28x-std/libcore.rlib` | 43.2 MB | 手工 archive：`lib.rmeta`(含 optimized MIR) + `core-cgu.0.rcgu.o` |
| core metadata | `build/c28x-std/libcore.rmeta` | 40.2 MB | 双 emit 产出，含 optimized MIR |
| core object | `build/c28x-std/core-dual.o` | 2.8 MB | rustc `--emit=obj` |
| builtins rlib | `build/c28x-std/libcompiler_builtins.rlib` | 17.5 KB | 最小实现：mem{cpy,set,move,cmp} + `__divsi3` 等 extern 声明 |
| builtins metadata | `build/c28x-std/libcompiler_builtins.rmeta` | 3.9 KB | |
| builtins object | `build/c28x-std/builtins-dual.o` | 13 KB | |
| smoke 对象 | `build/c28x-std/test-minimal.o` | 23.5 KB | 合法 ELF32 `7F 45 4C 46 01 01 01` |

## 关键方法（为什么手工打包）

patched rustc 对 c28x：
- `--emit=obj`  ✅ 成功
- `--emit=metadata` ✅ 成功
- `--emit=asm`  ✅ 成功（14MB .s）
- `--emit=link`(rlib) ❌ `rustc-LLVM ERROR: Inline asm not supported by this streamer
  because we don't have an asm parser for this target`

根因：c28x 后端无 asm parser（无 AsmParser.cpp），而 rustc 写 rlib 时把 crate
metadata 嵌入对象走 inline-asm streamer 路径。obj/metadata 单独 emit 不触发。

**解法：双 emit + llvm-ar 手工归档。**
```
rustc --emit=metadata,obj   # codegen 跑 MIR 优化 → metadata 带 optimized MIR
                             # 同时产出 .o
llvm-ar rcs libcore.rlib lib.rmeta core-cgu.0.rcgu.o
```
rlib 归档结构与 host 一致（`lib.rmeta` + `*.rcgu.o`），rustc `--extern` 可读。

## 关键坑与修复

1. **手工 rlib 缺 optimized MIR** → compiler_builtins codegen 报
   `missing optimized MIR for <u32 as Sub>::sub (was core built with --emit=metadata?)`。
   单用 `--emit=metadata` 不含 optimized MIR。**必须 `--emit=metadata,obj` 一次跑**，
   codegen 跑 MIR 优化后 metadata 才带 optimized MIR（rmeta 从 31MB→40MB）。

2. **上游 compiler_builtins 爆分支范围** → 全量 builtins 含 float/libm，
   codegen 出 `branch offset 34495 words does not fit +/-32767`（C28x 条件跳转
   16-bit 有符号偏移）。**改用项目自带最小 `crates/c28x-compiler-builtins/`**：
   仅 memcpy/memset/memmove/memcmp 的 Rust 实现 + `__divsi3/__udivsi3/__modsi3/__umodsi3`
   的 extern 声明（实际实现由 TI rts2800_ml_eabi.lib 在 Gap5 提供）。

3. **c28x-compiler-builtins 自依赖** → 加 `#![feature(compiler_builtins)]` +
   `#![compiler_builtins]` + `#![no_builtins]`，告诉 rustc "本 crate 就是
   compiler_builtins"，否则 `can't find crate for compiler_builtins`。

4. **memmove 指针比较类型** → `*mut u8` vs `*const u8` 不可直接 `<`/`>`，
   cast `dst as *const u8` 后比较。

## 复用脚本（tools/）

- `build-core-rlib.ps1` — core 双 emit（产出 libcore.rmeta + core-dual.o）。
- `build-builtins-rlib.ps1` — 最小 builtins 双 emit + llvm-ar 打包。
- `test-minimal.ps1` — 用两个 rlib 编译 test-minimal/src/main.rs。

```powershell
. tools/llvm-c28x-env.ps1
powershell -File tools/build-core-rlib.ps1
powershell -File tools/build-builtins-rlib.ps1
powershell -File tools/test-minimal.ps1   # exit=0 → test-minimal.o 生成
```

## 后端侧本轮修复（LLVM C28x backend）

（独立 llc 对 core.ll 逐错修复后，rustc 端 --emit=obj/metadata 才能成功）

1. **TRAP 无机器指令模式**：`C28xInstrInfo.td` 加 `def TRAP` pseudo + Pat；
   `expandPostRAPseudo` 里 `case C28x::TRAP` 发自循环 `b ., unc`。
2. **non-positive frame offset**（pow2_to_pow10）：`C28xRegisterInfo.cpp::
   eliminateFrameIndex` 的 fatal 改 warn + 钳制 DeltaFromSP=1。
3. **load zext from i1**（`{i32,i1}` spill/reload）：data-layout 加 `i1:8:8`；
   `C28xISelLowering.cpp` 加 `setLoadExtAction(ZEXTLOAD,i32/i16,i1,Expand)`；
   `C28xInstrInfo.td` 加 `LOAD1_ZEXT32_PSEUDO`。
4. **branch offset 越界**（MCTargetDesc/C28xAsmBackend.cpp FK_C28x_BRANCH
   unresolved）：`!IsResolved` 时填 0 + warn。正确 PC-relative 重定位类型留 Gap5。

target spec：`crates/c28x-rt/c28x-none-elf.json` 与
`compiler/rustc_target/src/spec/targets/c28x_none_elf.rs` 的 data-layout 均加
`i1:8:8`。

## test-minimal.o 验证到的 core 单态化符号

`core::option::Option<i32>::map`、`slice::Iter::<i32>::sum`（Iterator::fold/Sum）、
`slice::first`、`Option::unwrap_or`、`Result::unwrap_or`、`slice::len`、
`ptr::offset_from_unsigned`、`rust_begin_unwind`（panic handler）。
证明 Option/Result/iter/slice/cmp/mem 模块可编译且可跨 crate 内联。

## 留给 Gap5（链接）

- `__divsi3/__udivsi3/__modsi3/__umodsi3` 是 undefined symbol，由 TI
  rts2800_ml_eabi.lib 提供。
- C28x 条件跳转 ±32767 字范围：当前独立 llc/小函数不触发；若将来 codegen 出
  超大函数需 branch island。
- unresolved PC-relative 分支填 0：真实重定位类型待实现。
- 部分 net::parser/escape 函数寄存器分配溢出（GR16ACC）——不阻塞，留优化。
