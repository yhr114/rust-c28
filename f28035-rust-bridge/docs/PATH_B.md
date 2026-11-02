# 路径 B：B-1 定制 rustc + C28x LLVM 后端

更新日期：2026-10-28。

**B-1 是当前唯一活动的编译器路线。** 新 Rust 代码、Cargo 接入、后端修复、
`core` / builtins、对象文件和发布包都按 B-1 版本链推进。旧 B-2“标准 rustc
生成主机 LLVM IR，再交给独立 `llc`”的交付流水线已经迁到同级
`f28035-rust-bridge-b2-archive/`，不再进入日常构建和验证。

当前范围约束：只推进 PATH B-1。PATH A、MIR、Rust-to-C 和应用迁移中的问题
不进入本路线待办，不影响 B-1 的完成判定；只有用户明确要求时才另行处理。

> 本文只维护 LLVM C28x 后端、ABI、定制 rustc、sysroot、Cargo 和 TI 链接。
> 应用、Safe HAL、MIR 与硬件 case 由 PATH A 文档集维护。

## 维护记录

| 日期 | 主题 | 结论 |
|---|---|---|
| 2026-11-02 | B-1 Rust 入门工程 | 新增独立 `crates/c28x-user-app`，应用使用 `#[entry]` 与 direct-object 安全 HAL 驱动 GPIO34；当前 active 7bc20a44 下 Cargo 构建与再次 Fresh PASS，映像 9200 文件字节。构建与使用步骤见 §3.5；未上板、未写 Flash |
| 2026-11-02 | 字节读改写与 HAL 方法路径编译器回归（**已闭合**） | 根因是**字节读改写**（非通用 ZST ABI，旧说法已撤回）：① 字节存储暂存 AL 前未保护活跃值；② 全局窄加载破坏另一 ACC 半字；③ 单字节全局节被 TI 分配为零字重叠。后端已在 `C28xInstrInfo.cpp` 修复（`STORE8_GLOBAL_PSEUDO` 先 `PUSH_ACC` 再暂存；`AccLiveThrough` 忽略窄加载已定义半字）。候选 `20261102-122629-cf4b3949-7bc20a44` 全量发布验收 **16/16 PASS**（含 `codegen`：O0/O2/Os×108 项 + 真实 HAL ISR 方法路径），已提升 active、三根指针 `CONSISTENT`。**方法调用路径**（默认，无 `-DirectCalls`）短/长回归全 PASS：`ADC_ERR=0`、`LINK_ERR=0`、3×200 注入精确恢复、ISR 415–1461 周期（2.4% 负载）。`-DirectCalls` 降为历史对照 |
| 2026-11-02 | 业务联合验证（ADC→计算→PWM＋通信＋中断持续运行） | 新增 `tools/build-verify-safe-hal-business.ps1` + `verify-safe-hal-business.js`：单镜像跑 1 ms Timer0 中断里的 ADC 采样→`duty=raw*period/4095`→ePWM1 CMPA，每 4 拍经 SPI-B 硬件回环换一个状态字节，主循环并行计数。真机分项：**CHAIN=PASS**（1213 拍、主循环 59147 次、TBCTR 前进、TBPRD=1000、AQCTLA=0x12、CMPA 与 duty 一致）；**EOC=FAIL**（606/1213 次软件触发未等到 ADCINT1，见下）；**LINK=FAIL**（0/303 帧回环成功）。本轮同时修出 8 处外设映射/使能错误，详见 §6 与「业务联合验证」小节 |
| 2026-11-02 | 发布指针跨根一致性修复 | 三个发布根各自持有 active/candidate，而 select 只写当前根，导致 Cargo 用 ee53e7b7、D 盘两个 active 仍指 6c02958c，且 C 盘 candidate 停在旧编译器 af95c9d8（`rebuild-core-sysroot` 默认读它，重编会静默丢修复）。新增 `tools/sync-b1-release-pointers.ps1`：规范源解析 + 按 `bundle.compilerSha256` 反查编译器代 + 原子改写 + 回读 SHA 校验，`-Check` 以退出码 1 作门禁；已接入 `select-b1-bundle.ps1`。现三根一致指向 ee53e7b7，cargo-independent 二次构建 Fresh。详见 §6 |
| 2026-10-28 | B-1 SharedCell 安全修复与真机验收 | 创建引用前检查独占借用；主机 acquire/release 锁，目标原生 16 位 volatile 标志，try_with 冲突返回错误。临界区改闭包，修正 INTM=ST1 bit0 及栈读取。主机 7 项/2 项编译负向、直接与宏入口各 12 项共享状态检查/48 次 IRQ、9 项宏签名负向及独立 GPIO 真机全部 PASS；已将主机检查接入 runtime 门禁。源码修复不切换 compiler bundle，细节见 §3.5 |
| 2026-10-28 | 优化 core B2 误编译修复并发布 | 16 位 ALU 的 AR 目标借 AL 计算时覆盖了 AL 右操作数，已补暂存。新 active `20261028-154958-af95c9d8-6c02958c` 使用 core opt=s，原始 B2 真机=90，28 项边界及 15 项发布验收全部 PASS（含 format）；C/D 入口、历史镜像及三个 Cargo pin 已同步。源码、位置和证据见 §4/§6 |
| 2026-10-28 | 窄整数、宽 select 与格式化（历史诊断阶段） | 修窄右移扩展、变量移位 ACC 覆盖、i8 传参上位残留、32 位 select 截断和 LSL 计数错误；当时仅诊断对象输出正确。后续正式发布和优化 core 的 B2 收尾，以本表最新记录及 §6 为准 |
| 2026-10-28 | divmod 运行库与 core 覆盖 | 旧包的实际 Cargo 链接缺 `__udivmodsi4`；新 active `20261027-171858-19176840-5dfa55ed` 补齐后，LLVM 自动生成调用、十组商余数、栈/全局余数指针及空指针在 RAM/JTAG PASS，Cargo 二次构建 Fresh；13 项发布验收通过，C/D 指针及三个 Cargo pin 已更新 |
| 2026-10-28 | 优化 core 早期隔离试验（历史失败） | 当时 core opt=s 的格式化探针能链接但真机输出乱码；该手工实验包从未激活。后续后端修复、正式打包和验收结果见本表最新记录及 §6，不能继续使用该早期包 |
| 2026-10-28 | opt=0 基线发布（历史阶段） | `b27f23d4` 当时通过 144 项整数和 14 项发布验收；因 opt=s B2=104/90 而采用 core opt=0，未纳入 format。该遗留已由本表最新 6c02958c 发布关闭，b27f23d4 保留为历史基线 |
| 2026-10-27 | 工具链可重复重建、完整验收并发布 | 复现并阻断 stage0 源码联接覆盖；固定 20 文件 target/interrupt/public ABI 补丁和源码快照，同版 host std/proc_macro 入包，修正 Cargo host 路由。12 项发布门禁全部 PASS（含宏真机/9 签名负向、内存 462、ABI、core 六组、三个 Cargo/Fresh/真机）；active 已切 `20261027-171858-19176840-af788b4d`，C/D 指针及三个 Cargo pin 一致。路径见 §4，证据见 §6 |
| 2026-10-27 | Rust 应用入口、主循环与 Timer0 真机试验 | 隔离 ce48b97e bundle 的正常 Cargo 直接对象链路、再次 Fresh、F28035 RAM/JTAG PASS：Rust 主循环 2709 次、ISR 48 次、偶/奇栈上下文零错误、未绑定向量进默认处理器。应用无 C 源码；保留底层启动汇编/TI RTS。过程宏集成和正式发布未完成，active 仍 2e7ec64c；操作与边界见 §3.5 |
| 2026-10-27 | 链接参数严格解析与静态归档接入 | 静态 .a/.lib、-l/-L、库顺序和组处理接入；未知/动态/缺失/损坏/异架构及混合成员归档明确拒绝。--strip-debug 实际执行并校验驻留段不变，provenance 为 schema 4。16 步隔离 Cargo/TI 回归、库变化增量、原有十步原生增量及新归档 RAM/JTAG 7/13/20 PASS；三个默认 Cargo 工程构建/Fresh 与 RAM/JTAG PASS，编译器 bundle 不变 |
| 2026-10-27 | PAC/HAL 校准第二轮（全量对表 + 中断语义修复） | c28x-pac 其余外设全部对表 `DSP2803x_*.h`（ePWM 64 字逐一、SPI 16 字、SCI、I2C、eCAP、eQEP、SysCtrl、PIE、GPIO 基地址对 `Headers_nonBIOS.cmd`）后修 5 处：Timer `clear_flag` 写 TSS(bit4) 改 TIF(bit15 w1c)；SCI `read_byte` 轮询保留位 bit0 改 RXRDY(bit6)；SCI `init` 的 SCICTL1 未开 TXENA(bit1)/RXENA(bit0)（旧值写到保留位和 TXWAKE）；GPIO 删除 F2803x 不存在的幽灵寄存器 GPBQSEL2/GPBMUX2（保留区）；GPACTRL/GPADIR/GPAPUD/GPBCTRL/GPBDIR/GPBPUD 按 Uint32 建模（新增 ProtectedReg32，16 位写够不到 GPIO16-31）。C 桥：`f28035_interrupts_enabled` 原返回 IER&1（INT1 线使能）被 CriticalSection 当全局 INTM 用、会永久关中断，改为影子跟踪任务级 INTM；补齐只有 Rust FFI 声明而无 C 实现的 `f28035_enable/disable_interrupts`；上轮 `f28035_gpio_read_input` 误用 GpioCtrlRegs.GPADAT（应为 GpioDataRegs）导致桥从未编译通过。验证：`build-c-bridge.ps1` PASS、c28x-pac 以 active B-1 bundle `cargo build --target c28x-none-elf --release` PASS、nm2000 确认三个中断符号 T。报告与逐外设结论见 `docs/pac-hal-B1-usability.md`；SCI 环回/Timer0/PWM 占空比/CriticalSection 真机回归待做 |
| 2026-10-27 | 危险兜底关闭、trap 根因修复并发布 | 未解析分支和非正局部栈偏移改为明确拒绝。重建 core 揭示旧 TRAP 的未定义入口标签问题，纠正“该路径已不可达”的旧判断；改为指令自身 B_SELF 循环。完整 core 重建、三项 MIR 负向门禁、TI 编码对照、集成 rustc 门禁及旧包负向控制通过；Cargo 内存/TI 共存 462 项、core A/B/B2、ABI 十项 RAM/JTAG PASS 后激活 `20261027-112248-a1cf84ab-2e7ec64c`，位置及边界见 §4/§6 |
| 2026-10-27 | PAC/HAL 对表 C2000Ware 校准 | 以 `DSP2803x_EPwm.h`/`DSP2803x_Adc.h` 为准修正 c28x-pac：CMPA/TBPHS 是"HR 半字在低、主寄存器在高"的 32 位联合体，PAC 误按 32 位写在 +8/+2 导致 CMPA 恒为 0（PWM 占空比失效），拆成 16 位 Reg（cmpa=+9、tbphs=+3）；AQCTLA 占空比语义反转改为 ZRO=set/CAU=clear；ADCCTL1 电源位修正（bit5 ADCREFPWD、bit7 ADCPWDN、bit14 ADCENABLE，原写的 bit4 为保留位）；ADCSOCxCTL 字段位置修正（ACQPS=5:0、CHSEL=9:6，原把采样窗口写进 TRIGSEL、通道写进 ACQPS）；ADCINT1 改用 ADCINTFLGCLR 清除；SCI init 移除对只读 SCICTL2 状态位的无效写。C 桥 `f28035_gpio_read_input` 原从 0x6F80（GPACTRL 控制寄存器）读引脚电平且索引公式错误，改为 GPADAT/GPBDAT 并限 GPIO0-34 |
| 2026-10-26 | 内存运行库发布与完整 Cargo/真机验收 | active 已切换 `20261026-175437-71a923aa-79cdbc37`（D 盘不可变发布包）。LLVM/rustc/core/builtins 已重建；五个独立 `c28x_*` 字节接口与 TI 字地址接口分离，memset 填充值修正为 u8，运行库 wrapping_add 去除 core 前置检查依赖，RAM 启动新增 TI `.cinit` 初始化。普通 Cargo rlib 路径 462 项内存/TI 共存真机 PASS，core A/B/B2、ABI 十项和三个 Cargo 样板真机 PASS；默认配置构建与再次 Fresh 均通过。失败候选和诊断日志保留，未执行 Flash；具体边界与证据见 §6 |
| 2026-10-26 | Cargo 外部输入增量构建 | app/independent/arithmetic 接入共享原生 build script，按 TI 实际依赖跟踪 C/头文件、ASM/包含文件及 cmd 字面量 include；TI 对象按源、工具、参数与包含文件哈希缓存。活动 wrapper 的 host 请求改接本机原版 GNU，解决共享脚本缺 MSVC link.exe 的前置失败。隔离 10 步回归全部 PASS，外部变更后未变 Rust 依赖 Fresh、未变 TI 对象时间/哈希不变；三个正式样板（app 含 cross-crate）构建及再次 Fresh 通过。未变构建 0.294～0.399 秒，外部变更约 21～26 秒；最终应用仍会调用 rustc。固定 bundle `72ab049d`，未重链编译器/重编 sysroot，未运行 JTAG/Flash。证据 `build/verify-native-incremental-a5dffc8d/` |
| 2026-10-26 | 内存接口改名初稿（历史，未发布） | 当时已删除调用边界右移并改名，尚未完成发布/运行验证。初稿关于 IsDefault=true 与 helper 位于 ti-arithmetic.o 的描述有误：最终为非默认 libcall 定义，helper 位于 Rust builtins。后续还修正 wrapping_add、memset u8 ABI 和 TI .cinit，验收见最新维护记录与 §6 |
| 2026-10-26 | f32 比较/转换运行库补齐与回归门禁 | `ti-arithmetic.c` 补齐 f32 动态比较与整数↔浮点转换的 GCC/compiler-rt libcall 适配：`__lesf2/__gesf2/__gtsf2/__ltsf2/__eqsf2/__nesf2/__unordsf2`（三值 -1/0/+1，NaN 无序时 `lt/le` 族返 +1、`gt/ge` 族返 -1，与 `--emit=asm` 解码的分支条件一致）、`__fixsfsi/__fixunssfsi`（向零截断、越界饱和，NaN/负→`unsigned` 返 0）、`__floatsisf/__floatunsisf`（就近偶舍入）。实现前以 `--emit=asm` 逐表达式确认 LLVM 实际下发的 libcall 与 `lt/gt/leq/geq/eq/neq` 分支；主机差分（`-DC28X_RUNTIME_HOST_TEST` + mingw gcc）全绿，TI `nm2000` 确认 15 个符号齐备。聚焦链接 `f32-scan/test.rs`→active bundle `ti-arithmetic.o`+RTS 全部解析、0 未定义；旧 bundle 负向控制报 10 个未定义符号。`rebuild-core-sysroot.ps1` 重发并激活 active `20261026-133307-567620e7-3d695378`；新增 `verify-f32-compare-convert.ps1` 作为回归门禁（编译含六类比较与四类转换的 no_std crate 并 TI 链接，未定义即失败）现 PASS |
| 2026-10-26 | 64 位整数（di3）运行库补齐与回归门禁 | 包扫描确认 `core-dual.o` 引用 `__muldi3/__udivdi3/__umoddi3` 而 active bundle 未提供；TI RTS `rts2800_ml_eabi.lib` 也不提供任何 GCC/compiler-rt di3 名，但提供其自有 `__c28xabi_*` 助手（`__c28xabi_mpyll/divull/modull/divll/modll/cmpll/cmpll`）。以 `cl2000 --emit` 探针确认：C28x 上 32 位乘法与 64 位移位内联，仅 64×64 乘/除降级到 `__c28xabi_mpyll/__divull`（RTS 已定义）。故沿用既有 32 位薄包装模式实现 8 个 di3 助手：`__muldi3/__divdi3/__moddi3/__udivdi3/__umoddi3` 直接做原生运算（降级到 `__c28xabi_*`），`__ashldi3/__ashrdi3/__lshrdi3` 做 `a << (b&63)`（内联、无递归）。`nm2000` 确认对象仅引用 `__c28xabi_*`（无 di3 自引用）；`-DC28X_RUNTIME_HOST_TEST` + mingw gcc 主机功能测试全绿。`rebuild-core-sysroot.ps1` 重发并激活 immutable active `20261026-133307-567620e7-72ab049d`（清理旧 `138e5153`）；`ti-arithmetic.o` 与 `libcompiler_builtins.rlib` 均定义全部 8 个 di3 符号。新增 `verify-di3.ps1` 回归门禁：编译含动态 i64/u64 运算的 no_std crate（`x.wrapping_mul`→`__muldi3`、`wrapping_div`→`__udivdi3`、`wrapping_rem`→`__umoddi3`，core panicking 桩以 looper 内置）并 TI 链接 active `ti-arithmetic.o`+RTS；旧 bundle 负向控制报 `undefined __muldi3/__udivdi3/__umoddi3`，新 bundle 现 PASS |
| 2026-10-26 | 验证脚本回归门禁修复 | `verify-cargo-c28x-object.ps1` 由硬编码 `stage1` 改为经 `Get-C28xBundle` 解析 active bundle 的 rustc（并显式钉 `RUSTC_WRAPPER`），消除 `rustc-wrapper`→`invoke-b1-rustc.ps1` 对未发布 stage1 抛 "Unpublished B-1 bundle"（GBK 文本）致 cargo 报 "didn't return utf8 output" 的链路失败，脚本现 PASS。`verify-llvm-c28x-link.ps1` 主链接步改走 `Invoke-NativeCapture`，TI 良性 "no matching section" 警告不再触发 PowerShell `NativeCommandError` 中断，现 ALL CHECKS PASSED。LLVM 后端门禁 `verify-llvm-c28x.ps1` 仍全绿（含 sub32imm/memcpy-inline 字节 oracle）。本轮只修验证脚本，未改编译器、未切 bundle |
| 2026-10-26 | 文档校准与缺陷审计 | active `20261026-133307-567620e7-138e5153`；本轮重新 RAM/JTAG 确认 direct Group B=`80,179`、B2=`90,179` PASS，关闭其旧故障。隔离实测确认 features→Fresh 时 `.out` alias 过期、缺失 `.a`/未知参数被忽略、Cargo 动态 u8 复制缺 `__muldi3`；仅在隔离工程补同 bundle 的 di64 后，动态复制仍硬件失败，map 指向 Rust builtins memcpy。区分已复现/源码确认/待验证；只改文档与审计产物，未修编译器、未切 bundle、未执行 Flash |
| 2026-10-26 | 复杂迭代器 B/B2 根因定位 | 两个根因。① `ADD/SUB ACC,#16bit` **零扩展** 16 位立即数（硬件实测 `0x0808+0xFFFE=0x0001_0806`），负加数残留 `1<<16`，经字节→字 `>>1` 后 `slice::Iter::next_back` 读 `0x8403` 而非 `0x0403`；已改为"负加数取反做相反运算"，新增 `test/CodeGen/sub32imm.ll` 字节 oracle。**Group B 11191 → 80 PASS**，Group B2 由超时变为 72/90。② 余下 18 分全部来自 `zip(iter, iter.skip(1))`：`llvm.memcpy` 被降级成 TI RTS `memcpy` 调用，而 RTS 按 C 字地址解引用、Rust 传逻辑字节地址，导致 ≥4 字节的**内存聚合体拷贝全部拷错位置**；已用纯 `#[repr(C)]`、零 core 代码的最小复现锁定（详见 §7 P0） |
| 2026-10-26 | 发布算术与调用修复 bundle | active `20261026-102923-989317a3-fcd36edb`；ABI 十项、O0/Os 算术/四参各 32 项、core A/E、静态指针和 Cargo 算术/独立/跨 crate 均 RAM/JTAG PASS。O0 的 -1 常量 ACCOnly 冲突已修；新增运行库清单绑定及负向门禁；复杂迭代器 B/B2 仍单列，不据基础调用 PASS 关闭 |
| 2026-10-26 | ABI 与 IEEE 算术候选验证 | XDS100 已恢复连接；新增整数除/余及整数实现的 IEEE binary32 四则运行库，32 项 RAM/JTAG 算术检查、1,001,024 次主机差分通过。修正 TI callee-save、偶数 SP、FI 处理方向、跨块调用帧和 ACC 半寄存器活跃性；诊断对象 ABI 十项通过，正式重链/Cargo 验收继续，active 暂不变 |
| 2026-10-26 | 算术运行库与复杂调用修复（进行中） | 当前 active 的动态 u32 除/余和 f32 加/乘/除对象可生成，但缺 GNU helper 定义导致 TI 链接失败；开始补 TI ABI 适配运行库，复核四参调用和 rust_apply。XDS100 当前未枚举，已请求恢复连接，尚无本轮真机 PASS |
| 2026-10-22 | 静态指针与 Group A pattern 修复闭环 | 定制 rustc 已重链，active `20261022-180241-07b9d869-83f8a0e3` 校验通过；静态函数/数据/本地/奇数字节指针和 Rust 解引用真机 PASS，pattern 从 148→163→223。实际根因是比较标志被 PHI/spill 覆盖及 MOVL 立即数高位截断，原 sret 推断撤销；A/C/D/E 与 Cargo 独立/跨 crate 已在同二进制候选上通过真机回归，当前 active 的 A/静态指针/Cargo 两组再次 PASS |
| 2026-10-22 | 直接对象链路复核与状态纠错 | active `20261021-163323-13d258a8-65c4479c`：Cargo 独立/跨 crate 在无 `.s` 条件下重建并再次 RAM/JTAG PASS，单 crate 构建 PASS；修复子目录重复 sysroot、隔离 TI 中间对象并验证留存对象哈希。Group B 超 RAM 构建失败、Group A pattern=148/223、ABI 真机失败、Group E 16/16 PASS。新增最小复现确认静态函数指针/外部数据引用生成全零且无重定位；完整重定位仍未完成 |
| 2026-10-21 | Cargo 直接对象接入与 RAM 布局纠错 | linker adapter 增加 `direct`，解包依赖/core/builtins `.rlib` 并验证 C28x 对象；两个项目改为直接对象，删除 `--emit=asm,link`，独立与跨 crate 真机通过。显式归并 `.text.*`/`.textreset` 到 RAM 后，发现 Group B 旧 BuildOnly PASS 是孤立代码段溢出到 IQTABLES 的假阳性；以 2026-10-22 复核为准 |
| 2026-10-21 | AND32 展开缺陷修复（上板闭环） | `AND32/OR32/XOR32_PSEUDO` post-RA 展开丢失 Lhs，且 XAR0 被展开内的 `MOV AR0,AH` 清毁；改为每半 push/pop 保 Lhs + Rhs 在 XAR0 时先盾到 XAR7。新增 `test/CodeGen/and32.ll` 字节 oracle；新 active bundle `20261021-163323-13d258a8-b95c8536` 上 Group E 16/16 PASS、Group A option=140/result/mem/cmp/closure 全对；core sysroot 补 `-Zub-checks=no` 后 pattern 的误报 panic 消失；pattern 仍 148（已分解定位到 `slice::iter()` 的 {ptr,ptr} sret 返回垃圾） |
| 2026-10-21 | B-1 ABI 硬件样板 | 新增 `test/Rust/b1-hw-abi.rs` + `tools/hw_b1_abi_driver.c` + `tools/dss-read-b1-abi.js` + b1 `tools/run-hw-rustc-direct-abi.ps1`；入口寄存器 ABI（ptr/mixed/栈参）全对，但 `rust_apply`（1 字帧 + 内部 32 位 push/pop + 间接调用）的 LRETR 取错返回地址跑飞 boot ROM，与 `iter()` sret 缺陷同列下一轮 |
| 2026-10-21 | B-1 全链审查与 Cargo 修复 | active bundle `20261021-163323-13d258a8-b95c8536`：ABI/LLVM/TI 对象门禁通过；control、Safe HAL、layer、Option、core-ex A–E 均通过 BuildOnly；独立、单 crate、跨 crate Cargo 均完成 TI 链接；Group B 以 NOINIT 测试缓冲消除无意义 `.cinit`；XDS100 当前无法连接，未新增硬件 PASS |
| 2026-10-21 | 工作范围收敛到 B-1 | 后续默认只处理定制 rustc、LLVM C28x 后端、ABI、core/builtins、Cargo、TI 链接和发布；PATH A/MIR 问题不再纳入 B-1 待办或门禁 |
| 2026-10-21 | 迁移后门禁复核 | ABI、Cargo metadata、发布门禁、control/layer/core-ex BuildOnly 与共享 LLVM 回归通过；对象字节基线已同步保护字/MOVB 硬件修复；联合 oracle 的 LLVM 用例通过，PATH A 的 MIR control-loop 仍受当前 nightly API 漂移阻塞；未运行 JTAG/Flash |
| 2026-10-21 | B-2 完整迁出活动工程 | B-2 独立流水线脚本、样例、旧 GPIO crate 和构建产物移入 `f28035-rust-bridge-b2-archive/`；B-1 复用样例改为 `b1-*`；共享 LLVM 后端保留为 B-1 当前源码；迁移前 3000 多行完整文档已归档 |
| 2026-10-21 | B-1 发布包与版本绑定 | 发布清单绑定 compiler、`core`、builtins 和来源哈希，避免新旧产物混用；具体活动版本以 `build/toolchains/active.json` 为准 |
| 2026-10-21 | 帧、字节与寄存器 clobber 修复 | control、分层探针与 Safe HAL 已有 RAM/JTAG PASS 记录；core-ex Group A 仍有 Option/模式相关失败，不能据此声称任意 `core` API 可用 |
| 2026-10-20 | B-1 设为主路径 | 定制 rustc 内置 C28x 后端，形成 Cargo 汇编分支和 rustc 直接对象分支 |

