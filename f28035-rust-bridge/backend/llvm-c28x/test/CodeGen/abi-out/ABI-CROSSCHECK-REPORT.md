# C28x ABI 静态对照报告（Rust↔C 一致性）

生成时间：2026-10-21
方法：对同一批签名，分别用 TI cl2000 (CGT 25.11.1.LTS) 与我们的 llc 出汇编，逐项比对调用约定。
cl2000 侧：`mixed.c`（DWARF 寄存器位置 + 反汇编）及 `c28x-abi-oracle.c`/`i64ret.ll` 的 `-o0` 反汇编。
llc 侧：`abi-mixed.s` `abi-pointer.s` `struct-return.s` `sret-multi.s` `stack-args-many.s` 及新建 `c28x-abi-oracle.s` `i64ret.s`。

## 一、结论矩阵

| 特性 | Rust↔C 寄存器/栈约定 | 与 cl2000 对照 | 方向 |
|---|---|---|---|
| 混编 i16/i32 | 5/5 签名逐位一致（DWARF: reg0=ACC, reg12=AR4, reg14=AR5） | ✅ 完全一致 | R→R / R→C / C→R |
| 指针池 XAR4/XAR5 + sret XAR6 | 7/7 指针用例 + sret 落点 XAR6 | ✅ 一致 | R→R / R→C / C→R |
| 栈上传参（溢出） | 调用方写 SP-N，被调方读 SP-(N+4字节/2字)（返回地址偏移） | ✅ 与 cl2000 的 RA-shift 一致 | R→R / R→C / C→R |
| 多个 32 位参数 | 首参 ACC，其余上栈 | ✅ 与 TI（仅一个 32 位寄存器）一致 | R→R / R→C / C→R |
| sret 结构体返回（寄存器落点） | 隐藏返回缓冲 → XAR6（调用方搬入 XAR6 再 LCR） | ✅ 一致 | R→R / R→C / C→R |
| **i64 / u64 返回** | **被 sret 化（XAR6 缓冲）** | ❌ **cl2000 走 ACC:P 64 位对（低 32=P、高 32=ACC），不一致** | R→C / C→R **存在隐患** |

## 二、关键证据

### 1. 混编（寄存器分配，金标准 = cl2000 DWARF 位置）
cl2000 `mixed.asm` 的参数位置：`f_i32_i16_i16` 的 a→reg0(ACC)、b→reg12(AR4)、c→reg14(AR5)；`f_i16_i32` 的 a→AR4、b→ACC；`f_i16_i16_i32` 的 a→AR4、b→AR5、c→ACC。我们的 `abi-mixed.s` 完全同构。

### 2. 指针 + 整数混合（cl2000 oracle 注释对照）
`f_i16_ptr_i32(i16, ptr, i32)`：a→AR5、p→XAR4、b→ACC（i16 因存在 i32 跳过 AL/AH）。我们的 `abi-pointer.s` 一致。
第三个指针 → 栈（绝不上 ACC）；第二个 i32 → 栈。全部一致。

### 3. sret（XAR6）
cl2000 `c28x-abi-oracle.asm`：`use_wide` 在 `LCR #make_wide` 前 `MOVL XAR6,...`；我们的 `c28x-abi-oracle.s` `use_wide` 在 `lcr make_wide` 前 `movl xar6, xar7`。落点一致。

### 4. 栈溢出（调用方/被调方偏移）
cl2000 `call_many` 把 b/c/d/e 写到 `*-SP[2/4/6/8]`，`many` 在 LCR 压完 2 字返回地址后从 `*-SP[4/6/8/10]` 读回——**偏移差正好 2 字（返回地址）**。我们的调用方写 SP-1..SP-8、被调方读 SP-3/SP-7/SP-11，遵循同一 RA-shift 公式（`LowerCall` 的 `-1-(off/2)` + `LowerFormalArguments` 的 `offset+2`）。

### 5. i64 返回（发现的不一致 + 已查清根因）

**TI cl2000 的真实约定（ACC:P 64 位寄存器对）：**
- cl2000 `wide_mul`（返回 i64 = a*b）：用 `IMPYL P,XT,ACC` + `QMPYL ACC,XT,ACC` 把 64 位积**天然落在 P:ACC**（`ret_i64` 用 `MOV ACC,AL; ASR64 ACC:P,16; ASR64 ACC:P,16` 把符号扩展的 i64 移入对）。
- cl2000 `use_widemul`/`use_add`（调用方）：`LCR` 后 `MOVL ACC,P` 读 P（低 32）。
- `add_i64`：用 `ADDUL P,XAR7` + `ADDCL ACC,XAR6`（带进位的 64 位加）操作 ACC:P 对。
- **结论：TI 的 i64 活在 ACC:P 对（低 32=P、高 32=ACC），靠 ASR64/ADDUL/ADDCL/IMPYL/QMPYL/MOVL P,mem 整体操作，P 既是结果寄存器也是 64 位运算的一部分。**

