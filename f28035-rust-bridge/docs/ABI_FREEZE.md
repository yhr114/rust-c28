# C28x Rust ABI 冻结（FROZEN ABI）

> 本文档是 C28x 后端的 ABI 规范与变更契约。**冻结日期：2026-09-15**。
> 任何后续代码（LLVM 后端、rustc target、core 移植、链接脚本、PAC/HAL）
> 都必须遵守本文档；违反即视为回归。

## 1. 规范：32 位逻辑字节指针

- `usize` / `isize` / 数据指针 = **32 位逻辑字节地址**（4 字节，4 字节对齐）。
- 逻辑字节地址到物理字地址的映射（已真机验证，见 `C28X_RUST_ABI.md`）：

  ```
  logical_byte_address = word_address * 2 + lane   (lane ∈ {0,1})
  word_address         = logical_byte_address >> 1
  ```

- C28x 硬件按 16 位字寻址；Rust 的 `u8` 是 8 位。因此：
  - `u8`/`i8`：逻辑 1 字节，1 字节对齐；算术提升到 16 位寄存器，存储时打包到字的一个 lane。
  - `u16`/`i16`：逻辑 2 字节，2 字节对齐 = 1 个 C28x 字（MMIO 原生宽度）。
  - `u32`/`i32`/`f32` 与指针：逻辑 4 字节，4 字节对齐 = 2 个 C28x 字。
  - `u64`/`i64`/`f64`：逻辑 8 字节，4 字节对齐 = 4 个 C28x 字。

## 2. 权威字符串（所有位置必须一致）

```
data_layout : e-m:e-p:32:32-i32:32-i64:32-f32:32-f64:32-a:8:8-n8:16-S16
pointer_width : 32
target-pointer-width : 32
```

**禁止**出现旧模型：`p:16:16`、`pointer_width: 16`、`"target-pointer-width": 16`。

旧模型 `p:16:16`（16 位指针 = 64Ki 逻辑字节 = 32K words）小于 F28035
的 128Ki flash + 20Ki RAM，**不可用**。这也是冻结点 1 的核心理由。

## 3. 已冻结位置清单

| 文件 | 字段 | 状态 |
| --- | --- | --- |
| `backend/llvm-c28x/C28xTargetMachine.cpp` | DataLayout | 已改 |
| `backend/llvm-c28x/rustc-patches/c28x_none_elf.rs` | pointer_width / data_layout / c_int_width=16 | 已改 |
| `backend/llvm-c28x/rustc-patches/c28x_none_elf_1_100.rs` | pointer_width / data_layout | 已改 |
| `backend/llvm-c28x/rustc-patches/0001-add-c28x-target.patch` | pointer_width / data_layout | 已改 |
| `backend/llvm-c28x/PATCHING_RUSTC.md` | 示例代码 | 已改 |
| `crates/c28x-rt/c28x-none-elf.json` | data-layout / target-pointer-width | 已改 |
| `backend/llvm-c28x/C28xISelLowering.cpp` | GlobalAddress / callee → iPTR | 已改 |
| `backend/llvm-c28x/C28xInstrInfo.td` | 全局地址模式 → i32 MOVL_XAR_imm；LCR → i22imm | 已改 |
| `backend/llvm-c28x/C28xRegisterInfo.cpp` | getPointerRegClass 暂留 GR16（契约 L1-1） | 标注 |
| `C28X_MEMORY_MODEL.md` | 指针宽度描述 | 已改 |

强制校验：`tools/check-abi-freeze.ps1`（本机可运行）。

## 4. 契约项（写代码时按此落地）

### L1-1 指针承载路径（frame / deref / lane）
`getPointerRegClass` 翻转为 `GR32RegClass`（XAR），同时重写：
`LOAD16/STORE16_PSEUDO`（ptr 操作数 → GR32）、`MOV16fi`（→ GR32 字节地址）、
`eliminateFrameIndex`（byte 地址物化：`(SP + word_offset) << 1`）。
**解引用必须 >>1 回到字地址**，i8 存取要做 lane 选择 + 字 RMW（打包字节）。
此契约与 `C28X_RUST_ABI.md` 的真机验证一致，改动后必须跑 oracle 回归
（`tools/oracle`）。