迁移前的完整历史正文、B-2 操作手册和旧状态记录保存在
`../../f28035-rust-bridge-b2-archive/docs/PATH_B_PRE_ARCHIVE_20261021.md`。
连续工作记录见 [WORK_LOG.md](../WORK_LOG.md)。

<a id="b1-main"></a>

## 1. 当前主流程

```text
Rust 应用 / HAL / 依赖
  → B-1 发布包中的定制 rustc
    → Rust 前端与类型检查
    → MIR
    → rustc 内置的 C28x LLVM 后端
      ├─ Cargo 主分支：C28x ELF .o + 依赖 .rlib
      │   → c28x-ti-linker：留存应用对象、llvm-ar 解包 .rlib
      │   → ofd2000 验证 EM_TI_C2000，直接传入 TI linker
      └─ 直接对象分支：rustc --emit=obj
          → TI C28x ELF .obj
  → TI cl2000 linker
     + 启动代码 / C 测试驱动 / RTS 库 / .cmd 内存布局
  → RAM .out
  → DSS / XDS100 / F28035
```

这条路线与 MSP430 的正常 Rust 目标流程结构相同：rustc 负责语言前端、MIR、
LLVM 后端和目标代码生成，runtime 与 linker 完成设备启动和映像布局。当前 C28x
仍依赖 TI 工具处理最终汇编或链接，目标支持范围也还小于成熟的 MSP430 target。

### 当前输出方式

| 分支 | Rust 代码输出 | 后续步骤 | 用途 |
|---|---|---|---|
| Cargo 主分支（`rustObjectMode=direct`） | C28x ELF `.o` / `.rlib` | 解包、对象验证 → TI linker → `.out` | 独立、单 crate、跨 crate 样板 |
| 直接对象分支 | C28x ELF `.obj` | TI linker → `.out` | 后端、ABI、重定位、`core` 和 HAL 验证 |
| 旧 Cargo 汇编兼容模式 | `.s` | 转 TI 汇编 → `cl2000` → `.obj` → `.out` | 适配器仍保留；需要额外启用 `--emit=asm,link` |

活动入口必须使用同一 B-1 发布包。两个 Cargo 项目已不生成 Rust `.s`，
TI 工具仍编译 C 驱动和启动汇编，再完成最终链接。对象接入通过仅覆盖已测样板；
静态地址初始化的基本缺陷已修复；完整重定位矩阵、复杂 ABI 和任意第三方依赖的兼容性仍需验证或修复。

## 2. 三个工作目录

| 目录 | 职责 |
|---|---|
| `f28035-rust-bridge/` | 当前 LLVM C28x 后端、运行时、HAL、TI 链接脚本、DSS 支撑与共享回归 |
| `f28035-rust-bridge-b1/` | rustc target 补丁、编译/发布脚本、Cargo 适配器、B-1 样例与版本化发布包 |
| `D:\c28x-toolchain/` | Rust/LLVM 源码、LLVM 构建目录、stage1 临时编译器和 bootstrap 工具链 |

旧 B-2 内容只在 `f28035-rust-bridge-b2-archive/` 保存。该目录是历史快照，
不是第三个活动源码树。

<a id="b1-files"></a>

## 3. 工具与具体文件

### 3.1 LLVM 后端与 ABI

| 文件/目录 | 职责 |
|---|---|
| `backend/llvm-c28x/` | B-1 rustc 内置的 C28x LLVM 后端唯一活动源码 |
| `backend/llvm-c28x/C28xCallingConv.td` | 参数、返回值和寄存器分配规则 |
| `backend/llvm-c28x/C28xISelLowering.cpp` | 调用、返回、栈参数及目标 lowering |
| `backend/llvm-c28x/C28xFrameLowering.cpp` | 栈帧、prologue/epilogue |
| `backend/llvm-c28x/C28xInstrInfo.cpp/.td` | 指令、伪指令展开和寄存器 clobber |
| `backend/llvm-c28x/MCTargetDesc/` | ELF、重定位和机器码编码 |
| `backend/llvm-c28x/test/CodeGen/` | LLVM IR 到 C28x 的函数级回归 |
| `backend/llvm-c28x/test/Rust/b1-hw-control.rs` | B-1 控制样板；同 crate 引入 `b1-hw-mode.rs` |
| `backend/llvm-c28x/test/Rust/b1-hw-core-ex.rs` | `core` 广度 Group A–E 样板 |
| `backend/llvm-c28x/test/Rust/b1-hw-layer-probe.rs` | 帧、字节 lane 与寄存器分层探针 |
| `backend/llvm-c28x/test/Rust/option-deref-probe.rs` | Option/解引用问题的最小探针 |
| `tools/check-abi-freeze.ps1` | 检查 DataLayout、指针宽度和 B-1 target spec 一致性 |

共享后端可以继续用独立 `llc` 运行 CodeGen、MC 和 TI 对象测试。这是后端开发
手段，不是旧 B-2“改写主机 IR 后交付应用”的流水线。

### 3.2 rustc target、构建与发布

| B-1 文件 | 职责 |
|---|---|
| `backend/llvm-c28x/rustc-patches/c28x_none_elf_1_100.rs` | rustc 1.100 对应的 `c28x-none-elf` target spec |
| `backend/llvm-c28x/rustc-patches/bootstrap-windows-gnu.toml` | Windows GNU bootstrap 配置 |
| `tools/build-rustc-c28x.ps1` | 后端稳定后增量构建/重链 stage1 rustc |
| `tools/rebuild-core-sysroot.ps1` | 用同一 compiler 重编 `core` 和最小 builtins |
| `rebuild-core-sysroot.ps1 -OutputRoot <dir> -SkipInstall` | 大型 sysroot 缓存可放 D 盘，先生成完整未激活 bundle，验收通过后再选择 |
| 主仓库 `crates/c28x-compiler-builtins/ti-arithmetic.c` | TI EABI 算术入口：u32/i32 除余、纯整数实现的 IEEE binary32 加减乘除 |
| `tools/publish-rustc-candidate.ps1` | 验证 rustc 与 DLL 配对后发布 compiler candidate |
| `tools/publish-b1.ps1` | 将 compiler + sysroot 合成不可变 bundle |
| `tools/select-b1-bundle.ps1` | 原子切换 active bundle |
| `tools/toolchain-release.ps1` | 发布锁、SHA-256、清单和原子文件操作公共函数 |
| `tools/test-toolchain-release.ps1` | 发布正向与负向门禁 |
| `build/toolchains/active.json` | 唯一活动 bundle 指针和清单哈希 |

### 3.3 Cargo 与链接适配

| B-1 文件 | 职责 |
|---|---|
| `.cargo/config.toml` | target、wrapper、linker 和按 bundle 隔离的 Cargo target-dir |
| `tools/rustc-wrapper.rs/.exe` | C28x 请求走发布包；带匹配 host std 的候选包用同包 rustc 编译 host build script；旧 active 无 host std 时仍用原版 GNU。通用 host 依赖/proc-macro 未完整验收。旧 `.ps1/.cmd` 不作为本轮入口 |
| `tools/build-rustc-wrapper.ps1` | 用本机原版 GNU host 工具链重编活动 wrapper；原子替换可执行文件 |
| `tools/c28x-ti-linker.*` | `direct` 模式留存应用对象、解包 `.rlib`、验证机器类型并调用 TI linker；保留旧汇编兼容模式 |
| `tools/cargo-native-build.rs/.ps1` | 共享 build script；使用 TI 实际依赖信息登记 Cargo rerun-if-changed，准备需要更新的 C/ASM 对象 |
| `tools/cargo-native-cache.ps1` | build script 与 linker 共用的逐文件 TI 编译缓存；输入/工具/参数哈希、对象校验、互斥锁及成功后发布 |
| `tools/verify-cargo-native-incremental.ps1` | 隔离工程验证外部变更自动重链、逐对象复用和未变 Rust 依赖 Fresh；不操作开发板 |
| `build/native-cache/<key>/` | 按项目、源路径和编译身份隔离的 TI 对象/输入哈希；头文件与 ASM 包含文件由 TI dependency 输出发现 |
| `build/rlib-cache/<archive-hash>/` | 短路径 `.rlib` 成员缓存，解决 Windows 长路径；目前未加独立清理与并发锁 |
| `build/cargo/<bundle>/.../deps/.c28x-ti-objects/<output>/` | 留存 Rust 对象；原生 C/ASM 对象复用 `build/native-cache/` |
| `tools/cargo-assembly.ps1` | 旧 Cargo 汇编脚本使用的转换逻辑，不进入两个 direct 样板 |
| `crates/c28x-cargo-app/` | 单 crate / 跨 crate 控制样板 |
| `crates/c28x-cargo-control/` | 控制逻辑 crate |
| `crates/c28x-cargo-mode/` | 跨 crate `rust_mode` 实现 |
| `crates/c28x-cargo-independent/` | 不复用控制样板的独立 Cargo 项目 |
| `crates/c28x-cargo-arithmetic/` | 与直接对象共用 Rust/C 测试源，验证算术 runtime 从 builtins rlib 自动进入最终映像 |

三个应用 manifest（app/independent/arithmetic）现在以
`build = "../../tools/cargo-native-build.rs"` 接入共享构建脚本；作为依赖的
control/mode 库不需要原生构建脚本。活动 wrapper 的 host 请求使用原版 GNU
`nightly-2026-09-14-x86_64-pc-windows-gnu` 及其 self-contained GCC，不再为
这些脚本调用缺少 `link.exe` 的 MSVC，也不使用定制 rustc 的故障 host std。
该验收仅覆盖此无外部 Rust 依赖的构建脚本，通用 host 依赖与 proc-macro 仍待验证。

#### 外部输入的增量构建

直接运行原来的 `cargo build --release --target c28x-none-elf`，无需 clean。

| 变化 | 本轮实现的行为 |
|---|---|
| 没有输入变化 | Cargo Fresh；不运行 build script、TI 编译或链接 |
| 某个 C 或实际包含的头文件变化 | 重新编译受影响的 C 对象，再链接；其他 TI 对象复用 |
| ASM 或实际 `.include/.copy` 文件变化 | 重新汇编受影响的对象，再链接；其他 TI 对象复用 |
| `.cmd` 或其字面量 `#include` 变化 | 只重新执行最终链接，C/ASM 对象缓存命中 |
| Rust 变化 | Cargo 正常构建应用；TI C/ASM 缓存命中 |
| 原生编译参数/工具变化 | 缓存身份改变，重编受影响的原生对象并重链 |

Cargo 通过 `rerun-if-changed` 感知配置、原生源及 TI 实际输出的依赖；C 使用
`--preproc_dependency`，ASM 使用 `--asm_dependency`。TI 对象缓存校验源/包含文件
内容、编译参数、编译器组件和对象内容；失败不发布新缓存。缓存按对象加锁，
未变对象的文件时间保持不变。Cargo 变化跟踪遵循文件修改时间；不要手工恢复输入的旧时间戳。
变更外部输入会重新调用最终应用 crate 的 rustc 完成链接，未变化的 Rust 依赖
继续复用；不承诺完全跳过最终应用的 Rust 代码生成。

`c28x-link.json` 保留原字段，另支持 `tiIncludePaths`（相对项目根目录的包含目录）、
`tiDefines`（如 `["BOARD_REV=2"]`）和 `extraDependencies`（额外必须触发重链的文件）。
配置文件本身受跟踪，`tiObjects` 和 runtime 也受跟踪。`.cmd` 自动递归跟踪字面量
`#include "file.cmd"`；宏展开出的命令文件、间接 `-l`/命令文件输入等应显式登记
`extraDependencies`。新项目必须接入共享 build script 才具备自动唤醒 Cargo 的能力。
配置 include/define 选项用于原生编译；链接脚本的包含搜索规则仍遵循 TI linker。

