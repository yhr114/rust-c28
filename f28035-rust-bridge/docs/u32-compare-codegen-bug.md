# 32 位比较异常根因报告（两个 u16 合成 u32 后与字面量比较）

日期：2026-10-27
现象：`c28x-cargo-runtime` 的 `context_errors()` 中
`low | (high << 16) != 0x12345678` 在 B-1 真机上 10/10 判错，
而同一 `HW_RT_REGS` 数组被 dss 逐字读回完全正确。改用逐半字比较后通过，
根因长期未定（正确性风险）。

---

# 2026-10-28 复核：当前包仍失败，且上一轮根因被推翻

对 active bundle `20261027-171858-19176840-af788b4d` 重做最小复现（真机 XDS100 +
`tools/build-b1-u32-compose-ram.ps1` / `tools/dump-mailbox.js`），结论如下。

## 1. 当前包仍然失败（不是"应该没问题"的推测）

`U32_COMPOSE=FAIL`，4 项不符，与旧报告签名一致：

| 项 | 实测 | 期望 |
|---|---|---|
| `composed == 0x12345678` | 0 | 1 |
| `composed != 0x12345678` | 1 | 0 |
| `k - 0x12345678` 低/高半字 | 0x0004 / 0xEDCC | 0 / 0 |
| `k == 0x12345678` | 0 | 1 |

同一轮里这些**全部正确**：合成两半字（0x5678/0x1234）、`hi<<16`、
运行期 vs 运行期比较、字面量物化（`c^1`→0x12345679、`1-c`→0xEDCBA988）。

## 2. 上一轮"根因"是错的：`MOV32rr` 不是内存读

用 `.word` 绕过汇编器，直接把 `0xC5A4`/`0xC5A6` 放到硅片上执行
（`build/enc-probe/enc_probe2.asm`）：

| 编码 | 源 | 实测 `XAR7` |
|---|---|---|
| `0xC5A9`（MOVL XAR7,ACC，对照） | ACC=0x12345678 | 0x12345678 |
| `0xC5A4` | XAR4=0x12345678 | **0x12345678** |
| `0xC5A6` | XAR6=0xDEADBEEF | **0xDEADBEEF** |

→ 这两条编码在 F28035 上是**完整 32 位寄存器复制**，高半字保留，**不是**
`MOVL XARn, @ARm` 的内存读。上一轮据此写的"根因"不成立。

补充事实：TI 汇编器拒绝所有 XAR←XAR 拼写（`MOV32 XARn,XARm` 报
"Invalid instruction for specified floating point accelerator"，属 FPU 指令集，
F28035 无 FPU），所以它是**核心正式指令集之外**的编码——但硬件行为是复制，
这一点由硅片直接判定，优先于任何手册/反汇编推断。

**连带影响**：`C28xMCCodeEmitter.cpp` 把 `MOV32rr` 改成 `report_fatal_error`、
7 处 `BuildMI(MOV32rr)` 改成 `PUSH32/POP32`，都是基于错误前提。前者是**回归风险**
（合法的 32 位寄存器复制一旦出现就编译中止），后者只是变慢，不会修好这个 bug。
**不要按原计划重建后宣称"已修复"。**

## 3. 故障点收窄：比较时的操作数被破坏

新增观测点（邮箱 [25]–[33]）与断点读数：

- 邮箱 [25]/[26]（`k & 0xFFFF` / `k >> 16`）= 0x5678/0x1234 看似"合成正确"，
  但这是**优化器把它们折叠回输入 `lo3`/`hi3` 造成的假象**（见 §4），不能作为证据。
- **`u32` 直接来自内存**（`*(const u32*)0x13E10` 读 0x12345678）再与同一字面量
  比较 → **[33]=1 正确**。
- **`u32` 由 `lo|(hi<<16)` 算出来**再与同一字面量比较 → 错。
- 断点停在 `SUBL ACC,XT`（0x8214）时：`XT=0x12345678`（字面量正确），
  `ACC=XAR4=XAR7=0x0000567C`。

即：**字面量没问题、比较指令没问题；被破坏的是那个计算值本身**——
高半字丢失、低半字变成 `0x1234|0x5678`。原因见 §4（`LSL ACC,T` 只吃 4 位移位量）。

## 4. 根因已定位（2026-10-28 第二轮）：`LSL ACC,T` 的移位量只有 4 位

**C28x 的 `LSL ACC,T` 只用 T 的低 4 位（0–15），移位 16 会被当成 0；而
`LSRL`/`ASRL ACC,T` 正常支持 0–31。** 后端把 32 位移位展开成"两个 16 位半字
分别移位"，半字移位量直接来自运行期寄存器，一旦达到 16 就静默变成 0。