### L1-2 MC 编码（基线 2026-09-28 重新校准）

**字节序（强制）**：TI 对象文件把 16 位指令字按小端存放——**低字节在低地址**。
例：`MOV AL,@AR0`（字 0x92A0）在 `.text` 中是 `A0 92`；`LRETR`（字 0x0006）是
`06 00`。早期实现按"操作码字节在前"输出（`92 A0`）是错的。

**当前已验证编码**（TMS320F28035 = 定点 C28x 核，出处 TI **SPRU430F**；每条都用
厂商工具 `asm2000 -v28` + `dis2000` + `ofd2000` 与 `cl2000 -v28` 做过逐字节
交叉验证）：

| 指令 | SPRU430F opcode | 16 位字 | `.text` 字节 |
|---|---|---|---|
| `PUSH ACC` | `0001 1110 1011 1101` | 0x1EBD | `BD 1E` |
| `POP ACC` | `0000 0110 1011 1110` | 0x06BE | `BE 06` |
| `LRETR` | `0000 0000 0000 0110` | 0x0006 | `06 00` |
| `MOVB AX,#8bit`（MOV_AL_imm） | `1001 101A CCCC CCCC` | 0x9A00 \| imm8 | `imm 9A` |
| `ADDB AX,#8bitSigned`（ADD_AL_imm） | `1001 110A CCCC CCCC` | 0x9C00 \| imm8 | `imm 9C` |
| `MOV AX,loc16` | `1001 001A LLLL LLLL` | 0x92/0x93 \| loc16 | `loc16 92/93` |
| `ADD AX,loc16` | `1001 010A LLLL LLLL` | 0x94/0x95 \| loc16 | `loc16 94/95` |
| `SUB AX,loc16` | `1001 111A LLLL LLLL` | 0x9E/0x9F \| loc16 | `loc16 9E/9F` |
| `AND AX,loc16` | `1100 111A LLLL LLLL` | 0xCE/0xCF \| loc16 | `loc16 CE/CF` |
| `OR AX,loc16`  | `1100 101A LLLL LLLL` | 0xCA/0xCB \| loc16 | `loc16 CA/CB` |
| `XOR AX,loc16` | `0111 000A LLLL LLLL` | 0x70/0x71 \| loc16 | `loc16 70/71` |

- **A 位**：A=0 → AL，A=1 → AH（`MOV AH,AR2` → `93A2` 实证）。
- **loc16 寄存器直接寻址**（SPRU430F Table 5-1）：`@ARn = 1010 0AAA`（0xA0–0xA7）、
  `@AH = 0xA8`、`@AL = 0xA9`、`@PH = 0xAA`、`@PL = 0xAB`、`@TH = 0xAC`、`@SP = 0xAD`。
- **分支条件码**（`B 16bitOffset,COND` = `1111 1111 1110 COND` + 16 位字偏移）：
  `NEQ=0000 EQ=0001 GT=0010 GEQ=0011 LT=0100 LEQ=0101 HI=0110 HIS=0111
  LO=1000 LOS=1001 UNC=1111`。后端内部条件码 0-9（EQ,NEQ,GT,GEQ,LT,LEQ,HI,HIS,LO,LOS）
  与硬件 COND 只在 EQ/NEQ 上顺序相反，映射时需交换。
  第二字 = 目标字地址 − 分支自身字地址（`Field = (Value + 2) / 2`）。
  注意 asm2000 会把短跳转自动松弛成 1 字 `SB`，所以分支**不能**用 asm2000
  逐字节比对，只能比对 `B ...` 长形式的手算值。

**XARn（32 位辅助寄存器）编码表**：C28x 对 `XARn` **不使用连续字段**，
SPRU430F 把每条涉及 XARn 的指令写成 8 行独立 OPCODE。任何 `0x1EA0 | n`
式公式对多数 n 都是错的——下表全部由 `asm2000 -v28` + `dis2000` 逐项实测：