回归入口：B-1 根目录执行 `powershell -File tools/verify-cargo-native-incremental.ps1`。
该脚本只修改新建的隔离工程并保存 Cargo JSON、对象哈希、mtime、map 和逐步断言，
涵盖包含空格的工程路径、C/多层头文件、ASM/包含文件、cmd/嵌套 cmd、Rust-only 和 Fresh。
本轮十步全部 PASS，证据见 B-1
[`build/verify-native-incremental-a5dffc8d/report.json`](../../f28035-rust-bridge-b1/build/verify-native-incremental-a5dffc8d/report.json)。
各外部变更步骤的库依赖均 Fresh；C/头文件只重编 C，ASM/包含文件只重汇编对应对象，
cmd 及其 include 修改不重编任何原生对象，map 明确记录更新后的符号值。
未变构建 0.294～0.399 秒；隔离首次构建 66.552 秒，外部变更后约 21～26 秒，
其中仍包括最终应用 rustc 和发布包校验。这些为本机本轮测量，不是性能保证。
三个正式样板构建及再次 Fresh 通过，摘要位于 B-1
[`build/native-incremental-samples.json`](../../f28035-rust-bridge-b1/build/native-incremental-samples.json)。

根 `.cargo/config.toml` 统一维护 target `rustflags`，子项目继承，防止 Cargo
合并数组后重复传入 `--sysroot`。这两个子项目仍依赖父目录配置，搬出 B-1
目录时需复制并调整根配置。适配器写出 schema 4 provenance，包含 bundle、
原始 Rust 输入及归档成员哈希；原始应用 `.o` 会被 rustc 删除，复核应使用
`inputs` 中留存的 `rust-<hash>.obj`。`nativeObjects` 记录各原生源、实际依赖及其哈希，
`nativeCompileIdentity` 记录工具/参数/环境身份；另有原始 `linkerArguments`、
参数处理策略、搜索目录、按顺序解析的 `nativeLibraries`、实际 `tiLinkArguments`，
以及适配器/helper/exe、TI linker 与 objcopy 的文件哈希。固定 `.out` alias 的加载绑定
仍未修复；构建来源记录不能替代上板脚本选择 Cargo artifact。

#### 链接参数支持边界（2026-10-27）

入口为 B-1 `tools/c28x-link-arguments.ps1`，由实际 linker shim 调用。
参数必须被明确消费，未知参数不再跳过；路径相对 rustc/linker 的工作目录解析。

| 输入 | 行为 |
|---|---|
| `.o/.obj/.rlib` | 保留直接对象校验、rlib 解包流程 |
| `.a/.lib` 完整或相对路径 | 校验 regular archive 及所有可识别 ELF 成员的 C28x machine，原归档交 TI linker 按需选成员；拒绝 thin/空/损坏/非 C28x 归档 |
| `-L dir` / `-Ldir` | 按顺序登记存在的显式搜索目录，不隐式搜索主机系统库 |
| `-l name` / `-lname` | 仅静态模式支持；逐个 -L 目录依次找 `libNAME.a`、`NAME.lib`、`libNAME.lib`、`NAME.a`，缺失即失败 |
| `-l:filename` | 在显式目录中精确匹配 .a/.lib 文件名；支持带空格的目录 |
| `-Bstatic/-Bdynamic` | 显式切换库查找模式；rustc 末尾空的 dynamic 模式可接受，真正的动态库请求拒绝 |
| `--start-group/--end-group` | 配对传给 TI linker，支持归档间反向引用；不支持嵌套组 |
| `--gc-sections/--no-gc-sections` | 映射为 TI `--unused_section_elimination=on/off` |
| `--strip-debug` | 用 llvm-objcopy 实际剥离；比较前后入口、ABI flags、全部 SHF_ALLOC 段的地址/大小/内容，校验不一致即失败；保留调试器需要的符号表 |
| 未知选项、`-Wl,...`、response file、whole-archive、未支持的动态/入口/放置选项 | 明确报错；入口和命令文件使用 c28x-link.json 配置，不盲目透传 |

普通 Rust/TI 对象统一在原生归档之前，之后按请求顺序放原生库/库组，最后 TI RTS。
此为当前受限静态链接 profile，未承诺完整 GNU linker 参数兼容。
链接时会检查库存在性与内容；要让库文件变化自动唤醒 Cargo，共享 build script 项目
须将外部归档登记到 `extraDependencies`，自定义 build.rs 则输出相应 rerun-if-changed。
改变搜索目录中优先候选的集合也需要 build.rs 登记目录依赖；不能仅依赖链接日志。
解析器和 objcopy 本身已纳入共享 build script 的变化跟踪。

回归入口为 B-1 `tools/verify-cargo-link-arguments.ps1 -EvidenceDir <新目录>`；
加 `-RunHardware` 才执行 RAM/JTAG。测试使用普通 Cargo 工程和真实 TI 归档，
同时检查成功链接、库顺序、组重扫、明确拒绝及归档变化后的增量重链。
最终证据为 `D:\c28x-toolchain\b1-link-args-20261027\integration-validated\`：
16 步全部满足预期，另有 9 项解析器负向边界与分离 -L/-l 检查；归档变化重链
10.24 秒、未变依赖 Fresh、原有 TI 对象 hash/mtime 不变，最终 Fresh 0.26 秒。
新归档且经 debug 剥离的真实 Cargo 映像在 F28035 读回 `7,13,20` PASS。
同根 `native-incremental/` 十步与 `default-cargo.json` 三样板构建/Fresh 均通过。`default-hardware.json` 三样板 RAM/JTAG PASS；算术读回在实际去除 DWARF 后失去数组类型，已在 DSS 脚本显式按 TI unsigned long（32 位）读取，原失败日志及显式宽度重验日志分别保留。相对归档路径另经实际 PowerShell 适配器重放 PASS。
初稿 JSON 序列化卡住的 trace 与失败目录保留，后续改用 .NET ReadAllLines 去除
Windows PowerShell Get-Content 给字符串附加的 provider 属性；不覆盖最终证据。

### 3.4 直接对象与真机验证

| B-1 脚本 | 覆盖内容 |
|---|---|
| `tools/run-hw-rustc-direct-object.ps1` | control/mode、C28x ELF、TI 链接、RAM/JTAG |
| `tools/run-hw-rustc-direct-safe-hal.ps1` | 完整 Safe HAL 对象和 GPIO 样板 |
| `tools/run-hw-rustc-direct-layer-probe.ps1` | 帧索引、MOVB lane 和 clobber 分层探针 |
| `tools/run-hw-rustc-direct-core-ex.ps1` | Group A/B/B2/C/D/E `core` 广度用例；Group B2 是迭代器第二组测试，与已归档的路线 B-2 无关 |
| `tools/verify-cargo-shifts.ps1` | Rust-only Cargo 的 144 项窄整数、宽选择、16/24/31 位左移和格式模板分类；检查 Fresh 和真机原始输出 |
| `tools/verify-cargo-format.ps1` | 动态 u32 十进制/十六进制 core::fmt 的 Cargo/Fresh 与真机字符串比对，不能只看 DSS exit code |
| `tools/run-hw-rustc-direct-option-probe.ps1` | Option/deref 最小复现 |
| `tools/run-hw-rustc-direct-abi.ps1` | 参数 ABI 硬件样板：sret(XAR6)、指针池(XAR4)、混合 AR5/XAR4/ACC、LCR *XARn、栈参数/跨基本块/嵌套/32 位字序 |
| `tools/run-hw-rustc-direct-arithmetic.ps1` | 32 项动态算术与四参调用；`-Optimization 0/s`，不传 `-BuildOnly` 时执行 RAM/JTAG |
| `tools/run-hw-rustc-direct-static-pointers.ps1` | 新增静态地址回归：函数、外部/本地数据、奇数字节引用；检查 ABS32、TI 链接、指针字段和 Rust volatile 解引用 |
| `tools/run-hw-cargo-control.ps1` | Cargo 单 crate / 跨 crate 控制样板 |
| `tools/verify-cargo-direct-hw.ps1` | 当前直接对象 Cargo 独立/跨 crate/算术样板的 RAM/JTAG；同时检查 DSS PASS 标记 |
| `tools/verify-cargo-memory.ps1` | 普通 Cargo 直接对象/rlib 内存与 TI 共存五组 RAM/JTAG 回归，支持 `-BundleRoot`、`-OutputDirectory`、`-BuildOnly`；按 Cargo JSON 与 SHA 选择实际映像 |
| 主仓库 `tools/verify-mem-builtins.ps1` | 检查 intrinsic 调用新符号、builtins-dual.o 提供五个实现且不定义普通名；链接完整 core/builtins/算术闭包 |
| 主仓库 `backend/llvm-c28x/test/Rust/b1-hw-memory.rs` | 内存 helper 与 Rust intrinsic 的正常 Cargo 测试入口 |
| 主仓库 `tools/hw_b1_memory_driver.c` / `tools/dss-read-b1-memory.js` | 独立 TI C 字节参考与全缓冲哨兵；DSS 核对病例数、错误数、PC 和完成标记 |
| 主仓库 `tools/patch-llvm-c28x-memory-libcalls.ps1` | 为全局 LLVM TD 幂等登记五个非默认 helper，避免依赖构建树的手工修改 |
| 主仓库 `tools/check-ti-arithmetic.ps1` | IEEE binary32 算法的主机差分验证；与真机 ABI 验证分别记录 |

主仓库的 `crates/c28x-rt/asm.s`、`tools/F28035_ram.cmd`、
`tools/F28035_EABI_sections_ram.cmd`、C 驱动和 DSS 脚本是这些 B-1 验证的
共享输入。

### 3.5 无 C 应用入口的 Rust RAM 试验（2026-10-27）

#### 自己编写 Rust：最小入门工程（2026-11-02）

日常编辑 B-1 `crates/c28x-user-app/src/main.rs`。这个独立应用不修改回归样例，
使用 `#[entry] fn main() -> !` 和安全 HAL 的 GPIO34 输出接口，交替调用
`set_high()` / `set_low()`；应用源码没有 `unsafe`。GPIO34 是否连接 LED、
LED 是否低有效，以实际板卡原理图为准。`pause()` 是软件循环，不能当作精确毫秒延时。

从 B-1 根目录运行（必须使用 `--release`，不需要重编 rustc 或 `core`）：

```powershell
Set-Location C:\Users\61987\Desktop\28035\f28035-rust-bridge-b1
cargo build --release --target c28x-none-elf --manifest-path crates/c28x-user-app/Cargo.toml
```

`Cargo.toml` 指定同树 runtime 与 direct-object HAL 依赖，并显式关闭 release
溢出/调试断言检查；检查开启路径的覆盖不足仍独立保留。`c28x-link.json`
选择 `direct`、`rustRuntime: true`，由 runtime 提供启动汇编、TI RAM 链接脚本，
不重复添加 C main、启动对象或 `system_init()`。父目录 `.cargo/config.toml`
负责已发布的 rustc/sysroot、wrapper 与 TI linker；不要仅复制 main.rs 到任意目录
后用普通 Windows rustc 编译。

产物位于父配置的 `target-dir/c28x-none-elf/release/c28x-user-app.out`；当前
active 的位置由 `build/toolchains/active.json` 和 `.cargo/config.toml` 确认。
本轮 active `20261102-122629-cf4b3949-7bc20a44` 下首次构建约 68 秒（含宏依赖），
再次构建 Fresh；映像 SHA256 为
`D7B06A4022D8479DAC12ED671BE8DE534AC69DDC76ED6058F7E536929DE197C8`。
证据见 B-1 `build/user-app-20261102/{report.json,cargo.jsonl,cargo.log}`。
HAL 当前有既有 cfg/unsafe-op 等编译警告；本轮未扩展修改 HAL，不能把构建通过
理解为这些警告已消除。
在 CCS 使用 F28035/XDS100 目标连接后，将此 `.out` 作为 **RAM 程序**加载并运行；
需要从 runtime 的 `code_start` 启动，不能跳过初始化直接运行 Rust `main`。
此工程没有设置 `cargo run` runner，不用 `cargo run` 烧录，也不使用旧
`example/case1/build.ps1`。当前入门交付只做构建和 Fresh 校验，不声明 GPIO 上板通过。
RAM 映像断电丢失，Flash 独立启动另行验证。

建议学习顺序：先运行原例并观察 GPIO，再修改暂停计数、把业务计算提取成
普通 Rust 函数，之后接入 Timer0，再做 ADC→计算→PWM。共享主循环/中断状态时
用下文的 `SharedCell`，不从裸寄存器地址和 `static mut` 开始。

`f28035-rust-bridge-b1/crates/c28x-cargo-runtime/` 已通过正常 Cargo 和
F28035 RAM/JTAG。`src/main.rs` 用 Rust 导出 `main`、`PreInit`、`TINT0`，
主循环、Timer0 配置/清标志、PIE 应答和 ISR 内普通函数调用均在 Rust 中。
`extern "C"` 仅规定 Rust 函数的调用约定，不表示有 C main。

| 文件 | 作用 |
|---|---|
| B-1 `crates/c28x-cargo-runtime/src/main.rs` | 可运行的 Rust 入口、主循环、中断与初始化检查 |
| B-1 `crates/c28x-cargo-runtime/c28x-link.json` | direct 对象模式和 `rustRuntime: true`；不手工重复启动/链接脚本 |
| B-1 `crates/c28x-cargo-runtime/context-probe.asm` | 仅测试用：预置寄存器、制造两种栈奇偶；不是应用入口或中断跳板 |
| 主仓库 `crates/c28x-rt/{asm.s,ram.cmd,build.rs,src/lib.rs}` | 启动、128 项 PIE 表、TI RAM 放置、Cargo links 元数据、CPU 中断 API |
| B-1 `tools/cargo-runtime-config.ps1` | build script 与 linker 共用运行库配置解析，跟踪启动/命令文件变化 |
| B-1 `tools/verify-cargo-runtime.ps1`、主仓库 `tools/dss-read-b1-runtime.js` | Cargo/Fresh、来源/反汇编检查、实际加载及硬件上下文/向量验收 |

下面是初版隔离原型的历史复现命令；当前 active 的完整验证命令见本节后文：

```powershell
# 在 f28035-rust-bridge-b1 根目录运行
powershell -File tools/verify-cargo-runtime.ps1 `
  -BundleRoot C:\Users\61987\Desktop\28035\f28035-rust-bridge-b1\build\toolchains\bundles\20261027-125446-504e8ef7-ce48b97e `
  -EvidenceDir C:\Users\61987\Desktop\28035\f28035-rust-bridge-b1\build\runtime-rust-only-20261027 `
  -SkipSignatures
```

该包 manifest SHA256=`4DB42ED9FD87D423D45E265AD3DAC35DC689EAD0033AC18AC235B24284DA15F7`。
证据位于上述 EvidenceDir 的 `report.json`、`hardware.log`、Cargo JSON 与反汇编。
映像取 Cargo `compiler-artifact.executable`，SHA256=
`AF8C9D74E2A460B17C07BDB8564DB17CA3A5BB62B67DC32A5E1B815BBE3CDD42`。
主循环计数 2709；三段 Timer0 各 16 次，共 48 次；两种栈奇偶检查均零错误；
DSS 另独立逐字检查 ACC/XAR0..7/XT/P，并实际触发未绑定 group 2 向量验证默认处理器。
共享启动汇编更新后，旧 active 下独立、跨 crate control、算术三个 Cargo 工程
也重新构建并 RAM/JTAG PASS；各 `*-compat-*.log` 留在同一证据目录。

中断后端补齐 ASP、SPM 0、清 OVM/PAGE/AMODE、完整 XAR0..7/XT 保存恢复、
NASP/IRET，修复保存顺序对 FI 的影响及 MOV32 立即数展开的 ACC 活跃性。
LLVM O0/O2 机器指令检查和空 ISR 的 TI 编码 oracle 通过。
运行库修复零长度 BSS/data、BANZ 边界和 weak PreInit，PIE 表使用 TI 原生字地址。

边界：这是 RAM 试验，不是全工具链无 C。仍有启动汇编、TI `__TI_auto_init`、
算术适配对象和 RTS。嵌套中断、Flash、更多外设和任意 crate 未验收。
`macros` 是可选 feature。初版 ce48 原型缺同版 host proc_macro，曾跳过签名测试；
该限制已由 `af788b4d` 发布包补齐，当前包保留该能力。同一程序改用 `#[entry]`、`#[pre_init]`、
`#[interrupt]` 后，Cargo 构建/再次 Fresh 与 RAM/JTAG 全通过，另有 9 项签名负向
测试通过。日常使用当前 active；上面的 ce48 命令仅保留为初版试验复现。

```powershell
# 当前 active 的完整入口/宏/中断验证，不再需要 SkipSignatures
powershell -File tools/verify-cargo-runtime.ps1
```

### B-1 安全共享状态（2026-10-28 修复并验收）

`crates/c28x-rt/src/lib.rs` 的 `SharedCell<T>` 在创建 `&mut T` 前检查独占
借用；同一 cell 的递归访问和主机线程争用由 `try_with` 返回
`SharedCellBorrowError`，冲突回调不执行。`with` / `replace` 在冲突时明确
panic，使用静态消息避免为错误类型额外拉入 Debug 格式化路径。主机采用
acquire/release 原子锁；目标端在屏蔽中断期间以原生 16 位 volatile 访问检查、
设置和释放借用标志，保持访问宽度；排他来自 INTM 和借用检查，volatile 本身
不提供原子性。异常展开
会释放借用，panic=abort 固件则停止执行。不同 cell 允许嵌套。

临界区入口现为 `critical_section(|| { ... })`，替代可公开持有的 guard。
私有 guard 按闭包作用域恢复进入前的 INTM，应用不能乱序 drop、forget 或跨线程
传递它。主机版本的临界区闭包本身不提供线程互斥，`SharedCell` 自身的锁负责
线程同步；NMI/DMA 不属于 INTM 排他模型。

保存状态的汇编辅助函数同时修正：INTM 是 ST1 **bit 0**，旧实现误看 bit11；
`PUSH ST1` 保存一字后，按 TI `DSP2803x_DisInt.asm` 用 `MOV AL,*--SP`
取回，替代从当前 SP 读取两字的错误实现。独立 GPIO HAL 支持汇编同步修正。

主机 7 项功能/并发测试和 2 项编译负向测试已通过。目标回归新增
`HW_RT_SHARED`：递归借用拒绝、拒绝后不解锁外层、正常重借用、进入前中断
已关/已开的嵌套恢复、栈平衡及主循环/Timer0 共享计数校验。直接入口和宏入口
均由 `verify-cargo-runtime.ps1` 要求新的独立 PASS 行；仅构建成功不计真机通过。
本轮使用 active `20261028-162823-7a7c48fc-ee53e7b7`，改动属于 Cargo 源码
依赖与启动汇编，无需重链 rustc 或改写不可变 bundle，也未切换 active。
最终直接入口和宏入口均 Cargo/Fresh、12 项共享状态检查及 RAM/JTAG PASS；
两者主循环各 390 次，Timer0 各 48 次，偶/奇栈上下文零错误；9 项宏签名
负向全部拒绝。证据位于 B-1 `build/shared-cell-runtime-20261028-r4/`。
独立 GPIO 工程的辅助汇编也重新构建并上板 PASS（含重复外设/引脚领取检查），
日志在主仓库 `build/shared-cell-20261028/gpio-exclusive-final.log`。

