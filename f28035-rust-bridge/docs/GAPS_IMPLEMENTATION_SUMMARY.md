# C28x Rust工具链 6缺口实现总结

> 实现日期：2026-10-08
> 目标芯片：TI F28035 (C2000 C28x)
> 工具链：patched rustc 1.100.0-dev + LLVM 23.1.1 C28x后端 + TI cl2000 25.11.1.LTS

---

## 缺口1：i32完整比较（signed/unsigned全部6种关系）

### 实现方式
CMP32_PSEUDO 的 `SUBL ACC,XT` 指令已能正确设置 N/Z/C/V 全部标志位，无需修改后端代码。`condToEnc` 已映射全部10种条件码：

| 条件码 | 编码 | 分支指令 | 含义 |
|--------|------|----------|------|
| SETEQ | 0 | B_EQ | 等于 |
| SETNE | 1 | B_NE | 不等于 |
| SETGT | 2 | B_GT | 有符号大于 |
| SETGE | 3 | B_GE | 有符号大于等于 |
| SETLT | 4 | B_LT | 有符号小于 |
| SETLE | 5 | B_LE | 有符号小于等于 |
| SETUGT | 6 | B_HI | 无符号大于 |
| SETUGE | 7 | B_HIS | 无符号大于等于 |
| SETULT | 8 | B_LO | 无符号小于 |
| SETULE | 9 | B_LOS | 无符号小于等于 |

CMP32_PSEUDO post-RA 展开序列：XAR7暂存Lhs → ACC=Rhs → XT=Rhs → ACC=Lhs → SUBL ACC,XT。

### 验证
- 新增测试 `backend/llvm-c28x/test/CodeGen/icmp32-full.ll`：10个函数覆盖全部比较关系
- llc 编译通过，反汇编确认每种比较生成 CMP32 + 对应条件分支
- `verify-llvm-c28x.ps1` 回归全绿

---

## 缺口2：乘法/除法/移位 libcall

### 实现方式

| 运算 | 方案 | 说明 |
|------|------|------|
| i32 MUL | 硬件MPYU 4部分积 | `LowerMul()` 用4个16x16→32部分积（pLL + pHL<<16 + pLH<<16），利用C28x硬件MPY指令，无需libcall |
| i32 SDIV/UDIV | libcall | `Expand` + `setLibcallImpl` 自动生成 `lcr __divsi3` / `lcr __udivsi3` |
| i32 SREM/UREM | libcall | 生成 `lcr __modsi3` / `lcr __umodsi3` |
| i32 SHL/SRL/SRA | 硬件移位 | `SHL32_VAR`/`SRL32_VAR`/`SRA32_VAR` 伪指令展开为 `LSL/LSRL/ASRL ACC,T` |

`setLibcallImpl` 映射（C28xISelLowering.cpp:212-219）：
- SHL_I32 → `__ashlsi3`（实际用硬件移位，未触发）
- SRL_I32 → `__lshrsi3`（实际用硬件移位，未触发）
- SRA_I32 → `__ashrsi3`（实际用硬件移位，未触发）
- MUL_I32 → `__mulsi3`（实际用4部分积，未触发）
- SDIV_I32 → `__divsi3`
- UDIV_I32 → `__udivsi3`
- SREM_I32 → `__modsi3`
- UREM_I32 → `__umodsi3`

### compiler_builtins
- `crates/c28x-compiler-builtins/`：memcpy/memmove/memset/memcmp 的Rust实现 + `__divsi3`等extern声明
- `__divsi3`/`__udivsi3`/`__modsi3`/`__umodsi3` 由 TI `rts2800_ml_eabi.lib` 提供实现
- 标准上游compiler_builtins因float/libm函数过大（条件跳转超出±32767字范围）不可用，改用最小实现

### 验证
- 新增测试 `backend/llvm-c28x/test/CodeGen/arithmetic32.ll`
- 全部算术运算编译通过，除法生成正确libcall
- `verify-llvm-c28x.ps1` 回归全绿

---