硅片实测（`build/enc-probe/lsl_probe.asm`、`srl_probe.asm`，ACC 固定 0x00001234）：

| 指令 | 移位量 | 实测 | 期望 |
|---|---|---|---|
| `LSL ACC,T` | 0 / 1 / 15 | 0x1234 / 0x2468 / 0x091A0000 | ✓ |
| `LSL ACC,T` | **16** | **0x00001234（未移位）** | 0x12340000 ✗ |
| `LSL ACC,T` | **17** | **0x00002468（只移 1 位）** | 0x24680000 ✗ |
| `LSL ACC,#16`（立即数） | 16 | 0x12340000 | ✓ |
| `LSRL ACC,T` | 16 | 0x00001234 | ✓ |
| `ASRL ACC,T` | 16 | 0xFFFFF234 | ✓ |

即：**只有左移被掩码到 4 位**，右移没有这个问题。

### 完整因果链（与实测数值逐位吻合）

`(lo as u32) | ((hi as u32) << 16)` 被展开为 `LowerShiftParts`
（`C28xISelLowering.cpp:351`）：`a32 = amt & 31 = 16`，

- `ShLo = Lo << 16` → `LSL ACC,T`，T=16 → 掩码成 0 → **ShLo = Lo = 0x5678**
- `ShHi = (Hi << 16) | (Lo >> (32-16))` → 前项同样不移位 → `0x1234`；
  `Lo >> 16`（LSRL，正常）= `0x0000` → **ShHi = 0x1234 | 0x0000**
- 于是 `0x1234 | 0x5678 = 0x567C` —— **正是断点读到的 `ACC=0x0000567C`**

所以这个 bug 不是"比较错"，也不是"合成错"，而是 **`hi << 16` 静默变成 `hi`**，
后面所有数值（0xEDCC0004 的差值、`!=` 判真）都是它的必然结果。

### 为什么其它检查都"通过"

- 运行期 vs 运行期比较：两边都按同样方式算错，仍然相等 → PASS。
- `(k & 0xFFFF)` / `(k >> 16)` 这类观测点会被优化器折叠回 `lo`/`hi` → 显示"合成正确"，
  是假象（第一轮据此得出的"合成正确"结论已作废）。
- 右移类表达式正常，因为 `LSRL/ASRL` 没有 4 位限制。

### 影响面

**所有 32 位左移**，只要每半字的有效移位量落在 16–31（`x << 16`、`x << n`
（n≥16）、`u32 << var` 的交叉项）都会算错。右移、加减、乘、比较、字面量物化不受影响。

## 5. 修复位置（已定位，未实施）

`backend/llvm-c28x/C28xISelLowering.cpp::LowerShiftParts`（SHL 分支，约 381–390 行）：
`ShLo`、`ShHi` 的 `Hi << a32`、`BigHi` 三处 `C28xISD::SHL32_VAR`，在半字场景下
移位量 ≥16 时结果必然为 0。最小改法（无分支）：

```
shl16(x, a) = SELECT(a >= 16, 0, SHL32_VAR(x, a & 15))
```

或让 `SHL32_VAR_PSEUDO` 展开时用 `LSL ACC,#16` 先吃掉 bit4（`C28xInstrInfo.cpp:456`）。

**注意**：`C28xInstrInfo.cpp:486` 的注释"hardware reads the count from T's low five
bits"是错的，应为四位；这条错误注释正是本次缺陷的来源。


---

以下为 2026-10-27 原文，其"根因"部分**已被上节推翻**，保留作为过程记录。

## 结论（一句话，已被 2026-10-28 复核推翻）

**C28x 没有 XAR→XAR 的 32 位寄存器搬移指令。** 后端把 XAR→XAR 复制编码成
`MOV32rr`，而该编码实际是 `MOVL XARn, @ARm` —— `@ARm` 是**以 ARm 为地址的
寄存器直接寻址内存读**，不是复制寄存器。该缺陷有**两个发射源头**：

1. `copyPhysReg` 的 `GR32→GR32` / `XT→GR32`（上一轮已修，见下）；
2. **伪指令展开里直接 `BuildMI(MOV32rr, XAR7)`**（这才是真机比较失败的真实路径）：

   - `CMP32_PSEUDO`（把 `Lhs` 暂存进 XAR7）→ 复现里的 `MOVL XAR7, @XAR6` 即此；
   - `TRUNC32_16`、`SHL/SRL/SRA32_VAR_PSEUDO`、`ADD32imm32/SUB32imm32`、
     `ADD32_PSEUDO/SUB32_PSEUDO`、`AND/OR/XOR32_PSEUDO`，以及
     `C28xRegisterInfo.cpp::eliminateFrameIndex`（XAR7→Dst 反向）。