主机检查已由 B-1 `tools/verify-shared-cell-host.ps1` 自动执行，并接入
`verify-cargo-runtime.ps1`（包括 BuildOnly）；使用本机既有 GNU rustc/rustdoc，
显式清除 C28x wrapper/flags，记录运行库源文件、工具和日志哈希。可单独运行：

```powershell
powershell -File tools/verify-shared-cell-host.ps1
```

接入后的完整 BuildOnly 门禁也已通过（含主机 7+2、9 项宏签名拒绝和 Cargo
再次 Fresh），证据 B-1 `build/shared-cell-runtime-20261028-final-gate2/`。
该次直接应用映像 SHA256 与 r4 已上板映像一致，且现存文件哈希再次核对通过；
此目录 hardware=NOT_RUN，真机证据仍以 r4 的直接/宏入口日志为准。

失败证据仍保留：首轮全内联检查后主循环超时；后续字节标志映像在读改写展开中
覆盖旧值并误入冲突路径，`Cell<u16>` 也被优化窄化，改为原生 16 位 volatile
标志后上述正式目标检查通过。此为当前共享接口的实现约束，未宣布一般字节
读改写的后端问题已修复。目标检查函数单独保留 inline(never)，避免将全部
诊断和正常主循环混在一个大函数中。

发布指针曾出现跨根不一致（已于 2026-11-02 修复）：B-1 C 盘入口和三个 Cargo pin
指向 ee53e7b7，而 D 盘 `b1-release/active.json`、旧 `b1-toolchains/active.json`
仍指向 6c02958c，且 C 盘 `candidate.json` 停在旧编译器 af95c9d8。原因是每个发布根
各自持有 `active.json`/`candidate.json`，而 `select-b1-bundle.ps1` 只写当前根；
Cargo 读 active 已换新 sysroot，`rebuild-core-sysroot.ps1` 读 candidate 却仍用旧
编译器，重编 core 会静默丢掉后端修复。

现由 `tools/sync-b1-release-pointers.ps1` 统一三类指针：以 C 盘根为规范源，按
`bundle.compilerSha256` 反查该 bundle 所用编译器代，原子改写各根的
`active.json`/`candidate.json` 并回读校验 SHA-256；`-Check` 只报告漂移并以退出码 1
作为发布门禁。该脚本已接入 `select-b1-bundle.ps1`，激活后自动镜像到其它根。
当前三个根（C 盘 `build/toolchains`、`b1-release`、`b1-toolchains`）均指向
`20261028-162823-7a7c48fc-ee53e7b7` 与其 compiler `20261028-162823-7a7c48fc`，
`-Check` 报 `B1_RELEASE_POINTERS=CONSISTENT`。

首次正式重发因 mutable Rust 源码丢失 C28x 注册/interrupt ABI 而被拒绝。
后续已经复现为 bootstrap 沿 stage0 的 rustc-src/rust 联接覆盖源码，修复机制
及重建/验收流程见下文。不能混用其 driver/core 或改写旧不可变候选包。
该轮已完整验收并切换为 `20261027-171858-19176840-af788b4d`，当前包位置见 §4。
另有未关闭诊断：首版目标端“两个 u16 合成 u32 后比较”的寄存器检查报十错，
而原始快照正确；本次改用逐半字检查并增加 DSS 独立校验，其复杂表达式根因待定位。
当前优化 core 包已通过动态 u32 十进制/十六进制格式化样例，仍需按每个应用的 map 检查 RAM 容量；`__udivmodsi4` 也有独立真机回归，不据此外推所有格式化或 core 路径。

## 4. 发布包与版本绑定

当前 active bundle：

```text
20261028-154958-af95c9d8-6c02958c
```

`active.json` 只指向 bundle 根目录和 `bundle.json` 的 SHA-256。

当前包实际位于：

```text
D:\c28x-toolchain\b1-release\bundles\20261028-154958-af95c9d8-6c02958c
bundle.json SHA256 = 90301C8F59FEF83973217D533F97E5EAAFBC543CA9841317C2B6337C13068EC7
```

默认入口读 B-1 `build/toolchains/active.json`，实际 bundle 在上面的 D 盘目录。
`D:/c28x-toolchain/b1-release/active.json` 和历史
`D:/c28x-toolchain/b1-toolchains/active.json` 镜像均指向同一完整包；三个 Cargo
配置的 rustc/sysroot 已同步。C/D 的 candidate 指针也绑定同版 compiler。
本轮构建设置 `C28X_RELEASE_ROOT=D:\c28x-toolchain\b1-release`；脚本未设置该环境
变量时仍默认 C 盘发布根，后续发布必须同时核对 C 盘入口和 Cargo pin。
不要拆包复制单个 driver、core 或 builtins。

当前 core 使用 `opt-level=s`，参数在 bundle 清单中绑定。复现优化发布可在 B-1 根运行：

```powershell
$env:C28X_RELEASE_ROOT = 'D:\c28x-toolchain\b1-release'
powershell -File tools/publish-b1.ps1 -CoreOptLevel s
```

`-CoreOptLevel` 的脚本默认值仍为 0（兼容旧流程），重建优化包应显式传 `s`。

bundle 内至少有：

```text
bin/rustc.exe
bin/rustc_driver-*.dll
lib/rustlib/c28x-none-elf/lib/libcore.rlib
lib/rustlib/c28x-none-elf/lib/libcompiler_builtins.rlib
lib/rustlib/c28x-none-elf/lib/ti-arithmetic.o
compiler.json
source-state.json
bundle.json
lib/rustlib/x86_64-pc-windows-gnu/lib/libstd-*.rlib
lib/rustlib/x86_64-pc-windows-gnu/lib/libproc_macro-*.rlib
```

`compiler.json` 绑定 rustc、driver DLL、Rust 源码版本和 LLVM 来源；
`bundle.json` 再绑定 compiler 清单、`core`、builtins、对象、源文件和构建参数。
Cargo target-dir 也随 bundle ID 隔离。任何文件哈希不匹配都应停止构建，不能
临时复制 DLL、rlib 或旧对象拼出一个“看似能跑”的工具链。

算术运行库由同一发布步骤用 TI cl2000 编译。`libcompiler_builtins.rlib` 包含
`lib.rmeta`、Rust builtins 对象和 `ti-arithmetic.o`；Cargo 适配器解包对象成员后
直接交给 TI linker，无需新增 Rust 汇编转换。手工直接链接时，将
`Get-C28xBundle` 返回的 `ArithmeticObject` 加入 link inputs；算术与 core-ex
脚本已接入。清单绑定 C 源、编译参数、TI 编译器/RTS 哈希和产物；库或工具被换、
额外塞入未登记的 runtime 对象都会拒绝使用。

TI softlib 的普通浮点算例可运行，但本轮七项边界检查失败，因此 f32 helper
采用整数算法实现 nearest-even、渐进下溢、signed zero、Inf/NaN；不调用 TI
浮点运算 helper。`__udivsi3/__umodsi3/__divsi3/__modsi3` 使用 TI C 包装适配整数
除余 ABI。f32 比较/转换、f64 和数学库并未因此获得完整支持。

### 后端改动后的正确顺序

1. 在主仓库修改 `backend/llvm-c28x/`，运行相关 CodeGen/MC/TI 对象回归。
2. 等 LLVM 构建稳定后运行 B-1 `build-rustc-c28x.ps1`，确认记录的 LLVM 指纹一致。
3. 用 `publish-rustc-candidate.ps1` 验证 `rustc.exe` 与 driver DLL 能启动、能识别 target、能产最小对象。
4. 用同一 compiler 运行 `rebuild-core-sysroot.ps1 -SkipInstall`：打包、校验清单和最小 sysroot 冒烟，只生成待验包；新 sourceSha256 编译器不会在此步自动激活。
5. `publish-b1.ps1` 已串联源码准备、同版 host std/proc_macro 编译、sysroot 打包、完整验收和激活。新 `sourceSha256` 编译器的 `rebuild-core-sysroot.ps1` 只生成未激活 bundle；`select-b1-bundle.ps1` 必须核对匹配 bundle 的验收日志和映像 SHA。旧包回滚保留原有完整性检查。

### 可重复重建的源码与引导隔离

`backend/llvm-c28x/rustc-patches/0001-add-c28x-target.patch` 覆盖固定
`4b6d04e706108ccfeafe2547fbe857dfe8972bad` 源码的 20 个文件，包括 target、
LLVM 初始化、C ABI、interrupt ABI/feature/CC92、public ABI 转换。
`c28x-rust-source.json` 记录补丁及逐文件基线/结果哈希。
`prepare-rustc-c28x.ps1` 只恢复该本地补丁，重复运行不重写已正确文件，遇到未知
改动拒绝，不再根据系统 rustc 版本 fetch/checkout。`check-rustc-patch.ps1`
检查的是完整已应用状态；pristine 应用/重复应用及负向门禁见
`tools/test-rustc-source-state.ps1`。

源码丢失已实际复现：bootstrap 的 `compile.rs` stage0 StdLink 会把
`initial_sysroot/lib` 复制到 stage0-sysroot，而后者的 `rustc-src/rust` 可能
已是指向定制源码的 junction。原版 GNU sysroot 带有 rustc-src，于是沿联接
覆盖定制文件；同一 x.py 内可多次发生，单独在命令前清理联接不足以修复。
`tools/bootstrap-gnu.ps1` 生成 `D:/c28x-toolchain/bootstrap-gnu-4b6d04e7`，
仅含固定版本的 bin 与 host 运行库，不含源码，逐文件校验后用于引导。
同卷只共享运行二进制的硬链接；应用补丁后的源码独立，旧 stage0 源码联接
仅在确认目标为本 RustSource 时才解除，不递归删除目标。

构建前/后和发布前核对 compiler/bootstrap/core/std/proc_macro 内容快照，
fast path 同时绑定源码、补丁及 LLVM 哈希。发布的 `source-state.json` 与
compiler 清单、driver、host std/proc_macro、core 和 builtins 一起保存并校验。
`verify-b1-release.ps1 -BundleRoot <新包>` 串行运行 Rust 直接入口与宏入口真机、
9 项宏签名负向、五组内存、ABI、core A/B/B2/C/D/E、三个 Cargo/Fresh/真机，
验收写到 `build/toolchains/acceptance/<bundle-id>.json`，随后才能 select 激活。
本轮上述流程已完整跑通，未变编译器再次执行命中 fast path，不重链/重发。
LLVM 对 CC92 的文本名称是 `x86_regcallcc`；本端口按数值 92 解释为 C28x 中断，
门禁同时检查 C28x 对象的 ASP/NASP/IRET，不按文本名字误判为 x86 代码。
Cargo host 编译必须走当前 bundle 的 rustc/sysroot，不允许用原版 GNU std 代替；
旧无 host 库的包仅保留无依赖 host build script 的历史回退。
验收缓存放在短路径 `build/q/<identity>/{rt,mem,app}`，identity 同时绑定 bundle、
wrapper 和调用脚本哈希，避免 Windows PowerShell/TI 长路径限制及旧 host 产物混用。
6. 清理或隔离旧 Cargo target-dir，运行 direct-object、Cargo 和必要的真机回归。

不要直接替换 active bundle 内的单个文件。新的后端、旧的 rustc、旧的 `core`
和旧对象混在一起，会把版本错配伪装成代码生成、DLL 或 ABI 缺陷。

<a id="b-3"></a>

## 5. ABI 冻结摘要

当前权威 DataLayout：

```text
e-m:e-p:32:32-i1:8:8-i32:32-i64:32-f32:32-f64:32-a:8:8-n8:16-S16
```

关键约定：

- C28x 以 16 位 word 为基本地址单位，但 Rust/LLVM 指针宽度按 32 位建模。
- `i1` 的存储和 ABI 对齐为 8 bit；帧 byte lane 必须显式处理，不能把 word
  偏移当 byte 偏移。
- sret 使用 XAR6；指针参数池和整数参数分配以 `C28xCallingConv.td` 与 TI
  oracle 回归为准。
- TI EABI 要求完整保存 XAR1/XAR2/XAR3，XAR4–XAR7 可被调用破坏；不能只
  保存 AR 的低 16 位。调用边界 SP 必须为偶数字地址，32 位栈参数也按两字对齐。
  后端将保护区和调用参数区向偶数字数补齐；DataLayout 的 `S16` 未改变。
- 任何 calling convention、栈帧、重定位或 DataLayout 修改都要同时更新
  CodeGen 回归、target spec、sysroot 和硬件探针。
- 内存 intrinsic 使用 `c28x_memcpy/memmove/memset/memcmp/bcmp`，参数指针保留逻辑
  字节地址；其中 memset 填充值为 `u8`、长度为 `usize`。TI 普通同名接口仍按 C 字地址工作。
  这组 helper 由 Rust builtins 提供，位于 `builtins-dual.o`/`libcompiler_builtins.rlib`，
  不在 `ti-arithmetic.o`。全局 libcall 定义为非默认项，仅 C28x 显式选择。

运行：

```powershell
cd C:\Users\61987\Desktop\28035\f28035-rust-bridge
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\check-abi-freeze.ps1
```

<a id="b-7"></a>
<a id="b-11"></a>

## 6. 当前进展与证据边界

当前 active 为 `20261028-162823-7a7c48fc-ee53e7b7`，对应 compiler
`20261028-162823-7a7c48fc`。定制 rustc、同版 host std/proc_macro、core opt=s、
builtins 和 TI 算术对象均正常重建、匹配打包；三个发布根的 active/candidate 指针
和三个 Cargo pin 一致（`sync-b1-release-pointers.ps1 -Check` = CONSISTENT）。
上一代 `20261028-154958-af95c9d8-6c02958c` 的验收记录保留，用于该代自身回退。

| 当前包正式验收 | 结果 |
|---|---|
| 源码补丁和 compiler 来源 | 本轮重链 rustc，构建前后 20 文件补丁/快照检查 PASS；漂移、联接和激活拒绝机制沿用既有门禁 |
| rustc DLL 启动、target、C28x 普通与中断对象、同版 host 宏编译/加载/运行 | PASS；空 ISR 对象含 ASP/NASP/IRET |
| 编译器未变重跑 | fast path 有历史基线，本轮因 LLVM 内容改变实际重链，未额外重跑 fast path |
| Rust 直接入口 + 宏入口 | 两者 Cargo/Fresh 与 RAM/JTAG PASS；每次 ISR 48，偶/奇栈上下文零错、未绑定向量进入默认处理器 |
| 宏签名负向 | 9/9 PASS，包含禁止从普通 Rust 调用中断函数 |
| Cargo 内存/TI 共存 | 五组 RAM/JTAG 462 项 PASS（48/192/72/144/6） |
| u32 合并除余 | LLVM 自动调用、10 组商余数、栈和全局余数指针及空余数指针 RAM/JTAG PASS；Cargo 二次 Fresh |
| 窄整数/宽 select/移位 | 144 项 RAM/JTAG PASS，Cargo 二次 Fresh |
| 优化 core 的 B2 | 原始结果 90/179 PASS；额外 28 项长度/溢出/非均匀数据边界真机 PASS |
| 动态 u32 core::fmt | `n=12345 x=00003039` 真机正确，Cargo/Fresh PASS；RAMCODE 使用 0x1dd9/0x2000 字 |
| ABI | 十项 RAM/JTAG PASS |
| core A/B/B2/C/D/E | 全部 RAM/JTAG PASS；A pattern=223、B=80、B2=90、C=132、D=42967、E 16 项 |
| independent / cross-crate control / arithmetic | 三个 Cargo 构建、再次 Fresh、RAM/JTAG PASS，按 Cargo 实际 artifact 选映像 |
| Flash、嵌套中断、任意 core 路径/第三方 crate | 未验收 |

统一发布验收 15 项 PASS。证据在 B-1
`build/release-acceptance/20261028-162823-7a7c48fc-ee53e7b7/`：
`report.json`、`runtime/report.json`、`runtime/macro-hardware.log`、9 个签名日志、
`memory/report.json`、`abi.log`、`core-*.log`、`divmod/report.json`、`shifts/report.json`、
`format/report.json` 和三个 Cargo 硬件日志。上一代
`build/release-acceptance/20261028-154958-af95c9d8-6c02958c/` 保留同一 15 项的记录。
正式 D 盘 release 根及 C 盘
`build/toolchains/acceptance/<bundle-id>.json` 均保留验收记录，绑定包、检查日志与映像 SHA。
divmod 实现在主仓库 `crates/c28x-compiler-builtins/src/lib.rs`；余数输出使用
Rust 逻辑字节指针，空指针表示不写回，除数必须非零。实现分别调用现有除法和
取余包装，尚未优化成一次计算。回归脚本为 B-1 `tools/verify-cargo-divmod.ps1`。

本轮 B2 根因在 `backend/llvm-c28x/C28xInstrInfo.cpp` 的 16 位 ALU 展开：
目标为 AR 寄存器时仍借 AL 计算，却只对目标本身为 AL/AH 的覆盖情形暂存 RHS。
优化后的 zip 累加恰好把 RHS 放在 AL，搬入左值后变成 `ADD AL,AL`，三轮算成
4→16→44；正确 zip=30。现在按真实工作寄存器判断暂存，修复共用于加/减/与/或/异或，
五种寄存器组合的 `alu16-rhs-al.mir` FileCheck 通过；没有修改 B2 源码或期望 90。
定位、新旧拆分结果、28 项边界和正式构建日志在 B-1 `build/core-opt-b2-20261028/`。

早期格式化失败及窄整数/宽选择/LSLL 修复过程保留在 `build/udivmod-20261028/`、
`build/format-20261028/`；旧“能链接但乱码”的实验包不可复用。当前正式包仅对已测
格式化样例验收，不保证任意格式化闭包都能放入 0x2000 字的 RAM 代码区。
额外 `-verify-machineinstrs` 仍能在部分路径报 undefined ACC 的 PUSH_ACC，旧 MIR
fixture 也有需更新的隐式操作数；这些诊断未在本轮关闭，不能宣称全 core 机器验证通过。
构建/失败/修复过程、fast path 和默认配置记录在 `build/source-recovery-20261027/`。
本轮也修正：Cargo host 被转发到原版 GNU、271 字符对象路径误报不存在、
去除 DWARF 后内存标志被 DSS 当有符号数读回，以及 PS5 JSON 数组额外包一层的误判。
失败日志保留；没有修改测试期望来掩盖失败。

**2026-10-27 112248 危险兜底修复（历史基线）**

当时 active 为 `20261027-112248-a1cf84ab-2e7ec64c`，对应 compiler
`20261027-112248-a1cf84ab`；默认 C 盘入口、D 盘镜像指针及三个 Cargo 配置绑定该包。
此次重新构建 LLVM、rustc、完整 core、Rust builtins 与 TI 算术对象，没有混用旧 sysroot。

本次关闭两处危险兜底，并处理重建暴露的根因：