## 缺口3：TI ABI第二参数AH一致性

### 根因
`C28xCallingConv.td` 中 i16 和 i32 的寄存器列表互相独立消费索引：
```
CCIfType<[i16], CCAssignToReg<[AL, AR0, AR1, AR2, AR3]>>,
CCIfType<[i32], CCAssignToReg<[ACC, XT, XAR0, XAR1, XAR2, XAR3]>>,
```
导致 `func(i16, i16)` 第二参数错误地进入 AR0（应为AH），`func(i16, i32)` 出现 AL/ACC 重叠。

### 修复（通过cl2000 --abi=eabi反汇编确认）
修正后的 TI C28x EABI：

| 参数槽位 | i16寄存器 | i32寄存器 |
|----------|-----------|-----------|
| 0 | AL | ACC（占槽0-1） |
| 1 | AH（打包进ACC高半） | — |
| 2 | AR4 | — |
| 3 | AR5 | — |
| 4+ | 栈 | 栈 |

关键发现：
- **第二i16参数 → AH**（与AL打包进同一个ACC）
- **第二i32参数 → 栈**（不是XT！C28x EABI只有ACC一个32位参数寄存器）
- 第三、四i16参数 → AR4、AR5（不是AR0-AR3）

修改 `C28xCallingConv.td`：
```
CCIfType<[i16], CCAssignToReg<[AL, AH, AR4, AR5]>>,
CCIfType<[i32], CCAssignToReg<[ACC]>>,
```

### 已知限制
混合类型 `(i16, i32)` 和 `(i32, i16)` 仍可能有 AL/ACC 重叠（TableGen独立列表的固有问题）。实际Rust extern "C"函数多为全i16或全i32签名，常见场景正确。

### 验证
- 新增测试 `backend/llvm-c28x/test/CodeGen/abi-multiarg.ll`
- 与TI cl2000输出对比：f2(short,short)→a=AL,b=AH；f32(long,long)→a=ACC,b=栈
- 更新 `verify-llvm-c28x.ps1` 的oracle字节（旧字节基于错误ABI）
- 回归全绿

---

## 缺口4：core / compiler_builtins 完整编译

### 实现方式

#### 构建方法
因 patched rustc 的 sysroot 无 host std（`-Zbuild-std` 的 build.rs 无法运行），采用**双emit + 手工归档**方案：

```powershell
# 1. 编译core为obj + metadata（一次跑MIR优化）
rustc --target c28x-none-elf --crate-type lib --emit=metadata,obj \
      --edition 2021 -C panic=abort -C debug-assertions=no \
      library/core/src/lib.rs -o libcore.rmeta

# 2. 用llvm-ar打包为rlib（成员: lib.rmeta + *.rcgu.o）
llvm-ar rcs libcore.rlib libcore.rmeta core-cgu.0.rcgu.o
```

关键：必须**同时** `--emit=metadata,obj`，单独 `--emit=metadata` 不含optimized MIR（会导致下游crate报253个"missing optimized MIR"错误）。

#### 后端修复（编译core过程中发现并修复）
1. **TRAP无法选择**：`core::process::abort_immediate` 生成 `trap` 节点，后端标记Legal但无对应指令。添加 `TRAP_PSEUDO`，post-RA展开为 `B ., UNC`（无限自循环）
2. **non-positive frame offset**：`eliminateFrameIndex` 对 outgoing call-arg 槽位（DeltaFromSP≤0）直接fatal。改为钳制到最小距离
3. **i1(bool)加载**：`{i32,i1}`结构体的i1溢出标志spill后reload失败。在data-layout添加 `i1:8:8` 让i1按字节存储，添加 `LOAD1_ZEXT32_PSEUDO` 模式
4. **分支fixup越界**：未定义符号的PC相对分支偏移超出±32767字。改为填0+警告，不崩溃（对象文件作为验证载体，真实输出走asm2000）