**我们的 llc 现状：** `use_i64`/`use_widemul` 在 `lcr` 前把 XAR6 设为返回缓冲，调用后从缓冲读 i64 → **i64/u64 返回被 sret 化**。

**为何不是"改一行 CC"就能修（已实测验证）：**
- 根因之一：`CanLowerReturn([i64])` 返回 false；`RetCC_C28x` 的 `CCAssignToReg<[P, ACC]>` 因 P(PRC32) 与 ACC(ACC32) **属于不同寄存器类**，无法构成合法 i64 返回位置，故退化成 sret。
- 根因之二（更关键）：**C28x 的 P 是乘积寄存器，没有通用的"任意值 → P"的 MOV**。本后端 `copyPhysReg` 仅支持往 P 的 16 位半字 PL/PH 写（`MOV16rr`），但 PL/PH **不属于 GR16 类**——机器码校验器直接拒绝 `$pl = MOV16rr`（"Illegal physical register for instruction"）。后端也**没有任何 P←XAR/ACC 的 32 位 MOVL 指令**，只有一个 `movp acc,p`（P→ACC，且会破坏 ACC，不能用于构造返回）。
- 实测：尝试自定义 `RetCC_C28x_Custom` 把 i64 分配 P:ACC 后，callee 侧 `CopyToReg(P,...)` 与 caller 侧 `CopyFromReg(P,...)` 均撞到"unsupported physical register copy destination" / "Illegal physical register"，llc 直接崩溃。已回退该改动，后端恢复安全（i64 仍 sret、不再崩）。

**正确的修复方向（需作为独立后端特性立项）：**
1. 给后端新增 **P 的 32 位写入指令**（C28x 真实指令 `MOVL P, XARn` / `MOVL P, mem`，TI 已证明其合法性：`MOVL P,*+XAR4[0]`、`MOVL XAR7,P`）。
2. 在 `copyPhysReg` 中支持 P 作目的（P←XAR/ACC）与源（XAR/ACC←P）。
3. 让 i64 返回/参数走 ACC:P 对：callee 把低 32 写入 P、高 32 写入 ACC；caller 从 P:ACC 读回并 `BUILD_PAIR`。
4. 可选：为 64 位算术（add/sub/shift/mul）接入 ACC:P 对的 `ADDUL/ADDCL/ASR64/IMPYL/QMPYL`。

**影响：** 在修复前，任何跨 Rust↔C 的 64 位返回值/参数会读错（C 写 P:ACC，Rust 从 XAR6 缓冲读，反之亦然）。F28035 为 16 位 MCU，64 位整数使用较少，但一旦使用即静默出错。

## 三、剩余缺口 / 后续动作

1. **sret-multi 值级正确性**（历史未修项，`sret-multi.ll` 仅做结构检查）：`{i32,i32}` 返回的调用方回读是否取对值，需硬件运行时（`b1-hw-*`）或值断言测试闭环，不能仅靠静态对照。
2. **i64/u64 返回约定（独立后端特性，尚未实现）**：将 i64 返回/参数从 sret 改为 ACC:P 64 位对（与 TI 对齐）。这不是改一行 CC 能解决的——详见第四节证据 5：本后端缺 P 的 32 位写入指令与 ACC:P 寄存器对类，P 不能做通用拷贝。正确做法见证据 5 的"修复方向"，需新增 `MOVL P, XARn`/`MOVL P, mem` 指令并扩展 `copyPhysReg`，再让 i64 经由 ACC:P 对收发。当前后端已回退到安全态（i64 仍 sret、不崩溃），此项作为单独任务立项。

## 四、复现命令
```
# cl2000 侧
cl2000 -v28 --abi=eabi -k -o0 mixed.c
cl2000 -v28 --abi=eabi -k -o0 c28x-abi-oracle.c
# llc 侧
llc -mtriple=c28x-ti-none -mcpu=c28x -O0 -verify-machineinstrs -filetype=asm -o X.s X.ll
```
本目录已保留所有输入(.c/.ll)与产物(.asm/.s)，可直接复核。