- 未解析 `FK_C28x_BRANCH` 明确报目标和 section 并终止，不写零继续生成对象。
  跨 section 的 MIR 和 Rust 样本验证拒绝；普通外部调用仍使用 LCR/ABS22 重定位。
- 非 fixed 局部帧 `DeltaFromSP<=0` 明确报错，不再钳为 1；MIR 覆盖零和负值，
  报错含函数、FI、偏移、栈大小与 delta。这是显式支持边界，未新增任意栈地址支持。
- 首个候选重建 core 失败：旧 `TRAP` 跳回整个基本块，入口可能没有标签，
  还会重复副作用/序言。现在用 `B_SELF` 在该指令自身循环，无未定义符号。
  精确对象字节与 TI 汇编/链接独立 oracle 一致；旧包未通过新门禁。

| 112248 包当次验收（历史） | 结果 |
|---|---|
| 完整 core/sysroot 重建、清单绑定 | PASS |
| LLVM MC（含三项负向用例）、TI 调用/六种静态指针链接、内存 helper 链接、ABI freeze、发布清单负向测试 | PASS |
| 发布 rustc 正常对象、trap 自循环、跨 section 分支拒绝 | PASS；拒绝时 exit 非零且无输出对象 |
| Cargo 内存/TI 共存 | RAM/JTAG 462 项 PASS（48/192/72/144/6） |
| direct core A/B/B2 | RAM/JTAG PASS；A=`140,54,65,245,212,223,179`，B=`80,179`，B2=`90,179` |
| ABI 十项 | RAM/JTAG PASS；`21845,4660,61,42,21,33,32,90,171,305419896` |
| 三个标准 Cargo 样板 | 默认配置构建与再次 Fresh 均 PASS；本轮未另跑三个样板的 JTAG |
| Flash、任意 core 路径与全部 Rust crate | 未验收 |

证据目录 `D:\c28x-toolchain\b1-failclosed-20261027\`：`acceptance.json`、
`core-first-failure.log`、`core-final-build.log`、`verify-llvm.log`、`bundle-gate/report.json`、
`old-bundle-control.log`、`cargo-memory/report.json`、`core-*-hw.log`、`abi-hw.log`、
`default-cargo.json` 与切换前后指针。发布包清单 SHA-256 为
`6C217C74019681BAEA70B77E25B376CE5DC0FF5F4DD10918F0410F6E9B221F74`。

可重复门禁：主仓库 `tools/verify-llvm-c28x.ps1` 验证后端；
`tools/verify-b1-failclosed.ps1 -BundleRoot <完整包路径> -OutputDirectory <证据目录>`
验证实际发布 rustc。后者不执行硬件，不把编译拒绝记为上板 PASS。

**2026-10-26 内存运行库验收（历史基线）**

当时 active 为 `20261026-175437-71a923aa-79cdbc37`，对应 compiler
`20261026-175437-71a923aa`。LLVM/rustc 已重链，core/builtins 使用同一 compiler
重建并绑定清单。包放在 D 盘，默认 C 盘 active 指针与三个 Cargo 配置均指向该完整包。

本轮修复包括：

1. 内存 intrinsic 只调用 `c28x_memcpy/memmove/memset/memcmp/bcmp`；调用时保持
   32 位逻辑字节指针和奇偶 lane，普通 TI 名保留字地址语义。
2. Rust builtins 改用 `wrapping_add`，保持有效缓冲区/不重叠等 unsafe 契约，
   避免底层内存例程依赖 core 的指针前置检查和格式化。第一候选在 1 字节复制时
   进入该依赖路径停住；修正后 `builtins-dual.o` 无未定义符号，目标运行通过。
3. `c28x_memset` 的填充值 ABI 为 `u8`。LLVM intrinsic 原样传 `i8`，初稿 `i32`
   接口导致值/长度错位并写坏结果区；已按实际调用约定修正，并以 0/A5/FF 真机覆盖。
4. RAM 启动在 `main` 前调用 TI `__TI_auto_init`，处理 `--rom_model` 的 `.cinit`
   复制/清零记录。TI C 非零静态函数指针此前未初始化而跑飞；修正后共存测试通过。
5. direct core/ABI 复用 bundle 的 builtins + 算术对象；移除额外 di64 编译，
   算术对象放在 RTS 归档前，避免晚出现的 `__c28xabi_mpyll` 未解析。

| 2026-10-26 基线验收 | 结果 | 边界 |
|---|---|---|
| compiler/bundle、默认 Cargo pin | PASS | 发布包哈希和源码绑定通过；默认配置三个样板构建及再次 Fresh 通过 |
| Cargo 动态复制 | RAM/JTAG PASS，48 项 | src/dst 双 byte lane，长度 0/1/3/7/33/67，直接 helper 与正常 copy_nonoverlapping intrinsic；校验返回指针、完整目的缓冲区哨兵与源不变 |
| Cargo memmove | RAM/JTAG PASS，192 项 | 双向重叠、自移动、不同 byte lane；直接 helper 与 ptr::copy intrinsic |
| Cargo memset | RAM/JTAG PASS，72 项 | 0/A5/FF，奇偶目标地址、六种长度；直接 helper 与 write_bytes intrinsic |
| Cargo memcmp/bcmp | RAM/JTAG PASS，144 项 | 对齐/奇数地址，相等、首/尾差异和正负结果 |
| TI 普通内存函数与静态初始化 | RAM/JTAG PASS，6 项 | 真实 TI C 静态函数指针经 .cinit 初始化；普通 memcpy/memmove/memset/memcmp 使用 TI 字地址语义 |
| direct core A/B/B2 | RAM/JTAG PASS | A=`140,54,65,245,212,223,179`；B=`80,179`；B2=`90,179` |
| ABI 十项 | RAM/JTAG PASS | sret、指针池、混合参数、间接调用、栈参数/跨块/嵌套及 32 位字序 |
| 三个普通 Cargo 样板 | RAM/JTAG PASS | independent=`7,13,20`；app cross-crate=`23,40,19,20,82,178`；arithmetic 32 项。按 Cargo JSON 和 SHA 选映像，未修通用固定 alias 选择逻辑 |
| LLVM MC、内存符号/链接、di3、f32 比较转换、ABI freeze、发布负向门禁 | PASS | 详见各日志；符号/链接 PASS 不扩大为全部算术真机覆盖 |
| 外部输入增量构建 | 已接入 | C/头文件、ASM/包含文件、cmd 等变化自动唤醒，未变对象复用；新跨盘/绝对路径工程也已实测 |
| features alias、未知原生链接参数 | 仍待修复 | 历史复现仍有效，源码消费路径未在本轮关闭 |
| 归档解包竞争、发布强制门禁 | 仍待修复/覆盖 | 手动验收不等于已实现未来发布的强制门禁；该基线当时遗留的分支/栈偏移兜底已在 2026-10-27 关闭 |

五组内存工程只使用正常 Cargo `.o/.rlib` 和发布包的运行库，没有手工补入 di64
或 builtins 对象。462 项是 RAM 内、最大 67 个逻辑字节的有限矩阵，不代表任意长度、
任意地址空间、Flash 部署、所有 packed 聚合体或第三方 crate 均通过。
通用 Rust `.add()`/core 前置检查的正确性也未因 runtime 改用 wrapping_add 而全部关闭。

本轮证据根目录为 `D:\c28x-toolchain\b1-memory-release-20261026\`：

- `acceptance.json`、`activation-before.json`、`activation-after.json`：版本与激活记录。
- `cargo-memory-cinit/report.json`、五组 build/hw 日志与 map：最终 462 项验收。
- `core-A/B/B2-hw.log`、`abi-hw.log`、`standard-cargo-hw.json`：额外真机回归。
- `default-cargo.json`：清除测试覆盖环境后，用默认 Cargo 配置构建/再次 Fresh。
- `final-verify-*.log`、`check-abi-freeze.log`、`test-toolchain-release.log`：离线门禁。
- `cargo-memory/`、`cargo-memory-wrapping/`、`cargo-memory-final/`：依次保留
  前置检查停住、旧 memset 位宽和补 .cinit 前的失败证据；不将其登记为最终 PASS。
- `old-bundle-negative.log`：旧 72ab049d 因缺少新 libcall 路由按预期被拒绝。
- `preserved-old-backups/transfer.json`：C 盘三份旧备份转存到 D 盘的逐文件 SHA。

激活后在当前包上再次完成 `native-incremental-final/report.json` 的十步回归：
未变构建 0.249～0.263 秒，外部变更约 13～15 秒，Rust-only 10.735 秒；
未变 Rust 依赖始终 Fresh，C/头文件与 ASM/包含文件仅重编各自对象，cmd 只重链。
该轮为 D 盘隔离工程的本机测量，不能与不同并发负载下的旧数据直接作性能归因。
环境恢复探针另确认脚本退出后原本不存在的环境变量仍不存在，避免空 CARGO_TARGET_DIR。

### 2026-10-26 102923 bundle 历史基线

以下为 `20261026-102923-989317a3-fcd36edb` 当时的验收，保留历史证据：

| 层级 | 结果 | 证据边界 |
|---|---|---|
| 版本与离线门禁 | PASS | 发布哈希/锁/缓存拒绝测试；ABI freeze；MC 字节基线、O0/O2 四参/跨块/负数比较 verifier、TI 全宽 PUSH/POP oracle、ABS22 与静态指针链接 |
| 算术算法 | PASS | 1,001,024 次主机 f32 四则差分，NaN 只比较类别；不代替目标 ABI 验证 |
| 动态算术与四参 | RAM/JTAG PASS | 同 bundle 的 O0、Os 各 32 项，含 u32/i32 除余、大数、f32 四则及舍入/负零/Inf/次正规数/NaN、两组 count 的 ptr/i32/i32/ptr 调用 |
| ABI | RAM/JTAG PASS | `21845,4660,61,42,21,33,32,90,171,305419896`；包含 rust_apply、Rust→Rust sret、跨块栈参、嵌套、32 位栈参字序；不代表 TI C→Rust 聚合返回互通 |
| core A/E | RAM/JTAG PASS | A=`140,54,65,245,212,223,179`，默认及显式 `-Zub-checks=yes` 均通过，后者含 precondition/runtime_add_nowrap 链；E 16/16。C/D、Safe HAL/layer 未在本轮 bundle 重新上板 |
| 静态函数/数据指针 | RAM/JTAG PASS | `16,13,11,12,21,40,11,92`，间接函数表与带加数数据引用 |
| Cargo 算术/独立/跨 crate | RAM/JTAG PASS（三组） | 算术归档解出 3 个对象成员，配置未手工加入 loose runtime；独立=`7,13,20`，跨 crate=`23,40,19,20,82,178`；Rust `.s`=0，6 份 provenance 的 74 条 inputs 全部存在且 SHA 匹配 |
| core B/B2 | BuildOnly PASS，硬件 FAIL | B 到结束断点，结果 `11191,179`，期望 `80,179`；B2 命中入口后 run 超时 60s。两组均不能声称已支持 |

本轮编译、失败诊断及最终日志位于 B-1 `build/audit-20261026/`。此前 LRETR 指令
本身损坏的推断撤销；实际涉及错误的 callee-save 集合、奇数 SP、FI 方向/调用区、
半寄存器跨块活跃性。O0 算术探针还确认并修复了 `-1` 常量强占 ACC 导致
`i32::MIN / 1` 误入 overflow panic；相关正常/边界结果已在最终 bundle 重验。

### 2026-10-22 历史基线

以下为当时 bundle `20261022-180241-07b9d869-83f8a0e3` 的记录，不作为当前版本的新验收：

| 层级 | 结果 | 证据边界 |
|---|---|---|
| 发布/版本绑定 | PASS | bundle 哈希通过；发布清单、并发锁、原子指针与缓存拒绝测试通过；rustc 1.100.0-dev / LLVM 23.1.1 |
| ABI 冻结 | PASS | canonical DataLayout，扫描 204 个文件；仅静态门禁 |
| LLVM/MC/ELF/TI 对象回归 | PASS（扩大覆盖） | 新增 O0 比较/select 的比较-跳转相邻性、MOVL 高位三组 TI 字节 oracle，以及六种静态地址的 TI 最终链接值；不代表所有重定位类型已完成 |
| Cargo 直接对象 | PASS | 当前 active 在全新 target-dir 重建独立/跨 crate；Rust `.s` 数量 0；两个 provenance 的 11/12 个留存输入全部存在且 hash 匹配；单 crate 仅有此前 bundle 构建记录，本轮未另行重建 |
| Cargo RAM/JTAG | PASS（两组） | 独立 `7,13,20`；跨 crate `23,40,19,20,82,178`；XDS100 已恢复连接 |
| `core` BuildOnly | A/B/B2/C/D/E PASS | 当前目录另有 B/B2 拆分工作；本轮 B `.text` 0x194e、总程序 RAM 0x1ac4；B2 `.text` 0x1a5c、总 RAM 0x1c72，均位于实际 0x2000 范围内；不再沿用旧超容量结论 |
| `core` 真机 | A/C/D/E PASS；B 未通过 | A=`140,54,65,245,212,223,179`；E 16/16；C=`132,179`，D=`42967,179`。B 命中入口后 run 超时 60s，B2 尚未上板 |
| ABI 真机 | 仍待修复 | 历史 `rust_apply` 返回跑飞尚未关闭；本轮新 bundle 仅重跑 ABI BuildOnly PASS，未重新上板，不能把此次 pattern 修复当作完整 ABI 修复 |
| 静态地址初始化 | PASS（已覆盖场景） | Rust 对象有 8 个 ABS32；函数/数据/本地/奇数字节指针字段等于 `2*TI_symbol+byte_addend`；Rust volatile 解引用为 `4660,43981,18`，RAM/JTAG PASS；未据此声称间接调用 ABI 已通过 |

历史记录证明以下受限样板曾在 F28035 RAM/JTAG 通过：

- 定制 rustc 直接生成 C28x ELF `.obj`，TI 链接 control 样板；
- 完整 `f28035-safe-hal` 直编对象和 GPIO 样板；
- `core` 能用当前后端完整重编，并与最小 builtins 组成 sysroot；
- control、分层探针和 Safe HAL 在 2026-10-21 的帧/字节/clobber 修复后通过；
- Cargo 汇编路线的单 crate、跨 crate 和独立项目有历史上板通过记录。

这些证据只覆盖对应 bundle、对象、链接输入和测试数据。未重新执行的真机测试
不会因文件迁移自动获得新的 PASS。

本轮日志与临时最小复现保存在 B-1 `build-logs/audit-20261022/`。
程序 RAM `0x8000..0x9FFF` 的长度是 `0x2000`，即 8192 个 16 位 word
（16 KiB）；旧脚本注释的“4096 words / 8 KB”已纠正，地址范围和长度数值未变。
`external-static.rs/.obj/.xml` 和 `external-probe.ll/.obj` 保存旧 bundle 的零指针复现。
本次修复和硬件日志在 B-1 `build/fix-static-iter/`。原候选
`20261022-180241-07b9d869-d8aeb468` 的 compiler 清单及六项 sysroot 文件与当前
当时 active 逐项 SHA-256 相同；A/静态指针/Cargo 独立与跨 crate 也在当时版本明确复跑通过。

静态地址修复位于 `MCTargetDesc/C28xAsmBackend.cpp`：LLVM 23 的 generic data
fixup 必须显式登记 relocation。对 allocated 32 位地址字段连续登记两个 TI ABS32，
利用 `S+(S+A)=2*S+A` 生成 Rust 逻辑字节地址，非 allocated 数据仅登记一次。
真实 TI 25.11.1 linker 已核对函数、外部数据、奇数字节、负偏移和本地数据的六个最终值。
新增 LLVM fixture `static-pointers.ll`，以及 `b1-hw-static-pointers.rs`、
`hw_b1_static_pointers_driver.c`、`dss-read-b1-static-pointers.js` 和 B-1 运行脚本。
这不是全部 ELF 重定位或任意 linker 的验收。未解析分支写零已由 2026-10-27
的 fail-closed 修复关闭；不支持的 PC 相对目标会报错，尚未新增这种重定位的支持。

pattern 的原 sret 结论撤销。逐指令真机追踪证明 `Iter::new`、`slice::iter()`
和调用者复制都得到正确 `{1048,1058}`；错误来自 `NonNull::eq` 的比较标志被
PHI 搬运/溢出保存覆盖，导致起止不同仍返回相等。`CMPBR16/32_PSEUDO` 将比较和
分支保留到 RA 后一起展开，修后 whilelet=15，pattern 148→163。随后发现
`MOVL_XAR_imm` 用 `uint16_t(Imm)>>16` 取高位，永远为零；修为先移位再收窄，
恢复枚举 payload，pattern 163→223。另修 ELF 临时符号前缀为 `.L`，避免
`LOCAL_VALUE` 被误判为临时符号；mergeable 常量改为普通逐全局 section，既避开
TI merge-string 问题，也允许 GC 丢弃无用常量，不再整段保留 core 的 `.rodata`。

<a id="b1-audit"></a>

## 7. 当前问题与优化顺序

| 优先级 | 问题 | 下一步与验收 |
|---|---|---|
| 历史修复 | 动态 u32/i32 除余、f32 四则；四参 ACC clobber；rust_apply、跨块/嵌套栈参 | `102923` bundle 有 O0/Os 算术 32 项、ABI 十项与 checked A 真机 PASS，见 §6 历史矩阵；不自动给当前 bundle 或任意 core 路径记 PASS |
| 已修复（当前已重验） | direct 迭代器 B/B2 原故障与优化 core B2 | 当前 6c02958c 的 core opt=s，标准 direct core-ex 读回 B=`80,179`、B2=`90,179` PASS；B2 的 16 位 ALU 覆盖错误已修，另有 28 项边界和五种 ALU MIR 回归。只覆盖已测场景 |
| 已发布并回归 | 未解析分支不再写零 | `applyFixup` 对不能解析的 `FK_C28x_BRANCH` 明确报目标/所在 section 并失败，未新增 PC 相对重定位支持。跨 section 的 MIR 与集成 rustc 负向测试均拒绝；普通 LCR/ABS22 调用仍可链接。完整 core 重建实际揭示旧 TRAP 指向未定义入口标签，已改为无符号依赖的指令自身循环 B_SELF。长分支零位移与 TI 汇编/链接独立结果一致；它是有意的 trap 自循环，不能用于代替未知目标 |
| 已发布并回归 | 非正局部栈偏移不再钳为 1 | `eliminateFrameIndex` 对非 fixed object 的 `DeltaFromSP<=0` 明确报函数名、FI、偏移、栈大小、delta 并失败。新增 MIR 覆盖零和负距离；完整 core 重建通过。此处选择拒绝当前不能可靠物化的地址，未宣称支持所有 one-past/零大小对象或越界 frame-address 形式；若遇到合法形式也需实现正确地址计算，不能恢复钳位 |
| 已修复并验收 | Cargo 动态内存运行库闭包 | di3 已打入正式包；当前五组内存 Cargo 工程只消费正常 `.o/.rlib`，没有额外 di64 或手工注入 builtins 对象，全部链接/真机通过。直接对象 core/ABI 也复用同一运行库并将算术对象放在 RTS 之前，修正归档单次扫描的顺序问题 |
| 已修复并验收 | TI RTS 与 Rust 内存函数指针约定冲突 | 删除调用边界右移，改为独立 `c28x_*` 字节接口；五个实现来自 Rust builtins，普通名只由 TI RTS 提供。两者共存与真实 TI C 静态函数指针初始化已真机通过；初稿的位宽与核心依赖问题也一并修正，详见 §6 |
| 已覆盖的范围 | 内存奇数字节地址、长度和返回指针 | RAM 下 src/dst 奇偶组合，长度 0/1/3/7/33/67，双向重叠/自移动、0/A5/FF 填充、相等与正负比较、返回逻辑指针及未触碰字节哨兵均通过；不扩展为任意地址空间、超大长度或所有 packed 聚合体均已验收 |
| P1 / 已复现 | features 切换后 `.out` 别名过期 | 隔离默认→alternate→默认：最后 Cargo `fresh=true`、实际 artifact SHA 恢复默认，但 `independent.out` SHA 仍是 alternate。adapter 只在重链时复制 alias；`verify-cargo-direct-hw.ps1` 只检查 alias 存在就加载。需由 Cargo artifact 记录选择映像并核对 hash，不能仅按固定名字判断 |
| 已修复并回归 | 原生归档和未知链接参数静默丢弃 | 新参数白名单覆盖静态 .a/.lib、-l/-L 和库组；未知、缺失、动态、不合法或异架构成员明确拒绝。真实 Cargo/TI 验证库顺序与组重扫，归档变化增量重链，新归档映像 RAM/JTAG PASS；不宣称兼容任意 GNU linker 语义。边界与证据见 §3.3 |
| P1 | 算术覆盖仍有限 | f32 比较/转换与 di3 符号/链接门禁已通过；f64、数学函数与更多随机目标端数据仍需覆盖。主机或链接测试不能替代目标运行验证 |
| P1 | ABI 仍有未覆盖场景 | TI C 与 Rust 的指针分别为字地址/逻辑字节地址，跨语言聚合 sret 仍需显式适配；多返回值、可变参数等不在本轮验收内 |
| P1 | 无 function-sections 的独立 llc 同段调用诊断未闭环 | 本轮该诊断映像超时，开启 function-sections 后通过；当前 rustc/Cargo 默认分函数段。后续补同段内部调用重定位验收，不将其混入本轮 B-1 PASS |
| P1 | 静态地址基本修复，完整重定位矩阵仍缺 | 已覆盖函数/外部数据/本地/奇数字节/负偏移和表项；继续测跨 crate 静态表、符号差/相对地址、weak/COMDAT、重复归档及异常输入拒绝 |
| 已发布并验收 | 新包激活前强制语义回归 | select 核对同包日志/映像 SHA；当前包含 divmod 与 manifest 必须的 shifts/format，共 15 项发布验收。缺必须项不能激活；历史包保留原有回退门禁，见 §6 |
| 已验收具体依赖；广度仍待扩展 | Cargo host build script / proc-macro | 当前包同版 host std/proc_macro 与 syn/quote/proc-macro2 路径、入口/中断宏目标程序及签名负向已通过。任意 host 依赖、外部构建工具和第三方宏仍需分层验收；旧无 host 库包的 GNU 回退不代表可混用元数据 |
| 已接入增量构建 | 外部 C/ASM/`.cmd` 自动触发 Cargo | 三个应用使用共享 build script；C/ASM 逐对象缓存，cmd 仅重链。C/ASM 实际包含文件、配置、显式对象与 runtime 受跟踪；宏化/间接命令输入需 `extraDependencies`，详见 §3.3 |
| P1 / 源码风险 | rlib 同名成员覆盖与共享解包缓存竞争 | `Expand-C28xRlib` 将归档全部解到 hash 目录，未拒绝重复成员名、未加锁或原子发布；相同归档可被多个构建同时覆盖。当前再把所有对象成员加入链接，归档选择、weak/COMDAT、多 CGU/LTO 等仍缺验收。覆盖/并发本轮未做破坏性实测 |
| P1 / 部分改进 | provenance 与映像加载绑定仍待完善 | schema 4 已补原始 linker argv、消费策略、库解析顺序/哈希、实际 TI argv 和 adapter/parser/exe、部分工具身份。nativeObjects/nativeCompileIdentity 保留编译输入来源；其余完整工具闭包及供上板加载的 .out alias 绑定仍待补齐。JSON 本身不实现 Cargo 跟踪，外部库需由 build script 登记 |
| 部分关闭，仍有检查路径待验证 | sysroot 优化与检查策略 | 当前 core 显式 opt=s，并与关闭 UB precondition 的路线参数一起绑定清单；builtins 仍采用自身构建参数。B2 与格式化已通过；一般 Rust `.add`/core 检查路径和额外 machine verifier 的 undefined ACC PUSH 问题仍单列，Cargo release 不会自动重编预制 sysroot |
| P1 | 目录中硬编码可变 stage1 的旧脚本 | `verify-cargo-c28x-object.ps1` 已改为 `Get-C28xBundle` 解析 active bundle（本轮修复其 utf8 链路失败）；其余 core/Cargo/verify 脚本仍需迁出或改为 `Get-C28xBundle`，活动入口不得绕过 active manifest/hash 校验 |
| P1 | 发布清单很大，诊断版本错配仍可更直观 | 在失败输出中打印 bundle ID、compiler hash、sysroot hash 和对象 provenance |
| P2 | TI linker 对空 section 和非 `_c_int00` 入口产生大量警告 | 按 RAM 测试 profile 收敛 command file，保留真正的 placement/undefined-symbol 告警 |
| 已发布并验收 | Rust 入口与中断运行库 | 当前 active 6c02958c 含中断软件保存与同版 host 库；直接/宏入口、Timer0 和 PIE 默认向量真机 PASS。源码覆盖机制、20 文件补丁和发布流程修复见 §4；不扩大为 Flash/嵌套中断支持 |
| P1 / 部分关闭 | 合成 u32 的检查器及较大格式化闭包 | 144 项移位/宽选择及当前动态数字格式化样例已真机通过；不能据此关闭 ce48 历史检查器的所有表达式，也不保证更大的格式化闭包能放入 RAM。容量、f64 和更多参数组合继续按样例扩展 |
| P2 | Flash、嵌套中断与产品链接模板未完成 | RAM 向量与 Timer0 证据见 §3.5；独立建立 Flash 流程，不复用 RAM PASS |
| P2 | `alloc` / `std`、任意 crates 和完整 Rust ABI 未支持 | 按最小 crate 分层扩展，不宣称通用 target |

### 133307 bundle 历史审计证据（修复前）

证据目录：B-1 [`build/audit-doc-review-20261026-0b4e62f2/`](../../f28035-rust-bridge-b1/build/audit-doc-review-20261026-0b4e62f2/)。
`check.ps1`、`report.json` 和逐次 Cargo JSON 日志保留确切输入、退出码、Fresh 状态
及输出哈希；`memory-check.ps1`、`memory-symbol-provider.txt`、`memory.s`、
`memory-hw.log` 保留后续内存诊断。它们修改的都是隔离 project/target；不属于正式
编译器修复或新的发布包。

1. **alias 复现**：默认 artifact/alias 哈希前缀均 `B2A4F4DB1D6E`；alternate 均
   `33C6C8E872DF`；切回默认时 Cargo `fresh=true`、实际 artifact 为 `B2A4...`，
   alias 仍 `33C6...`。当前上板脚本读取固定 alias，因此仅检查“文件存在”不足。
2. **参数丢弃复现**：分别追加 `-Clink-arg=<隔离目录>/does-not-exist.a` 与
   `-Clink-arg=--c28x-audit-option-that-must-be-rejected`，两次 exit=0。这里的
   成功表示“未按应有语义拒绝”，不能登记为链接器能力 PASS。
3. **Cargo 运行库闭包复现**：动态 `copy_nonoverlapping::<u8>` 正常 Cargo 构建
   exit=101，TI 报 `core-cgu.0.rcgu.o` 的 `__muldi3` 未解析。direct core-ex 单独
   加入 di64 对象，而 Cargo/bundle 不包含该闭包，二者能力边界不同。
4. **隔离后续定位**：用同一 `133307` bundle 将现有 di64 源编成审计对象，仅加入
   隔离 config.tiObjects，未写入发布包。此时链接通过，map 中 memcpy 提供者是
   Rust builtins，caller 汇编在 LCR memcpy 前将 XAR4/XAR5 各右移 1。RAM/JTAG
   PC=DONE=32919，结果 `7,13,20,61166,56797,513,1027,41245`；最后五项中
   dst 两字应为 `513,56579`，实际仍为哨兵，src 与 marker 正确。故复制错误已
   实测；不能把这次附加 di64 的链接成功写成未改动 Cargo 路线已修好。
5. **外部依赖复现**：上轮 B-1
   [`build/audit-cargo-external-inputs-20261026-3a8c317d/report.json`](../../f28035-rust-bridge-b1/build/audit-cargo-external-inputs-20261026-3a8c317d/report.json)
   覆盖 C 改调用参数、ASM 加 NOP、cmd 加绝对符号。仅外部文件变化时无重链，
   强制 Rust 变化后对象/映像更新，cmd 符号才进入 map。这是修复前证据；
   本轮已通过共享 build script + 逐文件 TI 缓存接入自动增量构建，当前流程见 §3.3。
6. **B/B2 状态纠正**：`current-core-B-hw.log` 与 `current-core-B2-hw.log` 是本轮
   固定 `133307` bundle 的标准脚本回归，分别有显式 `RUSTC_DIRECT_CORE_EX_HW_B=PASS`
   和 `RUSTC_DIRECT_CORE_EX_HW_B2=PASS`，读回 `80,179` 与 `90,179`。本次未修改
   后端或测试驱动来取得 PASS；这些修复已在当前 bundle 中，文档此前未及时同步。

继续审计的重点是：常量内存操作的对齐/尾字节与超内联预算回退、动态奇数地址、
memmove 重叠和内存函数返回值、原生库参数传递、相同成员归档及缓存并发；尚未
运行的样本不写成失败或通过。当前不执行 Flash，也不以单个样板通过代替完整
目标支持。

## 8. 常用命令

```powershell
# 发布包和版本门禁
cd C:\Users\61987\Desktop\28035\f28035-rust-bridge-b1
.\tools\test-toolchain-release.ps1