上一轮只修了源头 1，源头 2 仍在原地，所以故障路径**并未闭合**——这正是
"根因未定、仍有风险"的真正原因。本次（2026-10-27 第二轮）已把源头 2 全部
改为 `PUSH32`/`POP32` 栈中转，并让 `MOV32rr` 的编码分支改为显式报错，彻底堵死
该陷阱。

## 证据链

### 1. 真机最小复现（`crates/b1-u32-compose` + `tools/verify-b1-u32-compose-ram.js`）

邮箱（0x9E00）实测：

| 项 | 值 | 结论 |
|---|---|---|
| composed 低/高半字 | 0x5678 / 0x1234 | **合成正确** |
| `hi<<16` 高半字 | 0x1234 | 移位正确 |
| 乘法合成高半字 | 0x1234 | 正确 |
| `composed == ref_val`（运行期） | 1 | 正确 |
| `composed - ref_val` 半字 | 0/0 | 减法正确 |
| **`composed == 0x12345678`** | **0** | **错误（应 1）** |
| **`composed != 0x12345678`** | **1** | **错误（应 0）** |
| `c ^ 1` 半字（字面量物化） | 0x5679 / 0x1234 | 字面量物化正确 |
| `1 - c` 半字 | 0xA989 / 0xEDCB | 32 位减法含字面量正确 |

→ 排除：合成、移位、减法、字面量物化、运行期比较。
→ 锁定：**只有"运行期值 vs 32 位字面量"的比较错**，且错误发生在比较前的
搬移（`SUBL ACC,XT; B EQ` 本身正确）。

### 2. 反汇编（expanded-probe.out，上一轮真机映像）

比较序列：
```
MOVL XAR7, @XAR6      ; ← 想把 k 搬进 XAR7
MOVL ACC, XAR3        ; XT = 0x12345678
MOVL XT, ACC
MOVL ACC, XAR7
SUBL ACC, XT
B .LBB0_2, EQ
```
`MOVL XAR7, @XAR6` 是"从 AR6 指向的内存读 32 位"，不是寄存器复制。

### 3. 编码与语义

`C28xMCCodeEmitter.cpp` 的 `MOV32rr` 分支：
```cpp
Word = xarOpcode(Dst, XAR_OP_MOVL_TO_XAR) | loc32RegEncoding(Src);
```
`loc32RegEncoding(XAR6)=0xA6` → `MOVL XAR7, @AR6`。原注释称"已用
asm2000/dis2000 对全部 64 组验证"——但那只验证了**编码一致性**，
没有验证语义：SPRU430F 中 `@ARm` 属于寄存器直接寻址（内存访问），
C28x 根本没有 `MOVL XARn, XARm` 这条指令。

### 4. 为何运行期比较能过

运行期 vs 运行期的比较路径不需要 XAR→XAR 搬移（值已在 ACC/XT），
故正确；一旦需要把值搬进另一个 XAR 参与 SUBL，就踩中该缺陷。

## 修复

### 第一轮（copyPhysReg，已重建但未覆盖故障路径）
`backend/llvm-c28x/C28xInstrInfo.cpp::copyPhysReg`：

1. `GR32→GR32`：改用 `PUSH32 src` + `POP32 dst`（32 位完整、不碰 ACC/XT）；
2. `XT→GR32`：同一类陷阱（loc32 的 0xAC = `@XT` 也是内存读），同样走
   PUSH32/POP32。

### 第二轮（2026-10-27，闭合真实故障路径）
把**所有**直接 `BuildMI(MOV32rr, XAR7)` 暂存改为 `PUSH32 src` + `POP32 XAR7`
（与第一轮同源手法，不碰 ACC/XT），并把反向的 `MOV32rr Dst, XAR7` 改为
`PUSH32 XAR7` + `POP32 Dst`：

- `C28xInstrInfo.cpp`：`TRUNC32_16`、`SHL/SRL/SRA32_VAR_PSEUDO`、
  `ADD32imm32/SUB32imm32`、`CMP32_PSEUDO`、`ADD32_PSEUDO/SUB32_PSEUDO`、
  `AND/OR/XOR32_PSEUDO` 共 6 处；