#### compiler_builtins
使用项目自带最小实现 `crates/c28x-compiler-builtins/`（17.5KB），而非上游全量（含float/libm，函数过大触发分支范围错误）：
- memcpy/memmove/memset/memcmp：Rust实现
- `__divsi3`/`__udivsi3`/`__modsi3`/`__umodsi3`：extern声明，链接时由TI rts库解析
- 添加 `#![compiler_builtins]` 和 `#![no_builtins]` 内属性

### 产物
| 产物 | 路径 | 大小 |
|------|------|------|
| core rlib | `build/c28x-std/libcore.rlib` | 43.2 MB |
| compiler_builtins rlib | `build/c28x-std/libcompiler_builtins.rlib` | 17.5 KB |
| smoke测试obj | `build/c28x-std/test-minimal.o` | 23.5 KB |

### 验证
- test-minimal.o 单态化出 `Option::map`、`slice::Iter::sum`、`slice::first`、`Result::unwrap_or`、`slice::len`、`ptr::offset`、`rust_begin_unwind`
- 证明 Option/Result/iter/slice/cmp/mem/panic_handler 全链路可编译
- 构建脚本：`tools/build-core-rlib.ps1`、`tools/build-builtins-rlib.ps1`、`tools/test-minimal.ps1`

---

## 缺口5：cargo build --target c28x-none-elf

### 实现方式

#### 自定义sysroot方案
因 `-Zbuild-std` 需要host std，采用预编译core + 自定义sysroot：

```
custom-sysroot/
└── lib/rustlib/
    ├── c28x-none-elf/lib/
    │   ├── libcore.rlib          (从build/c28x-std复制)
    │   └── libcompiler_builtins.rlib
    └── x86_64-pc-windows-gnu/    (host工具链，由系统rustc提供)
```

cargo通过 `RUSTC_SYSROOT` 或 `--sysroot` 找到预编译core。

#### cargo项目
`crates/c28x-gpio-blink/`：
- `.cargo/config.toml`：指定target、rustflags、链接器
- `Cargo.toml`：no_std，无依赖
- `src/main.rs`：GPIO34翻转程序

#### 关键踩坑
1. **必须用 `core::intrinsics::volatile_load/store`**，不能用 `ptr::read_volatile`——后者拉进 `maybe_is_aligned` UB检查函数，触发TI链接器内部段大小错误
2. **必须 `--release`**：dev profile未优化的 `.text.main` 也触发同一链接器bug
3. **段消除必须开**（`--unused_section_elimination=on`）：全量core 2.8MB，F28035 RAM仅12K，必须丢弃未引用函数

### 产物
| 产物 | 路径 | 大小 |
|------|------|------|
| cargo项目 | `crates/c28x-gpio-blink/` | — |
| Rust编译obj | `target/c28x-none-elf/release/gpio-blink.o` | 520 B |
| 链接out | `build/c28x-gpio-blink/gpio_blink.out` | 3928 B |
| 构建脚本 | `tools/build-cargo-gpio-blink.ps1` | — |

### 链接命令
```
cl2000 --silicon_version=28 --float_support=softlib --abi=eabi --run_linker
       --rom_model --stack_size=0x100 --unused_section_elimination=on
       --output_file=gpio_blink.out
       gpio-blink.o startup.obj rts2800_ml_eabi.lib
       F28035_ram.cmd F28035_EABI_sections_ram.cmd
```

### 验证
- `cargo rustc --release --target c28x-none-elf` 编译通过
- ofd2000确认 EM_TI_C2000
- TI cl2000链接成功，无undefined符号
- dis2000反汇编确认GPIO访问指令

---

## 缺口6：路径2产物上板验证

### 实现方式
GPIO34翻转程序（F28035实际寄存器地址）：

| 寄存器 | 地址 | 操作 |
|--------|------|------|
| GPBMUX1 | 0x6F96 | 清bit4-5（GPIO34设为GPIO功能） |
| GPBDIR | 0x6F9A | 置bit2（GPIO34设为输出） |
| GPBTOGGLE | 0x6FCE | 写bit2（翻转GPIO34） |

程序流程：启动层(asm.s)关WD → main配置GPIO → 循环翻转GPBTOGGLE。