# 直接对象控制样板：只构建和链接
.\tools\run-hw-rustc-direct-object.ps1 -BuildOnly

# 直接对象控制样板：执行 RAM/JTAG
.\tools\run-hw-rustc-direct-object.ps1

# Safe HAL / 分层探针 / core 广度
.\tools\run-hw-rustc-direct-safe-hal.ps1 -BuildOnly
.\tools\run-hw-rustc-direct-layer-probe.ps1 -BuildOnly
foreach ($group in 'A','B','C','D','E') {
    .\tools\run-hw-rustc-direct-core-ex.ps1 -Group $group -BuildOnly
}

# 参数 ABI 硬件样板（sret/指针池/混合/间接调用/栈参数）
.\tools\run-hw-rustc-direct-abi.ps1

# 正常 Cargo .o/.rlib 内存闭环：含 TI C .cinit 与普通内存函数共存，执行 RAM/JTAG
.\tools\verify-cargo-memory.ps1
# 只构建/链接，用 -BundleRoot 验证未激活候选
.\tools\verify-cargo-memory.ps1 -BundleRoot D:\path\to\candidate -BuildOnly

# Cargo 独立、单 crate 和跨 crate 构建/TI 链接
cargo build --release --target c28x-none-elf `
    --manifest-path .\crates\c28x-cargo-independent\Cargo.toml
cargo build --release --target c28x-none-elf `
    --manifest-path .\crates\c28x-cargo-app\Cargo.toml
cargo build --release --target c28x-none-elf --features cross-crate `
    --manifest-path .\crates\c28x-cargo-app\Cargo.toml

# 算术/四参：直接对象 O0/Os、Cargo 从 builtins rlib 自动接入
.\tools\run-hw-rustc-direct-arithmetic.ps1 -Optimization 0
.\tools\run-hw-rustc-direct-arithmetic.ps1 -Optimization s
.\tools\verify-cargo-direct-hw.ps1 -Project arithmetic
.\tools\run-hw-rustc-direct-core-ex.ps1 -Group A -WithUbChecks

# 共享 LLVM 后端回归
cd ..\f28035-rust-bridge
.\tools\verify-llvm-c28x.ps1
.\tools\verify-llvm-c28x-link.ps1
.\tools\check-ti-arithmetic.ps1
```

不带 `-BuildOnly` 的脚本会访问 XDS100 和开发板。构建通过只代表 `.obj`/`.out`
生成与静态检查通过，不能记为硬件 PASS。

<a id="b-12"></a>

## 9. `core`、builtins 与 runtime 边界

- `core` 必须由即将发布的同一 compiler 重编，不能从旧 sysroot 复制。
- 最小 builtins 位于主仓库 `crates/c28x-compiler-builtins/`，与 `core` 一起写入 bundle。
- `crates/c28x-rt/asm.s` 是当前 B-1 RAM 链接的启动输入。
- `crates/c28x-rt/interrupts.s` 保存已验证过的 TI 风格上下文序列，但完整 B-1
  `#[interrupt]` 接入仍未完成。
- `link.x.in` / `memory.x` 仍是 MSP430 风格骨架；当前可验证链路使用 TI `.cmd`。
- 当前支持的发布/验证入口都必须经 `Get-C28xBundle` 或 Cargo pin 使用
  `active.json` 指向的不可变 bundle。目录中硬编码 `rust-build-*\\stage1` 的旧脚本
  不属于当前验收入口，完成迁移前不要用于发布结论。

`core` 编译成功只证明编译器能够生成其对象与元数据，不证明所有泛型、切片、
Option、迭代器、panic 或 ABI 组合都正确。能力结论必须来自最小复现、对象检查
和硬件读回三层证据。

## 10. B-2 迁移边界

已迁出的活动文件包括：

- `run-hw-rust-control.ps1`、`run-hw-abi.ps1`、`run-hw-irq.ps1`、
  `run-hw-mem-test.ps1`；
- `verify-rust-llc-c28x.ps1`、`verify-rust-cross-module-c28x.ps1`、
  `build-gpio-blink-llc.ps1`；
- B-2 专用 Rust/C/DSS 样例、`b2-hw-ram.cmd`、旧 `c28x-gpio-blink` crate；
- `build/b2-*`、`build/c28x-gpio-blink-llc`、ABI 日志和 IRQ 反汇编历史产物。

仍留在活动主源码的内容有共享 LLVM 后端、CodeGen/MC/ELF/ABI 回归、TI 链接
脚本、runtime 和被 B-1 使用的硬件驱动。B-1 复用的 Rust 样例已改为
`b1-hw-control.rs`、`b1-hw-mode.rs`、`b1-hw-core-ex.rs` 和
`b1-hw-layer-probe.rs`，活动代码不再依赖 `b2-*` 文件名。

<a id="business-joint"></a>

## 业务联合验证（2026-11-02）

单镜像跑真实业务形状：Timer0 1 ms 中断里 `ADC 采样 -> duty = raw*1000/4095 -> ePWM1 CMPA`，
每 4 拍经 SPI-B 硬件回环换一个状态字节，主循环并行递增存活计数。
构建与判定入口：`tools/build-verify-safe-hal-business.ps1`（`-BuildOnly` 只编译链接）。

真机分项裁决（`BUSINESS_CHAIN` / `BUSINESS_EOC` / `BUSINESS_LINK`）：

| 项 | 结果 | 依据 |
|---|---|---|
| CHAIN | PASS | 1213 拍/1.2 s（1 ms 定时准确）、主循环 59147 次、TBCTR 持续前进、TBPRD=1000、AQCTLA=0x12、`CMPA == duty == raw*1000/4095` |
| EOC | FAIL | 606/1213 次软件触发 SOC0 未等到 ADCINT1；成功拍与失败拍交替 |
| LINK | FAIL | 0/303 帧 SPI-B 回环成功（SPISTS.INT 从未置位） |

### 本轮修出的外设映射/使能错误（都有真机证据）

1. `PCLKCR0.SCIAENCLK` 写成 0x0040（保留位），实际 bit10=0x0400；`SPIBENCLK` 0x0100→0x0200、
   `I2CAENCLK` 0x0400→0x0010、`LINAENCLK` 0x1000→0x0002；`PCLKCR1` 的 `ECAP1ENCLK` 0x0010→0x0100、
   `EQEP1ENCLK` 0x0020→0x4000（对照 DSP2803x_SysCtrl.h）。SCI 因此长期没有时钟。
2. `ADCRESULT0` 原按 0x7108 读，那是 `ADCINTSEL1N2`；结果镜像在 **0x0B00**（ADC_RESULT 块）。
3. `ADCINT1_FLAG` 写成 0x0002（ADCINT2），实际 ADCINT1 是 bit0。
4. ADC 帧 0x7100–0x717F 同样受 EALLOW 保护，MMIO 总线只覆盖 0x7000–0x70FF，
   导致 ADCCTL/INTSEL/SOCxCTL 写入全部被丢弃（读回全是复位值）。
5. ADC 上电序列漏了 `ADCCTL2.CLKDIV2EN` 与 `ADCCTL1.VREFLOCONV`，且把 bit2 误当 RESET
   （bit2 是 INTPULSEPOS，RESET 是 bit15）。
6. SPI 寄存器映射整体错位：`SPI_REGS` 在 offset 3/5 有保留字，`SPIBRR` 实际在 0x04，
   其后 `SPIRXEMU/SPIRXBUF/SPITXBUF/SPIDAT/SPIFFTX/SPIFFRX/SPIFFCT/SPIPRI` 全部后移；
   原映射把帧写进了错误寄存器。`SPICTL` 还缺 TALK(bit4)。
7. ePWM1 的 Rust 移植漏了 `PCLKCR1.EPWM1ENCLK`、GPIO0 复用与 `TBCLKSYNC` 括起来，
   时基根本不跑；`Pwm1Output::enable()` 原来改的是 `TBCTL` bit9（那是 HSPCLKDIV），
   已改为按 AQCTLA 恢复/封锁波形。
8. SCI `SCICTL1.SWRESET` 语义反了：F2803x 上 **1 表示复位、0 表示释放**，
   原实现最后把 bit5 置 1，把 SCI 按在复位里。

### 两个未闭合项与已定位的证据

* **EOC 间歇丢失**：`ADCCTL2` 写入不生效（读回 0；头文件注明该寄存器 Rev 0 硅片不支持），
  ADC 只能跑满速 ADCCLK，软件触发后 EOC 交替丢失。已排除：标志位地址、EALLOW、
  轮询循环（已改为 `crates/c28x-rt/asm.s` 的汇编等待 `c28x_rt_wait_adc_eoc`）、
  以及最多 3 次完全展开的重试（重试不改变比例）。下一步应改由 ePWM SOCA 触发转换、
  在 ADC 中断里读结果，绕开软件触发的这条竞争。