- `C28xRegisterInfo.cpp::eliminateFrameIndex`：1 处（XAR7→Dst）。

同时在 `MCTargetDesc/C28xMCCodeEmitter.cpp` 把 `MOV32rr` 编码分支改为
`report_fatal_error`——任何未被展开的 `MOV32rr` 走到发射器都会**显式报错**
而非静默发射内存读，从根上消除"编码看起来对、硬件读内存"的同类陷阱。
`C28xInstrInfo.td` 的 `MOV32rr` 定义保留但标注 DEPRECATED（已无发射点）。

LLVM 静态库 `libLLVMC28xCodeGen.a` 须用 ninja 重建（第一轮已做物理链接，
第二轮改动需再次重建；见下"待完成"）。

## 待完成（源码已修复，待重建 + 真机验证）

源码层面两路修复均已落地（copyPhysReg + 伪指令展开 7 处 + 编码器致命化）。
运行中的构建曾持有 B-1 发布锁，以下步骤待其结束后执行（第二轮改动需重建
`libLLVMC28xCodeGen.a`）：

```
powershell -File f28035-rust-bridge-b1\tools\build-rustc-c28x.ps1 -BuildHostStd
powershell -File f28035-rust-bridge-b1\tools\rebuild-core-sysroot.ps1
powershell -File f28035-rust-bridge\tools\build-b1-u32-compose-ram.ps1
# 期望全部 OK（含 [4]=1、[5]=0、[16]=[17]=0、[18]=1）
dss.bat tools\verify-b1-u32-compose-ram.js <ccxml> build\b1-u32-compose\u32_probe_ram.out
```

回归判据：`U32_COMPOSE=PASS`；随后重跑 `verify-cargo-runtime.ps1`
（`context_errors()` 应为 0，`HW_RT_RESULT[4]/[6]` 由 10 → 0）。

**注意**：该缺陷是**潜在（latent）**的——只在操作数被分配到普通 XAR（需经
XAR7 中转）时触发，分配到 ACC/XT 时走的是正确的 `MOVL_XAR_ACC`/`MOVL_ACC_XAR`
而绕开。所以此前多数 ALU 测试"碰巧"PASS，只有 u32-compose 探针确定性命中。
修复后建议对所有 32 位运算（加/减/乘立即/与或异或/移位/截断/比较）各补一条
"操作数落在普通 XAR"的回归用例，确认不再依赖寄存器分配运气。

## 风险提示

- 该缺陷影响**所有 XAR→XAR 的 32 位搬移**（不只比较）：任何把 long/指针/
  结构体字段在辅助寄存器间搬运的代码都可能读到垃圾。逐半字检查只是绕开
  了症状。
- 同族缺陷还包括 `MOVL XARn, @XT`（XT→XARn），已一并修复。
- 探针 `crates/b1-u32-compose` 与 `tools/verify-b1-u32-compose-ram.js`
  保留为回归用例（邮箱约定见 lib.rs 头注释）。

---

## 2026-10-28 独立复现 + 修复状态更新（静态反汇编复核）

### 1. 复现（无需真机即可判定）

在 active bundle `20261027-171858-19176840-5dfa55ed` 与新可用 bundle
`20261028-111803-1ced7f30-60498fb4` 上分别重编译 `crates/b1-u32-compose`
（`cargo rustc --target c28x-none-elf --release -- --emit=obj,asm`），两包生成的
`(hi as u32) << 16` 序列逐指令一致：

```
mov al, ar5        ; ACC 低 = hi (0x1234)
mov ah, #0         ; ACC = 0x00001234（hi 零扩展成 32 位）
movl xar6, #16
push xar6 / pop xar7
mov t, ar7         ; T = 16
lsl acc,t          ; ← LSL ACC,T 只吃 T(3:0)=4 位 → 移位 16 被当 0，等于没移
movl xar4, acc     ; xar4 = 0x00001234（本应 0x12340000）
... 两半字 OR 合成 → composed = 0x0000567C（应为 0x12345678）
```

→ **静态确认根因 = `LSL ACC,T` 移位量只取 T 低 4 位**，与同日第二轮硅片实测
（移位 16→0、17→只移 1 位）完全吻合。旧报告"根因未定"的前提不再成立；根因
已定位。

### 2. "新包是否同样有问题"——对当前可用包：是

两个已构建 bundle（active `5dfa55ed` 与 newer `60498fb4`）都仍发射 `lsl acc,t`
（T=16），即**当前已发布/可用的新包（`60498fb4`）仍带此 bug**。候选编译器
`20261028-114107-a66c78a7`（11:41）仅有编译器、无 c28x sysroot，无法直跑复现。