| 形式 | n=0..7 的 opcode |
|---|---|
| `MOVL loc32, XARn` | `3A B2 AA A2 A8 A0 C2 C3` |
| `MOVL XARn, loc32` | `8E 8B 86 82 8A 83 C4 C5` |
| `MOVZ ARn, loc16`   | `58 59 5A 5B 5C 5D 88 80` |
| `MOVL XARn, #22bit` | `8D00 8D40 8D80 8DC0 8F00 8F40 7680 76C0` |
| `MOVB XARn, #8bit`  | `D000 D100 D200 D300 D400 D500 BE00 B600` |

- `MOVL XARn,#22bit`：两字。`word0 = opcode(XARn) | (imm >> 16)`（imm[21:16]
  落进 word0 的低 6 位），`word1 = imm & 0xFFFF`。22 位是**字地址**。
  边界实证：`XAR1,#0x00FFFF→8D40 FFFF`、`XAR2,#0x010000→8D81 0000`、
  `XAR3,#0x3FFFFF→8DFF FFFF`、`XAR7,#0x3FFFFF→76FF FFFF`。
- 超过 `0x3FFFFF` 的常量必须在**指令选择**阶段被拒（`imm22` 值谓词，
  `C28xInstrFormats.td`），不得让编码器静默截断成另一个外设地址。
  负向守卫：`test/CodeGen/mmio-oor.ll`。
- **间接寻址 loc16 字段 = `0xC0 | n`**（区别于寄存器直接寻址 `@ARn` = `0xA0 | n`）：
  `MOV AX,*XARn` = `1001 001A 1100 0nnn` → `92C0|n` / `93C0|n`；
  `MOV *XARn,AX` = `1001 011A 1100 0nnn` → `96C0|n` / `97C0|n`
  （实证 `MOV *XAR0,AL→96C0`、`MOV *XAR0,AH→97C0`、`MOV *XAR4,AL→96C4`、
  `MOV *XAR5,AH→97C5`）。
- `MOVZ ARn, loc16` 是唯一合法的"16 位寄存器 → XAR7"零扩展路径。
  `mov xar7, al` 被 asm2000 以 `[E0004] Illegal operand combination` 拒绝。
- **栈调整**：`ADDB SP,#7bit` = `0xFE00 | imm`、`SUBB SP,#7bit` = `0xFE80 | imm`，
  均为 7 位。asm2000 会**静默截断** 255→127，故编码器必须 fail-closed。

**裸常量地址（MMIO）**：`inttoptr(i32 N)` 直接喂给 volatile load/store 时，地址
既不是 `tglobaladdr` 也不涉及重定位。i32 的寄存器类是 `ACC32`，而
`LOAD16/STORE16_PSEUDO` 的地址操作数是 `GR32`（XARn），因此必须有一条
`(i32 imm22:$src) -> MOVL_XAR_imm` 模式把常量物化进 XARn。缺它则报
`LLVM ERROR: Cannot select: t1: i32 = Constant<4160>`。
实证（`test/CodeGen/mmio-const.ll`）：
`load volatile i16, ptr inttoptr(i32 4160 to ptr)` →
`MOVL XAR0,#0x1040` + `MOV AL,*XAR0` + `LRETR` = `8D00 1040 92C0 0006`，
`.text` 字节 `00 8d 40 10 c0 92 06 00`；store 版为 `…96C0…`。

**`applyFixup` 契约（关键）**：`MCAssembler::layout()` 传给 `applyFixup` 的
`Data` 指针**已经包含 fixup 偏移**（`MCAssembler.cpp`:
`Data = Contents.data() + Fixup.getOffset()`），后端**不得**再写
`Data[Fixup.getOffset() + i]`。早期实现加了两遍偏移，单分支函数掩盖了该 bug
（错位后仍落在 fragment 内），只有在同一 fragment 内有两条以上分支时才暴露：
`branch.ll` 的 `0x0004` 被写到 word 4，覆盖了 `lretr`。
回归守卫：`test/CodeGen/branch-multi.ll`。