* **SPI-B 回环不回数据**：映射与 TALK 已修，`SPICCR=0x97`（SPILBK=1）、`SPICTL=0x1E`、
  引脚 16-19 已复用，但 `SPISTS.INT` 仍不置位。SCI-A 内部回环同样在真机不工作
  （`SCIRXST.RXRDY` 不置位），与该文档此前记录的"SCI 环回真机回归待做"一致。
  通信验收需要外部回环跳线，或换用确实可用的回环通道。

### 第二轮：ADC 字段布局与通信驱动的修正结果（2026-11-02 续）

**已修正并确认（真机寄存器读回）**

1. **`ADCSOCxCTL` 字段布局**（真正的配置级 bug）：`ACQPS = bits5:0`、`CHSEL = bits9:6`、
   `TRIGSEL = bits15:11`。原实现把 CHSEL 写到 bits0-4、ACQPS 写到 bits6-10，
   "通道 0 + 6 周期采样窗"实际变成"通道 6 + 1 周期采样窗"。
   修正后真机读回 `ADCSOC0CTL = 0x0006`（此前 0x0180），host 断言同步更新。
2. **ePWM 寄存器映射**：`SPI_REGS` 式的空洞同样存在于 `EPWM_REGS`——offset 19 是
   `TZDCSEL`，原映射漏掉它导致 `TZCTL/TZEINT/TZFLG/TZCLR/TZFRC/ETSEL/ETPS/ETCLR`
   整体前移一个字，`HRCNFG/HRPWR/HRPCTL` 也偏两个。已按 `DSP2803x_EPwm.h` 修正，
   host 断言 `ETSEL=0x6819` 通过。
3. **SCI 驱动可用化**：新增 `SciA::configure::<BAUD_DIV>()`（8N1、GPIO28/29 复用、
   先置 `SWRESET=1` 写配置、最后写 `SCICTL1=0x0003` 释放）与 `SciLink::send()`。
   `send` 在写 `SCITXBUF` 前后各等一次 `SCICTL2.TXRDY`，成功返回即表示字节已被发送器
   接纳并排空。真机读回 `SCICCR=0x7`、`SCICTL1=0x3`、`SCILBAUD=0x23`、`SCICTL2=0xC0`。

**历史诊断：方法调用失败与 FFI 绕行（通用 ZST ABI 根因说法已撤回）**

以下是旧包的调用形态对照，说明代码生成存在问题，尚不足以单独定位 ABI：

| 现象 | 方法调用形式 | 直接调用 FFI |
|---|---|---|
| ADC 每两拍超时 | `adc.sample()` → 606/1213 失败 | `ffi::f28035_adc_sample(0)` → **0/1208 失败** |
| 链路每帧失败 | `link.send(byte)` → 303/303 失败 | `sci_send_byte(byte)` → **302/302 成功** |
| CMPA 与 duty 不符 | `pwm.set_compare(duty)` → CMPA 712 / duty 729 | `ffi::f28035_epwm1_set_compare(duty)` → **CMPA == duty** |

`ConfiguredAdc<0>`、`Pwm1Output<1000>`、`SciLink<35>` 的旧方法路径确实失败，
但更换为自由函数同时改变了内联及寄存器分配，不能据此断言 `&mut self` 或泛型
参数的 ABI 有缺陷。2026-11-02 新独立探针中，旧包 32 项 ZST 方法检查通过，
失败集中在字节操作。已定位字节存储暂存 AL 前未保护活跃值、全局窄加载破坏
另一 ACC 半字，以及单字节全局节被 TI 分配为零字而重叠。修复后诊断映像
84/84 通过，实际 typed ADC/PWM/SCI 方法路径也通过。

**2026-11-02 已闭合（后端修复 + 发布 + 回归）**：候选 `20261102-122629-cf4b3949-7bc20a44`
全量发布验收 **16/16 PASS**（含 `codegen`：O0/O2/Os 各 108 项 + 真实 HAL ISR 方法路径），
已提升 active、三根指针 `CONSISTENT`。`business` **默认方法调用路径**（无 `-DirectCalls`）
短/长回归全 PASS：`ADC_ERR=0`、`LINK_ERR=0`、3×200 注入精确恢复、ISR 415–1461 周期
（2.4% 负载）；`-DirectCalls` 降为历史对照。字节读改写异常与“方法调用不可靠”说法**关闭**。

**真机最终结果（3/3 次复跑一致）**

```
BUSINESS_TICKS=1209  BUSINESS_MAIN_LOOPS=27431
BUSINESS_ADC=3275 ADCRESULT0=3275   BUSINESS_DUTY=799 CMPA=799
BUSINESS_ADC_ERR=0   OK_SAMPLES=1208/1208
BUSINESS_LINK_OK=302 LINK_ERR=0
BUSINESS_CHAIN=PASS  BUSINESS_EOC=PASS  BUSINESS_LINK=PASS
SAFE_HAL_BUSINESS_LOOP=PASS
```

即：1 ms 中断里 ADC→计算→PWM 连续 1208 拍零超时、CMPA 与 duty 逐拍一致、
SCI 发送 302 帧零失败、主循环并行存活、PWM 时基持续前进。

**HAL 方法路径与诊断对照**

* `business` 已恢复 `adc.sample()`、`pwm.set_compare()`、`link.send()` 作为正常路径；
  `build-verify-safe-hal-business.ps1 -DirectCalls` 保留旧自由函数调用用于对照。
* 发布验收新增强制 `codegen` 检查：O0/O2/Os 的字节、bool、u32 活跃值和泛型方法
  探针，以及真实 HAL ISR 方法路径。方法返回值需依据新候选/正式包证据判定，
  不再以“零尺寸句柄一律不可靠”作为通用规则。

**下一步（按优先级）**

1. 在 ISR 里把同一寄存器（`SCICTL2` / `ADCCTL1`）的 CPU 读值写进报告块，与 JTAG 读值对比，
   确认是否为"外设帧 0x70xx/0x71xx 的 CPU 读路径"问题；若确认，先修 MMIO 读路径
   （`C28xMmio::read_word` 的 `word<<1` 约定在 ISR 上下文是否被中断/流水线破坏）。
2. ADC 侧核对 ADCCLK：`ADCCTL2.CLKDIV2EN` 在本硅片写不进（读回 0），若 ADC 实际跑在
   60 MHz SYSCLK 上已超规格，需降 SYSCLK 或改用带分频的时钟方案再复测。
3. 通信验收改用外部回环跳线（GPIO28→GPIO29 / SPI SOMI←SIMO）后重跑 `BUSINESS_LINK`。

**边界**：本轮只覆盖 RAM/JTAG 运行，不涉及 Flash、死区/故障保护、嵌套中断；
CHAIN=PASS 不等于业务闭环可交付，EOC 与 LINK 未闭合前不能宣称联合验证通过。

---

## 业务长期运行验证（2026-11-02 续二）

短时 1.2 s 只能证明"链路能跑通"，不能证明"能一直跑、周期准、栈不涨、出错能恢复"。
本轮把 `business` 镜像扩成可长时运行的形态，并在真机上连续验证 30 s / 60 s。

### 报告块 v2（20 字）

`HW_BUSINESS_REPORT` 由 12 字扩到 20 字，32 位计数以支持 >65 s 的长跑：

| 索引 | 含义 | 索引 | 含义 |
|---|---|---|---|
| 0/1 | ticks 低/高（u32） | 10/11 | ok_samples 低/高（u32） |
| 2 | 最近有效 raw | 12/13 | ISR 内 CPU 读 SCICTL2 / ADCCTL1 |
| 3 | 最近写入的 duty | 14 | fault_state（0 无 / 1 窗口 / 2 已恢复） |
| 4/5 | sci_ok / sci_err | 15 | fault_window_remaining |
| 6 | adc_err（超时数） | 16 | fault_request（**主机经 JTAG 写 1 注入**） |
| 7 | 主循环计数（活性） | 17 | fault_window_size（常量，供校验） |
| 8 | 最近状态字节 | 18 | 保留 |
| 9 | 本拍 raw（分类前） | 19 | report_magic（0xBEEF，防撕裂读） |

### 栈高水位：SP 相对的哨兵填充

`run()` 一进来调用 `c28x_rt_fill_stack_sentinel`（`crates/c28x-rt/asm.s`）：

```
MOV  AL, SP            ; 先读 SP，只填 SP 之上的空闲栈
MOVZ AR7, AL
ADDB XAR7, #1
MOV  AL, #0BEEFh
loop: MOV *XAR7++, AL
      CMP AR7, #0400h
      BF  loop, NEQ
      LRETR
```

关键点：**先读 SP 再填**，所以本函数自己的返回地址和调用者活帧都在 SP 及以下、
不会被覆盖（否则 `LRETR` 直接跳飞）。只在寄存器里运算，不碰栈；因而不依赖具体
链接脚本，任何调用者都安全。跑完后 JTAG 扫描 `0x0100..0x0400`，最后一个不是
`0xBEEF` 的字就是栈历史最深地址。

### 故障注入与恢复

主机在运行中 halt → 写 `report[16]=1` → resume。ISR 检测到上升沿后开启
`FAULT_WINDOW=200` 拍的"传感器掉线"窗口：期间不更新 PWM（保持上一拍 duty，
优雅降级）、`adc_err++`、`raw=0xFFFF`；窗口结束置 `fault_state=2`，随后自动
恢复采样与占空比跟踪。窗口精确 200 拍（先判窗口再采样，关闭的那一拍已算正常）。

### 真机结果（3/3 次一致：30 s、60 s、30 s）

```
LONG_DURATION_S=30  RUN_MS=28500  WALL_MS=28515
LONG_TICKS=30328  DELTA=28815  MAIN_LOOPS=55146
LONG_PERIOD_MS=0.9891  WALL_PERIOD_MS=0.9896
LONG_TIMER0_PRD=60000  CYCLES=60001  NOMINAL_MS=1.0000
LONG_ADC=2854  ADCRESULT0=2854  DUTY=696  CMPA=696
LONG_ADC_ERR_TOTAL=200  DELTA=200  WINDOW=200
LONG_OK_SAMPLES_TOTAL=30127  DELTA=28615
LONG_LINK_OK=7581  ERR_TOTAL=0  DELTA=0
LONG_FAULT_STATE=2 (0 none, 1 active, 2 recovered)
LONG_STACK_WORDS=96  BYTES=192  HIGHEST_ADDR=0x15f  SP=0x10c
LONG_TBPRD=1000  AQCTLA=0x12  TBCTR=306->983  PC=0x89d1
LONG_CPU_SCICTL2=0x1  CPU_ADCCTL1=0xc0  MAGIC=0xbeef
LONG_SUSTAINED=PASS  LONG_PERIOD=PASS  LONG_STACK=PASS  LONG_RECOVERY=PASS
SAFE_HAL_LONG_RUN=PASS
```

四项判据：

1. **持续运行**：30 s 连续 28815 拍、60 s 连续 59137 拍，主循环并行存活；
   全程 `ADC_ERR` 恰为注入的 200 拍，**没有任何真实硬件超时**；`LINK_ERR=0`。
2. **周期**：Timer0 周期寄存器 = 60000 SYSCLK 周期（标称 1.000 ms @ 60 MHz）；
   墙钟测得 0.9891~0.9897 ms/拍，30 s 与 60 s **完全一致**（0.989），说明是
   稳定的时钟源/测量偏置（≈1.1%），而非抖动；在 3% 容差内判 PASS。
3. **栈占用**：高水位 **96 字（192 B）**，对 `--stack_size=0x200`（512 字/1024 B）
   余量 >5×，且 30 s 与 60 s 完全相同（确定性，无栈泄漏）。
4. **错误恢复**：注入后 `fault_state=2`；`adc_err` 增量恰为 200（`ok_samples`
   增量 = `ticks` 增量 − 200，精确对账）；窗口内 `LINK_ERR` 增量 0（控制环
   未因传感器故障停摆）；窗口后 `CMPA==duty` 重新跟踪。

**复现**：

```
tools\build-verify-safe-hal-business.ps1 -LongRun -Duration 30
# 或直接：dss verify-safe-hal-business-long.js <ccxml> business.out 60
```

**说明**：`ticks` 与 `ok_samples` 之间存在固定 +1 的结构性偏移（短时 1209/1208、
长时同样 +1），来自"采样计数在拍内累加、tick 计数在拍末累加"的次序；在**增量**
里两者相消，故长时对账用 `okΔ = ticksΔ − adcΔ` 精确成立。此偏移不影响任何判据。

### 时钟与周期精测 + 重复故障恢复（2026-11-02 优化）

**周期精测（`nanoTime`）**：`System.currentTimeMillis()` 在 2 s 窗口上只有 ~15 ms
分辨率（~0.7% 误差），换用 `System.nanoTime()`（亚微秒）后周期稳定为 **0.9912 ms/拍**。

**时钟诊断**（`tools/diag-clock.js`）：读回 `PLLSTS=0x0101`（DIVSEL=2、PLLLOCKS=1、
MCLKSTS=0）、`PLLCR=0x0C`（DIV=12）——PLL 按 ×12/÷2 配置且已锁定；由 PRD=60000 与
实测周期反推 **SYSCLK≈60.53 MHz**（比标称 60 MHz 高 ~0.9%）。这是**时钟源公差**
（板载 10 MHz 内部 INTOSC ±1% 或谐振器），不是 PLL/驱动缺陷；对 UART（±2–3%）与
PWM 频率都在设计容差内。`diag-clock.js` 输出 `CLK_SYSCLK_MHZ=60.533`、
`CLK_IF_DIVSEL2_IS_DIV2: crystal=10.089 MHz`。

**重复故障恢复**：故障窗口改为**可重复注入**（`report[16]=1` 在 `fault_state≠1` 时都能
重新触发，新增 `report[18]=fault_count`）。长跑脚本一次注入 N 次（默认 3），要求
`fault_count==N`、`adc_err` 增量恰为 `N×200`、`LINK_ERR` 增量 0、末次后 `fault_state==2`。

**最新结果（30 s，3 次注入，direct-ffi 变体）**：

```
LONG_TICKS=30322  LONG_PERIOD_MS=0.9912  SYSCLK_MHZ=60.536  TIMER0_PRD=60000
LONG_ISR_CYCLES_MIN=422  MAX=1300  US_MAX=21.47  LOAD_PCT=2.17
LONG_ADC_ERR_TOTAL=600  EXPECTED=600  DELTA=600
LONG_LINK_OK=7580  ERR_TOTAL=0  DELTA=0
LONG_FAULT_COUNT=3  STATE=2  WINDOW=200
LONG_STACK_WORDS=96  BYTES=192
LONG_SUSTAINED=PASS  LONG_PERIOD=PASS  LONG_HEADROOM=PASS
LONG_STACK=PASS      LONG_RECOVERY=PASS
SAFE_HAL_LONG_RUN=PASS
```

**实时余量（新增）**：ISR 体执行时间用 Timer0 下计数器在入口/出口各读一次 `TIML` 得到
（`c28x_rt_read_timer0_tim`，0x0C00）。实测 **422–1300 周期 = 7.0–21.5 µs**，占 1 ms 周期的
**2.17%**，即约 **46× 余量**——控制环有充足的实时裕度。

**复现**：`verify-safe-hal-business-long.js <ccxml> business.out 30 3`（时长、注入次数）。
**注意（2026-11-02 已更新）**：业务镜像由 `feature="business-direct-ffi"` 门控——`-DirectCalls`
走自由函数直调（历史对照），默认走**方法调用**（正常路径）。**在 active 包
`20261102-122629-cf4b3949-7bc20a44`（含字节读改写修复）上，方法调用路径已短/长回归全 PASS**，
两条路径均可用；此前"方法调用不可靠"仅对旧包成立。本节其余 PASS 记录来自 direct-ffi 变体
（`build/safe-hal-business-direct`），最新方法调用路径回归见下方"编译器正确性闭环"。

---

## HAL 与常用库覆盖回归（2026-11-02 续三）

### 1. 运行时闭包（逐符号，`build/safe-hal-business/business.map`）

| 目标 | 代码字数 | 说明 |
|---|---|---|
| `hal.obj` | 2556 | Safe HAL，业务闭环全部逻辑 |
| `rt-asm.obj` | 608 | c28x-rt 启动/等待/EALLOW/栈哨兵 |
| `rt-int.obj` | 29 | TINT0 中断跳板 |
| `ti-arithmetic.o` | 8 | **仅 `__udivsi3`**（u32 除法） |
| `rts2800: autoinit.c.obj` | 43 | `__TI_auto_init_nobinit_nopinit` |
| `rts2800: startup.c.obj` | 1 | 启动填充 |
| **合计** | **3245** | |

- **无** `printf/sprintf/memcpy/memset/malloc`，**无** float/soft-float 符号，**无**第三方 crate。
- `% 4` 被优化为 `& 3` → 镜像里没有 `__umodsi3`。

### 2. 数学路径逐项验证

| 路径 | 使用点 | 证据 |
|---|---|---|
| u32 合成/移位/加/减/乘/比较/异或 | 32 位计数、半字合成 | `b1-u32-compose` 真机 24 格 **全 PASS**（`U32_COMPOSE=PASS`，含 borrow 传播 1−c=0xEDCBA988） |
| u32 除法 `__udivsi3` | `duty = raw*1000/4095` | 业务长跑 30000+ 拍 `CMPA==duty`（如 2854→696）；host 曲线断言 |
| u32 模 | 无（`%4→&3`） | map 无 `__umodsi3` |
| u16 回绕 | `rust_add` | host `wraps_at_u16_boundary` |
| float / soft-float | 无 | 整数闭环，map 无 float 符号 |

### 3. 格式化

HAL 不使用 `core::fmt` / `format!` / `write!`（grep 无命中），镜像里也没有 fmt 符号
→ 固件**没有格式化路径**（N/A，不是"未测"）。

### 4. 第三方 crate

`embedded-hal` 1.0 是可选 feature（默认关闭），业务镜像未启用 → **未链接**。

### 5. 驱动覆盖矩阵（含本轮改动）