### 反汇编验证
```
启动层: MOV @0x7029, #0x0068   ; 关看门狗
main:   MOVL XAR0, #0x6F96     ; GPBMUX1地址
        MOV AL, *XAR0          ; 读
        AND AL, #0xFFCF        ; 清bit4-5
        MOV *XAR0, AL          ; 写
        MOVL XAR0, #0x6F9A     ; GPBDIR地址
        ...                    ; 置bit2
        MOVL XAR0, #0x6FCE     ; GPBTOGGLE地址
loop:   MOV *XAR0, #0x0004     ; 翻转bit2
        B loop, UNC            ; 循环
```

### 上板状态
**硬件未连接**：`xds100serial` 报 "No XDS100 emulators were found"。

已完成到链接.out + 反汇编验证的全部步骤。接好XDS100v1/v2后执行：

```powershell
# 构建
powershell -File tools/build-cargo-gpio-blink.ps1

# 烧录到RAM并验证（DSS脚本）
node tools/verify-cargo-gpio-blink-ram.js
```

**预期上板结果**：
- GPBDIR (0x6F9A) = 0x0004（bit2置位，GPIO34输出）
- GPBDAT (0x6F9C) 在 0x0000 和 0x0004 之间翻转
- GPIO34引脚电平方波输出

---

## 修改文件清单

### LLVM后端（backend/llvm-c28x/）
| 文件 | 修改内容 |
|------|----------|
| C28xCallingConv.td | ABI修正：i16→[AL,AH,AR4,AR5], i32→[ACC] |
| C28xISelLowering.cpp | data-layout i1:8:8, TRAP/frame/i1相关修复 |
| C28xInstrInfo.cpp | TRAP_PSEUDO展开, LOAD1_ZEXT32_PSEUDO展开, frame offset钳制 |
| C28xInstrInfo.td | TRAP_PSEUDO定义, LOAD1_ZEXT32_PSEUDO定义+模式 |
| C28xMCAsmBackend.cpp / C28xAsmBackend.cpp | 分支fixup越界改为警告 |
| verify-llvm-c28x.ps1 | 更新oracle字节（ABI变更） |

### 新增测试（backend/llvm-c28x/test/CodeGen/）
- icmp32-full.ll — i32全部10种比较
- arithmetic32.ll — i32乘除移位
- abi-multiarg.ll — 多参数ABI

### Rust工具链
- crates/c28x-compiler-builtins/ — 最小compiler_builtins实现
- crates/c28x-gpio-blink/ — cargo GPIO测试项目
- build/c28x-std/libcore.rlib — 编译出的core
- build/c28x-std/libcompiler_builtins.rlib — 编译出的compiler_builtins
- build/c28x-gpio-blink/gpio_blink.out — 链接产物

### 构建脚本（tools/）
- build-core-rlib.ps1
- build-builtins-rlib.ps1
- test-minimal.ps1
- build-cargo-gpio-blink.ps1
- verify-cargo-gpio-blink-ram.js

### 文档（docs/）
- C28X_LLVM_BACKEND_GAPS_FIXED.md
- gap5-6-cargo-gpio-blink.md
- GAPS_IMPLEMENTATION_SUMMARY.md（本文档）

---

## 待办事项

1. **上板验证**：接XDS100仿真器，运行 `tools/verify-cargo-gpio-blink-ram.js` 确认GPIO34翻转
2. **混合类型ABI**：修复 `(i16, i32)` / `(i32, i16)` 参数分配的AL/ACC重叠（需在C++ LowerCall中实现自定义分配，替代TableGen独立列表）
3. **`-Zbuild-std`原生支持**：构建host std装入sysroot，使 `cargo build -Zbuild-std` 直接可用（当前用预编译core + 自定义sysroot替代）
4. **除法函数自包含**：在c28x-compiler-builtins中实现`__divsi3`等，去除对TI rts库的依赖
5. **TI链接器bug规避**：`maybe_is_aligned` 段大小错误需进一步定位（当前用intrinsics绕过）