**`MCInst` 操作数计数陷阱（2026-09-28 修复）**：TableGen 的
`let Defs = [...] / Uses = [...]` 会给 MCInst 追加**隐式操作数**，因此
`MI.getNumOperands()` **不等于** `(ins ...)` 的形参个数。`ADDB_SP`/`SUBB_SP`
（`Defs = [SP], Uses = [SP]`）有 3 个操作数、`MOV_XAR7_AL`（`Defs = [XAR7]`）
有 2 个，于是编码器里的 `assert(MI.getNumOperands() == 1)` **永远不成立**：
任何带栈帧的函数在 `-filetype=obj` 下直接 abort（`PLEASE submit a bug report`），
而 asm 通道毫发无伤（AsmPrinter 不编码字节），所以全部 asm-only 测试都看不出。
编码器现统一改用 `numExplicitOperands(MI, MCII)`
（= `MCII.get(MI.getOpcode()).getNumOperands()`，只含显式操作数）。
回归守卫：`test/CodeGen/frame.ll`（负向，必须**干净拒绝**而非崩溃）。

**"拒绝" ≠ "崩溃"（判别方法）**：`llc` 对 `report_fatal_error` 与 assertion
abort 的退出码**都是** `0xC000001D`，而且两者都会打印
`PLEASE submit a bug report ... Stack dump:`。唯一可用的判别标志是
`Assertion failed`。`verify-llvm-c28x.ps1` 的负向门禁据此校验"拒绝必须是故意的"，
不允许用 `PLEASE submit a bug report` 当崩溃标志（会误报全部正常拒绝）。

**更正记录（2026-09-28）**：早先记为"已实证"的 `PUSH_ACC 6E80`、`POP_ACC 6F80`、
`MOV_AL_imm 6800|imm8`、`ADD_AL_imm 6400|imm8`、`LRETR 007B` **全部无效**：
SPRU430F 中不存在操作码为 `0110 1000` / `0110 0100` 的 16 位指令，`LRETR` 是
`0000 0000 0000 0110` 而非 `007B`。旧值同时把字按大端打印。已按厂商工具修正，
`test/CodeGen/{const3,const255,addsub,logic}.ll` 的期望字节与
`tools/verify-llvm-c28x.ps1`、`tools/oracle/cases.json` 同步更新。

未验证指令一律 `report_fatal_error`，不得静默输出错误字节。
新指令编码必须先有 TI 手册出处 + oracle 字节回归，再合入 emitter。

实证结果（2026-09-28，llc 23.1.1 + gcc 16.2 MinGW）：
- `llc --version` 注册 `c28x - TI TMS320C28x [experimental]` ✓
- `verify-llvm-c28x.ps1` 全绿（exit 0）：`[1/4]` c28x 已注册；`[2/4]` 7 个正向
  对象字节用例（hello / const3 / const255 / branch / branch-multi / alu-acc /
  mmio-const）全部与 TI oracle 逐字节一致；`[3/4]` 3 个负向门禁（core-ops.ll 因
  符号地址重定位被拒、mmio-oor.ll 因 22 位越界在指令选择阶段被拒、frame.ll 因
  局部栈帧的待验证编码被拒），且每个都校验拒绝不是 assertion abort；
  `[4/4]` core-ops.ll 与 frame.ll 的序列汇编（sub/cmp/movl xar/lcr/addb sp/subb sp）✓
- oracle：`llvm-hello` / `llvm-const3` / `llvm-const255` / `llvm-addsub` /
  `llvm-logic` 五个 ll 用例（后端真实输出 vs golden 字节/序列对照）
- 落地需 LLVM 侧补丁（Triple::c28x 等 7 处）：`tools/patch-llvm-triple-c28x.ps1`
  （幂等）；LLVM 23 需 gcc 11+（gcc 8.1 无法编译 C++20）。