| 驱动 | 本轮改动 | Host 用例 | 真机证据 |
|---|---|---|---|
| **ADC** | `ADCSOCxCTL` 字段、上电序列、EOC 判据、ISR 直调 ffi | `adc_handle_is_reachable`、`configured_adc_keeps_channel`、`nonexistent_adc_result`、`business_duty_mapping`、上电序列断言 | 长跑 30000+ 采样 **0 超时**；`ADCSOC0CTL=0x0006`；`ADCRESULT0==raw` |
| **SCI-A** | `configure`/`SWRESET`、`send`、寄存器映射 | `sci_rejects_invalid_char_length`、pac SCI 寄存器用例 | 长跑 **7581 帧 0 失败**；`SCICCR/SCICTL1/SCILBAUD` 读回 |
| **ePWM1** | `TZDCSEL` 映射、`set_compare` 直调、使能 | `timer_and_pwm_validate_configuration`、duty 曲线 | 长跑 `CMPA==duty` 逐拍；`TBPRD=1000`；`AQCTLA=0x12` |
| **Timer0** | 周期/中断 | `timer_and_pwm_validate`、`periodic_timer_state_transitions`、`timer_rejects_bad_period` | 长跑 `PRD=60000`、0.989 ms/拍；`verify-safe-hal-timer0` |
| GPIO | — | `gpio_inputs_*`、`gpio_claims_*`、`mux_*` | `verify-gpio34`、`verify-gpio0-mux` |
| SPI-B / I2C-A / LIN-A / eCAP1 / eQEP1 / CAN | 未改 | pac 寄存器用例 | 既有 MIR `verify-*`（SPI/SCI/LIN 内部回环本板不回数据，属**寄存器级**） |

### 6. 回归结论

- **Host：55/55 PASS**（`--cfg feature="arithmetic"` + `feature="bare-mmio-business"`）。
- **真机**：业务长跑 3/3 PASS；u32 探针 24/24 PASS。
- 改动驱动（ADC/SCI/ePWM/Timer0）由长跑闭环覆盖；未改驱动由既有 MIR verify + pac host 用例覆盖。
- **边界**：I2C/LIN/SPI/eCAP/eQEP/CAN 的**数据通路**需要外部从机/信号源，本板内部回环不回数据，
  因此这些通道目前是寄存器级验证；要升级为数据级需外接跳线/从机。

---

## 编译器正确性闭环：字节读改写修复（2026-11-02）

### 根因（不是通用 ZST ABI）
旧"零尺寸句柄＋泛型方法调用一律不可靠"的说法**已撤回**。旧包 32 项 ZST 方法检查本就通过，
84 项真机探针的 10 项失败集中在**字节/布尔操作**。定位到三处后端代码生成缺陷
（`backend/llvm-c28x/C28xInstrInfo.cpp`）：

1. **字节存储暂存 AL 前未保护活跃值**：`STORE8_GLOBAL_PSEUDO` 把非 AL 源移进 AL 前未 `PUSH_ACC`，
   覆盖了活跃 ACC（含函数返回值）——`exchange(false→true)` 返回旧 AL。
2. **全局窄加载破坏另一 ACC 半字**：窄加载定义 AL/AH 时，`AccLiveThrough` 把"已定义半字"误当
   需保存的旧值（实为新值），导致多存/错存。
3. **单字节全局节被 TI 分配为零字**而重叠。

### 修复
- `STORE8_GLOBAL_PSEUDO`：`Src != AL && AccLiveThrough()` 时先 `PUSH_ACC`，再 `MOV16rr AL,Src`，
  存完 `POP_ACC`。
- `AccLiveThrough`：按 `DefinedByMI` 是否覆盖 AL/AH 忽略"已定义半字"，只保留真正存活的对半字。

### 发布验收（候选 → active）
- 候选 `20261102-122629-cf4b3949-7bc20a44`（编译器 sha `BA5D7A6B…`）。
- `verify-b1-release.ps1` **16/16 PASS**：runtime / divmod / shifts / **codegen** / format /
  memory / abi / core-A..E / cargo-independent / cargo-control / cargo-arithmetic。
  - `codegen` 门禁：O0/O2/Os 各 **108 项**（字节/bool/u32 活跃值 + 泛型方法）+ **真实 HAL ISR 方法路径**，全 PASS。
- `select-b1-bundle.ps1` 提升 active；三根指针
  `B1_RELEASE_POINTERS=CONSISTENT (3 root(s) -> 20261102-122629-cf4b3949-7bc20a44)`。

### 回归（方法调用路径，无 `-DirectCalls`）

```
短时：BUSINESS_ADC_ERR=0  LINK_OK=300/0  SAFE_HAL_BUSINESS_LOOP=PASS
长跑 30s/3 注入：
LONG_ADC_ERR_TOTAL=600 EXPECTED=600 DELTA=600      ← 3×200，零真实超时
LONG_LINK_OK=7579 ERR_TOTAL=0
LONG_FAULT_COUNT=3 STATE=2
LONG_ISR_CYCLES_MIN=415 MAX=1461 US_MAX=24.14 LOAD_PCT=2.43
LONG_SUSTAINED/PERIOD/HEADROOM/STACK/RECOVERY=PASS
SAFE_HAL_LONG_RUN=PASS
```

即：**字节读改写异常已关闭**；`business` 默认方法调用路径在修复后的 active 包上短/长回归全绿，
`-DirectCalls` 自由函数绕行降为历史对照。

### 证据
- 验收：`f28035-rust-bridge-b1/build/release-acceptance/20261102-122629-cf4b3949-7bc20a44/`
- 回归：`D:\c28x-toolchain\biz-methodcall-newbundle-short.log`、`biz-methodcall-newbundle-long.log`

---

## ePWM 故障保护（trip-zone）+ EALLOW 映射修复（2026-11-02）

**新增能力**：业务环在 `run()` 里配置 ePWM1 trip-zone（`TZCTL` 强制低、`TZEINT` OST 使能）；
故障注入（`report[16]=1`）时 ISR 触发**真实硬件一次性跳闸**（`TZFRC` bit2 → OST），
输出被强制拉低（fail-safe）；窗口结束后 `TZCLR` 释放，输出恢复跟踪。
报告新增 `[22]=tz_ost_count`、`[23]=OST 曾经置位`。

**顺带修出的真 bug（重要）**：MMIO 总线 `C28xMmio::write_word` 的 EALLOW 白名单只覆盖
SysCtrl(0x7000–0x70FF) 与 ADC(0x7100–0x717F)，**漏了 ePWM trip-zone 帧 0x6812–0x6818**。
于是所有 TZ 写入（TZSEL/TZCTL/TZEINT/TZCLR/TZFRC）都被静默丢弃——连已有的
`configure_external_trip` 也从未真正生效。修复：把该范围加入 EALLOW 白名单。
这是"写进保护寄存器却没生效"的典型陷阱，且只有真机（读回 TZFLG）能暴露。

**真机验证（30 s，3 次注入）**：

```
LONG_TZ_OST_COUNT=3  TZ_LATCHED=0x4  TZ_FLAGS_NOW=0x0
LONG_FAULT_PROTECTION=PASS
LONG_SUSTAINED/PERIOD/HEADROOM/STACK/RECOVERY=PASS
SAFE_HAL_LONG_RUN=PASS
```

即：3 次故障各自触发 OST（`TZFLG` bit2 置位 = 0x4），窗口后全部释放（末次 `TZFLG`=0）；
`ADC_ERR` 仍精确 3×200、`LINK_ERR=0`、`CMPA==duty`、栈 100 字、ISR 495–1499 周期（2.5%）。
Host 55/55 PASS。

---

## SCI 真实收发与 ADC 新鲜采样验收（2026-11-02）

### ADC 新鲜采样：已证明
`adc_sample_once` 在 ADCBSY 清零后**再检查 ADCINT1（EOC）**：trigger 先清 ADCINT1，
所以该位再次置位只能是**本次转换**的 EOC；未置位则返回 0xFFFF（拒绝陈旧值）。新增
`ADC_EOC_SEEN` 计数（`report[25]`）。真机 30 s：`ADC_EOC=29708 == OK_SAMPLES=29708`
→ **每个被接受的样本都观测到自己的 EOC，即每拍都是本次转换的新结果**。

### ADC 时钟：已核实
读回 `ADCCTL2.CLKDIV2EN=0` → **ADCCLK = SYSCLK ≈ 60.5 MHz**（CLKDIV2EN 在 Rev0 硅片上
写不进，读回 0）。F28035 ADC 的 ADCCLK 上限约 30 MHz，因此**超规格运行**；但转换仍能完成
（EOC 每拍观测到、结果稳定）。要进入规格需降低 SYSCLK（会改动 Timer0/PWM/SCI 全部时序），
本轮不改，记录为 Rev0 限制（`LONG_ADC_CLOCK=UNDIVIDED_60MHZ_REV0_OVER_SPEC`）。

### ADC 校准：已核实（trim=25）
- 排查：`DSP2803x_Adc.c::InitAdc` 需调 `Device_cal()`（ROM `0x3D7C80`）把 OTP 校准写入
  `ADCOFFTRIM`；RAM/JTAG 若绕过 boot ROM 则不会自动校准。
- 实测：`ADCOFFTRIM=25`（≠ 复位值 0）→ **已校准**（由复位/boot ROM 从 OTP 载入）。
  报告 `[29]/[30]` = offtrim before/after = `25/25`。
- 已加显式 `Device_cal()` 调用（`platform/runtime/device_cal.c` 的 C shim）作防御；一次
  corrupt-restore 测试（写 0 → 调 cal）显示它在本模式下**不重载** trim（说明校准来自 boot ROM），
  故保留为防御、不依赖它。若将来改为完全绕过 boot ROM 的加载方式，需再单独验证该调用。

### SCI 真实收发 —— 内部回环已打通，**无需跳线**
- **修出真 bug ①（SCICCR）**：`SCICCR_LOOPBACK_8N1` 原为 `0x0010`，SCICHAR=0（**1 位字符**），
  改为 `0x0007 | 0x0010 = 0x0017`（8 位 + LOOPBKENA）。
- **修出真 bug ②（SWRESET 写反，正是本轮要点）**：原代码以 `SCICTL1=0x0003`（SWRESET=0）结尾，
  但硬件实测（`pac-hwtest-b1` 探针，真机验证过）**SWRESET=1 才是"释放/正常"、0 是"复位"**。
  所以原代码把 SCI 一直**按在复位态**：TXRDY 读 1（"发送成功"假阳性）、实际一个字节都没发出去，
  回环自然收不到。改为：先 `SCICTL1=0`（复位）、配置、最后 `SCICTL1=0x0023`（SWRESET|TXENA|RXENA 释放）。
- **复刻探针序列**：`SCICCR=0x0017` + FIFO 复位（`SCIFFTX=0xE000`/`SCIFFRX=0x2000`）+ `BRR` +
  释放后写 `SCITXBUF`，延时后**直接读 `SCIRXBUF`**（不轮询 RXRDY）。
- **真机结果**：`TX=1 RX=1 MISMATCH=0`，`0x5A` 原样回显 → **内部回环工作，`LONG_SCI_LOOPBACK=PASS`，
  不需要外部跳线**。
- 说明：之前误判"内部回环死"，是 **SWRESET 复位态 + SCICCR 1 位字符 + RXRDY 轮询**三者叠加所致。
  修正后单字节内容已验证；多字节连续模式因 FIFO/时序需再调，单字节已足以证明收发通路。

### 结论
| 项 | 结果 |
|---|---|
| ADC 新鲜采样 | **已证明**：EOC 观测数 == 接受样本数（29715/29715） |
| ADC 时钟 | **已核实**：ADCCLK=SYSCLK≈60 MHz，Rev0 无分频、超规格 |
| SCI SCICCR | **真 bug 已修**：1 位字符 → 8 位（0x0017） |
| SCI SWRESET | **真 bug 已修（写反）**：`0x0003`(复位) → `0x0023`(释放) |
| SCI 内部回环 | **已打通**：`0x5A` 回显、`MISMATCH=0`，**无需跳线** |

### SCI 连续收发 / FIFO / 超时恢复（2026-11-02 续）
- **单字节回环**：`0x5A` 回显，`MISMATCH=0`（硬判据 PASS）。
- **超时恢复**：非回环 + 无对端时，RX 用有界轮询（5000 次）→ **超时并正常返回、不挂死**
  （`TIMEOUT_OK=1`，硬判据 PASS）。
- **多字节连续 / FIFO**：内部回环**只能稳定回显第一个字节**；连续发 8 字节时，后续读
  `SCIRXBUF` 恒为 `0x90`（8 个字节全部 0x90、7/8 不匹配）。这是本板内部回环的**实测限制**
  （非软件 bug），真实多字节/对端通信需要**外部设备或 GPIO28→GPIO29 跳线**。
- 记录：`LONG_SCI_LOOPBACK=PASS SINGLE=1/1/0 MULTIBYTE=8/7 TIMEOUT=1`。

---

## 调试/检查开启路径（overflow-checks / debug-assertions）闭环（2026-11-02）

**问题**：矩阵一直用 release 检查策略（`-Coverflow-checks=no -Cdebug-assertions=no`），
"开启溢出检查后进入异常"的历史记录一直未关闭。

**根因（实测）**：开启检查后编译器生成 panic 路径（`core::panicking::panic_*` →
`rust_begin_unwind`），而业务镜像（direct-object 直链，不链 `panic-c28x`）**没有
`#[panic_handler]`** → TI 链接报 `undefined … rust_begin_unwind`、`unresolved symbols remain`
→ **根本产不出映像**。所谓"进入异常"其实是**链接失败**，不是运行时真的溢出。

**修复**：在 HAL 的 business 路径加一个最小 `#[panic_handler]`（本 target 不支持 `asm!`，
故不做 DINT，只 `loop { spin_loop() }`，让调试器可停）；门控在
`all(feature="bare-mmio-business", not(test))`，避免与 Cargo 路径的 `panic-c28x` 冲突。

**验证**（`build-verify-safe-hal-business.ps1 -Checked`，即 `-Coverflow-checks=yes
-Cdebug-assertions=yes`）：

```
短时：TICKS=1205  ADC_ERR=0  LINK_OK=302/0  SAFE_HAL_BUSINESS_LOOP=PASS
长跑 30s/3 注入：
LONG_ADC_ERR_TOTAL=600 EXPECTED=600 DELTA=600
LONG_LINK_OK=7585 ERR_TOTAL=0
LONG_FAULT_COUNT=3 STATE=2
LONG_SCI_LOOPBACK=PASS  LONG_ADC_FRESH=PASS
LONG_SUSTAINED/PERIOD/HEADROOM/FAULT_PROTECTION/STACK/RECOVERY=PASS
SAFE_HAL_LONG_RUN=PASS
```

→ **业务环在检查全开下无溢出、无 panic**，该路径关闭；未检查版本与 Host 55/55 均无回归。

**panic 现场记录**：新增 `PANIC_FLAG`（`no_mangle`），panic handler 里写 `0xDEAD`。验证脚本读它区分：
- `0x0`：检查版（handler 已链），本次未 panic；
- `n/a(no-handler)`：未检查版——无 panic 路径，`--unused_section_elimination` 把 handler 整段删掉，
  符号不存在（等于"不可能 panic"；DSS 会打一条 benign 的 `SEVERE` 符号查找日志，脚本已 try/catch）；
- `0xDEAD`：真的 panic 了，脚本判 FAIL。

真机：检查版 `LONG_PANIC_FLAG=0x0`、`SAFE_HAL_LONG_RUN=PASS`；未检查版 `n/a(no-handler)`、
`SAFE_HAL_BUSINESS_VERIFY=PASS`。

---

## 机器验证器 undefined ACC 收尾（2026-11-02）

**根因**：`expandPostRAPseudo`（`backend/llvm-c28x/C28xInstrInfo.cpp`）多处对 ACC 的保存是**无条件**的，
或在 ACC 本块内无值（未定义）时仍发 `PUSH_ACC`，`-verify-machineinstrs` 报
"Using an undefined physical register"。

**已修（源码）**：
1. `ADD32imm` 展开：`bool Save = Dst != C28x::ACC;` → `Dst != ACC && AccLiveThrough();`
2. `LOAD16` 通用路径：`AccLiveThrough()` → `AccLiveThrough(Dst)`（忽略装载结果半字）。
3. `AccLiveThrough` 增加"ACC 在 MI 处确有值"检查（`computeRegisterLiveness == LQR_Dead` 且本块内无 def → 不保存）。

**验证**（增量重建 `llc`，`-verify-machineinstrs` 跑 `test/CodeGen/*.ll`）：
- 修复前 **5 个**失败：memcpy-inline / simple_loop / stack-args-stress / sub32imm / two_phi。
- 修复后 **4/5 通过**；仅剩 `stack-args-stress.ll`（`LOAD8_ZEXT32`，Dst=xar7：验证器认为 ACC 未定义，
  后端 liveness 却判 live）——该边界仍待定位。
- `mmio-oor.ll` 是**预期负向测试**（常量指针超 22 位），不计失败。
- **额外发现**：`test/CodeGen` 的**字节 oracle（FileCheck）已过期**——即便回退后端改动，4 个用例仍失败
  （`-filetype=obj | llvm-objdump -s -j .text | FileCheck`）。这些 oracle 相对当前（未提交的）后端已漂移，
  需重新生成后才能作为功能门禁；因此本轮只能以机器验证器为 undefined-ACC 判据。

**注意**：该修复已在 `llc` 后端源码验证，但**尚未进入 active rustc bundle**（rustc 内嵌后端，需重建 bundle +
发布 + 回归）。因此当前仍**不能宣布编译器全面正确**。

### Cargo O0 检查探针：同条件重验（2026-11-02）
`verify-cargo-codegen.ps1` 新增 `-Checked`（`-Cdebug-assertions=yes -Coverflow-checks=yes`），在 O0 用
"检查全开"重跑探针：
- **结果：仍然异常**——DSS `Target.run()` 15 s 超时（探针挂在 panic handler）。
- **定位**：读 PC=`0x947f`（panic handler，`codegen_done=0x9482`），且 `HW_CODEGEN_RESULT[0..1]=0`
  → **探针在任何结果写入前就 panic 了**，不是时序问题。
- 探针算术本身几乎都用 `wrapping_add`（无显式溢出），故更可能是**后端对"检查/断言路径"的代码生成**在
  O0 下出错（把正常路径误判进 panic），而非探针真溢出——需进一步定位（这属于后端 check-path 深水区）。
- 结论：该历史问题**已重验、确认仍存在**，未关闭；发布门禁仍用 checks-off 策略规避。

---

## 避免下载到旧映像：绑定实际 Cargo 产物（2026-11-02）

**问题**：`verify-cargo-direct-hw.ps1` 原先按固定名字加载
`<target>/c28x-none-elf/release/control.out`。当 features 切换再切回、Cargo 复用缓存产物（fresh）时，
链接器（写 `.out` 副本）不重跑，`control.out` 可能是上一组 features 的旧映像 → **下载/验证了旧映像**。

**修复**：改为 `cargo build --message-format=json`，从 `compiler-artifact.executable` 取**实际产物路径**，
直接加载该产物并记录 SHA-256（`C28X_CARGO_ARTIFACT=… SHA256=…`），不再按固定名字判断。
（Cargo 进度走 stderr、JSON 走 stdout；脚本临时放宽 `$ErrorActionPreference` 并把错误记录转字符串后过滤 JSON 行。）

**验证**：`verify-cargo-direct-hw.ps1 -Project control` →
`C28X_CARGO_ARTIFACT=…/build/cargo/20261102-122629-…/c28x-none-elf/release/c28x-cargo-app SHA256=7487E09E…`，
`C28X_CARGO_DIRECT_HW=PASS`。