### 3. 修复已在工作树实现（但未打包）

`backend/llvm-c28x/` 存在大量未提交改动，其中：

- `C28xInstrInfo.cpp`：把 `SHL32_VAR_PSEUDO` 的展开指令由 `LSL_ACC_T` 改为
  `LSLL_ACC_T`。
- `C28xInstrInfo.td`：
  `// Legacy LSL ACC,T (FF50) only consumes T(3:0); LSLL uses T(4:0).`
  `def LSLL_ACC_T : C28xInst<... "lsll acc,t" ...>`（opcode 563B，移位量取 T 低 5 位，
  支持 0–31）。

→ 修复方向正确、对症下药：把 4 位掩码的左移换成 5 位掩码的左移长指令。
**但此修复仅存在于未提交工作树，尚无任何 bundle 包含它**——故仍不能用
"已修复" 来描述任何已发布的包。

### 4. 闭环待办

用当前工作树重新 `build-rustc-c28x.ps1` + `rebuild-core-sysroot.ps1` 打包，
再 `build-b1-u32-compose-ram.ps1` / `verify-b1-u32-compose-ram.js` 真机读邮箱，
确认 `composed == 0x12345678` 由 0 变 1，才算修复闭环。修复实施前，旧报告
"修复位置（未实施）" 的描述需更新为本节。

---

## 2026-10-28 修复闭环（静态 + 真机双证据）—— 13:59

**结论：修复已构建进新包，最小复现静态与真机均通过，当前新包不再带此 bug。**

### 构建路径（绕过脚本包装的缺陷）

`build-rustc-c28x.ps1` 的包装环节有缺陷：它在跑 x.py 前调用
`Disconnect-C28xBootstrapSources`（`rustc-source-state.ps1:64`）删除了
`rust-build-gcc14fix\host\stage0-sysroot\lib\rustlib\rustc-src\rust` 等指向源码的
junction，导致 x.py 在启动 cargo 构建 bootstrap 后异常死亡、留下孤儿 cargo 空转。
**改用直接跑 x.py 绕开**：

1. LLVM C28x 后端：`libLLVMC28xCodeGen.a` 已含修复（opcode `563B` 存在、旧 `FF50` 归零）。
2. `python x.py --config bootstrap.toml build --stage 1 --jobs 6 compiler/rustc`
   （env 用脚本一致的 PATH=`$selfBin;D:\mingw64\bin;$gnu\bin;...`、RUSTUP_HOME、
   LIBRARY_PATH、linker、TEMP；并 touch `llvm-config` 强制 rustc_llvm 重链）。
   → `Build completed successfully in 0:04:56`，stage1 `rustc.exe` 13:54:13。
3. 手动 `Publish-C28xCompiler`（c28x-only，无 host std）→
   candidate `20261028-135552-78ef1fa0`（因 C: 仅剩 0.33GB，`C28X_RELEASE_ROOT`
   指向 `D:\c28x-toolchain\b1-release`）。
4. `rebuild-core-sysroot.ps1`（同 root）→ 新 bundle
   `D:\c28x-toolchain\b1-release\bundles\20261028-135552-78ef1fa0-139f7317`
   （core rlib 43.7MB，builtins 85.9KB，已校验未激活）。
5. `build-b1-u32-compose-ram.ps1`（`C28X_B1_BUNDLE` 指向新 bundle）→
   `U32_COMPOSE_BUILD=PASS`。

### 静态证据（`.s` 反汇编）

新包编译的 `b1_u32_compose-f8c022703cb15046.s`：
- **`lsll acc,t` × 3，`lsl acc,t` × 0**；
- 关键序列：`movl xar6,#16; mov t,ar7; lsll acc,t`（L76–L80）——按 16 正确左移，
  替代旧包错误的 `lsl acc,t`（4 位掩码 → 移位 16 变 0）。

### 真机证据（XDS100，DSS）

`verify-b1-u32-compose-ram.js` 读邮箱 `0x9E00` 全部 25 格匹配，**`U32_COMPOSE=PASS`**；
关键格 `[4]=1`（`composed==0x12345678` 通过，旧 bug 下为 0）。

### 遗留

- `build-rustc-c28x.ps1` 的 x.py 死亡缺陷仍未修复（本次为绕过，非修好脚本）。
- 本次新包在 `D:\c28x-toolchain\b1-release`（C: 空间不足迁盘），未走完整发布验收
  `verify-b1-release.ps1`（那需真机全项，非本 bug 复现所需）。