- 契约外仍拒绝（fail-closed）：**符号**地址的绝对重定位（`R_C28x_*` 未实现，
  `getRelocType` 为 fatal）——即 `.obj` 里的全局变量/外部函数地址；
  `MOVL XARn,#symbol`、`LCR symbol` 目前只能在汇编通道（`-filetype=asm`）通过。
  裸常量地址（MMIO）自本轮起已支持，不再需要重定位。
- **asm 与 obj 两个通道能力不等**（2026-09-28 实测，`tools/c28x-probe.ps1` 探测）：
  `-filetype=asm` 已覆盖栈帧、函数调用、全局变量、i32 算术等形状；
  `-filetype=obj` 目前只对"无栈帧 / 无调用 / 无全局 / i16-only"的窄集合能出字节。
  已知 **obj 通道**缺口：`LCR`（函数调用）、32 位算术（`ADD32rr`）、符号绝对
  重定位（`R_C28x_*`）、spill 落到未编码寄存器（`frame.ll`）。
  已知 **ISel 层**缺口（asm 也过不去）：i8 存取（lane 选择 + 字 RMW，契约 L1-1）、
  `mul`、i64 返回值分配（`unable to allocate function return #1`）。

**工具链约定（Windows）**：`llc.exe` / `llvm-objdump.exe` 是 MinGW/UCRT 构建，
需要 `api-ms-win-crt-*.dll` 在 `PATH` 上，否则退出码 `0xC0000135`；
`tools/llvm-c28x-env.ps1` 负责注入（dot-source 后 `ninja` 子进程同样受益，
否则 `.td` 变更触发的 tblgen 步骤会无诊断地 FAILED）。
**禁止**用 `& $exe ... 2> $file` 捕获原生命令的 stderr：PowerShell 会把每条
stderr 行转成 ErrorRecord 并按控制台宽度（80 列）**硬换行**，长诊断会在词中间
插入 CRLF，任何子串匹配都会失效。统一走
`Invoke-NativeCapture`（`llvm-c28x-env.ps1`）取原始字节。

### L1-3 函数指针 / 代码地址
代码地址在硬件上是 22 位字地址；LLVM 侧按 i32 承载。fn 指针的字节映射
（是否统一为 32 位逻辑字节地址）**未定**，落地前不得假设。

### L1-4 rustc spec 字段核验（已完成，2026-09-15，对 rustc 1.100 真实源码）
对 `nightly-2026-09-14` 的 rustc 源码（rustc-src 组件）完成核验：
- **已废弃（不得使用）**：`has_elf_div0`、`abi = "C28x"`、字符串形式
  `linker_flavor: "ti"`、`arch: "c28x"` —— 旧版 `c28x_none_elf.rs` 与
  旧 0001 补丁即为该格式，**在 1.100 上无法编译**，已标注过时。
- **1.100 合法字段**：`c_int_width: 16`、`linker_flavor: LinkerFlavor::Unix(Cc::No)`、
  `max_atomic_width`、`atomic_cas`、`panic_strategy: Abort`、`relocation_model: Static`、
  `singlethread`（存在，无 pub 前缀）等全部存在。
- **补丁必备项**：`Arch::C28x` 变体与 `sym::c28x` 在上游不存在，
  0001 补丁已按 1.100 重写（5 处修改：新 target 文件 + supported_targets 注册 +
  Arch 枚举 + desc_symbol + symbols.rs），context 与 1.100 源码逐行核验通过。
- 自动化门禁：`tools/check-rustc-patch.ps1`（可应用性 + 一致性 + 字段/枚举/符号
  双向断言），当前 PASS。

## 5. 验证命令

```powershell
# 冻结一致性（本机可跑，零依赖）
powershell -File tools/check-abi-freeze.ps1

# rustc 补丁可应用性 + spec 字段核验（本机可跑，需 rustc-src 组件）
powershell -File tools/check-rustc-patch.ps1

# 后端构建后：MC 层 + oracle 回归
powershell -File tools/build-c28x-backend.ps1   # 需要 LLVM 源码/网络
powershell -File tools/verify-llvm-c28x.ps1
powershell -File tools/oracle/run-oracle.ps1
```
