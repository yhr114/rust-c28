# 工作日志

本日志按日期追加，记录每次实际修改。路线的当前操作说明见
[路径 A](docs/path-a/PATH_A.md) 和 [路径 B](docs/PATH_B.md)；日志中的历史结果不自动代表当前状态。

每条记录写：**修改范围、原因、完成内容、过程事件、验证与结果、遗留事项**。
验证须区分文档检查、主机构建和硬件实测；没有运行的项目直接写“未运行”。

## 2026-10-22 B-1 静态指针与迭代器修复（进行中）

- 数据 fixup 原先写零且未注册重定位。补 TI ABS32，并对 allocated 32 位地址字段
  发出两个同位置 ABS32：TI 的 `S+A` 组合为 `2*S+A`，保持 Rust 逻辑字节地址。
  六种 LLVM 初始化器（函数、外部数据、奇数字节、负偏移、本地数据）经 TI 实际链接
  验证最终值全部正确；加入 `static-pointers.ll` 和扩展 link 回归。
- 纠正前次 sret 推断：F28035 断点逐段追踪确认 `Iter::new`、`slice::iter()` 返回
  `{1048,1058}` 正确，调用者复制到 iterator 也正确；`MOVL XAR6,@XAR7` 是寄存器复制。
  真正错误在 `NonNull::eq`：`SUBL` 比较得到 -10 后，PHI 的 `MOV AL/ MOV AH` 与
  spill 覆盖 ST0，`B EQ` 错跳，两个不同地址返回 true。修为 RA 后才展开比较和跳转。
- 新增 O0 compare/select 回归，检查每个条件分支紧邻比较；LLVM MachineVerifier、
  MC 回归与 TI link 回归均通过。原 frame 字节基线因循环分配/布局变化更新；独立 TI
  汇编核对新循环指令与目标，TI 默认选择短分支/寄存器别名编码，非逐字节相同。
- LLVM 首次重建因旧 Qt Ninja 不识别新版本 `.ninja_log` 触发大范围重编；随后因
  MCSectionELF 不支持 LLVM cast 的 classof 编译失败，改为确定类型的 static_cast 后通过。
  定制 rustc 重链成功，compiler candidate `20261022-174757-e1a3db67`，配套 core/builtins
  候选正在构建；active 仍为旧 bundle，尚未把修复记作 B-1 上板通过。
- XDS100 初两次 RAM load 超时，恢复连接并增加 reset 后 halt 后多次 trace 成功；用户
  确认供电/JTAG 正常。新增完整 B-1 静态地址真机回归源、TI driver、DSS 与运行脚本，
  覆盖指针字段和 volatile 解引用；等待新 bundle 后验证。未执行 Flash。

## 2026-10-21 — 后续工作范围收敛到 PATH B-1

- 修改范围：`AGENTS.md`、`README.md`、`docs/PATH_B.md` 与本日志。
- 原因：当前目标只推进 B-1，PATH A 的 MIR、Rust-to-C、应用迁移及其失败不再处理。
- 完成内容：将 B-1 设为后续默认且唯一的工作范围；明确 PATH A 问题不进入
  B-1 待办、发布门禁或完成判定。B-1 范围包括定制 rustc、C28x LLVM 后端、
  ABI、`core`/builtins、Cargo、TI 链接、版本化发布包和对应硬件验证。
- 过程事件：保留 PATH A 现有文件和历史记录，不继续诊断上一轮联合 oracle 的
  MIR control-loop nightly API 漂移。
- 验证与结果：仅修改范围说明；未运行构建、JTAG 或 Flash。
- 遗留事项：只有用户以后明确要求时才恢复 PATH A 工作。

## 2026-10-21 — B-2 完整迁出活动工程

- 修改范围：主仓库的 B-2 脚本、Rust/C/DSS 样例、旧 GPIO crate、B-2 构建
  产物、B-1 复用样例命名、Cargo 清单、ABI 门禁、README/SETUP/PATH A/PATH B，
  以及同级 `f28035-rust-bridge-b2-archive/`。
- 原因：当前开发、发布和 Cargo 接入已经统一走 B-1；B-2 文件继续留在活动树会
  混淆独立 `llc` 开发工具与实际交付路线，也让 B-1 仍依赖 `b2-*` 名称。
- 完成内容：将 8 个独立 `llc` 流水线入口、3 个 B-2 专用 Rust 样例、相关
  C/DSS 支撑、旧 `c28x-gpio-blink` 和 9 组构建产物移入归档；B-1 复用的
  control/mode/core-ex/layer-probe 改为 `b1-*` 并更新脚本、Cargo 和文档引用；
  `check-abi-freeze.ps1` 改为直接校验 B-1 target spec；活动 PATH B 收敛为 B-1
  操作手册，迁移前完整文档原样保存在归档。
- 过程事件：确认 `backend/llvm-c28x/` 是 B-1 rustc 内置后端的唯一活动源码，
  因此没有把共享后端误搬入 B-2 归档；独立 `llc` 的 CodeGen/MC 回归继续作为
  B-1 后端开发手段。control/mode 在归档内保留原名副本，便于解释旧脚本。
- 验证与结果：5 个相关 PowerShell 脚本解析通过；两个 Cargo manifest 的
  `cargo metadata` 通过；ABI 冻结扫描 165 个文件通过；发布清单、锁、原子指针
  和缓存拒绝门禁通过；control direct-object BuildOnly 首次全量 BUILD、第二次
  全量 SKIP；layer-probe 与 core-ex Group A BuildOnly 均重新生成 Rust 对象并
  完成 TI 链接。`verify-llvm-c28x.ps1` 初次发现 10 个对象字节基线仍是保护字和
  MOVB 修复前版本，按已有硬件真值更新为“TI 指令编码 + B-1 帧基线”后全部通过；
  联合 oracle 的 6 个 LLVM 用例通过，MIR control-loop 因当前 nightly 的
  `rustc_driver` API（`run_compiler`、`loop_hint_attrs`、`ConstExt`）漂移构建失败。
  本次未执行 JTAG/RAM 读回或 Flash。
- 遗留事项：归档脚本保持历史相对路径，默认不保证可直接运行；若未来恢复 B-2，
  必须在隔离目录重新绑定共享源码版本，不能重新接入 B-1 active bundle。

## 2026-10-19 — 建立持续更新和记录规则

- 修改范围：`AGENTS.md`、`README.md`、`docs/PATH_A.md`、`docs/PATH_B.md`、`WORK_LOG.md`。
- 原因：每次工程改动都需要同步路线说明，并留下可追溯的经过和结果。
- 完成内容：加入项目维护规则；两份路线文档增加维护记录；建立统一工作日志。
- 过程事件：核对主工程 `docs/` 当前只有 A、B 两份路线文档，沿用这一结构。
- 验证与结果：检查文档链接和章节锚点；本次不涉及固件构建或上板测试。
- 遗留事项：后续每次改动按 `AGENTS.md` 增补路线文档和本日志。

## 2026-10-19 — 路径 A/B 文档合并（补记）

- 修改范围：主工程 `docs/`、B-1 历史路线说明、`README.md`、`SETUP.md` 及相关引用。
- 原因：原路线资料分散且重复，难以判断当前 B-2 与旧路径的边界。
- 完成内容：将 23 份路线资料全文并入 `docs/PATH_A.md` 和 `docs/PATH_B.md`；
  原文件校验值写在对应章节；移除合并后的 23 份重复文档及两个旧索引，更新入口链接。
- 过程事件：保留了各硬件测试用例目录中的 README，因为它们承载用例级操作信息。
- 验证与结果：移除原文前逐个核对 SHA-256；文档相对链接和章节锚点检查通过；
  未运行固件构建或硬件测试。
- 遗留事项：合并章节保留了原文的日期和旧文件名，阅读时以文档开头的当前路线说明为准。

## 2026-10-19 — Cargo 直编接入与 LLVM 一致性校验

- 修改范围：B-1 的 TI 链接适配器、主机入口、两个 Cargo 示例、真机验证脚本，
  主工程 LLVM 指纹工具及 `docs/PATH_B.md`。
- 原因：把已通过的 B-2 汇编／TI 对象路径接到普通 Cargo 命令，并防止 LLVM
  后端更新后沿用不匹配的 patched rustc 或 Cargo 缓存产物。
- 完成内容：rustc 为项目及路径依赖生成汇编，适配器转 TI 汇编与对象并链接
  `.out`；两个示例项目直接运行 `cargo build`，一个跨两个 Rust crate，
  另一个使用独立 Rust 源码。增加 LLVM 内容指纹检查，构建脚本只在 LLVM
  构建前后指纹一致时记录成功；示例 `build.rs` 监视 LLVM `lib`、`bin`
  目录及链接工具变化。
- 过程事件：早先两项目 `cargo build` 与 F28035 RAM/JTAG 读回通过；随后并行
  后端构建反复更新 LLVM 静态库，patched rustc 的后续增量重建虽完成编译，
  但指纹检测拒绝将其标记为当前版本。曾发现算术级数函数输出错误，独立样板
  改用已验证的 `u16` 加法；未掩盖该后端缺陷。
- 验证与结果：跨 crate 控制环读回 `23,40,19,20,82,178`、独立项目读回
  `7,13,20`，两者均有先前 `PASS:` 真机标志。指纹保护触发验证通过。
  新增 LLVM 变更监视后的两项目回归尚未运行；不能视为当前后端版本通过。
- 遗留事项：待 LLVM 库不再并行更新，重新增量构建 patched rustc 并对两项目
  重新运行 Cargo＋真机回归。任意 Rust crate、`std`、所有 `core` helper 和
  已发现的算术／寄存器问题仍未解决。

## 2026-10-20 — 定制 rustc 直接对象控制示例上板

- 修改范围：B-1 `tools/run-hw-rustc-direct-object.ps1`、两份直接对象烟雾验证脚本；
  主工程 `docs/PATH_B.md` 与本日志。
- 原因：推进 `rustc --emit=obj` 路线，去掉 Rust 汇编文本转换和 TI 汇编器处理
  Rust 代码这两步，并验证直接对象能否真正进入可运行的 F28035 `.out`。
- 完成内容：新增可重复的 `rustc → C28x ELF .obj → TI 链接 → RAM/JTAG`
  控制示例脚本；检查目标 triple、`ofd2000` 文件格式、`.map` 中的函数和
  RAM 数据地址，并要求 DSS 明确输出 PASS。修复旧烟雾脚本在资料迁移后
  引用已不存在的 B-1 源文件和环境脚本路径；更新目标 DataLayout 检查。
- 过程事件：初次直接调用 patched `rustc` 因缺少 UCRT 环境退出，加载主工程
  `llvm-c28x-env.ps1` 后恢复。`-Copt-level=0` 产出对象但链接时仍有
  `core` helper 与 `__muldi3` 未解析；切到 `-Copt-level=s` 后直接对象
  成功链接。未使用 `-Zub-checks=no` 也能产生与本次优化配置相同的对象。
- 验证与结果：旧 `verify-rustc-c28x-object.ps1`、
  `verify-cargo-c28x-object.ps1` 重新 PASS；新脚本 `-BuildOnly` 通过；
  新脚本完整运行经 DSS/JTAG 在 F28035 RAM 读回
  `23,40,19,20,82,178`，`RUSTC_DIRECT_OBJECT_HW=PASS`。
- 遗留事项：这是受限控制示例的 RAM 验证，尚未覆盖完整 `core` 重编译、
  Safe HAL、通用 ABI/重定位、安全索引和 Flash 启动；仍使用 TI 工具编译
  非 Rust 启动与 C 驱动并链接最终 `.out`。

## 2026-10-20 — GPIO PAC 常用操作接入 Safe HAL 直编路径

- 修改范围：`sdk/f28035-safe-hal/src/pac.rs`、`src/lib.rs`、
  `tools/hw_rust_safe_hal_driver.c`、`tools/dss-read-rust-safe-hal.js`、
  B-1 `tools/run-hw-rustc-direct-safe-hal.ps1`、两份路线文档及本日志。
- 原因：让 GPIO 输入、输出、数据读回和 MUX 在 B-1 直编 `.obj` 时实际
  经 Rust PAC 寄存器操作，并与原 C bridge 的 GPA/GPB 寄存器效果对照。
- 完成内容：PAC 增加独立 `input_sample`、`mux_field`；Safe HAL 在
  `direct-obj-mmio` 下使用 PAC 配置和命令；GPIO 受保护配置写入经
  `eallow_inst`/`edis_inst` 包围，直接对象 MMIO 路径内联常量地址；
  宿主测试覆盖 GPIO0/15/16/31/32/44 边界及非法引脚。
- 过程事件：首次直接对象链接因 `expect` 引入未解析的 `core::result::unwrap_failed`
  而失败，样板改为显式 `Option`/`Result` 分支。早期动态 PAC 地址路径
  虽链接但 GPIO34 输出在板上失败；改为 const PIN 的 PAC 路径并内联
  MMIO 原语后通过。扩展的 MUX 硬件测试发现 Rust 布尔比较
  `mux::<0>() == 1` 产生错误标志，而物理寄存器和原始读回为 1；
  样板返回原始 MUX 值，由 DSS 验证。构建脚本还曾因 PowerShell
  `$Rustc`/`$rustc` 大小写同名误判编译结果，继续验证前已修正。
- 验证与结果：`cargo test -- --test-threads=1` 53/53 单元测试、15/15
  文档测试通过；`cargo check --features bare-mmio` 与
  `cargo check --features embedded-hal` 通过；B-1 直接
  `.obj` 构建/链接通过；RAM/JTAG 返回
  `SAFE_HAL_INPUT=17,0,32,768,7599`、`SAFE_HAL_RESULTS=0,0,0,4,7595,178`，
  `RUSTC_DIRECT_SAFE_HAL_HW=PASS`。未运行 Flash 烧录。
- 遗留事项：比较/分支后端问题未修；本次只上板验证 GPIO0 MUX 和
  GPIO34 输入/输出/读回，不能推广为任意引脚或其他外设；C 驱动、
  汇编启动和 TI 链接仍为可信底座。

## 2026-10-20 — Safe HAL 直编对象上板（B-1）

- 修改范围：`sdk/f28035-safe-hal`（新增 `direct-obj-mmio` 特性）、B-1
  `tools/run-hw-rustc-direct-safe-hal.ps1`、主工程
  `tools/hw_rust_safe_hal_driver.c`、`tools/dss-read-rust-safe-hal.js`、
  `backend/llvm-c28x/test/Rust/mmio-lowering-probe.rs`、`docs/PATH_B.md`
  与本日志。
- 原因：把 B-1 直编路线从受限控制示例推进到完整 Safe HAL，验证 patched
  rustc `--emit=obj` 能否承载真实 crate 并在 F28035 上运行。
- 完成内容：MMIO lowering 探针反汇编实证——冻结 ABI 下 Rust 指针为逻辑
  字节地址，后端字访问前自动折半，字地址寄存器须 `<<1`；Safe HAL 在
  `direct-obj-mmio` 下以 `core::intrinsics::volatile_*` 访问翻倍后的地址，
  并对 `0x7000-0x70FF` 保护寄存器镜像 MIR 后端的 EALLOW/EDIS 包裹；
  新增 C 驱动与 DSS 读回脚本，真机核对 GPBDIR 方向位与 GPBDAT 电平。
- 过程事件：首次上板 GPBDIR bit2 未置位，定位为 EALLOW 保护寄存器写入
  被硬件丢弃（GPBDAT 读到悬空输入电平）；EALLOW 包裹后通过。脚本曾因
  PowerShell 变量名不区分大小写（`$rustc` 结果变量撞上 `$Rustc` 路径参数，
  对象被强转为字符串）而误判失败，已改名修复。PATH A 的 MIR 路线回归
  脚本失败（dump-c28x-mir.ps1 cargo 退出无输出），按用户要求暂不排查。
- 验证与结果：`run-hw-rustc-direct-safe-hal.ps1` 完整运行 DSS/JTAG 读回
  `GPBDIR=4`、`GPBDAT` bit2=0、`RUSTC_DIRECT_SAFE_HAL_HW=PASS`；宿主测试
  15/15 通过；控制示例直编基线复跑仍 `RUSTC_DIRECT_OBJECT_HW=PASS`。
- 遗留事项：完整 `core` 重编译、Flash 启动、通用 ABI/重定位与安全索引
  仍未验证；PATH A MIR 路线 Safe HAL 回归失败原因待查。

## 2026-10-20 — 参数 ABI oracle 补齐、指针池实现与 spill 修复

- 修改范围：`backend/llvm-c28x/C28xISelLowering.cpp`（CC_C28x_Custom 指针池 +
  预扫描）、`C28xInstrInfo.cpp`（storeRegToStackSlot/loadRegFromStackSlot
  不再经物理 ACC COPY）、`C28xRegisterInfo.cpp`（eliminateFrameIndex 的
  LOAD32/STORE32 FI 分支补 staging 与 Dst 路由）、`C28xCallingConv.td`
  （注释）、`test/CodeGen/abi-mixed.ll`（栈用例+FileCheck）、新增
  `test/CodeGen/abi-pointer.ll`、`test/CodeGen/struct-return.ll`（sret=XAR6）、
  `tools/verify-llvm-c28x.ps1`（A/B/指针/sret 断言）、`docs/PATH_B.md` 与本日志。
- 原因：推进三项遗留 ABI 问题——混合类型参数 ABI 未证明、胖指针/聚合返回/
  函数指针未证明、dev profile 链接器错误。
- 完成内容：①用本机 cl2000（CGT 25.11.1）对 120 个 i16/i32/ptr 参数排列做
  oracle 扫描 + 定向用例，确认混合 i16/i32 规则与既有 CC_C28x_Custom 一致
  （该实现早已存在，缺的是证据与回归）；②按 oracle 新增指针池：指针参数→
  XAR4/XAR5→栈，sret→XAR6，i16 跳过被指针预占的槽；间接调用确认
  `LCR *XARn` + 逻辑字节→字地址转换，L1-3 “未定” 关闭；③补齐
  abi-mixed/abi-pointer/struct-return 三项 FileCheck 与脚本回归。
- 过程事件：指针参数分配暴露 spill 路径缺陷——mem-builtins.ll
  `-verify-machineinstrs` 崩溃（14 项 machine code error）。根因：
  storeRegToStackSlot 在 InlineSpiller 阶段插入 `COPY $acc, vreg`，
  而 LiveIntervals 已结束物理 liverange 计算，$acc 无 live segment；
  连带发现 eliminateFrameIndex 的 LOAD32 FI 分支 load 到 AL/AH 后未
  路由回 Dst（旧代码依赖 loadRegFromStackSlot 的 ACC 中转兜底）。
  两处一并修复后通过。
- 验证与结果：`verify-llvm-c28x.ps1` 全绿（11 个字节 oracle、负向门禁、
  全部 asm 断言），`llc -verify-machineinstrs` 下 abi-mixed/abi-pointer/
  struct-return FileCheck 均 PASS；spill 修复后 mem-builtins.ll 退出 0。
  dev profile 复测：最小 `LCR` 用例与带 3 条 `R_C28X_ABS22_BR` 重定位 +
  全局变量的 core-ops.ll，`-O0` 与默认优化两级 obj 均可被 cl2000 完整
  链接生成 `.out`（exit 0），旧记录中的链接错误不复现；B-1 patched-rustc
  直编场景因 stage1 rustc 不在位未复测。**未运行任何硬件（JTAG）验证。**
- 遗留事项：①多 i16 + i32 + 指针且 i16 相邻时（如 `(i16,i16,i32,ptr)`）
  cl2000 把最后一个 16 位槽给靠后的 i16，本后端给靠前的，形状不一致，
  已记录未修；②Rust `&[T]` IR 层拆为 (ptr→XAR4, usize→ACC)，与 TI C
  8 字节结构体整体引用传入不同，跨语言胖指针需显式转换；③dev profile
  复测仅覆盖 B-2 llc obj 路径；④指针参数的硬件（JTAG）行为未验证。

## 2026-10-20 — a-1 章节迁出为独立文档

- 修改范围：`docs/PATH_A.md`、新增 `docs/F28035_RUST_DEV_GUIDE.md`、`WORK_LOG.md`。
- 原因：开发约定与 AI 接手指指南和路线文档混排在 PATH_A.md 内，阅读和维护时
  互相干扰。按维护规则路线总文档仍保持 PATH_A/PATH_B 两份，本次是整节迁出，
  不是拆出重复的专题路线文档。
- 完成内容：a-1 章节全文（含原文出处与 SHA-256）迁至
  `docs/F28035_RUST_DEV_GUIDE.md`，正文未改动；PATH_A.md 目录移除第 1 项并
  重新编号为 1–9；文档开头增加迁出指引；维护记录增加一行。
- 过程事件：核对 `#a-1` 锚点仅被 PATH_A.md 自身目录引用，无外部文档链接
  指向 a-1，迁出不产生断链；锚点 `a-2`..`a-10` 编号保持不变，README 等处
  对 `#a-7`/`#a-9` 的引用不受影响。
- 验证与结果：迁移后 PATH_A.md 的目录链接、章节锚点与各节标题一致；新文档
  与原章节逐节比对一致。未运行任何构建、烧录或硬件测试。
- 遗留事项：新指南正文中引用的 `SAFETY.md`、`ABI_FREEZE.md`、
  `C28X_RUST_ABI.md`、`migration_ledger.md` 等旧文件名对应的内容已并入
  PATH_A/PATH_B，链接修正留待后续单独处理。

## 2026-10-20 — 完整 core 重编译、RAM 尺寸修正与 core 广度测试

- 修改范围：`backend/llvm-c28x/test/Rust/b2-hw-core-ex.rs`（新增）、
  `backend/llvm-c28x/test/Rust/i8-frame-store.ll`（新增）、
  `crates/c28x-di64-helpers`（新增）、`tools/F28035_ram.cmd`、
  `tools/hw_rust_core_ex_driver_{a,b,c,d}.c`（新增）、
  `tools/dss-read-rust-core-ex-{a,b,c,d}.js`（新增）、
  `tools/dss-diag-core-ex.js`（新增）、
  `f28035-rust-bridge-b1/tools/rebuild-core-sysroot.ps1`（新增）、
  `f28035-rust-bridge-b1/tools/run-hw-rustc-direct-core-ex.ps1`（新增）、
  `build/c28x-sysroot` 的 `libcore.rlib`/`libcompiler_builtins.rlib`
  （备份后替换）、`docs/PATH_B.md` 与本日志。
- 原因：推进 B-1 路线遗留的“完整 `core` 重编译”和“通用 ABI/重定位、
  安全索引”验证，按用户要求不再处理 PATH A 的 MIR 回归、不涉及烧录。
- 完成内容：当前后端对完整 `core` 的 `--emit=metadata,obj` 编译成功，
  2026-09-30 记录的 i8 栈帧 lane 卡点已消除（最小 IR 复现改为
  `movb *+xar7[ar0],al` 字节 lane 写入）；新增可重复的 sysroot 重建脚本
  （双 emit + llvm-ar 打包，旧 rlib 备份）；新增 `c28x-di64-helpers`
  （`__muldi3`/`__udivdi3`/`__umoddi3`/`__moddi3`，16 位 limb 实现，
  主机边界断言通过）；把 `F28035_ram.cmd` 的 `RAML0L1` 长度从 0x3000
  修正为 0x2000（F28035 实际程序 RAM 8K 字节=4096 字，GEL 内存表为准）；
  建立分组的 core 广度测试（12 入口 + 4 组驱动/DSS/运行脚本，宿主
  `rustc --test` 12/12）。
- 过程事件：`--emit=link` 仍因 C28x 无 asm parser（rlib 元数据段内联汇编）
  失败，沿用双 emit 打包；链接 `core` 对象需显式列入（共享泛型实例未全部
  内联），且需要 di64 辅助对象；关闭 `--unused_section_elimination` 后
  `core` 的 `.rodata` 达 0x8d51 字节远超 RAM，故消隐必须开启。真机上
  Group A 入口命中正确（PC=0x93AE），`core_ex_option` 返回 138（期望 140）、
  `core_ex_pattern` panic 停在 `rust_begin_unwind`（`B 0,UNC`）。
  定位到测试对象 `.rodata` 只被放置 0x128/0x250 字节，被丢弃尾部中的
  `Some(1u16)` 常量重定位解析为 0x8244（落在 `__muldi3` 代码区）。
- 验证与结果：新 sysroot 下控制示例 `23,40,19,20,82,178`
  （`RUSTC_DIRECT_OBJECT_HW=PASS`）、Safe HAL `0,0,0,4,7595,178`
  （`RUSTC_DIRECT_SAFE_HAL_HW=PASS`）均在新 RAM 尺寸下回归通过；宿主
  core 广度测试 12/12、di64 辅助边界断言通过；Group A 真机读回
  `138,54,65,245,212,0,0`（后四项为编译期常量折叠，不构成代码生成证据）。
- 遗留事项：修复后端的三类缺陷——`.rodata` 局部放置（消隐与 MOVL 立即数
  重定位的引用跟踪）、`rust_begin_unwind` 的坏分支、以及布尔比较
  （与并发记录的 `mux::<0>() == 1` 问题可能同源）；测试入口应带 C 传入
  参数以避免常量折叠；Group B/C/D 上板、Flash 启动仍未验证。

## 2026-10-20 — B-1 直编对象和 core sysroot 增量构建

- 修改范围：B-1 新增 `tools/incremental-build.ps1`；修改三个
  `run-hw-rustc-direct-*.ps1` 和 `rebuild-core-sysroot.ps1`；同步本文与
  `docs/PATH_B.md`。
- 原因：普通 Rust/PAC、C 驱动、启动或 `.cmd` 改动不应每次重编所有对象，
  更不能无意触发 LLVM 或定制 rustc 的全量构建。
- 完成内容：每个编译/链接步骤独立记录输入、参数和输出签名；无变化时跳过，
  输入或产物变化时只重做对应步骤；core/builtins 分别缓存，目标 rlib 相同
  时跳过安装与备份。增加显式 `-ForceRebuild`，保留 `-BuildOnly`；修正三
  个直编脚本的符号 RAM 上界检查为 `0xA000`。
- 过程事件：首次真实 `safe-hal -BuildOnly` 到 Rust 对象步骤时，默认
  stage1 `rustc.exe` 被 Windows 拒绝启动（“不是有效的应用程序”）；没有
  因此启动 LLVM、rustc 或 core 全量重建。
- 验证与结果：五个 PowerShell 脚本解析通过；缓存自检依次得到 BUILD、
  SKIP、输入变化 BUILD、输出改写 BUILD。以现有 `safe_hal.obj` 等对象
  运行 TI 编译和链接，各两次得到 BUILD 后 SKIP；新 `.out` 为 12100
  字节。新的 Rust 编译和 JTAG 本次未运行完成，不能把缓存自检记为
  上板回归通过。
- 遗留事项：stage1 `rustc.exe` 恢复可运行后，重新执行三条直编链路的
  `-BuildOnly` 两次，核对第二次所有构建步骤均 SKIP；再对实际源码和
  `.cmd` 分别改动验证局部失效，并运行硬件回归。

## 2026-10-20 — stage1 rustc 恢复可运行的复核

- 修改范围：`docs/PATH_B.md` 与本日志；未修改或重建 LLVM、rustc、core。
- 原因：上一轮 `rustc.exe` 无法启动，需要区分可执行文件恢复、目标支持、
  实际对象生成与最新 LLVM 同步状态。
- 过程事件：stage1 目录现有 `rustc.exe`（44,780 字节）和
  `rustc_driver-c120f36b8f1c923d.dll`（219,154,432 字节）时间戳为
  15:28，另保留 `.new-broken` 的 581,671,799 字节 DLL 和对应 exe。
  本轮没有执行恢复复制，不能将这次文件替换归因于本轮操作。
- 验证与结果：`rustc --version --verbose` 成功，目标列表包含
  `c28x-none-elf`；`run-hw-rustc-direct-safe-hal.ps1 -BuildOnly` 首次完成
  Rust `.obj`、TI C/汇编对象和 RAM `.out` 链接，二次所有步骤 SKIP。
  可运行 exe/DLL 已成对备份到
  `D:\c28x-toolchain\rust-build-gcc14fix\stage1-known-good-20261020`，
  SHA-256 逐文件一致，备份目录中的 `rustc --version` 通过。
  当前 LLVM 库指纹与 rustc 上次成功构建指纹不同。本轮未运行 JTAG。
- 遗留事项：若要使用最新 LLVM 修改，需在保留可运行 stage1 备份后
  有范围地增量重链 `compiler/rustc`，再复核直编对象与硬件行为。

## 2026-10-20 — 保留备份并增量重链 stage1 rustc

- 修改范围：stage1 `rustc.exe`/`rustc_driver` 构建产物、LLVM 指纹状态文件、
  B-1 Safe HAL 对象及 RAM `.out`、`docs/PATH_B.md` 和本日志；未清理构建目录，
  未触发 LLVM 全量构建或 `core` 重编译。
- 原因：先前可运行的 stage1 编译器所记录的 LLVM 指纹落后于当前后端库，
  需要在保留备份的前提下增量重链。
- 过程事件：先核对 `stage1-known-good-20261020` 与现有 exe/DLL 哈希一致。
  第一次 `build-rustc-c28x.ps1 -Jobs 2` 编译完成，但运行期间
  `libLLVMC28xCodeGen.a` 内容变化，指纹门禁拒绝记录成功；将新 exe/DLL
  移到 `stage1-failed-relink-20261020-1550`，从备份恢复原配对并验证可运行。
  第一次新编译器在缺少 LLVM MinGW `libc++.dll` 的普通 shell 中返回
  `0xC0000135`，加载 `llvm-c28x-env.ps1` 后可以启动。LLVM 指纹稳定后，
  相同命令第二次在约 1 分 16 秒内完成增量重链。
- 验证与结果：新 stage1 `rustc --version --verbose` 可运行，目标列表含
  `c28x-none-elf`；记录与当前 LLVM 指纹同为
  `E6B5ACB522872F57DC76EDEC360159C6F3A5343E927C57B2D85EB1FA5700732E`。
  `run-hw-rustc-direct-safe-hal.ps1 -BuildOnly` 首次重编 Rust `.obj` 并由 TI
  链接成 RAM `.out`，第二次所有编译、链接步骤 SKIP。备份仍保留在
  `D:\c28x-toolchain\rust-build-gcc14fix\stage1-known-good-20261020`。
- 遗留事项：本轮未运行 JTAG 真机验证；`core` rlib 未随此次重链重编译。

## 2026-10-20 — 新 stage1 rustc 产物的 F28035 上板验证

- 修改范围：`docs/PATH_B.md` 和本日志；未修改源码、工具链或固件产物。
- 原因：确认增量重链后的 `rustc` 所生成的 Rust Safe HAL 对象不止能通过
  TI 链接，也能在 F28035 RAM 中执行并得到预期读回。
- 过程事件：执行 B-1 `run-hw-rustc-direct-safe-hal.ps1`；Rust 对象、三个
  TI 对象和 TI 链接全部命中缓存，DSS/JTAG 将上一轮生成的 `.out` 下载到板上。
- 验证与结果：`SAFE_HAL_RESULTS=0,0,0,4,7595,178`，
  `SAFE_HAL_INPUT=17,0,32,768,7631`，脚本报告 GPIO0 MUX 与 GPIO34
  输入/输出 `RUSTC_DIRECT_SAFE_HAL_HW=PASS`。
- 遗留事项：本次验证范围为 Safe HAL GPIO 样板的 RAM 运行；未验证 Flash
  启动、其他 Safe HAL API 或重新编译完整 `core`。

## 2026-10-20 — 新 rustc 后端缺口复核

- 修改范围：`docs/PATH_B.md` 和本日志；未改 LLVM/rustc 源码或触发工具链
  重建。B-1 Group A/E 的测试对象与 RAM `.out` 因输入变化按增量缓存重建。
- 原因：核对新 stage1 `rustc` 除 GPIO 样板外，对通用 `core`、`Option`
  和标准 rlib 流程的现有支持范围。
- 过程事件：Group A 直编与 TI 链接通过，JTAG 等待 `hw_done` 超时；
  `dss-diag-core-ex.js` 抓到 `PC=0x9432`（`rust_begin_unwind` 自循环），
  结果 `138,54,65,245,212,178,17`，`core_ex_option` 预期 140。
  当前对象反汇编的常量地址已是 `0x8122`。Group E 运行到结果读回，
  基础比较正确，但 `some_of(1)=0`、`none_of(1)=1`，与预期相反；
  `unwrap_or` 两分支正确。现有 `core-dual.o`/`libcore.rlib` 时间戳
  14:17，早于新 rustc 的 15:52，不能把这些失败全归因于最新后端。
- 验证与结果：Safe HAL GPIO 上板 PASS 保持；Group A/E 硬件 FAIL 如上。
  新 rustc 对最小 crate 的 `--emit=link --crate-type=rlib` 仍因缺少
  C28x asm parser 失败。`verify-llvm-c28x.ps1` 仅 `mem-access.ll` 的两处
  预期字节 `0x0004` 对现值 `0x0002` 不匹配，其余用例通过。
- 遗留事项：先以新 rustc 增量重编 core 后重复 A/E；定位 Option 判别值
  与 UB 检查参数传递；修复非正栈偏移钳制、未解析分支填零等静默错码风险；
  补 asm parser/rlib 与必要重定位，核对 mem-access oracle。

## 2026-10-20 — addend 字节/字缺陷修复、三项疑点定性、rustc 重链阻塞

- 修改范围：`backend/llvm-c28x/MCTargetDesc/C28xAsmBackend.cpp`（addend
  修复）、`backend/llvm-c28x/test/Rust/bool-cmp-probe.rs`（新增）、
  `backend/llvm-c28x/test/Rust/b2-hw-core-ex.rs`（新增 Group E 入口与
  硬件状态说明）、`tools/hw_rust_core_ex_driver_e.c`、
  `tools/dss-read-rust-core-ex-e.js`（新增）、
  `f28035-rust-bridge-b1/tools/run-hw-rustc-direct-core-ex.ps1`
  （新增 `-Group E`、`-WithUbChecks`）、`docs/PATH_B.md` 与本日志。
- 原因：修正上一轮 core 广度测试暴露的三项问题。
- 完成内容：`FK_C28x_ABS22` 的 22 位字段改为 `Value >> 1`（MC 的字节偏移
  → TI 链接器按字消费的 addend），与 `FK_C28x_BRANCH` 的 `(Value+2)/2`
  同一约定；核对 map 后发现上一轮“`.rodata` 只放置 0x128/0x250”是
  **单位误读**（map 输入段长度是字，0x128 字 = 0x250 字节，实际完整放置），
  真正的错误是 `MOVL XAR0,#0x8244` 应为 `#0x8122`；确认
  `rust_begin_unwind` 的 `B 0,UNC` 是 `bb1: br bb1` 的自跳（panic handler
  `loop{}` 内联），不是坏分支；定位 `core_ex_pattern` panic 的真实链路为
  `Iter::next` → `ptr.add` 的 `precondition_check` → `runtime_add_nowrap`
  （调用方按字节存实参、被调用方按 16 位读回，高字节为垃圾）→
  `panic_nounwind_fmt` → `rust_begin_unwind`；用 `bool-cmp-probe.rs` 反汇编
  确认 `==`/`<`/字节 lane/立即数比较/`!bool`/`Option` 标签的代码生成正确。
- 过程事件：`llc` 重建成功，但直编路线用的 rustc 是静态链接后端，必须重链。
  执行 `rebuild-rustc.bat` 后 `rustc-main.exe` 被链接成 44,780 字节非法 PE：
  节表首项为 GCC 14.2 运行库的 `.debug` 段（长名 `/4`），VA 停在哨兵值
  `0xffc00000`（驱动 DLL `0xf0000000`），`ERROR_BAD_EXE_FORMAT`(193)。
  在 `config.toml` 加 `rustflags`、把 linker 换成带 `-Wl,--strip-debug` 的
  包装脚本均未生效；`strip --strip-debug` 能修好节表，但驱动的 DllMain
  仍失败（1114）。随后从 `D:\c28x-toolchain\build-temp\runtest\`
  （10-13 的可用组合，驱动 DLL 219MB 已 strip）恢复
  `host/stage1/bin/{rustc.exe,rustc_driver-*.dll}`，`rustc -vV` 与直编
  控制示例恢复正常；`config.toml` 已回滚。
- 验证与结果：恢复后的 rustc 跑控制示例真机
  `RUST_CONTROL_RESULTS=23,40,19,20,82,178`、`RUSTC_DIRECT_OBJECT_HW=PASS`；
  根目录后台还跑通了 `cargo test`。addend 修复已在源码与 `llc` 中，
  但**尚未进入 rustc**，因此 Group A（option 期望 140）与 Group E
  的真机验证仍需等 rustc 重链问题解决。
- 遗留事项：修复 rustc 重链产生的非法 PE（建议换与 GCC 14.2 运行库匹配的
  链接器，或在 bootstrap 层加 `--strip-debug`），再重建后端→core→
  Group A/E 完成 addend 与布尔比较的端到端验证；`runtime_add_nowrap` 的
  8/16 位实参传递缺陷仍待修。

## 2026-10-20 — 负向测试门禁、文档修复与 ABI 上板样板

- 修改范围：`sdk/f28035-safe-hal/src/lib.rs`（新增 InputPin 输出方法
  compile_fail 与 peripherals 单例单测）、`docs/F28035_RUST_DEV_GUIDE.md`
  与 `docs/PATH_A.md`（旧文件名引用改指 PATH_A/PATH_B 对应章节）、新增
  `backend/llvm-c28x/test/Rust/b2-hw-abi.rs`、`tools/hw_abi_driver.c`、
  `tools/dss-read-abi.js`、`tools/run-hw-abi.ps1`、
  `backend/llvm-c28x/C28xInstrInfo.cpp`（AccLiveThrough 补向后 kill 检查；
  LOAD16_ZEST32_PSEUDO 的 PUSH_ACC 加门）、`docs/PATH_B.md` 与本日志。
- 原因：补齐三项 ABI 遗留之外的缺口——负向测试门禁、失效文档引用、
  ABI 改动的硬件（JTAG）验证。
- 完成内容：①负向门禁：本地无 trybuild（registry 无缓存、离线），按项目
  既有 doc-test 机制补两个缺失样例（输入脚调 `set_low`、第二次
  `Peripherals::take` 返回 None）；②文档失效引用清零；③建立 ABI 上板样板
  四件套（Rust 样板 + C 驱动 + DSS 读回 + 构建脚本），入口断点读
  AR4/AR5/ACC 验证寄存器分配，结果区校验计算值。
- 过程事件：上板样板连抓三个真问题——(a) C 驱动把 Rust 指针参数声明成
  `unsigned long`（TI 按整数传 ACC，Rust 期望 XAR4），必须声明为 C 指针
  类型并乘 2 传逻辑字节地址；函数指针同理（首跑 CPU 跳飞 boot ROM
  0x3FFF79 即因 C 传字地址、Rust 减半后跳到 0x4058）；(b) `.hw_result`
  与栈相邻，结果先写后被 Rust 调用的栈帧冲掉，须“先算后存”；(c) DSS 脚本
  首个 `run()` 前必须已有断点，否则 CPU 跑飞。(d) llc 的
  `LOAD16_ZEST32_PSEUDO` 展开无条件 `PUSH_ACC`，入口 ACC 参数被
  `movl xt, acc` kill 后读未定义物理寄存器，verifier 崩；AccLiveThrough
  补向后 kill 检查修复。
- 验证与结果：`cargo test -- --test-threads=1` 54 单元 + 16 doc-test
  全绿；`run-hw-abi.ps1` 在 XDS100v2/F28035 上完整跑通（PC==hw_done）：
  **指针参数=XAR4 读回 0x1234 正确、间接调用 ti_double(21)=42 正确、
  混合 (i16,ptr,i32) 入口寄存器 a=AR5/b=ACC/p=XAR4 探针全对**。
  **两个新后端缺陷（测试按预期 FAIL，未绿灯）**：`rust_mixed` 上板返回
  15≠10（ADD32 链操作数错选，与已知算术缺陷同类）；`rust_sret_self_check`
  返回 0x11F5FC≠0x3333（sret Rust→Rust 结构内容错）。跨语言结构体返回
  （TI C 侧字地址 sret 指针 vs Rust callee 减半）确认不兼容，样板已改
  Rust→Rust 内部调用规避。`verify-llvm-c28x.ps1`：除 mem-access.ll 两个
  立即数字节（`008d0400`→`008d0200`，val32 的 MOVL 高位）外全绿；该差异
  出现在后端源码被并发修改（AsmBackend/MCInstLower/InstrFormats 等重定位
  编码区，本时段有他人的 addend 修复入库）之后，与本会话两项改动的因果
  关系已二分排除本会话改动，疑与并发修改有关，待源码树稳定后重新比对。
- 遗留事项：①ADD32 操作数错选（上板实证 15≠10）与 sret Rust→Rust
  结构内容错（0x11F5FC≠0x3333）待修，修好后 `run-hw-abi.ps1` 应全绿；
  ②mem-access oracle 差异待并发修改稳定后重新核对；③跨语言 sret/胖指针
  互操作需要显式适配器（地址空间约定不同）。

## 2026-10-20 — PATH B 文档一致性收敛（仅文档，不涉及 PATH A）

- 修改范围：`docs/PATH_B.md`、`README.md` 的 PATH B 两行状态与目录树注释、
  本日志。**未修改任何 PATH A/MIR 相关内容**，也未运行构建、烧录或硬件测试。
- 原因：通读路线文档后发现 PATH B 内部存在相互矛盾的结论和失效引用，
  继续叠加新记录会让读者按错误信息实现（尤其 sret 寄存器与混合 ABI 两条）。
- 完成内容：①文首新增「当前状态速览」，用三张表分别给出已有上板证据、
  已知未修缺陷、尚未覆盖范围，避免读者通读 3000 行才能判断现状；②修正
  b-4 的 `sret` 寄存器 `ACC`→`XAR6` 并加更正说明（依据 cl2000 oracle 与
  `struct-return.ll` 的 `CHECK: movl acc, xar6`）；③b-6「Known Limitation」与
  b-9「已知限制」的混合类型 ABI 重叠结论标注为已过时，指向
  `abi-mixed.ll` 与第 10 节；④b-9「上板状态：硬件未连接」更新为已通过并
  指向现行 B-1 直编入口；⑤第 8 节「不支持范围」按现状改写（函数调用/栈帧、
  `FK_C28x_ABS22` addend 已可用，`R_C28x_*` 仍 fail-closed）；⑥新增
  `b-1-10`、`b-1-12` 两个锚点，替换误指文首的 `#b-1`（原「第 10 节」
  「第 12 节」共 4 处）；⑦正文中 `ABI_FREEZE.md`/`C28X_RUST_ABI.md`/
  `B2_USER_GUIDE.md` 改指 `#b-3`/`#b-4`/`#b-1`，`C28X_MEMORY_MODEL.md`
  补全相对路径；⑧b-6/b-9 标注与 b-10/b-14 的重复关系，明确后续只改一处；
  ⑨b-8 标注 rustc 构建脚本实际位于 `f28035-rust-bridge-b1/tools/`；
  ⑩README 中 LLVM 后端规模由 43 改为 146 文件、补丁路径改指 B-1 目录。
- 过程事件：`C28X_MEMORY_MODEL.md`、`tools/oracle/cases.json`、
  `tools/llvm-c28x-env.ps1` 均存在，仅路径写法有误；`archive/ONE_FILE_MAIN.md`
  与 `archive/OWNERSHIP_ONCE_RAM.md` 在仓库中不存在，但二者属 PATH A/MIR
  内容，按本轮范围未改动，留待 PATH A 文档统一处理。
- 验证与结果：修改后 `PATH_B.md` 共 3009 行、CRLF 与首行编码未变；锚点
  `b-1-10`/`b-1-12` 与全部 `#b-*` 目录链接一一对应；正文已无指向
  `ABI_FREEZE.md`/`C28X_RUST_ABI.md`/`B2_USER_GUIDE.md` 的失效引用
  （`> 原文：` 溯源行按设计保留）。未运行构建与硬件验证。
- 遗留事项：①`SETUP.md` 第三步把 B-1 的 rustc 构建标为「PATH A 核心」，
  并引用主仓库不存在的 `prepare-rustc-c28x.ps1`/`build-rustc-c28x.ps1`，
  因涉及 PATH A 命名拆分，本轮未改；②`PATH_B.md` b-6 与 b-9、b-9 与
  b-10/b-14 仍有约 300 行重复内容，只加了关系标注，未做合并；
  ③PATH A 侧统计数字（140/141/146、29/54/63）与实际 `case.toml` 不一致，
  本轮按范围要求未处理。

## 2026-10-20 — PATH A 文档独立成目录，与 PATH B 解耦

- 修改范围：新建 `docs/path-a/`，迁入 `docs/PATH_A.md` 与
  `docs/F28035_RUST_DEV_GUIDE.md`；修改 `README.md`、`AGENTS.md`、`SETUP.md`、
  `docs/PATH_B.md` 与本日志的入口/交叉引用。**未修改任何代码、脚本、配置或
  固件产物**，未运行构建与硬件测试。
- 原因：PATH A 与 PATH B 的文档长期互相引用、互相复制状态，改一边就要同步
  另一边，且两处数字容易分叉。按用户要求把 PATH A 收进独立目录并切断与
  PATH B 的引用关系。
- 完成内容：①`docs/path-a/` 容纳两份 PATH A 文档，`docs/` 下只留
  `PATH_B.md` 与 `path-a/`；②PATH A 文档内删除 3 处指向 B 路线文档的链接
  （开头导语、优化清单说明、Zero-C 实验记录），指南中「B-2 当前状态」小节
  改为一段范围声明，不再复制编译器侧结论；③按新层级把 `../AGENTS.md`、
  `../WORK_LOG.md`、`../README.md` 改为 `../../`；④指南中「第 2/4/5 节」的
  章节号按 a-1 迁出后的实际编号改为「第 1/3/4 节」；⑤PATH B 侧删掉指向
  `PATH_A.md` 的链接，改为范围声明，并把「PIE/SYS_CLK 全是 scaffold」改为
  「尚未迁移」；⑥README（4 处）、SETUP（2 处）、WORK_LOG 头部导航、
  AGENTS.md 维护规则同步指向新路径，并在 AGENTS.md 写入「两套文档互不引用」
  的规则；⑦PATH_A 维护记录加一行。
- 过程事件：两份文档在 git 中均为未跟踪文件（`??`），`git mv` 报
  "not under version control"，改用普通移动，因此本次不产生重命名历史；
  移动前确认没有脚本（`.ps1`/`.js`/`.py`/`.toml`）引用这两个文档，只有
  markdown 链接需要改。
- 验证与结果：`docs/path-a/` 内 `grep PATH_B` 无任何命中；两份文档的相对
  链接全部为 `../../` 且目标存在；README/SETUP/AGENTS/WORK_LOG 中
  `docs/PATH_A.md` 已无残留（历史日志条目里的旧路径按规则保留不改）。
  未运行构建与硬件验证。
- 遗留事项：①`docs/path-a/` 内两份文档的统计数字仍是旧的（140/141/146、
  29/54/63），与真实 `case.toml` 不一致，未在本次范围内修；②`PATH_A.md`
  正文仍有历史遗留的 `archive/ONE_FILE_MAIN.md` 等失效文件名引用，属
  PATH A 自身清理，待单独处理；  ③若后续希望 PATH A 也搬走代码
  （`backend/c28x-mir`、`crates/rust-api` 等），需另做一次带路径重写的大改。

## 2026-10-20 — PATH B 文档事实核对（第二轮）

- 修改范围：`docs/PATH_B.md`（b-2、b-3、b-9、b-11、b-12）与本日志。
  **未修改代码、脚本、配置**，未运行构建与硬件测试。
- 原因：用户要求复查 PATH B。除文字一致性外，本轮把文档里的关键断言与仓库
  实际代码/脚本逐条比对，确认哪些结论已经落后于实现。
- 完成内容：①b-11 的 DataLayout 补回漏掉的 `i1:8:8`，与 b-3 权威字符串、
  `tools/check-abi-freeze.ps1` 的 `$canonicalLayout`、`C28xTargetMachine.cpp`
  三处对齐，并说明该字段是 core 编译期 `{i32,i1}` spill 的前提；②b-3
  「已冻结位置清单」把 `C28xRegisterInfo.cpp` 的 `getPointerRegClass` 由
  「暂留 GR16」更正为已返回 `GR32RegClass`（实测源码第 59–61 行），状态改
  「已改」，字节 lane 部分指向 `test/Rust/i8-frame-store.ll`；③b-9 缺口 5
  「必须 `--release`」标注为当前版本不复现，并指回 b-10 遗留问题第 1 条；
  ④b-12「All of core's data structures (Vec, Option, Result, HashMap)」更正为
  `Option`/`Result`/切片/迭代器/`cmp`/`mem`，并明确 `Vec`/`HashMap` 属
  `alloc`/`std`、本目标不支持；⑤b-2 两处指向 `archive/ONE_FILE_MAIN.md`、
  `archive/OWNERSHIP_ONCE_RAM.md` 的死链改为文字说明（这两个文件在仓库中
  不存在）。
- 过程事件：用脚本抽取文档中 159 个文件类 token 逐一比对，排除「原文：」
  溯源行、glob 写法与 Rust/LLVM 源码树内的外部路径后，正文真正的死链只有
  上述两条；b-2 的 `c28x-rt/asm.s` 等是省略 `crates/` 前缀的简写。
- 验证与结果：PATH B 引用的 20 个主仓库 `tools/` 脚本、13 个 B-1 脚本、
  8 个关键测试文件（`abi-mixed.ll`、`abi-pointer.ll`、`struct-return.ll`、
  `branch-multi.ll`、`mem-builtins.ll`、`i8-frame-store.ll`、
  `bool-cmp-probe.rs`、`b2-hw-abi.rs`）**全部存在**；文内 16 个锚点无悬空。
  未运行构建与硬件验证。
- 遗留事项：①b-2「Architecture」共约 240 行，其中 688–866 行（Track 1
  应用路径 + PATH 2A MIR）属 PATH A 内容，与刚完成的解耦不一致，是否迁出
  待定；②b-6 与 b-9、b-9 与 b-10/b-14 约 300 行重复仍未合并；
  ③b-1 §12.6「PIE 表是全零」「只有一个中断入口」等缺口未逐条复核。

## 2026-10-20 — 文档整理：架构段归位与重复章节合并

- 修改范围：`docs/PATH_B.md`、`docs/path-a/PATH_A.md` 与本日志。
  **未修改代码、脚本、配置**，未运行构建与硬件测试。
- 原因：上一轮把 PATH A 文档拆成独立目录后，`PATH_B.md` 的 Architecture 章节里
  仍有一大段讲应用路径与 MIR 后端；同时 b-9 的六个缺口正文与 b-6/b-10/b-14
  重复。两条都属于「同一事实写两遍」，需要收敛。
- 完成内容：①把 b-2 中的 Track 1（应用路径）、PATH 2A（PAC 层、MIR 分类器、
  五种 MMIO lowering、XAR 间接寻址、EALLOW 自动包裹）以及整段 MIR 硬件验证
  迁入 `PATH_A.md`，成为第 10 节（锚点 `a-11`），并在该节保留原文与出处
  SHA-256；②b-2 只留两轨概览、B-2 流水线图与 B-2 状态，并注明 2A 的实现细节
  属应用侧文档；b-2 的 Hardware Verification 段改写为 B-2 验证入口指引；
  ③b-9 六个缺口的正文改为一张「缺口 → 现行章节」索引表（Gap1–3→b-6、
  Gap4→b-14、Gap5–6→b-10），保留唯一的「修改文件清单」，把「待办事项」
  改为带现状标注的表格（1、2 已完成，3、4 未做，5 已规避）；④目录第 2 项
  改为「Architecture（仅编译器路线）」，第 9 项改为「六个缺口的历史汇总（索引）」，
  PATH_A 目录增补第 10 项。
- 过程事件：两份文档换行符不一致（`PATH_B.md` 为 LF、`PATH_A.md` 为 CRLF），
  首版脚本按 CRLF 匹配导致断言失败；改为按文件探测换行符并做转换后重跑，
  未产生半成品写入。改动前两份文件已备份到 `/tmp`。
- 验证与结果：`PATH_B.md` 3044 → 2626 行，`PATH_A.md` 949 → 1134 行；
  两文件锚点分别为 16 / 10 个，**无悬空锚点**；`docs/path-a/` 内 `#b-*`
  锚点与 `PATH_B` 字样均为 0；三份文档的 markdown 链接**断链 0**。
  未运行构建与硬件验证。
- 遗留事项：①`PATH_B.md` b-6 与 b-10/b-14 之间仍有 Gap4–6 的重复叙述（本轮只
  合并了 b-9 这一层）；②b-3 的 L1-2 编码表与 b-6/b-9 的实现说明仍分散在三处，
  可考虑合并为单一编码表；③b-1 手册里夹着 2026-10-20 的 oracle 更新段，
  结构上更像日志，后续可考虑移到「当前状态速览」下方。

## 2026-10-20 — B-1 设为项目主路径

- 修改范围：主仓库 `README.md`、`SETUP.md`、`docs/PATH_B.md`、
  `docs/path-a/PATH_A.md`、`docs/path-a/F28035_RUST_DEV_GUIDE.md`，
  以及同级 `f28035-rust-bridge-b1/README.md`。
- 原因：按用户要求，将 B-1 定制 rustc 明确为新 Rust 应用、Cargo 接入与
  编译器能力完善的主路径；B-2 独立 llc 保留为共享后端开发、定位和回归路线。
- 完成内容：新增 `b1-main` 操作入口，区分 Cargo 汇编分支与脚本直接对象分支；
  写明增量构建、后端重链、sysroot 更新和硬件验证顺序；修正 README/SETUP
  与路线正文中仍将 B-2 称为主线、将 B-1 当前环境称为历史归档的说明。
  PATH A 文档通过 README 选择默认路线，不新增跨路线文档链接。
- 过程事件：工作区文档已迁到 `docs/path-a/`，按现行 AGENTS 读取和更新；
  发现新 stage1 重链、LLVM 指纹一致和 Safe HAL 真机 PASS 已有后续记录，
  因此同步修正状态速览的旧 PE 阻塞描述，并保留旧 core 对象与 Group A/E
  异常的验证边界。未改动既有历史日志或用例 manifest。
- 验证与结果：检查本次相关导航链接 10 个全部可解析，`b1-main` 锚点唯一；
  四份编译器入口文档中旧的“B-2 当前主线 / B-1 仅历史归档”定位搜索为 0。
  本次只调整文档，未运行编译、单元测试、烧录或硬件验证。
- 遗留事项：路线选择不等于新功能通过；core 广度测试、参数传递、ADD32、
  聚合返回、通用 Cargo 直接对象接入及 Flash 等范围继续按实际证据推进。

## 2026-10-20 — B-1 主路径问题审查与优化清单

- 修改范围：`docs/PATH_B.md`、同级 `f28035-rust-bridge-b1/README.md` 与本日志。
  未修改源码、构建脚本、Cargo 配置、链接脚本、固件或用例 manifest。
- 原因：按用户要求，查找当前主路径的问题与优化点，形成可按证据推进的文档。
- 完成内容：新增 `b1-audit`，记录 14 个有具体源码依据的问题/风险（A01–A14）、
  6 类既有后端/能力缺口及 9 项验证与效率优化；逐项标注优先级、证据等级、
  影响、建议和验收。重点包括 Rust 子模块漏入缓存、core rlib/对象来源不一致、
  启动空段写入、Cargo 临时对象并发冲突、构建指纹未绑定实际编译器、UTF-8
  参数读取、wrapper 路径覆盖、UB 检查配置、对齐/外部符号、Cargo 产物选择等。
- 过程事件：读取本机 GEL，发现以前“0x8000–0x9FFF = 4096 字/8KB”的说明
  错了一倍；实际跨度 0x2000 = 8192 个 16 位字 = 16384 个逻辑字节，Group A
  的 0x1425 = 5157 字并未超过该区域。现行正文已更正；旧日志和维护条目保留，
  源码注释待后续同步。另将 ABI 上板证据表改为“部分探针”，避免与 sret 失败
  同时被读成整套 ABI 通过；历史非法 PE 段补后续恢复说明。
- 验证与结果：临时目录调用实际 `incremental-build.ps1`，主输入不变、只改
  未跟踪子文件时得到 BUILD→SKIP，输出仍为 v1；结合真实控制源文件引入
  `b2-hw-mode.rs` 而脚本漏列它的静态证据，确认 A01。无 BOM UTF-8 参数经
  Windows PowerShell 5.1 默认读取，与显式 UTF-8 比较为 False，复现 A06。
  临时实验目录为 `C:/Users/61987/AppData/Local/Temp/c28x-b1-audit-8125739dea5043f1aca8c83d44e5a6f2`。
  文档检查：14 个问题 ID 唯一，18 个显式锚点唯一，53 条路线锚点链接可解析。
- 未运行：LLVM/rustc/固件构建、sysroot 安装、单元测试、真实 Cargo 并发或中文
  路径链接、JTAG 与 Flash。隔离实验不等于硬件验证；竞态、启动写入的实际损害
  范围及对齐影响明确保留待验状态。
- 遗留事项：按文档顺序先保证构建来源与缓存可靠，再验收启动和后端正确性，
  随后扩展 Cargo 场景与性能优化。文档完成不代表问题已修复。

## 2026-10-20 — 优化审查：ADD32/SUB32 clobber 声明（上板验证）

- 修改范围：`backend/llvm-c28x/C28xInstrInfo.td`（ADD32_PSEUDO/SUB32_PSEUDO
  加 `let Defs = [ACC, XT]`）、`backend/llvm-c28x/C28xInstrInfo.cpp`
  （抽出 `AccProvablyDead`，LOAD16_ZEXT32 的 PUSH 门改为“除非可证明已死
  否则保留”）、`test/CodeGen/abi-mixed.ll`、`abi-pointer.ll`、
  `tools/verify-llvm-c28x.ps1`（断言改为寄存器号/帧尺寸无关）、本日志。
- 原因：审查上板样板时定位到 `rust_mixed` 返回 15≠10 的根因。
- 完成内容与证据：`ADD32_PSEUDO`/`SUB32_PSEUDO` 的 post-RA 展开把 Lhs
  暂存 ACC、Rhs 暂存 XT（`MOV_ACC_rr XT, ACC`），但 pseudo 未声明
  clobber，RA 允许把其他活跃值放在 XT：fast-isel 把 i32 参数 b 放在 XT
  （`movl xt, acc` kill ACC）后，第一个 ADD 的展开用 XT 存 Rhs 时把 b
  覆盖，第二个 ADD 读到的是 `*p` 而非 b，于是 1+7+7=15。加
  `Defs = [ACC, XT]` 后上板读回 **10（正确）**；只声明 XT 的变体实测
  仍错（4），说明 ACC 也必须声明。
- 验证与结果：`run-hw-abi.ps1` 上板 ABI_RESULTS =
  `8738,4660,10,42,171,21`，PC==hw_done：指针参数 0x1234 ✓、
  混合 (i16,ptr,i32) 10 ✓、间接调用 42 ✓、标记 0xAB ✓；仅
  sret 自检仍错（期望 0x3333，实得 0x2222 = len 字段值 → sret 缓冲的
  第一个字段 ptr 丢失，len 正确，线索已明确）。
  `verify-llvm-c28x.ps1`：除 mem-access.ll 的 `008d0400`→`008d0200`
  外全绿（该处属 addend 编码区，待并发修改稳定后核对）；
  abi-mixed/abi-pointer/struct-return 三项 FileCheck 全 PASS。
- 遗留事项：①ADD32 的 clobber 声明使若干函数帧增大约 2 字（3→5/7/9），
  属正确性换空间，后续可让展开按 liveness 精确保存 ACC 以减帧；
  ②同一 bug 类需审计其他 post-RA 展开（AND32/OR32/XOR32、
  ZEXT16_32_CORE、LOAD16_ZEXT32、STORE32/LOAD32、byte load/store 都用
  ACC/XT/XAR7 作 scratch）；③sret Rust→Rust 首字段丢失待修；
  ④`run-hw-abi.ps1` 与 `run-hw-rust-control.ps1` 约 90% 重复，可提取
  共享 helper；⑤样板自检公式宜加权（当前 sret 用 ptr+len，字段交换不可
  检测）。

## 2026-10-20 — 优化推进：clobber 审计、sret 定位、自检加权

- 修改范围：`backend/llvm-c28x/C28xInstrInfo.td`（ADD32imm32/SUB32imm32
  加 `Defs = [ACC, XT]`）、`backend/llvm-c28x/test/Rust/b2-hw-abi.rs`、
  `tools/hw_abi_driver.c`、`tools/dss-read-abi.js`（自检公式加权）、本日志。
- 原因：继续推进上一轮列出的优化项（同类 bug 审计、sret 定位、自检强度）。
- 完成内容：①**clobber 审计完成**——逐个核对 post-RA 展开的 scratch 使用：
  AND32/OR32/XOR32 系列只读 XT 并用 push/pop 保护 ACC（无需声明）；
  CMP16/CMP32、移位、UMUL/SMUL、LOAD32_XT 均已声明 Defs；
  STORE32_XT 用 push/pop 保护 ACC（Defs=[] 正确）；**唯一遗漏是
  ADD32imm32/SUB32imm32**（展开把常量经 ACC 搬进 XT，无声明）——已补
  `Defs = [ACC, XT]`，回归无变化。②sret 定位：自检函数实际计算
  `*buffer + ptr`（加权前得 0x2222=0x1111+0x1111），说明 `len` 的
  spill 槽读到的是 `ptr`；可疑点是与调用前后 `addb sp,#2`/`subb sp,#2`
  的帧调整相关（消除帧索引时的 SPAdj 与实际不符）。③自检公式加权：
  sret 用 `ptr*3+len`（交换字段得 0x7777）、mixed 用
  `a + *p*4 + b*16`（操作数错选得 121），避免“碰巧相等”。
- 验证与结果：`verify-llvm-c28x.ps1` 仍为除 mem-access 外全绿；
  `run-hw-abi.ps1` 上板 ABI_RESULTS=`46314,4660,61,42,171,21`，
  PC==hw_done：指针 0x1234 ✓、加权混合 61 ✓、间接调用 42 ✓、标记 ✓；
  sret 自检仍错（0xB4EA，槽位错读）。
- 遗留事项：①sret Rust→Rust 的 spill 槽错位待修（建议从
  eliminateFrameIndex 的 SPAdj 处理入手）；②ADD32/ADD32imm32 的 clobber
  声明使帧增大 2 字，可按 liveness 精化；③`run-hw-abi.ps1` 与
  `run-hw-rust-control.ps1` 重复可提取共享 helper（未做，避免动用户
  正在使用的脚本）。

## 2026-10-20 — 优化续：栈参数 32 位存储修复与栈参数路径缺陷定位

- 修改范围：`backend/llvm-c28x/C28xISelLowering.cpp`（i32 栈参数改存两个字）、
  `backend/llvm-c28x/C28xInstrInfo.td`（ADD32imm32/SUB32imm32 补
  `Defs=[ACC,XT]`）、`C28xRegisterInfo.cpp`（记录栈参数偏移缺陷）、
  `test/Rust/b2-hw-abi.rs` + `tools/hw_abi_driver.c` + `tools/dss-read-abi.js`
  （新增 5×u16+1×u32 栈参数上板用例）、本日志。
- 原因：继续推进 sret 定位与 ABI 完整性。
- 完成内容与证据：①`LowerCall` 的栈参数原先只用 `STORE_STK16` 存一个字，
  **i32 栈参数的高半从未写入**——已改为低半/高半各存一次（MIR 可见
  `STORE_STK16 -2` + `-1`）；②新增栈参数上板用例
  `rust_stack_args(1,2,3,4,5,6)`（期望 21）：**实测 38**，证明栈参数路径
  仍然错误；③三次偏移实验定位：原 SUBB 路径 70、正向 `SP+帧+1+argword`
  读成 0（只累加了 4 个寄存器参数=10）、`+2` 读到无关内存。结论：**入参
  距被调方帧的距离取决于调用方出栈区大小，被调方无法从 MFI 推出**，需要
  把栈参数钉在返回地址的固定偏移（或传入调用方区大小）——属 ABI 约定
  变更，未在本轮实施，已在 `eliminateFrameIndex` 注释中完整记录；
  ④sret 自检失败的原因随之明确：`make_pair` 第二个 i32 参数正是走栈。
- 验证与结果：`verify-llvm-c28x.ps1` 维持除 mem-access 外全绿（32 位存储
  修复未改变任何字节 oracle）；上板 `ABI_RESULTS=69089105,4660,61,42,38,171`：
  指针 0x1234 ✓、加权混合 61 ✓、间接调用 42 ✓、标记 ✓，sret 与栈参数 ✗。
- 遗留事项：①栈参数约定（最高优先，影响任何 >4 参数或 i32 落栈的跨边界
  调用）；②sret 依赖 ①；③ADD32/ADD32imm32 clobber 使帧增大 2 字可按
  liveness 精化；④脚本去重未做。

## 2026-10-20 — 栈参数约定：三次假设全部被硬件证伪，缺陷已精确定界

- 修改范围：`backend/llvm-c28x/C28xRegisterInfo.cpp`（缺陷注释改为实测
  数据）、新增 `tools/dss-probe-stkargs.js`（栈布局探针）、本日志。
- 原因：继续推进"定栈参数约定"。
- 完成内容与证据：①用 DSS 探针在 `rust_stack_args` 入口读 SP 与栈内容：
  **SP=532，唯一的栈参数 e=5 位于 SP-5**；被调方帧 17 字，故 e 落在
  callee_SP-22。②据此逐一验证三种被调方公式：
  `SUBB`（原路径）→ 上板 70；`SP+帧+1+o/2` → 10（只累加到 4 个寄存器
  参数）；`SP+帧+ArgAreaWords-o/2`（从参数区顶部计数）→ 10；
  `SP+帧+2+o/2` → 无关内存。③结论：**入参到被调方 SP 的距离由调用方
  决定**——TI C 的调用方把首字放在 SP_entry-2..-5（视其帧而定），我们的
  LowerCall 放在 -2，两者不同，因此不存在纯被调方侧的公式。修法必须是
  约定变更：两侧共同把参数钉在返回地址的固定偏移，或让序章在入参区
  下方分配。已把全部实测数据写入 `eliminateFrameIndex` 注释。
- 验证与结果：回退到原路径后 `verify-llvm-c28x.ps1` 恢复为除
  mem-access 外全绿；上板 `ABI_RESULTS=340787,4660,61,42,10,171`（指针/
  混合/间接调用/标记 ✓，sret 与栈参数 ✗）。32 位栈参数存储修复保留。
- 遗留事项：①栈参数约定（需设计决策，非局部修补）；②sret 依赖 ①；
  ③`ADD32/ADD32imm32` clobber 的帧增大可按 liveness 精化；④脚本去重。

## 2026-10-20 — 栈参数布局实测与根因定位（transient PUSH 破坏帧基址）

- 修改范围：新增 `tools/probe-ti-stack.c`（纯 C 探针）与
  `tools/dss-probe-stkargs.js`（加宽 dump + 打印参数寄存器）；
  `C28xRegisterInfo.cpp`、`C28xISelLowering.cpp` 注释记录实测与根因
  （公式回退到基线，未保留未验证的改动）。
- 原因：定栈参数约定。
- 完成内容与证据：①纯 C 探针（cl2000 编译，1 个与 4 个栈参数）在
  callee 入口实测：**调用压入 2 字返回地址，第一个栈参数在 SP_entry-3，
  后续向下**（1 字时 e@-3；4 字时 e,f,g,h@-3,-4,-5,-6；AR4/AR5=23/24
  证实 a,b 在 AL/AH）。②Rust 被调方（`rust_stack_args`）入口寄存器实测
  ACC=6、AR4=1、AR5=2，栈上 c,d,e 在 -3,-4,-5 —— 与 TI 完全一致，说明
  参数**放置**没有问题。③按 `帧字数+3+o/2` 计算后，生成的读偏移精确落在
  SP-20/21/22（= 参数所在字），但求和仍为垃圾（33678，取自 SP-18 的
  代码地址）。**根因：帧索引寻址用 `MOVZ XAR7,SP` 取当前 SP，而该访问
  发生在会 `PUSH_ACC` 的 post-RA 展开内部，SP 被临时下压若干字，导致
  偏移随压栈数漂移**；局部对象只是靠“+1 保留字”的余量侥幸躲过。
- 验证与结果：公式回退到基线后 `verify-llvm-c28x.ps1` 在 mem-access 处
  出现新的 verifier 错误（`$ar0 = MOV16_imm 0`：`$ar0 is not a GR16ACC
  register`）——该指令定义属并发修改区域（C28xInstrInfo.td 的 MOV16_imm
  约束），非本会话改动；其余用例通过。
- 遗留事项：①栈参数的真正修法是**帧基址不受 transient PUSH 影响**（引入
  帧指针，或禁止在帧索引使用点跨越 PUSH/POP，或展开前先把帧基址算进
  寄存器）；②sret 依赖 ①；③mem-access 的新 verifier 错误待并发修改
  稳定后核对。

## 2026-10-20 — 栈参数修复成功（第二条方案：补偿 SP 的临时偏移）

- 修改范围：`backend/llvm-c28x/C28xRegisterInfo.cpp`（帧索引寻址加入
  `LivePushWords` 补偿 + 固定对象按 TI 布局 `帧字数+3+o/2`）、
  `C28xISelLowering.cpp`（调用方栈参数改到 SP-1 起）、本日志。
- 原因：按用户选定方案二（禁止帧索引跨越 PUSH/POP 的影响）实施。
- 完成内容与证据：①定位到真正差：序幕是 `push ar4` + `addb sp,#17`，
  **保存 callee-saved 的 push 也让 SP 偏移 1 字**，而帧索引寻址用
  `MOVZ XAR7,SP` 取实时 SP，公式未计入 → 栈参数读高一个字（读到
  SP-18 的代码地址 33678）。②修复：`eliminateFrameIndex` 从 MI 向块首
  扫描 PUSH/POP 累计 `LivePushWords`，加进偏移；固定对象（入参）按实测
  TI 布局 `帧字数(含保留字)+3+o/2` 计算。③调用方栈参数改到 `SP-1-o/2`
  （TI 的调用方把首字放 SP-1，返回地址压在其上方）。
- 验证与结果：上板 `ABI_RESULTS=2192913203,4660,61,42,**21**,171` ——
  **栈参数用例返回 21（正确）**，指针 0x1234 ✓、加权混合 61 ✓、
  间接调用 42 ✓、标记 ✓；字节 oracle 全绿（hello/const/branch/alu/
  mmio/core-ops/frame 全部一致）。
- 遗留事项：①sret 自检仍错：调用点把 len 放进 XAR4（而非栈）并 spill
  XAR6，需查该签名的 CC 分配（sret + 两个 i32）；②mem-access 因并发
  修改的 `MOV16_imm` 约束（`$ar0 is not a GR16ACC`）暂无法跑，
  与本改动无关；③`LivePushWords` 补偿同样作用于局部对象，字节 oracle
  未变，但仍建议后续用 mem-access/stack-byte-stress 的语义测试复核。

## 2026-10-20 — sret 残留定位：多值结构体返回路径

- 现象：栈参数修复后 `rust_sret_self_check` 仍返回垃圾（上板
  2192978739，期望 0x5555）。IR 显示 `make_pair` 返回的是 Rust 结构体
  `{i32,i32}`（非 extern "C"），LLVM 语义为**多值返回**，后端通过
  sret 形参具现化。
- 已确认正确的环节：调用方把 len 低/高半分别存到 SP-1/SP-2（修正高半
  偏移后）；被调方 `addb sp,#5` 后从 SP-8/SP-9 读回 len ✓；make_pair
  经 XAR6 把 ptr、len 写入返回缓冲的代码形态正确。
- 残留：调用方读回结构体时出现可疑的 `movl xar0,#16` 常量与 `lsrl acc,t`
  移位（像地址计算里的常量 16），导致读回垃圾。**需把 Rust 多值结构体
  返回 `{i32,i32}`（同 (u32,u32)）作为独立用例继续追**（建议加一个
  `#[repr(C)]` 两字段结构体返回的 CodeGen 断言与上板用例，与 least-
  significant-word 返回约定分开验证）。
- 备注：sret 缓冲的 XAR6 spill/恢复与栈参数无关，勿与前两条混淆。

### sret 补充（同日续）：已排除的分支

- 已排除：调用方的 `movl xar0,#16` + `lsrl acc,t` **不是 bug**，是 32 位栈
  参数拆出高半字的合法移位（去掉乘法后依然存在）。
- 已排除：`CALLSEQ_START` 不预留返回地址空间不是原因——改为
  `StackBytes + 4` 后 ADJCALLSTACKDOWN/UP 失衡（DOWN 8 vs UP 4，verifier 直接
  报错），且偏移公式要整体平移两层，已回退；参数在两种分配下都落在
  SP_entry-3（实测一致）。
- 已确认的环节：调用方把 len 低/高半存到 SP-1/SP-2；被调方 `addb sp,#5` 后
  从 SP-8/SP-9 读回；make_pair 经 XAR6 写字段 0/1（第二字段用
  `add acc,#4` 的字节偏移）代码形态正确；调用方读回用保存的 XAR6 + `ror`
  取字地址。
- 结论：问题在调用方读回后的**算术/取字段环节**（最小用例
  `/tmp/c28x-oracle/sret4.ll` 的 use1/use2 均复现，去掉乘法不消失）。
  下一步建议：对 `use1`（只取字段 0）单步对比预期：入口 a=0x1111,b=0x2222
  应返回 0x1111，看实际读回的中间量。

## 2026-10-20 深夜：三项缺陷收尾与 MOVB 编码根因

- **流程结论（对"为什么重建 llc"的回答）**：llc 不是 B-1 的交付通道。
  patched rustc 静态链接 C28x 后端，后端修复必须经 `rebuild-rustc.bat`
  重链才进入直编路线；`sync-and-build-c28x.ps1` 重建 llc 只作编译冒烟测试。
- **第 1 项（addend）闭环**：`FK_C28x_ABS22` 改 `Value>>1` 后，带修复的
  stage1 rustc 发射 `#0x000122`；DSS 硬件读回 `*(u16*)0x8122 = 0x0001`，
  `Some(1u16)` 落位正确。
- **第 2 项**：`rust_begin_unwind` 的 `B 0,UNC` 是 panic handler 内联死
  循环，行为正常，非缺陷。
- **第 3 项真根因（已修复）**：MOVB 索引形式编码错误。asm2000 实证
  `*+xar7[ar0]`=c697、`*+xar7[2]`=c6d7；发射器 `0xC690|indirectXarField`
  与返回的 `0xC0|n` 位重叠（0x90|0xC7=0xD7）算出位移形式，字节访问忽略
  AR0 的 lane 按 word_addr+2 寻址。已改为 `0xC600|((indexed?0x90:0xC0)|n)`，
  llc 重建验证 C697 正确发射。误诊的 MOV16_imm/GR16ACC 改动已回退。
- **阻塞**：rustc 重链 PE 缺陷——exe 补丁验证通过（与 known-good 布局
  一致），DLL 干净删段后 DllMain 报 1114、VA 搬迁重叠报 193；stage1 现为
  恢复的 known-good 对。双发射权宜路径代码生成与直编不同，探针不过。
- **下一步**：调试 DLL 加载失败（或换匹配 GCC 14.2 运行库的链接器）→
  重链 rustc → `rebuild-core-sysroot.ps1` → Group A–E 端到端回归。

## 2026-10-21 — 当前优化优先级复核

- 修改范围：`docs/PATH_B.md` 与本日志，仅文档。
- 原因：用户询问当前仍可优化的点，需依据新增进展而不是重复旧审查结论。
- 完成内容：新增 `b1-next` 七项优先级，按工具链发布、sysroot 来源一致性、
  帧/聚合返回验证、Cargo/增量构建、代码生成效率、体积耗时、测试状态收敛排序。
  修正当前说明：ADD32 与栈参数已有新样板通过记录；最新 MOVB 定位替代旧参数
  宽度归因；重链曾恢复但最新 DLL 加载再次阻塞，known-good 不等于最新修复交付。
- 检查依据：读取最新 WORK_LOG、PATH_B 与相关脚本；确认子模块缓存、core 独立
  对象、Cargo 临时目录和编码问题仍存在；检查 C28xRegisterInfo.cpp，发现
  LivePushWords 与 PreserveAcc 均为当前基本块内扫描，新增跨基本块验证风险，
  未把风险写成已复现缺陷。
- 验证与结果：新 `b1-next` 锚点唯一；未编译、重链、测试或运行 JTAG/Flash。
- 遗留事项：优先解决新编译器发布与 core 版本一致性后再做性能优化；具体缺陷
  和验收仍按 A01–A14 及本次优先级执行。

## 2026-10-21 上午：帧/字节/寄存器 clobber 六项修复，control 首次全绿

按"多改一些再重跑"的要求，这一轮先用 TI 工具链+硬件取地面真值，再一次改完
再重建（共 3 次完整重建）：

**地面真值**（新增探针，可复用）
- `tools/probe-byte-semantics.c` + `dss-read-byte-sem.js`：TI C 的 `char*` 是逻辑
  字节地址（`p+1` 走 ADDL ACC,#1）；`*(u8*)&word` 取低字节。
- `dss-probe-stkargs.js`（callee_a/b）实测：入口 SP 在返回地址之上、RA 在
  `SP-2/SP-1`、首个栈参数 `SP-3`，后续参数逐字向下（与 `+o/2` 公式一致）。
- asm2000：MOVB 四种形式编码（C6C7/C6CF/C6D7/C697）、`MOV AR5,AH`=97A5、
  `MOV AH,AL`=93A9 均与我们的发射器一致；`B disp,cond`=FFE1+disp、target=PC+disp。

**修复**
1. 固定对象基址 `FrameWords` 与 prologue 口径统一（原 `StackSize/2+1`）。
2. `PUSH_ACC`/`POP_ACC` 是 32 位 push，帧扫描记账 1→2 字。
3. 新增 `MOVB_disp_load_AL`/`MOVB_disp_store_AL`（字地址+常量 lane），帧字节
   读写改用它们，删除把字地址当字节地址用的 `wordToByte()`。
4. 字节/32 位逻辑伪指令补 `let Defs = [XAR0]`（展开写 AR0 存 lane，RA 不知道，
   实测把 XAR0 里的指针覆盖成 lane 值）。
5. **保护字**：prologue/epilogue 在 `StackSize == 0` 时也保留 1 字；此前无帧函数
   （如 `rust_mode`）的 32 位 `PUSH ACC` 直接压到返回地址高字，LRETR 跳飞。

**结果**（候选 `20261021-113358-edeaeaae`，bundle `...-4fa9545d`）
- control PASS：`23,40,19,20,82,178`
- 新增分层探针 13/13 全对（参数/比较/分支/循环/栈字节/字节指针/字指针）
- Safe HAL PASS：`0,0,0,4,7339,178`
- core-ex Group A：`138,54,65,245,212,178,17`（期望 `140,...,223,0xB3`）
  → result/mem/cmp/closure 正确；option 仍 138、pattern 挂死（0x945b），待修。

**磁盘事故与清理**：本轮两次把盘写满。已删除 `build/toolchains` 的历史
backup/compiler/bundle（保留 active 与最新候选）、D: 的 `tmp`/`build-temp`/
`_downloads`/`llvm-build-c28x`、以及会话编辑备份 `modify_backup`（5.3GB）。

## 2026-10-21 — B-1 工具、文件与当前流程手册

- 修改范围：扩写 `docs/PATH_B.md` 的 `b1-files`，并在主仓库与 B-1 README
  增加入口；按当前发布包和脚本解释工具链制作、Cargo/直接对象分支及产物位置。
- 原因：需要把当前主路径涉及的仓库、外部工具、rustc 制作、core/builtins
  打包、TI 链接、DSS 验证和具体文件职责集中说明，避免继续依赖零散历史记录。
- 当前证据：active bundle 为 `20261021-115718-e6081a39-07c87358`；
  `Get-C28xBundle` 全部哈希校验通过，`rustc -vV` 返回 1.100.0-dev、GNU host、
  LLVM 23.1.1。发布清单/并发锁/原子指针/缓存负向测试全部 PASS。
- 构建验证：`run-hw-rustc-direct-object.ps1 -BuildOnly` 成功，Rust 对象和 TI
  RAM 映像的各步骤均命中已有缓存；未声称本次重新生成目标对象。
- Cargo 验证：独立样板 `cargo metadata` 通过；`cargo build --release --target
  c28x-none-elf` 在宿主 build.rs 阶段失败，因为系统 MSVC rustc 找不到
  `link.exe`（exit 101），目标 C28x 编译未开始。
- 未运行：本次没有重新执行 Group A–E、JTAG/RAM 读回或 Flash。
- 遗留：为 Cargo wrapper 提供可用的 Windows host linker 或改用现有 GNU host；
  旧 `D:\c28x-toolchain\rebuild-rustc.bat` 仍优先 Qt 旧工具链，不是现行发布入口；
  `c28x-gpio-blink` 仍是旧 build-std/noop-link 实验配置。
## 2026-10-21 — B-1 全链审查、Cargo 解阻与 Group B RAM 链接修复

- 范围：只检查 PATH B-1；未处理 PATH A/MIR。审查 active bundle
  `20261021-163323-13d258a8-b95c8536`、Cargo 配置、直接对象、core-ex、TI
  链接和版本绑定。
- Cargo 根因与修复：两个样板的 `build.rs` 只输出 `rerun-if-changed`，却让构建
  先依赖宿主链接器。本机两个 VS Build Tools 实例均缺 Windows SDK（`LIB` 为空、
  `kernel32.lib`/`rc.exe` 缺失）；同 Rust 提交 `4b6d04e70...` 的 GNU nightly
  能生成宿主 exe，但 exe 因系统 `bcryptprimitives.dll` 不导出 `ProcessPrng` 而以
  `STATUS_ENTRYPOINT_NOT_FOUND` 在 main 前退出，静态 CRT 也无效。删除两个非必要
  build script，并给 B-1 根 `.cargo/config.toml` 补齐 TI linker、bundle sysroot、
  `--emit=asm,link`；修复了从根目录使用 `--manifest-path` 时误调用 x86-64 `ld`。
- Cargo 验证：独立项目、`c28x-cargo-app` 单 crate、`--features cross-crate`
  三者均完成定制 rustc → C28x 汇编 → TI 汇编对象 → TI RAM 链接，输出
  `C28X_CARGO_TI_LINK=PASS`。`cargo metadata` 两个项目均通过。当前结论只覆盖
  无 build.rs/proc-macro 样板；外部链接输入自动失效仍待 hash/stamp 方案。
  实测 `cargo clean -p ... --target` 在共享 target-dir 删除 0 个文件，不能作为
  失效手段；改用带 manifest 的整 C28x target clean，删除 92 个文件后重新构建，
  三种场景再次全部 PASS。
- 直接对象验证：ABI freeze PASS（211 files）；LLVM/MC/ELF/TI link gate 全部
  PASS；当前 bundle 强制重建的 control、Safe HAL、layer probe、Option probe
  均完成 TI RAM 链接。core-ex A/C/D/E 先通过，B 因 RAML0L1 只余 0xe words、
  最大连续洞 1 word，无法放置 0xa-word `.cinit` 而失败。
- Group B 修复：`HW_CORE_RESULT/HW_CORE_DATA` 在 main 中会逐项写满，启动清零
  没有语义用途。把它们放入独立 `.hw_result_noinit`，linker 以 `type=NOINIT`
  分配到 RAMM1，删除 `.cinit` 后 Group B 强制重建和链接通过；最终 A–E
  BuildOnly 全部 PASS。
- 硬件结果：尝试 Group B RAM/JTAG，DSS 在连接阶段返回 XDS100/FTDI Error -151，
  目标代码未执行。本轮没有新增硬件 PASS，也没有 Flash 操作。
- 仍需处理：匹配版本且可运行的 host 工具链/build.rs/proc-macro；Cargo 外部
  链接输入自动失效；Cargo 直接消费 C28x `.o`/`.rlib`；迁出硬编码可变 stage1
  的旧脚本；收敛 TI 空 section 警告；恢复硬件后执行完整语义回归。


## 2026-10-21 傍晚：AND32 展开缺陷修复（上板闭环）+ pattern 分解定位

- **缺陷根因（is_some/Group E/Option 138）**：`AND32_PSEUDO`/`OR32_PSEUDO`/`XOR32_PSEUDO` 的
  post-RA 展开把 Lhs 弄丢了——Lhs 载入 ACC 后，`EmitLoadRhs()` 立刻用 Rhs 覆盖 ACC，
  高低半都在对 Rhs 自身做 AND（恒等），实际返回 Rhs。且当 Rhs 是 XAR0 里的物化常量时，
  抽取高半的 `MOV AR0, AH`（AR0 是 XAR0 低半）会把 XAR0 清 0，第二次读 Rhs 读到 0。
  硬件实证：is_some（`and i32 tag,1`）在 next() 调用点 dump，`MOVL ACC,XAR0` 把 AL 里
  的 tag=1 冲掉 → some_of(1)=0、none_of(1)=1、core_ex_option=138。
- **修复**（C28xInstrInfo.cpp expandPostRAPseudo）：① 每个 EmitLoadRhs() 前后用
  PUSH_ACC/POP_ACC 保住 Lhs（与 *_HALF_PSEUDO 一致）；② Rhs 在 XAR0 时先用
  `MOV32rr XAR7, XAR0` 盾到保留的 XAR7（XAR0 只可能是 dying operand，伪指令已声明
  `Defs=[XAR0]`）。
- **回归**：新增 `test/CodeGen/and32.ll`（and/or/xor 三形态 + push/pop 纪律 CHECK），
  verify-llvm-c28x.ps1 注册字节 oracle；verify-llvm-c28x.ps1 与 verify-llvm-c28x-link.ps1
  全绿，其他测试零漂移。
- **工具链链条**（PATH_B §4 顺序）：sync-and-build-c28x → build-rustc-c28x.ps1
  （候选 20261021-163323-13d258a8）→ rebuild-core-sysroot.ps1 → 发布 bundle
  20261021-163323-13d258a8-b95c8536（active）。
- **上板结果**（新 bundle）：Group E **16/16 PASS**（some_of(1)=1、none_of(1)=0 等）。
  Group A：option **140 ✓**、result 54 ✓、mem 65 ✓、cmp 245 ✓、closure 212 ✓；
  pattern 返回 148（期望 223）。
- **pattern  panic 消失**：panic 链是 core 预编译对象里 `Iter::next` 的
  `assert_unsafe_precondition!`（precondition_check → runtime_add_nowrap →
  panic_nounwind_fmt → rust_begin_unwind）。本路线策略本就是 -Zub-checks=no，
  但 rebuild-core-sysroot.ps1 漏了该旗标，导致从 core-dual.o 共享实例化出的
  Iter::next 自带误报检查。已在 coreCommon 加 `-Zub-checks=no`（只摘除这些
  precondition），sysroot 重建后 panic 消失。
- **pattern 148 分解定位**：新增分解探针（每个子计算一个 extern "C" 入口，手动
  走 rustc --emit=obj → cl2000 链接 → DSS 读回）：shapes=1（want 61）、
  whilelet=0（want 15），其余 7 项全对且合计恰为 148。两项都驱动 slice::Iter。
  硬件探针（next() 入口 dump）显示 `iter()` 的 {ptr,ptr} sret 返回写成
  {start=0, end=0x0A0B0401} 垃圾；反汇编 core 的 iter() 发现入口保存 XAR6
  （sret 指针）后被一条 `MOVL XAR6, @XAR7`（取自疑似未初始化的帧槽）覆盖，
  随后按垃圾指针写返回结构。与刚修的 AND32/XAR0 属同类"寄存器被错误重载"缺陷，
  为直接对象路线新发现的开放缺陷，待下一轮修复。
- **B-1 ABI 硬件样板**（对应 PATH_B §7 "sret/栈参数/混合 ABI 未完成"）：新增
  `backend/llvm-c28x/test/Rust/b1-hw-abi.rs`、`tools/hw_b1_abi_driver.c`、
  `tools/dss-read-b1-abi.js`、b1 `tools/run-hw-rustc-direct-abi.ps1`（移植自已
  归档的 B-2 四件套）。BuildOnly + 符号校验通过；真机结果：入口寄存器 ABI 全部
  正确（ptr=XAR4=0x800、mixed a=AR5=1/p=XAR4=0x804/b=ACC=2、栈参 1/2/3/4/5+6），
  但 `rust_apply` 的 LRETR 把栈参字当成返回地址，CPU 跳飞进 boot ROM
  （PC=0x3FF599，结果全垃圾）。已排除：LCR *XAR7 编码=0x3E67 与 TI 一致；
  MOVL *SP++/ACC,*--SP 编码=0x1EBD/0x06BE 与 TI 一致；驱动侧参数构造正确；
  rust_apply 内部 SP 账目实测自洽（541→543→541）。残留疑点：直接 LCR 留下的
  返回地址与该函数尾声期望的位置不一致（1 字 ADDB 帧 + 内部 32 位 push/pop +
  内部调用的组合），需与 iter() 缺陷一并下一轮专攻。
- 未运行：JTAG/Flash、Group B/C/D、core-ex 全量。

## 2026-10-22 — B-1 直接对象接入复核、遗留修正与新增重定位缺陷

- 范围与原因：用户要求仔细核对当前状态、已做修改与缺口；仅处理 B-1。
  同步 `docs/PATH_B.md`、两个 README 与 B-1 既有 Cargo 指南，纠正文档仍称
  “Cargo 只消费汇编、XDS 未恢复、Group A–E 全 BuildOnly PASS”的过期结论。
- 补记上一轮已做修改：`c28x-ti-linker.ps1` 增加 `rustObjectMode=direct`，
  直接使用应用 `.o`，以 llvm-ar 解包依赖/core/builtins 的对象成员，逐个经 TI
  ofd2000 验证 `EM_TI_C2000` 后链接；保留旧 assembly 模式。两个项目设置
  direct，根与子项目移除 `--emit=asm,link`；归档采用短路径内容哈希缓存。
  provenance 升为 schema 2，记录 bundle、原始 Rust 输入和归档成员。
  `verify-cargo-direct-hw.ps1` 从根目录用 `--manifest-path` 调用 Cargo。
- RAM 假阳性纠正：上次 NOINIT 缓冲只减少 `.cinit`；TI linker 仍把孤立
  `.text.*`、`.textreset` 溢出到 Boot-ROM IQTABLES（0x3FE000 起）。因此旧
  Group B BuildOnly PASS 无效，之前连接恢复后的加载失败并非 XDS 故障。
  `F28035_ram.cmd` 已显式收集所有代码段到程序 RAM；core-ex/Cargo 还检查
  程序分配。2026-10-22 重跑 B 在链接阶段失败：`.text` 0x2294 words，
  RAML0L1 总长 0x2000、剩余连续洞 0x1e96。未扩地址或借 ROM 放代码。
- 本轮发现与小范围修正：子项目目录的 Cargo 仍因父子 `rustflags` 合并而
  重复传 sysroot，实测 `cargo check` 失败。删除两个子配置的重复数组，
  继承根配置后子目录 check 通过。发现原始应用 `.o` 会被 rustc 删除，旧
  provenance 各缺一个对象；验证上次新增的留存 `rust-<hash>.obj` 逻辑。
  再把 TI 中间对象按输出文件名隔离，避免不同项目覆盖共享 `extra-N.obj`；
  分配检查补上具名 section 行和分配末地址越界判断。
- 发布与共享门禁：`Get-C28xBundle` 确认 active 为
  `20261021-163323-13d258a8-65c4479c`，清单全部通过；rustc 1.100.0-dev、
  GNU host、LLVM 23.1.1。`test-toolchain-release.ps1` 正/负向门禁通过；
  ABI freeze 扫描 199 文件 PASS，`verify-llvm-c28x.ps1` 与
  `verify-llvm-c28x-link.ps1` PASS。后者覆盖 ABS22 LCR 跨对象解析，不代表
  完整重定位或 ABI 真机语义通过。本轮未重链或发布新 rustc/bundle。
- Cargo 重建与上板：清理当前 bundle 的整个 C28x target，独立项目与跨 crate
  重新构建，Rust `.s` 数量为 0；单 crate 另构建 PASS。独立输入 3/rlib 成员 2，
  跨 crate 输入 4/成员 3；两组本轮 RAM/JTAG 读回分别为 `7,13,20` 与
  `23,40,19,20,82,178`，均有明确 DSS PASS 标记。随后三个 provenance 的
  `inputs` 全部存在且哈希匹配，未再混用共享 TI 对象。
- core/ABI 复核：A/C/D/E BuildOnly 通过，B 因上述容量失败。Group A 真机
  `140,54,65,245,212,148,179`，pattern 应为 223，失败；Group E 16/16
  PASS。ABI 样板链接通过、PTR/MIXED/APPLY 入口已命中，但最终
  PC=0x3FF599（Boot ROM）、DONE=0x80AA，结果未通过；断点清理还出现
  Error -1066，DSS exit 0 仍被脚本判为失败。没有据此关闭 sret/返回地址问题。
- 新增 P0 重定位证据：审阅 `C28xAsmBackend.cpp`，对象 writer 只映射
  ABS22；未解析分支还有写零的源码路径（本轮未复现该分支）。先用 llc
  生成外部调用/数据地址与静态指针混合对象：指令有 ABS22 重定位，静态
  指针数据为零且无对应重定位。再用同一 active bundle rustc 编译
  `external-static.rs`：`FUNCTION_POINTER` 与 `DATA_REFERENCE` 各为
  4 字节零，`TOTAL_RELOCATIONS=0`，编译 exit 0。已保存源、对象和 OFD XML；
  这是直接对象路线的实质缺口，不能以 Cargo 样板通过宣称地址初始化正确。
- 证据位置：B-1 `build-logs/audit-20261022/` 保存 Cargo 三种构建、两组
  Cargo 上板、core A–E 构建、A/E/ABI 硬件和两类外部地址最小复现。
- 未解决/未运行：未修静态地址 fixup、sret/复杂调用 ABI、Group B 拆分；
  C/D、Safe HAL、layer 本轮未重新上板，未运行 Flash。外部 C/ASM/cmd/适配器
  变化自动失效、host build.rs/proc-macro、归档多 CGU/weak/COMDAT/LTO/同名
  成员矩阵、native link args、来源/别名验证、缓存并发与清理、旧 stage1
  脚本仍待处理。发布当前是完整性/最小对象检查，尚未强制全语义门禁后激活。
- 体积优化线索：清单的 `coreArgs`/`builtinsArgs` 未显式设置优化级别；可在
  新候选 bundle 试 `opt-level=s/z`，对比 RAM 占用和语义结果。本轮未改参数，
  未重编 sysroot，也未把该线索当成 Group B 容量问题的已验证解法。
- 单位纠错：本机 TI `f28035.gel` 的 L0/L1/L2/L3 分配为
  0x800/0x400/0x400/0x1000，合计 0x2000 个 16 位 word（8192 words，16 KiB）。
  修正 RAM `.cmd`、core-ex 与 Safe HAL 脚本注释中的“4096 words / 8 KB”；
  地址与长度数值本来正确，保持不变。此项也纠正本会话早先的口头单位说明。

## 2026-10-22 傍晚：Group B 容量问题——拆分 `core_ex_iter_slice` 为 B + B2

- 问题：Group B（`core_ex_iter_slice`，C 侧 slice ABI + bounds-checked 迭代）链接
  失败，`.text` = 0x22aa words > RAML0L1 0x2000（`.text ... FAILED TO ALLOCATE`，
  `core_ex_b.out` 未生成）。旧“Group B BuildOnly PASS”是假阳性——代码段曾被 TI
  linker 静默塞进 Boot-ROM IQTABLES（0x3FE000+），RAM 里根本没有可执行副本。
- 根因量化（map 地址排序符号表）：`core_ex_iter_slice` 单函数塞了 11 种迭代器
  适配器（map/filter/sum、enumerate/fold、zip/skip/map/sum、filter/count、position、
  any/all/find/nth/last、rev/copied/sum），每个单态化几百字，合计 ~0x1400+ 字迭代
  机机构 + di64 helpers + bounds-check 的 offset_from_unsigned + panic(abort) 路径。
  因 `-Cpanic=abort`，未拖入 ~4K 的 `__fmt_inner` 格式化闭包。
- 方案（用户指定“拆分测试或优化体积”）：选**拆分**（低风险、无需重编 sysroot）。
  每组是独立镜像、各自 0x2000 字预算，且各 driver 只调用本组符号、
  `--unused_section_elimination` 裁掉另一半适配器。把 `core_ex_iter_slice` 拆成：
  - Group B  = map/filter/sum + filter/count + position + any/all/find/nth/last → 期望 **80**
  - Group B2 = enumerate/fold + zip/skip/map/sum + rev/copied/sum → 期望 **90**
  （80+90=170，与原单函数值一致；已用 Python 逐项复算核对，values=[2,4,6,8]）
- 改动文件：
  - `backend/llvm-c28x/test/Rust/b1-hw-core-ex.rs`：拆出 `core_ex_iter_slice2`；
    host test 加 `iterator_adaptors2`(90)、原 `iterator_adaptors` 改断言 80；
    测试计数 12/12→13/13。
  - `tools/hw_rust_core_ex_driver_b2.c`（新，复制 b 改调 `core_ex_iter_slice2`）。
  - `tools/dss-read-rust-core-ex-b2.js`（新，期望 [90,0xB3]）。
  - b1 `tools/run-hw-rustc-direct-core-ex.ps1`：ValidateSet 加 'B2'、`$groupSymbols`
    加 `B2=@('core_ex_iter_slice2')`、头注释同步组划分与 13/13。
  - 5 个既有 dss 脚本注释 12/12→13/13。
- 验证（`-BuildOnly`，TI link，均 exit 0 + 门禁过 + 无 Boot ROM 溢出）：
  - Group B ：`.text` 0x1942，RAML0L1 余 0x5b8，`core_ex_b.out` 生成。
  - Group B2：`.text` 0x1a92，RAML0L1 余 0x404，`core_ex_b2.out` 生成。
  - Group A ：`.text` 0x1236（无回归，改共享源不影响 A/C/D/E）。
- 假阳性门禁说明：`F28035_ram.cmd` 已显式收集所有代码段入 RAML0L1（溢出即
  FAILED TO ALLOCATE），脚本 RAM-escape 门禁（分配须在 [0x8000,0xA000)）也已在位；
  拆分前 B 正是被此门禁挡下（真实失败）。本次无需新门禁代码。
- 未运行/限制：host 测试（`rustc --test`）本机无法链接——VS Build Tools 缺 Windows
  SDK（`kernel32.lib` 缺失）、GNU nightly 亦因 `bcryptprimitives.dll` 在 main 前退出
  （既有环境限制，WORK_LOG 2026-10-21 已记）。80/90 由 Python 复算 + dss 脚本钉值。
  硬件（DSS/XDS）语义回归仍待 XDS 恢复后执行：B=80、B2=90。

## 2026-10-22 傍晚：B-1 静态指针与 Group A pattern 修复闭环

- 修改与原因：
  - `C28xAsmBackend.cpp` 为 generic data fixup 显式登记 TI relocation；allocated
    32 位地址字段用两个 ABS32 合成 `2*S+A`，非 allocated 字段保留单次登记。
    `static-pointers.ll`/TI link 回归覆盖函数、数据、本地、奇数字节和负偏移六个最终值。
  - `C28xISelLowering.cpp`、`C28xISelDAGToDAG.cpp`、`C28xInstrInfo.td/.cpp`
    将比较实参随 `CMPBR16/32_PSEUDO` 保留到 RA 之后再展开，避免 PHI copy 和
    spill 的 MOV/访存覆盖比较标志。branch analysis 在展开前对该复合 terminator
    保守拒绝分析，避免把 `[CMPBR][JMP]` 误当单个无条件跳转。
  - 真机追踪撤销旧 sret 诊断：`iter()` 的返回及调用者复制均为正确 `{1048,1058}`，
    实际 `NonNull::eq` 比较产生 -10 后被 MOV AL/AH 覆盖 ST0，错误返回 true。
    比较修复后 whilelet=15，pattern 由 148 提高到 163，仍未宣称成功。
  - 继续追踪四个 enum 元素，发现 circle/rect/labeled 的首个 payload 为零。
    `C28xMCCodeEmitter.cpp` 的 `uint16_t(Imm)>>16` 永远取不到高位，
    把合并初始化常量 `0x50001` 写成 1；改为先移位再收窄后 pattern=223。
    新 `upper-immediate.ll` 三组常量（0x50001/0x3fffff/0x10000）的对象字节与
    独立 TI 汇编输出逐字节一致。O0 `compare-select.ll` 保护比较/跳转相邻性。
  - 完整 Rust 回归还暴露两处必要修正：`C28xMCAsmInfo.cpp` 的内部前缀改 `.L`，
    避免 `LOCAL_VALUE/LOCAL_REFERENCE` 被泛用的 `L` 前缀误判为 temporary 并断言；
    `C28xTargetMachine.cpp` 将 mergeable global 视为普通 ReadOnly 再走逐全局
    section 选择，维持无 SHF_MERGE，并允许丢弃无用常量。中间候选曾整段保留
    core `.rodata`，使 Group A 链接超 RAM；修后正常，未扩大设备内存。
- 完整 B-1 交付与版本证据：LLVM 最终重建、定制 rustc 重链、匹配 core/builtins
  构建完成。compiler 为 `20261022-180241-07b9d869`；候选 bundle
  `20261022-180241-07b9d869-d8aeb468` 已验证。工作期间目录中的 active 被其他
  发布操作切至 `20261022-180241-07b9d869-83f8a0e3`，未覆盖该切换：逐项比较
  compiler 清单和六项 sysroot 文件，SHA-256 全相同，再在当前 active 重跑
  Group A 与静态指针并通过。Cargo 按当前 active pin 重建并继续核验。
- 硬件结果（RAM/JTAG，无 Flash）：
  - 当前 active Group A：`140,54,65,245,212,223,179`，明确 PASS。
  - 当前 active 静态指针：8 个 ABS32；函数/外部数据/本地/奇数字节字段分别
    `65536,65934,65940,65935`，全部等于期望；Rust volatile 解引用
    `4660,43981,18`，明确 PASS。不把字段检查等同于间接调用 ABI 验收。
  - 同二进制候选 E 16/16、C=`132,179`、D=`42967,179`，全部明确 PASS。
  - 同二进制候选 Cargo 独立=`7,13,20`，跨 crate=`23,40,19,20,82,178`，
    均 PASS；direct 输入/rlib 成员为 3/2、4/3，Rust `.s` 数量 0，两个
    provenance 的 11/12 个 inputs 均存在且 hash 匹配。当前 active 的最后一轮
    Cargo 硬件核验结果在后续条目补齐。
- 其他验证：共享 LLVM/MC 和 TI link 回归 PASS，ABI freeze 扫描 204 文件 PASS，
  发布清单/锁/原子指针/缓存正负向测试 PASS。GNU host 测试先为 13/13；目录另有
  B/B2 拆分修改后重编当前源码为 14/14 PASS。首次漏传 edition、随后默认 MSVC
  缺 link.exe，均为 host 命令配置失败；改用 GNU nightly 的 self-contained GCC/ld
  后成功。未改 Windows SDK，也未把主机结果当作硬件验证。
- 失败/边界：XDS 初期 load 超时，恢复后多次 trace 成功；用户确认供电/JTAG 正常。
  最终静态回归有一次 FTDI -151 连接失败，xds100serial 仍列出 TI1P9CM8，重试 PASS。
  当前目录另有 B/B2 拆分工作，本轮不认领该改动；B 可链接（`.text` 0x194e、
  程序 RAM 用 0x1ac4），但硬件命中入口后 run 60s 超时，没有 PASS。发现 B 的 DSS
  仍写旧总和 170，已同步为当前 host Rust 的 80；未因修改期望值而记作通过。
  B2 未上板。ABI 仅重做 BuildOnly PASS，历史 rust_apply 返回地址故障未关闭。
  符号差/相对数据 fixup、跨 crate 静态表、weak/COMDAT、全部归档矩阵仍待验。
- 文档：更新 PATH_B 当前 active、修复机制、文件入口、验收表与待办；旧日志保留，
  在当前说明中明确撤销 sret 推断。修复/构建/硬件证据保存在 B-1
  `build/fix-static-iter/`；本记录补全此前“进行中”记录的实际结果。

### 同轮收尾：当前 active 的 Cargo 与 B2 构建

- 当前 active `20261022-180241-07b9d869-83f8a0e3` 的独立与跨 crate Cargo
  在新 target-dir 重新编译并 RAM/JTAG PASS，读回仍为 `7,13,20` 与
  `23,40,19,20,82,178`。Rust `.s` 数量 0；两份 schema 2/direct provenance
  均绑定当前 active，11/12 个 inputs 全存在且 SHA-256 匹配。
- 当前 active 的 Group B2 BuildOnly PASS：`.text` 0x1a5c，程序 RAM 总用量
  0x1c72，剩余 0x38e；未上板。B 的 60s 运行超时与 ABI 遗留故障保持开放。
- 当前源码 GNU host 14/14 PASS。单 crate Cargo 本轮未另行重建；Safe HAL/layer
  本轮未重新上板。未执行 Flash；未将这些历史或未运行项目写作新 PASS。

## 2026-10-22 傍晚：静态地址重定位上板闭环 + 证据矩阵补齐

- **静态地址重定位（P0 #1）闭环**：后端 `C28xAsmBackend.cpp`（用户 17:52 的改动）已把
  `FK_Data_1/2/4` 映射到 TI 的 R_C28X_ABS8/16/32，并在 `applyFixup` 里为 SHF_ALLOC 段
  的 32 位指针字段写两条 ABS32 重定位（S+(S+A)=2S+A），把 Rust 逻辑字节地址还原出来；
  ABS22 的 `Value>>1` 修正也一并生效。
  - 对象级：`external-static.rs` 由 0 条重定位变为 12 条；`.rodata.DATA_PTR` 字段内容
    = 0x00000002（+2 字节加数），配 2 条 R_C28X_ABS32。
  - 链接级：ofd2000 解出的镜像 `.rodata` 为 TABLE=[0x100F4,0x101D8]、DATA=[7,11,13]、
    DATA_PTR=0x101BA —— 全部非零且指向真实符号（含加数）。
  - **真机级**：新增 `test/Rust/b1-hw-static.rs` + `tools/hw_b1_static_driver.c` +
    `tools/dss-read-b1-static.js` + b1 `tools/run-hw-rustc-direct-static.ps1`；
    `STATIC_RESULTS=16,13,11,12,21,40,11,92` PASS（Rust 经表调用、C 经表调用、
    Rust 经 DATA_PTR 读、C 经 DATA_PTR 读全部正确）。
  - 驱动侧互操作约定（新增踩坑）：Rust 指针是逻辑字节地址，TI C 的函数/数据指针是
    字地址；C 侧从表里取出指针后必须 `>>1` 再调用/解引用（与 ABI 样板里 C→Rust 的
    `*2ul` 互为镜像）。`use_table`/`use_ref` 会被常量折叠成直接调用，所以表项真正
    被使用的地方是 C 驱动。
- **证据矩阵补齐（本轮真机）**：control `23,40,19,20,82,178` PASS；Safe HAL
  `0,0,0,4,7595,178` PASS；分层探针 13/13 OK；Group C `132` PASS；Group D
  `42967` PASS；Group E 16/16 PASS；Group A `140,54,65,245,212,148,179`（pattern 仍 148）；
  Group B 仍因 `.text` 0x2294 > RAM 0x2000 构建失败；ABI 样板仍 PC=0x3FF599 跑飞。
- **新缺陷（4 参调用 ACC 被冲）**：`Iter::new` 的 ub-check 路径
  `precondition_check(ptr %p, i32 %n, i32 2, ptr @alloc)` 生成码先把 `%n` 装入 ACC，
  随后把 `%p` 也装入 ACC 再 `MOVL XAR4, ACC`，`%n` 被冲掉；同时 `@alloc` 地址发成
  `MOVL XAR5,#0`（静态地址零值，已被本轮重定位修复覆盖）。这正是
  `-Zub-checks=on` 时 `core_ex_pattern` 误报 panic 的根因；`-Zub-checks=no` 只是
  绕开。已在 llc -O0 用 20 行 IR 精确复现（`Iter::new` 形状），待修。
- **ABI 样板仍卡在 `rust_apply`**：入口寄存器全对（ptr/mixed/栈参），但该函数
  （1 字 ADDB 帧 + 内部 32 位 push/pop + `LCR *XAR7`）的 LRETR 取到栈参字当返回地址，
  跳飞 boot ROM。已排除：LCR/MOVL 编码与 TI 逐位一致；驱动参数构造正确；三处调用点
  SP 均为 538（无漂移）；`rust_apply` 内部 SP 账目自洽。剩余疑点是该形状下直接 LCR
  的 RPC 落点与尾声期望不一致，需结合 C28x 栈语义继续。
- 未运行：Flash、Group B 拆分（依赖 sret/LRETR 修复后再做才有意义）。

## 2026-10-26 算术运行库与复杂调用修复（进行中）

- 用户授权推进动态整数除/余、f32 软浮点和四参/rust_apply 调用缺陷。当前 active
  `20261022-180241-07b9d869-83f8a0e3`。此前最小探针已证实对象编译成功但 TI link
  缺 `__udivsi3/__umodsi3/__addsf3/__mulsf3/__divsf3`，不是 Rust 语法问题。
- 新增 TI 编译的算术入口适配源码 `crates/c28x-compiler-builtins/ti-arithmetic.c`，
  用真实 C 包装让 cl2000 处理内部 RTS helper ABI，避免未经验证的符号别名。
  新增 `call-four-args.ll` 作为 count/ptr/栈参共存的复现；仍在定位，未记录修复成功。
- 本轮 XDS100 枚举为空，已异步请用户连接并供电；编译/链接和后端定位继续。
  未执行 Flash，尚无新增硬件 PASS。过程产物位于 B-1 `build/audit-20261026/`。

## 2026-10-26 续：运行库边界与复杂调用根因（候选验证中）

- 用户确认 XDS100 已连接并供电，实际枚举 TI1P9CM8。本轮恢复 RAM/JTAG，未执行 Flash。
- 首个 TI C 包装版本：整数除/余和普通 f32 正确，但舍入、负零、无穷、次正规数、NaN 共七项失败。
  因此不能直接采用 TI softlib 的浮点语义。ti-arithmetic.c 改为纯整数 IEEE binary32 四则运算，
  nearest-even、渐进下溢、signed zero、Inf/NaN 均有独立检查；主机 1,001,024 次差分通过，
  bundle 20261026-094827-4e53441b-24cfcace 的 32 项算术/四参真机测试通过。
- runtime C 对象进入 libcompiler_builtins.rlib，另保留版本绑定的 ti-arithmetic.o；清单记录
  C 源码、参数、cl2000 与 TI RTS 哈希。读取 bundle 拒绝未入清单的 runtime、被替换的 TI RTS；
  fake 目录负向门禁通过，旧无 runtime 的 bundle 仍可校验。
- 复杂调用修正：完整 callee-saved XAR1/XAR2/XAR3，LCR caller-clobber 列表和寄存器 mask；
  全宽 PUSH32/POP32 由 TI 汇编独立确认编码；栈帧/调用参数区保证 SP 偶数，32 位栈参两字对齐；
  AR0 scratch 改保完整 XAR0；FI reload 在四参设置时保护 live ACC。
- 过程失败如实保留：第一候选 ABI 能返回但结果 1041/1041/42；简单删除 SPAdj 后 sret 又失败。
  根因是 LLVM 23 默认反向消除 FI，而本后端按前缀扫描栈变化；改为正向处理并仅用 SPAdj
  计调用区，新 select 基本块继承调用帧大小。之后 ABI 为 33/29/90；AH 中的 c 仅在偶数后继
  存活，原块内活跃性扫描漏掉它。补全半寄存器与后继活跃性后，诊断对象 ABI 十项全对。
- 独立 llc 诊断未开 function-sections 的映像曾在首次断点超时；开 function-sections 后通过；
  此结果仅作定位证据，正式 B-1 rustc bundle 的最终结果另记，不混作发布验收。
- 新回归 call-four-args.ll/call-stack-select.ll，O0/O2 + verifier；新增 Iter::new 形状还暴露
  变量移位保存未定义 ACC 的问题，改为只保护实际 live-through ACC。MC 偶数栈帧等字节基线
  已按有意 ABI 改动更新；TI oracle 独立核对 XAR0–3 PUSH/POP。ABS22/静态指针 TI 链接回归、
  ABI freeze PASS。正式 rustc 再重链，active 仍为 20261022-180241-07b9d869-83f8a0e3。
## 2026-10-26 收尾：算术/调用正式 B-1 bundle 发布及 RAM/JTAG 闭环

- active 已切换到 `20261026-102923-989317a3-fcd36edb`（compiler `20261026-102923-989317a3`），
  rustc、driver DLL、core、Rust builtins 和 TI arithmetic 对象同一版本发布，根/子项目 Cargo pin
  及 target-dir 同步。旧 active 未直接覆盖，可用于回退。最终源码未再修改 C++ 语义。
- 追加发现并修复 O0 signed division：前 16 项正确，`i32::MIN / 1` 却进入 overflow panic，
  停在 PC=35955。独立 llc O0 verifier 暴露 -1 的 ACCOnly 与已占 ACC 比较操作数冲突（Fast RA
  ran out of registers）；不把这种对象编译成功当语义通过。负 i32 常量改为可选宽寄存器 pseudo，
  新增 negative-compare.ll O0/O2 回归；最终正式 rustc 的 MIN/1、signed 除余均真机正确。
- 正式 bundle RAM/JTAG：ABI 十项 `21845,4660,61,42,21,33,32,90,171,305419896` PASS；
  动态算术/四参 O0 和 Os 各 32 项 PASS（含 u32/i32 除余、f32 四则、ties-even、负零、Inf、
  次正规数、NaN、两组 count 的指针四参调用）。DSS runner 必须检查显式 PASS；算术脚本改为
  超时也读回 PC 与部分结果，避免只得到空泛 timeout。
- Cargo 新增 c28x-cargo-arithmetic，直接共用 Rust/C 测试源。首次 Cargo 构建因源文件缺
  no_main 失败，补齐后通过。config 中不手动列出 ti-arithmetic.o；来自 libcompiler_builtins.rlib
  的第三个对象成员由现有 adapter 自动解包。当前 active 的普通 Cargo pin（无候选环境覆盖）
  下算术 32 项、独立 7/13/20、跨 crate 23/40/19/20/82/178，三组 RAM/JTAG PASS。
  Rust .s 数量 0；6 份 provenance 的 74 条留存 inputs 均存在且 SHA-256 匹配，均含版本化
  runtime 成员。C/ASM 原始源码、工具及完整 link argv 的 provenance 仍是旧待办。
- core A 默认 PASS：140/54/65/245/212/223/179；E 16/16 PASS；静态函数/数据指针
  16/13/11/12/21/40/11/92 PASS。core-ex 直接链接增加 bundle ArithmeticObject，并纳入 link
  cache 输入。纠正 -WithUbChecks：原来仅省略 -Zub-checks=no，并不保证优化构建开启检查；
  现在显式 yes/no。真实 -Zub-checks=yes 的 A BuildOnly + RAM/JTAG PASS，pattern=223，map
  含 precondition_check/runtime_add_nowrap；程序 RAM 用量 0x13b4/0x2000。
- 仍失败：当前 active 的 B BuildOnly PASS，真机能到结束但结果 11191/179，期望80/179；
  B2 BuildOnly PASS，命中入口 PC=34256 后 run 60s 超时。独立记录为迭代器适配器遗留缺陷，
  不用基础调用修复将其关闭。无 function-sections 的独立 llc 同段调用诊断也仍未闭环。
- 离线：MC 全回归、四参/Iter::new/跨块调用帧/负数比较 O0/O2 verifier、TI PUSH/POP oracle、
  ABI freeze、ABS22 与静态地址 TI link、发布清单/RTS 交换/未绑定 runtime/缓存负向测试均 PASS。
  浮点主机差分 1,001,024 次 PASS；ABI Rust host 1/1 PASS。C/D、Safe HAL/layer 本轮新 bundle
  未重新上板；未执行 Flash。f32 比较/转换、f64/数学函数、跨 TI C/Rust 聚合 sret、通用 host
  build.rs/proc-macro、更多归档/重定位、Cargo 外部输入自动重链等仍未完成。
- docs/PATH_B.md 当前说明、工具文件表、active、验收矩阵、复现命令及待办已同步；
  旧 2026-10-22 矩阵明确为历史。全部本轮过程与最终日志在 B-1 build/audit-20261026/。
## 2026-10-26：复杂迭代器 B/B2 根因定位（B 已闭环，B2 定位到 memcpy 约定）

### 根因 1：`ADD/SUB ACC,#16bit` 零扩展负立即数（已修，硬件验证）

- 现象：Group B `11191,179`（期望 `80,179`）；Group B2 命中入口后 run 超时。
- 定位路径：用 `tools/iter-probe` 把 B/B2 拆成逐项 `extern "C"` 入口真机读回，
  得到 `plain_sum=36767`、`count=1154`、`nth=29576`、`last=32941`，而 `any/find`
  偶然正确（提前退出）→ 说明迭代器**边界**错而不是元素读错。
- 决定性证据：parts3 显示 `slice_len=2048`、`rust_ptr_word=2` —— 驱动把
  `(unsigned long ptr, unsigned len)` 声明成整数，TI 按位置把 32 位放 ACC、
  16 位放 XAR4，而本后端按**类别**分配（指针→XAR4/XAR5，i16→AL/AH），
  两侧约定交叉，callee 读到 ptr=4、len=0x800。B/B2 驱动已改为 C 指针声明
  （与 `hw_rust_control_driver.c` 一致）。
- 第二层：修好声明后仍有 `last()`/`rev()`/`skip(1)` 错。parts4/parts7 定位到
  `slice::Iter::next_back` 的 `end.sub(1)`：生成码是 `ADD ACC,#0xFFFE`，
  而该指令**零扩展**立即数（asm2000 编码一致，硬件实测 `0x0808+0xFFFE=0x0001_0806`），
  残留的 `1<<16` 经字节→字 `>>1` 后得到字地址 `0x8403`（应 `0x0403`），
  于是读到了代码区。
- 修复：`C28xInstrInfo.cpp` 的 `ADD32imm32/SUB32imm32` 展开在 `Val < 0` 时
  翻转运算并取绝对值；`C28xMCCodeEmitter.cpp` 保留同样的防御性翻转（保持两字长度）。
  新增 `test/CodeGen/sub32imm.ll` + `verify-llvm-c28x.ps1` 字节 oracle。
- 链条：sync-and-build → build-rustc-c28x（候选 `20261026-111852-ee98b5b1`）
  → rebuild-core-sysroot → bundle `20261026-111852-ee98b5b1-232da1ac`（active）。
- **真机结果**：Group B `80,179` **PASS**；Group B2 由超时变为 `72,179`
  （enumerate/fold 40 ✓、rev/copied/sum 20 ✓、zip 12 ✗）。

### 根因 2：`llvm.memcpy` → TI RTS `memcpy`，地址约定不一致（已定位，未修）

- 拆分验证：`skip(1)` 单独 18 ✓、`zip(iter,iter)` 40 ✓、手写 while-let 配对 30 ✓，
  只有 `zip(iter, iter.skip(1))` 错（首对 b=0，第二对 b=0x41F）→ 问题在
  `ZipImpl::new`（`sret 28B + ptr + ptr + ptr`，第三个指针走栈）。
- 零 core 代码的最小复现（`tools/iter-probe/parts13.rs`，纯 `#[repr(C)]`）：
  寄存器指针 ✓、sret 返回 ✓、3 个标量 ✓、**两个栈上指针** ✓，
  但 `&B12`（12 字节）被 memcpy 拷进返回值后字段全错（`b.p`=0 应 0x101、
  `b.e`=8 应 0x202、`b.n`=59915 应 1）。
- 原因：`pr_mk_zip2` 的 IR 就是一句 `llvm.memcpy` 12 字节，llc 把它降级成
  `lcr memcpy` —— TI RTS 例程按 **C 字地址**解引用，而 Rust ABI 传**逻辑字节地址**，
  于是拷贝源/目的都偏到别处。`findOptimalMemOpLowering` 在本目标上总是失败
  （因此每个 ≥4 字节的内存聚合体拷贝都走 libcall）。
- 已加前置项：`C28xTargetLowering::allowsMisalignedMemoryAccesses` 对 i16/i32
  在 align≥2 时返回 true（此前基类恒 false）。单独不足以让 memcpy 内联，
  仍需覆写 `findOptimalMemOpLowering` 或改名到 `c28x_memcpy` + shim。
  回归 `verify-llvm-c28x.ps1` 在加该覆写后仍全绿、无字节漂移。
- 影响面：所有依赖内存聚合体拷贝的 core 路径（Zip/Skip、含大结构体的适配器、
  切片整体拷贝）都不可信，属 P0。

### 附带发现

- B/B2 驱动把 Rust 指针参数声明成 `unsigned long` 是错的（见根因 1 第一层）；
  已在两个驱动里加注释说明必须声明为 C 指针。
- 探针套件已固化到 `f28035-rust-bridge-b1/tools/iter-probe/`（parts1–13 + 驱动 +
  DSS 脚本 + build.ps1 + README），可直接复用来做后续迭代器/ABI 回归。

## 2026-10-26：更新当前路线文档并继续缺陷审计（133307 bundle）

- 用户要求“更新文档，也查找问题”。本轮只修改 docs/PATH_B.md、追加本工作日志及隔离审计
  目录；没有修后端/正式 Cargo 配置/运行库，没有切换 active，没有执行 Flash。读取并校验
  active `20261026-133307-567620e7-138e5153`，根 Cargo pin 与其一致。旧 102923 验收矩阵
  改为明确历史，维护记录和 §4/§6/§7 同步；过去日志不重写。
- 发现文档落后于源码：当前后端已有 findOptimalMemOpLowering 回退、16 次 store 内联预算和
  动态内存调用的指针右移适配，不应再写“所有 >=4B 复制都未修”。标准 direct core-ex B/B2
  在本轮用当前 bundle 再 RAM/JTAG：B=80/179、B2=90/179，显式 PASS。关闭这两个旧故障；
  当前代码已有修复，本轮未为取得 PASS 修改后端/驱动。
- 隔离目录 B-1 build/audit-doc-review-20261026-0b4e62f2/ 保存 check.ps1、report.json 和
  Cargo JSON 日志。默认→alternate→默认实测：默认 SHA B2A4F4DB1D6E…，alternate SHA
  33C6C8E872DF…；第三次 Cargo fresh=true，正式 artifact 恢复默认，而 independent.out
  alias 仍是 alternate。正式 verify-cargo-direct-hw.ps1 读取 alias 且只检查存在，存在选错
  features 映像的真实问题；不是仅凭猜测记录。
- 同一隔离 Cargo 分别传不存在的 does-not-exist.a 与未知 --c28x-audit-option-that-must-be-rejected，
  均 exit=0。c28x-ti-linker.ps1 只收集 o/obj/rlib，原生归档与未知参数被忽略，已实测确认。
- 新增最小动态 copy_nonoverlapping::<u8> 入口后，正常 Cargo 构建 exit=101，TI link 缺
  __muldi3（首次引用 core-cgu.0.rcgu.o）。未把失败时残留的旧 alias 当成新可运行映像。
  map 已见 Rust builtins 的 memcpy。direct core-ex 额外链接 di64，普通 bundle/Cargo 无此
  运行库闭包，故两条路线结果不同。
- 为分离后续问题，只在隔离 config.tiObjects 添加用同一 bundle 从现有 di64 源新编的 di64.o，
  未写入正式 bundle。此后链接通过；memory.s 中 audit_copy 对 XAR4/XAR5 各右移 1 后
  LCR memcpy；map 的 .text.memcpy 来自 builtins-cgu.0.rcgu.o，而其 Rust 定义使用逻辑字节地址。
  RAM/JTAG PC=DONE=32919，读回 7/13/20/61166/56797/513/1027/41245：动态复制3字节后
  dst 仍 EEEE/DDDD，应为0201/DD03；src和marker正确。DSS虽exit0但有异常且无PASS，按
  真实读回记 FAIL。memory-hw.log/memory-symbol-provider.txt/memory.s 保存证据。
- 静态确认但本轮未新增上板复现：未解析分支警告后写零；非fixed局部FI距离<=0时钳为1；
  P>>1丢失奇数字节lane及内存函数返回指针缺统一适配；rlib同名成员/无锁共享解包目录；
  发布最小cmp对象冒烟后即可激活，未强制语义门禁；provenance遗漏C/ASM/头文件、工具、
  完整argv及alias绑定。按源码缺陷/风险分别登记，不称全部已复现。
- 进一步核实 current bundle 的 builtinsArgs：无显式opt-level及ub-checks开关；core显式
  ub-checks=no。动态复制map确实带入checked_mul、runtime_add_nowrap、检查/格式化闭包。
  release应用不会重新优化预编sysroot，优化/检查策略和运行库闭包需要统一；未据此关闭检查。
- 上轮外部C/ASM/cmd Fresh缺陷的8步报告仍保留在 audit-cargo-external-inputs-20261026-3a8c317d/。
  本轮summary.json对本轮features哈希、缺失库/未知参数exit、缺helper文本及RAM读回做断言核对。
  Markdown代码围栏成对、相对文件链接均存在。未声称其他f32/ABI/Flash/中断/通用host能力完成。

## 2026-10-26：Cargo 外部输入自动重链与逐文件 TI 缓存

- 用户要求优化外部 C/ASM/`.cmd` 变化检测，并明确避免全量重建。本轮只处理 B-1
  Cargo/原生增量构建；固定发布包 `20261026-133307-567620e7-72ab049d`，未重链
  定制 rustc、未重编 core/builtins、未发布新 bundle、未运行 JTAG/Flash。
- 新增 tools/cargo-native-build.rs/.ps1 作为三个应用 manifest 的共享 build script。
  通过 Cargo rerun-if-changed 登记配置、原生源、实际头文件、汇编包含文件、cmd
  字面量 #include、显式 tiObjects、runtime 与相关工具/脚本，跟踪 C2000_C_OPTION/C_DIR。
  新项目需接入该 build script；宏化/间接命令输入使用 extraDependencies 显式登记。
- 新增 cargo-native-cache.ps1，由 build script 和 c28x-ti-linker.ps1 共用。
  TI C 使用 --preproc_dependency + --preproc_with_compile；ASM 的 --asm_dependency
  只生成依赖，需单独进行实际汇编。缓存逐源比较工具组件、编译参数、环境、源与
  包含文件内容以及对象哈希；互斥锁保护读写，成功后才发布对象/状态。仅变化对象
  重编，cmd/Rust-only 变化复用 TI 对象。新增 tiIncludePaths/tiDefines 配置字段。
- linker provenance 升到 schema 3，增加 nativeObjects 的源/包含文件哈希和
  nativeCompileIdentity；保留原有字段。完整 link argv 和固定 .out alias 消费问题
  不在本轮关闭范围，rlib 解包缓存的竞争也未在本轮修复。
- 首轮真实 build script 编译失败，报 MSVC link.exe 不存在。活动 rustc-wrapper.rs/.exe
  的 host 分支改走本机原版 GNU nightly-2026-09-14 及其 self-contained GCC；C28x
  分支仍经 invoke-b1-rustc.ps1 校验精确发布包。新增 build-rustc-wrapper.ps1 便于重建。
  此次只验收无外部 Rust 依赖的共享 host 脚本，不宣称通用 proc-macro/host 依赖兼容。
- 过程纠错：TI dependency 中的绝对路径不能再用 PowerShell Join-Path 拼到项目根，
  已改为识别绝对路径；按 TI 实际输出处理带空格路径。首个隔离回归发现监控生成的
  cache object 会造成下一次无变化构建冗余重链，已移除生成对象的 rerun 依赖，
  只跟踪输入（实际 native preparation/link 时仍校验缓存）。第二轮第 8 步仅 map
  断言错误：绝对符号使用 abs 列，不是 page 0/1；实际 map 已有 0x1358，断言修正。
  失败证据保留在 verify-native-incremental-ee0ec394/ 和 f96dc38e/，未改写旧报告。
- 最终 tools/verify-cargo-native-incremental.ps1 十步全部 PASS，证据
  B-1 build/verify-native-incremental-a5dffc8d/（report.json、每步 Cargo JSON/诊断、map）。
  初始构建 66.552 秒；未变 0.399 秒；C 改动 25.147 秒；嵌套头文件 25.875 秒；
  ASM 24.643 秒；ASM include 23.367 秒；cmd 21.854 秒；cmd include 21.155 秒；
  Rust-only 15.827 秒；最终未变 0.294 秒。变更步骤依赖 crate 始终 Fresh；按对象
  mtime/SHA 断言 C/ASM 只更新受影响对象，cmd/Rust-only 不重编原生对象；嵌套 cmd
  map 明确更新符号值。最终应用 crate 仍会调用 rustc 完成链接，不承诺纯 linker 调用。
- 正式 independent、app --features cross-crate、arithmetic 均 cargo build --release
  --target c28x-none-elf 成功，随后同配置再次构建均 Fresh；日志及摘要在 B-1
  build/native-incremental-c28x-cargo-*.log 和 native-incremental-samples.json。
  五个相关 PowerShell 脚本语法解析通过。主 PATH_B 当前说明、维护记录、工具表、
  问题表及 B-1 README/既有接入说明同步更新。本轮结果为离线构建增量语义验证，
  不增加任何目标运行正确性/真机 PASS。

## 2026-10-26：内存函数发布、462 项 Cargo 真机验收与 TI 初始化补齐

- 用户要求把独立 c28x_* 内存接口推进到发布包、Cargo 和真机，并继续优化。本轮仅
  处理 B-1。旧 active 为 20261026-133307-567620e7-72ab049d；最终激活
  20261026-175437-71a923aa-79cdbc37，compiler 为 20261026-175437-71a923aa。
  包位于 D:\c28x-toolchain\b1-toolchains，默认 C 盘 active/candidate 与 Cargo pins
  及 D 盘 active 均同步。未执行 Flash；全部硬件证据来自 F28035 RAM/JTAG。
- 前置恢复：发现上次全 LLVM 构建的 llvm-debuginfo-analyzer 因 SDNode::print 未解析
  失败，并遗留无父进程、CPU=0 的 bootstrap cargo 16776。核实完整命令行及孤立状态
  后结束该进程，发布锁随后释放。仅构建 llc/llvm-config/llvm-ar/llvm-objdump，249 项
  必要增量构建成功；未把与目标无关的全工具构建失败当作本轮目标后端成功。
- C 盘由约 100 MB 耗尽至 0，首次新补丁脚本写入失败并留空文件；恢复空间后重写完整
  脚本。三份明确的旧诊断备份 130628/132836/173708 逐文件复制到 D 盘并核对 SHA，
  再移除 C 盘已校验副本，释放约 670 MB；转存表在 preserved-old-backups/transfer.json。
  未删除源码或活动发布包。新增 rebuild-core-sysroot.ps1 -OutputRoot 支持 D 盘重型缓存。
- 新增 patch-llvm-c28x-memory-libcalls.ps1，sync-and-build 在构建前确保五个非默认
  RuntimeLibcalls.td 声明可重现；不得 IsDefault=true，避免污染 x86 等宿主目标。
  LLVM 门禁改检验 c28x_*，运行期 copy 不再右移指针；memset fixture 填充值按 i8。
  定制 rustc 重链、清 PATH/DLL/对象探针及候选发布通过；core 与 builtins 由该 compiler
  重建。后续两轮仅运行库改变，core/算术步骤正确复用，未重复重链 rustc。
- 第一候选 e6c748b1：符号与链接门禁通过，但真机复制 1 字节停住。map/反汇编定位到
  builtins .add 引入的 checked_mul/runtime_add_nowrap/前置检查及格式化路径。运行库
  改用 wrapping_add：有效缓冲区与 memcpy 不重叠的 unsafe 契约保持，底层实现不依赖
  该 core 检查路径；未全局关闭 UB checks。后续 builtins-dual.o 无任何未定义符号。
- 第二候选 c243c683：copy 48、move 192 项通过，fill 组写坏结果。对照 SelectionDAG
  源码、wrapper 汇编和 C28x 寄存器分配确认 llvm.memset 传 i8，而运行库误声明 i32，
  使长度/填充值错位。将私有 c28x_memset 改为 (*mut u8,u8,usize)->*mut u8，直接调用
  原型及 CodeGen fixture 同步；TI 普通 memset 原型/字地址语义不变。第三候选 79cdbc37
  的 fill 72 项（0/A5/FF）及四组内存均通过。
- TI 共存第 5 组保留真实非零静态函数指针并强制间接调用，最初跑进 Boot ROM。
  map 证实其 .data 为 UNINITIALIZED，初值放在 .cinit，而现有 RAM startup 没有执行
  TI 初始化。asm.s 在 main 前调用 __TI_auto_init，使用 TI RTS 的普通字地址内存
  helper 处理 ROM-model copy/zero records。未改成测试内手工初始化来绕过问题。
  随后完整重跑五组：copy 48、move 192、fill 72、memcmp/bcmp 144、TI 共存 6，共
  462 项 RAM/JTAG 全 PASS，PC=hw_done，错误数为 0、完成标记正确。
- 新增 b1-hw-memory.rs、hw_b1_memory_driver.c、dss-read-b1-memory.js 和 B-1
  verify-cargo-memory.ps1。测试用正常 Cargo .o/.rlib，未注入额外 di64 或 builtins
  对象；map 提供者为解包的 Rust builtins 或对应 TI RTS。覆盖 0/1/3/7/33/67 长度、
  src/dst 奇偶 byte lane、双向重叠与自移动、返回指针、完整哨兵和比较符号。
  按 Cargo compiler-artifact JSON 与 SHA 选映像，不依赖固定 .out alias。
- direct core/ABI 补齐同 bundle builtins/算术闭包，移除 core-ex 另编 di64。首次
  direct core A link 缺 __c28xabi_mpyll，确认算术对象放在 RTS 归档之后；改为所有
  普通对象先于 RTS。构建通过后全部重新上板：A=140/54/65/245/212/223/179，
  B=80/179，B2=90/179，ABI=21845/4660/61/42/21/33/32/90/171/305419896，显式 PASS。
- 三个标准 Cargo 项目重新构建后按 artifact/SHA 上板：independent=7/13/20，
  cross-crate control=23/40/19/20/82/178，arithmetic 32 项（含 NaN）均 PASS。
  新包内存 libcall/链接、di3、f32 比较转换、LLVM MC、ABI freeze、发布负向门禁均通过。
  旧 72ab049d 用同一内存门禁按预期因缺 c28x_memcpy 调用被拒绝。
- 验收后才切 active；源/清单哈希、五组内存、core/ABI 与三个 Cargo 的 PASS 标记在
  激活前逐项核对。清除测试环境覆盖后，默认配置三个 cargo build 与再次 Fresh 通过。
  此过程中发现 PowerShell 7/.NET 将 API 的 null 恢复成空环境值，导致测试清理后
  CARGO_TARGET_DIR 为空。两个回归脚本及 build-rustc 的 finally 改为：原本不存在的
  变量用 Remove-Item Env: 精确删除，原有值仍恢复；保留 default-env-empty-failure.log。
- 跨盘工程使用 C 盘源码/命令文件及 TI include，补齐 adapter/native helper 对绝对路径
  的解析；普通相对路径三个样板也通过。启动源码仍为外部原生输入，由增量跟踪与
  provenance 绑定；bundle 本身保持不可变。
- 所有过程/最终证据根目录 D:\c28x-toolchain\b1-memory-release-20261026：
  acceptance.json、activation-before/after.json、cargo-memory-cinit/report.json、五组
  build/hw/map、core-A/B/B2-hw.log、abi-hw.log、standard-cargo-hw.json、default-cargo.json
  以及 final-verify-*.log。e6/c243/补 cinit 前失败证据保留在各独立目录，不覆盖旧报告。
- 主 PATH_B 当前版本、工具表、验收矩阵、问题表与历史记录校准；memory model、runtime
  README 和既有 Cargo 接入说明同步。不关闭未解析分支/异常栈偏移、固定 alias、未知
  链接参数、归档并发、通用 host/proc-macro、任意长度/地址/packed 数据、Flash 和
  全部 core UB 检查等独立问题；本轮手动验收不等同于已经实现未来发布的强制门禁。

- 收尾复核：激活后的 79cdbc37 再跑完整十步 native-incremental-final，全 PASS。
  初始 36.946 秒；Fresh 0.263 秒；C 14.732、嵌套头 15.089、ASM 14.903、ASM include
  13.831、cmd 13.415、cmd include 13.244、Rust-only 10.735 秒；最终 Fresh 0.249 秒。
  依赖始终 Fresh，对象 mtime/SHA 断言通过；此为不同负载与 D 盘缓存下的本机测量，
  不作单因素性能归因。environment-restore-probe 实际运行 BuildOnly 后确认所有原本
  未定义的测试环境变量仍未定义；不覆盖 462 项 hardware=PASS 的最终报告。
  13 个相关 PowerShell 脚本语法检查、文档围栏检查通过；单独用同一 LLVM 的 x86
  后端确认仍调用普通 memcpy，不出现 c28x_*，输出保留 host-memory.s。

## 2026-10-27：B-1 关闭危险兜底、修复 trap 自循环并发布

- 用户指定关闭未解析分支写零、异常栈偏移钳成 1 的两处兜底。本轮开始时两处
  源码已改为 report_fatal_error，但文档仍标待重链，active 仍为 79cdbc37；继续
  完成可重复负向测试、真正的 core 重建、根因修复、发布与验收，未处理 PATH A。
- applyFixup 在 FK_C28x_BRANCH 未解析时明确拒绝，诊断目标及所在 section；
  普通外部函数仍走已有 LCR/ABS22 重定位。不新增不可靠的 PC 相对重定位。
  eliminateFrameIndex 对非 fixed 局部对象 DeltaFromSP<=0 拒绝，报函数/FI/
  偏移/栈大小/delta，不再篡改地址。当前不支持的 one-past/零大小对象地址形式
  也可能明确失败，未宣称已实现任意栈地址物化。
- 新增 branch-unresolved.mir（合法 MBB 跨 section）、frame-offset-invalid.mir
  （负距离）、frame-offset-zero.mir（零距离）并接入 verify-llvm-c28x。
  构造外部 B 的第一版 MIR 在机器分支分析阶段触发 isMBB assertion，不能算
  正确拒绝；改成有效跨 section CFG 后确认到达 MC 并报预期错误。
- 首候选 20261027-111452-b4251479 重建完整 core 实际失败：未解析目标为无名
  temporary，并非“所有兜底触发都已不可达”。导出 core.ll 用同一 LLVM 定位到
  TRAP 的旧展开 B_JMP &MBB：入口块可能没有发出标签，而且会重复执行块内
  副作用/序言。改为真实 B_SELF 指令，编码为 FFEF/0000，无符号或 fixup，
  在 trap 指令自身循环。保留 core-first-failure.log 和诊断输出，未恢复写零。
- 新增 trap.ll 精确对象字节回归。TI 直接 B $,UNC 会优化为短 SB，故独立
  oracle 先汇编外部目标、再用 TI linker 绑定到分支自身，验证长指令确为
  efff0000。中途 oracle 长/短编码误判已纠正，最终门禁通过。
- 新增 b1-failclosed.rs 和 verify-b1-failclosed.ps1，验证实际发布 rustc 的
  正常对象、trap 自循环、basic-block-sections 跨段分支拒绝，拒绝 exit 非零且
  无输出对象。旧 79cdbc37 被此门禁按预期拒绝（缺指令自身 trap 循环）。
- 最终 LLVM/rustc 重链，完整 core/builtins/TI 算术对象重新绑定，发布
  D:\c28x-toolchain\b1-toolchains\bundles\20261027-112248-a1cf84ab-2e7ec64c。
  compiler 为 20261027-112248-a1cf84ab；bundle manifest SHA-256 为
  6C217C74019681BAEA70B77E25B376CE5DC0FF5F4DD10918F0410F6E9B221F74。
- LLVM MC、TI 调用/六种静态指针链接、内存 helper 符号/链接、ABI freeze、
  发布清单/锁/指针/缓存负向门禁均 PASS。新候选先完成真机验收再激活：
  Cargo 内存/TI 共存五组 48/192/72/144/6 共 462 项 PASS；core A 为
  140/54/65/245/212/223/179，B 为 80/179，B2 为 90/179；ABI 十项为
  21845/4660/61/42/21/33/32/90/171/305419896，均有显式 PASS 与完成 PC。
- 默认 C 盘 active/candidate、D 盘 active 与三个 Cargo 配置已切新包。
  清除测试环境覆盖，independent、app cross-crate、arithmetic 用默认配置
  构建与再次 Fresh 全 PASS。未另外重跑三个标准样板的 JTAG，未执行 Flash；
  RAM 正向回归不扩大为任意 core/Rust crate 或全部重定位支持。
- 证据根目录 D:\c28x-toolchain\b1-failclosed-20261027：acceptance.json、
  core-final-build.log、verify-llvm.log、bundle-gate/report.json、旧包拒绝日志、
  cargo-memory/report.json、core-*-hw.log、abi-hw.log、default-cargo.json 及
  activation-before/after.json。PATH_B 当前包位置、当前/历史验收与问题表同步。
  归档并发、未知链接参数、固定映像 alias 和未来发布强制语义门禁仍待处理。

## 2026-10-27：B-1 链接参数严格处理与静态原生库接入

- 用户选择处理 .a/.lib、-l/-L 与未知参数被忽略的问题。新增 B-1
  tools/c28x-link-arguments.ps1，替代原先“只看 .o/.obj/.rlib，其余 continue”
  的扫描；每个选项必须明确消费，未知、缺值、重复输出、非法库组及不支持
  的动态/whole-archive/response-file 等语义明确失败，不盲目透传 TI linker。
- 直接 .a/.lib 先校验 regular archive，llvm-ar 列成员、ofd2000 验证每个成员
  为 C28x ELF，然后保持库/库组顺序传 TI linker 按需选成员。Rust/TI 普通对象
  在原生归档前，TI RTS 在后；支持 start/end-group 反向引用重扫，嵌套拒绝。
  库在链接前后核对 SHA，变化则失败。原有 rlib 展开并发问题未在本轮处理。
- -L 分离/连接形式及 -l 分离/连接、:filename 精确形式均显式解析；只在
  已声明的目录找静态库，顺序为各目录内 libNAME.a/NAME.lib/libNAME.lib/NAME.a。
  缺失目录/库、不支持的名字或动态请求均明确拒绝。
- 默认 Cargo 带 --strip-debug，不能作为未知参数忽略。现使用 llvm-objcopy
  实际剥离，比较入口、ABI flags、所有 SHF_ALLOC 段的地址/大小/内容后才替换。
  独立 ABI 旧映像剥离探针确认驻留数据相同，符号表仍在；最终用新 Cargo 映像
  做 DSS 符号/运行验收。--gc-sections/no-gc-sections 映射 TI section elimination。
- provenance 升 schema 4，记录原始 linker argv、消费策略、搜索目录、按顺序
  解析的归档及 SHA、实际 TI argv、适配器/parser/exe 和部分工具身份。PASS
  标记移到 provenance 成功写出后，避免元数据失败时提前输出成功。
- 初次集成发现 Windows PowerShell 的 Get-Content 为字符串附带 PSProvider
  等属性，新增 raw argv provenance 在深度 15 的 JSON 序列化中遍历提供器图，
  导致 CPU 持续占用。保留 trace-adapter.log 等诊断，核对进程身份后只终止
  本轮诊断子进程；改为 .NET ReadAllLines 读取干净字符串。ELF machine
  校验常数初稿误写 140，按当前 LLVM ELF.h 更正为 EM_TI_C2000=141。
- cargo-native-build.ps1 跟踪新增 parser 和 objcopy。新增原生库的变化唤醒
  仍遵循 Cargo build script 契约：共享脚本项目把归档列入 extraDependencies，
  自定义 build.rs 输出 rerun-if-changed；搜索目录候选集合变化需另登记目录。
  不声称只在最终 linker 看到归档就能让 Cargo Fresh 自动失效。
- 新增 tools/verify-cargo-link-arguments.ps1，在含空格的隔离工程中调用真实
  Cargo、rustc、TI 编译/归档/链接；覆盖命名/精确搜索、直接归档、顺序、库组、
  错误拒绝、剥离及库文件变化后的增量重链。证据根目录
  D:\c28x-toolchain\b1-link-args-20261027；integration/integration-final 为过程
  记录，integration-validated 为补齐混合成员检查后的最终回归。
- 编译器、core、builtins 和 active bundle 均未修改，仍为
  20261027-112248-a1cf84ab-2e7ec64c；本轮为外部 Cargo/TI adapter 的更新。
  最终回归结论另在本条收尾追加；固定映像 alias、通用 host/proc-macro、Flash
  与发布强制语义门禁仍是独立待办。

- 收尾验收：integration-validated 的 16 步全部满足预期（正常链接或明确拒绝），
  另有 9 项解析器负向边界及分离 -L/-l、GC 策略检查。库反向顺序明确 unresolved，
  组重扫成功；混入非 ELF 文本成员的归档也被拒绝。修改已登记的 bias.lib 后
  重链 10.24 秒，未变 Rust 依赖 Fresh、原有 TI 对象时间/SHA 不变，映像 SHA
  确实变化；最终 Fresh 0.26 秒。含空格的相对归档路径单独重放适配器 PASS。
- 原有 C/嵌套头、ASM/include、cmd/嵌套 cmd、Rust-only/Fresh 的十步原生增量
  回归全 PASS，未变步骤约 0.25 秒。三个正式 Cargo 工程构建/再次 Fresh PASS。
  新归档映像 RAM/JTAG 读回 7/13/20 PASS；标准 independent、cross-crate app、
  arithmetic 三样板也全部上板 PASS，均按 Cargo artifact 与 SHA 选取实际映像。
- arithmetic 首次读回到达 hw_done，但结果出现 7/0/2/0 等高低字交错。原因是
  以前 --strip-debug 被忽略，DSS SYMBOL[i] 依赖 DWARF 数组类型；现在真实去除
  DWARF 后，CCS 默认用 16 位索引。dss-read-b1-arithmetic.js 改为用 ELF 符号
  地址加显式 unsigned long*（TI 32 位）读回，不改测试期望和驱动。随后完整
  32 项（含 NaN 与四参调用）PASS。default-arithmetic-hw.log 失败证据保留，
  成功日志为 default-arithmetic-explicit-width-hw.log，未覆盖或掩盖首轮失败。
- PATH_B 参数契约、当前问题表/维护记录及 B-1 既有 Cargo 接入说明同步；
  没有修改 active、compiler 或 bundle 文件，没有执行 Flash。

## 2026-10-27 B-1 Rust 入口、主循环与 Timer0 RAM 实验

- 用户要求尝试不再使用 C main。新增 B-1 crates/c28x-cargo-runtime，入口 main、
  PreInit、Timer0 ISR、主循环和 MMIO 均为 Rust。extern C 是调用约定；工程没有
  C 应用源码。context-probe.asm 只用于异步寄存器哨兵和偶/奇栈测试。
- 后端补齐 interrupt CC 的 XAR0..7/XT 软件保存、ASP/SPM/模式位清理、NASP/IRET，
  修正 FI 计算跳过 IRQ_ENTER、CSR 入栈顺序以及 MOV32 立即数展开对 ACC 活跃性的处理。
  LLVM O0/O2 verify-machineinstrs、空 ISR 与 TI 汇编机器码 oracle 全部通过。
- c28x-rt 改为 TI RAM 模板和 Cargo links 运行库元数据；启动维护唯一的 128 项
  原生字地址 PIE 表，未绑定 weak 向量替换为默认处理器，跳过前 3 个 ROM 槽。
  修复零长度 BSS/data、BANZ N-1 边界和 PreInit 名称；保留 TI auto-init。
  添加 CPU 中断叶函数。build script/linker 共用 runtime config 并跟踪原生输入。
- entry/pre_init/interrupt 宏补严格签名及 c28x-interrupt ABI；2 项 host 单测和
  doctest 通过。第一次 doctest 因 RUSTDOC 指向另一版 MSVC 而失败，改同版 GNU
  RUSTC/RUSTDOC 后通过。macros 改为显式可选 feature；本次应用直接导出 Rust 符号。
- host 编译包装器按 bundle 中有无同版 std 选择 compiler；新候选用自身 rustc
  编译 build script，旧 active 保持原版 GNU host 回退。构建/发布脚本新增
  host std/proc_macro 的打包和加载门禁；多 driver 时按 rustc PE 的实际导入选择。
- 已冻结可用候选：B-1/build/toolchains/bundles/20261027-125446-504e8ef7-ce48b97e，
  manifest SHA256=4DB42ED9FD87D423D45E265AD3DAC35DC689EAD0033AC18AC235B24284DA15F7。
  同版 host hello 运行 MATCHING_HOST_OK；bundle 只有 std，缺 host proc_macro。
  首次 Cargo 在 proc-macro2 因缺 proc_macro 失败，证据保留；后改为宏可选，
  不混用其他版本的 host rlib。新工程的宏目标签名测试显式 SkipSignatures。
- 后续尝试补齐 proc_macro 的完整重建失败：mutable Rust 源码的 C28x target
  注册/interrupt ABI 修改缺失，新编译器 target-list 不含 C28x，原因未确定。
  发布门禁拒绝；未把失败候选当完成。保留 ce48 不可变快照，active 从未切换，
  仍为 D:/c28x-toolchain/b1-toolchains/bundles/20261027-112248-a1cf84ab-2e7ec64c。
- 过程诊断：数组迭代路径引入大 core 格式化闭包，超 RAM 并缺 __udivmodsi4，
  本次使用聚焦的非迭代 irq_work，未宣布通用 core 闭包已修好。首版合并两个
  u16 再作 u32 比较的检查器报 10 错，而原始寄存器完全正确；根因仍待定位。
  改为逐半字比较，并由 DSS 独立校验全部原始寄存器。原失败日志保留。
  初次直接 Cargo 还因完成标记函数被内联导致 requiredSymbols 拒绝，补 inline(never)。
- 最终证据 B-1/build/runtime-rust-only-20261027：正常 Cargo 构建 14.71 秒，
  再次 Fresh，映像 SHA256=AF8C9D74E2A460B17C07BDB8564DB17CA3A5BB62B67DC32A5E1B815BBE3CDD42。
  F28035 RAM/JTAG 明确 PASS：Rust loop=2709、ISR=48，偶/奇背景 SP=288/289，
  中断入口 SP=303/304；两组上下文 errors=0；PreInit/BSS/data/调用校验通过，
  ACC/XAR0..7/XT/P 原始字独立校验通过，实际触发未绑定 PIE group 2 到默认处理器。
  DSS 只以明确 PASS 行判定，不能依赖进程退出码。没有执行 Flash 或嵌套中断。
- D 盘空间降至约 125 MB。旧诊断备份和未激活失败候选通过带根目录检查的
  原生 Move-Item 移至 B-1/build/preserved-runtime-diagnostics；后续两批有前后
  哈希核对台账 preserved-diagnostics-transfer.json / preserved-candidate-transfer.json。
  第一批保留迁移后哈希，不冒称有迁移前证据。一次递归 copy/delete 方案被
  自动审批拒绝，未执行；改用原生移动完成。active 与已验收历史包未移动。
- 文档：PATH_B §3.5、维护记录/当前待办和运行库 README 已更新，可按显式
  BundleRoot 重现。候选正式发布、proc_macro、复杂表达式诊断、Flash/嵌套中断
  和更广泛外设仍未完成；不把这次 RAM 小工程 PASS 等同于全 Rust 生态可用。
- 收尾兼容回归：使用原 active、Cargo 返回的实际 executable（不依赖固定 .out
  别名），independent=7/13/20、cross-crate control=23/40/19/20/82/178、
  arithmetic 32 项全部 RAM/JTAG PASS；日志在 runtime-rust-only-20261027 的
  independent/control/arithmetic-compat-cargo.log 和 -compat-hardware.log。
  验证器报告补 signatureChecks=SKIPPED，区分代码生成检查与真机上下文检查；
  BuildOnly 不再将未运行的硬件上下文记成 PASS。
## 2026-10-27 B-1 可重复重建与正式发布（进行中）

- 用户要求关闭新工具链重建/发布阻塞。原补丁只有 5 个基础 target 文件，未收录
  完整 interrupt ABI，prepare 脚本还引用不存在的 toolchain.ps1，且默认会按
  系统 rustc 版本 fetch/checkout。改为固定本地 1.100 源码、逐文件基线/结果哈希
  校验、未知修改明确拒绝；补丁扩展为 18 个文件，包含 canonical ABI/feature/
  LLVM CC92/稳定公共 API 转换，保留 i1:8:8 数据布局。
- 构建前新增源码完整性检查：原缺失状态明确失败，恢复后通过。构建记录完整
  compiler/bootstrap/core/std/proc_macro 文件内容快照，fast path 也绑定快照；
  构建后及发布前再次核对，source-state.json 将随编译器及 bundle 保存。
- 找到并本轮复现源码丢失机制：stage0-sysroot/lib/rustlib/rustc-src/rust 是指向
  定制源码的 junction。bootstrap compile.rs 的 initial_sysroot/lib 复制步骤
  （约 814 行）将原版 GNU rustc-src 沿此联接复制到源目录，随后又创建该联接。
  fsutil 还确认被覆盖文件与原版 GNU rustc-src 共享 NTFS hard link。
  第一轮重建中，恢复后的 abi_c28x_interrupt 再次消失；主动停止本轮构建树，
  保留 compiler-build.log，不继续发布。这里有可重复机制证据，不再只推测
  是某个外部进程重置源码。无法从现有记录断言最初是哪次命令引入该状态。
- 在每次 x.py（compiler 与 host std/proc_macro）之前，只删除经验证位于命名
  build root 内、且目标恰为该 RustSource 的 stage0 源码 junction 本身，不递归
  删除源目录；不修改 upstream bootstrap 代码。恢复补丁后第二轮重建进行中。
- 空间：对 D 盘 stage1-rustc 现有缓存使用可逆 NTFS 压缩，5941 文件、6.46GB
  逻辑数据压到约 3.68GB，保留内容。bootstrap 缓存也压缩以提供重链空间；
  临时文件改放 C 盘 B-1/build/rustc-temp。未删除 active 或 ce48 候选。
- 当前证据 B-1/build/source-recovery-20261027；正式发布及硬件回归尚未完成，
  active 保持 20261027-112248-a1cf84ab-2e7ec64c。最终结果将追加。
- 进一步复现：仅在 x.py 之前断开 junction 仍不足，同一次 bootstrap 命令内也会
  再次经过 stage0 StdLink 复制步骤。第二轮构建虽然返回成功，紧接着源码校验
  明确拒绝（compiler-build-unlinked.log），没有发布。最终增加独立、无源码
  payload 的 GNU bootstrap sysroot，切断 initial_sysroot/lib 输入中的 rustc-src。
  它只含固定 commit 的 bin 与 host target 库，使用前校验全部文件哈希；保留
  原版 GCC/linker 设置。D 盘同卷硬链接仅共享这些只读二进制，不共享源码。
- 首次将该 bootstrap 放 C 盘时，bootstrap 向 D 盘 stage0 复制大库因空间不足
  失败（compiler-build-isolated-bootstrap.log）。将失败 stage0 普通目录移到
  C 盘诊断目录，已先解除源码联接并检查没有其他 reparse point；改为 D 盘
  runtime-only bootstrap，使内部复制复用硬链接，避免跨卷大拷贝。
  一次递归删除缓存方案被自动审批拒绝、未执行，已用原生 Move-Item 保留替代。
- 新流程当前实际编译到了 rustc_hir_typeck，18 文件补丁持续存在。
  增加 test-rustc-source-state.ps1：幂等已应用检查、源码漂移拒绝、未知修改保留、
  只断开预期 junction、外部 junction 拒绝、无验收拒绝、不完整验收拒绝、
  验收日志改写拒绝均 PASS。check-rustc-patch.ps1 改为核验完整固定补丁。
- 增加 verify-b1-release.ps1，规划串行运行 runtime（含 9 项宏负向签名及
  同一 Rust 程序的宏入口/中断正向真机）、五组内存、ABI、core A/B/B2/C/D/E、
  三个 Cargo/Fresh/真机。新 sourceSha256 编译器的 sysroot 默认不再自动激活，
  select-b1-bundle.ps1 必须核对同 bundle 的验收和日志/映像 SHA；publish-b1
  将准备、编译、sysroot、验收、激活串联。尚未实际验收的步骤不记 PASS。
- 完整构建另发现 rustc_public 的 CanonAbi -> CallConvention 转换漏两处，明确
  E0004 拒绝；补 enum C28xIntr 和 CanonAbi 映射，完整补丁现在为 20 文件。
  保留 compiler-build-isolated-bootstrap-2.log 失败证据，复用完成产物重建。
  新测试从反向补丁生成 pristine fixture 后应用/重复应用，不依赖历史备份；
  source-state-tests-20-files.log 全 PASS。也修正补丁中新文件的 new file mode
  头（最初 fresh check 报 dev/null 不存在），保留失败与修复后日志。
- LLVM 当前 MC/ABI/O0/O2 ISR 字节 oracle 再次全 PASS（llvm-regression.log）。
- 为最终链接空间，把 inactive stage1-tools、bootstrap debug incremental、
  已完成的 middle/trait_selection/hir_typeck/hir_analysis incremental 缓存移到
  E:/c28x-b1-build-relocated，原路径留 junction，未删除缓存；路径均限定在
  命名 build root / E 盘新目录，并先查 reparse point。一次尝试的旧备份路径
  不存在，实际未迁移；不采用那条非终止错误后打印的 CACHE_PRESERVED 为证据。
  真正完成的缓存迁移台账为 cache-relocation.json / incremental-cache-relocation.json。
  这些是构建缓存路径，不是活动包或源文件，runtime-only bootstrap 仍不带源码。
### 本轮收尾：2026-10-27 171858 正式发布并激活

- 编译器候选 20261027-171858-19176840 成功生成；source-state.json 记录完整
  compiler/bootstrap/core/std/proc_macro 内容，完整 20 文件补丁及来源绑定。
  host std/proc_macro 同版重建，通过实际编译宏 DLL、由同编译器加载并运行
  C28X_MATCHING_HOST_PASS。clean-PATH rustc-vV、C28x target/普通对象和中断对象门禁通过。
- 一次发布被新增 IR 文本检查误拒：LLVM 将 CC92 打印为 x86_regcallcc。按
  CallingConv 编号核对后接受该别名，同时独立验证对象 ASP/NASP/IRET；不是
  放宽 target 架构检查。原失败 compiler-build-20-files.log 保留，修复后的
  事务 compiler-build-publish-final.log 成功，未直接给任意 stage1 手工盖章。
- 同版 C28x core/builtins/ti-arithmetic 重建，发布完整 bundle：
  C:/Users/61987/Desktop/28035/f28035-rust-bridge-b1/build/toolchains/bundles/20261027-171858-19176840-af788b4d
  bundle.json SHA256=0B73BEB3F10AE2CA7D8FB5850BF7DAB773EEC6770DBD005964290D37E0F817A8。
  compiler-unchanged.log 确认再次执行命中 fast path，无需重建。
- Cargo 实测发现 invoke-b1-rustc.ps1 仍把 host 请求转向原版 GNU（旧注释称
  proc_macro 为 rmeta stub，已不符合新包）。宏 DLL 元数据不匹配，目标编译
  报 DLL 类型未知/E0463；修为有 host 库的包始终使用同包编译器/sysroot，
  原版 GNU 只为无 host 库的旧包保留受限回退。原脚本和失败日志已保留。
  修正后使用干净 target 缓存，9 项宏负向如期拒绝，真正执行到宏的诊断。
- 正向宏应用曾因对象路径 271 字符，Rust 已生成文件而 WinPS5 File.Exists
  返回 false 导致链接拒绝。验收缓存改为 build/q/<identity>/{rt,mem,app}，
  identity 绑定 bundle manifest、wrapper EXE 和 invoke 脚本 SHA；避免旧 host
  产物混用。详细证据仍在原目录。默认 Cargo 同名宏对象路径计算为 232 字符，
  没有把全局开发目录改到临时目录。任意超长路径兼容不在本轮声明范围。
- 首次内存硬件验收实际读回 48 项、错误 0，但完成标志 0xB1E1 被去掉 DWARF
  后的 DSS 表达式当有符号数读为 -19999。dss-read-b1-memory.js 改为符号地址
  加显式 unsigned int* 逐字读，不改测试期望。五组随后均 PASS。
  汇总还遇 PS5 ConvertFrom-Json 顶层数组被 @(...pipeline...) 额外包一层，
  修正汇总及旧 memory report 重载，避免嵌套/重复报告；json-array-proof.ps1
  证实 wrapped=1、direct=5、failures=0，失败日志全部保留。
- 最终统一验收目录：
  B-1/build/release-acceptance/20261027-171858-19176840-af788b4d-host-match。
  release-acceptance-json-fixed.log / report.json 的 12 项发布检查全部 PASS：
  runtime（直接/宏入口各 ISR48、偶/奇栈零错、默认 PIE 向量、9 项签名负向）、
  memory 五组 48/192/72/144/6=462 项、ABI 十项、core A/B/B2/C/D/E、
  independent/control-cross-crate/arithmetic 三个 Cargo 构建/Fresh/真机。
  core A=140,54,65,245,212,223,179；B=80,179；B2=90,179；C=132,179；
  D=42967,179；E=1,0,1,0,1,0,1,0,1,0,1,0,5,9,0,179。
- verify-b1-release 记录真实 Cargo artifact 路径、映像和检查日志 SHA；不使用
  固定 .out alias 推断新旧。所有实际硬件测试均要求明确 PASS 行。
  同包验收写入 build/toolchains/acceptance/20261027-171858-19176840-af788b4d.json。
  select-b1-bundle 校验验收后成功激活（activation.log），同时显式同步 D 盘
  b1-toolchains/active.json 镜像；两处指针和三个 Cargo pin 都指向完整 C 盘新包。
- 激活后默认配置复核 independent/control-cross-crate/arithmetic：每个都构建
  成功，第二次 fresh=true（Cargo 日志均 0.04s）。只按正常配置执行，未继承
  验收用 RUSTC/CARGO_TARGET_DIR 覆盖，见 default-*-1/2.log。
- PATH_B 当前包位置、流程、维护记录、验收矩阵和待办，以及运行库/B-1 README
  已同步。旧 2e7ec64c 包留在 D 盘，ce48 原型仍为历史快照。无 Flash 操作，
  嵌套中断、合成 u32 检查器历史诊断、较大格式化闭包及任意 crate 仍未关闭。
  本轮完成的是可重复构建流程和匹配包发布/验收，不宣称位级可重复二进制或
  通用 Rust target 已完成。
## 2026-10-28 B-1 divmod 运行库与 core 覆盖（进行中）

- 用户要求补齐 __udivmodsi4 和扩大 core 覆盖。当前 active 仍为
  20261027-171858-19176840-af788b4d，先用隔离工程取得可复现负向证据。
- 读取 LLVM SelectionDAG ExpandDivRemLibCall 和 compiler-builtins 原型：
  同时计算商和余数时，函数返回商、通过第三个指针参数写余数；C28x LLVM
  汇编探针证实该指针是逻辑字节地址。普通 TI C 指针按字寻址，不能直接按
  C 指针写回；选用 Rust 实现以匹配调用方的地址模型并复用既有算术包装。
- 新增 B-1 crates/c28x-cargo-divmod，计划验证动态商/余、栈输出指针和空指针；
  目前只创建负向复现，未声明通过、未发布。临时探针第一次因 dot-source 脚本
  覆盖通用变量 dir 而写日志到系统目录被拒；未写入系统目录，改用任务专属
  probeDir 后正常生成汇编，证据在 B-1/build/udivmod-20261028/。- 隔离候选 bundle `20261027-171858-19176840-5dfa55ed`：保持已发布 rustc/core，增量重编 builtins；`__udivmodsi4` 用 Rust 逻辑字节指针写余数，并调用既有 u32 商/余数运行库。除数必须非零；空余数指针允许。
- 用 `c28x-cargo-divmod` 核查真实 LLVM 自动生成的重定位，F28035 RAM/JTAG 通过十组输入、栈/全局余数指针和空指针；第二次 Cargo 构建 Fresh。证据 `f28035-rust-bridge-b1/build/udivmod-20261028/candidate/`。修复无额外 TI 源文件时配置残留空路径的问题。
- 新增 `c28x-cargo-format-probe`，实际动态 u32 十进制/十六进制的 `core::fmt` 和字节迭代在候选包上仍链接失败：TI 报 `.text` size 0x12a48，RAMCODE 共 0x2000 字；失败 map 的 output `.text` 为 0x12aec（含对齐），另有 `.rodata`。这是容量不足，不能推断其它潜在缺符号已全部解决。证据 `build/udivmod-20261028/format-candidate.jsonl` 及对应 Cargo map。
- `verify-b1-release.ps1` 新增 divmod 真机验收；原有选择器对历史 bundle 的 12 项门禁保持兼容。完整候选验收与独立 `core -Copt-level=s` 试验进行中；尚未更改 active 或宣称格式化可用。
- `core -Copt-level=s` 隔离探索：仅替换 core 对象会导致旧应用引用的泛型符号无法匹配，改为重建 core 元数据、builtins 和应用后，格式化探针可成功链接；RAMCODE 0x1d1d/0x2000 字（剩余 0x2e3 字）。实验包在 `build/udivmod-20261028/experimental-size-core-bundle`，明确不可发布；该结果尚无真机和完整回归，不能外推通用格式化可用。实验的第一次只换 core 导致 E0460，保留日志；目前已使用匹配的 core/builtins。
- 发布门禁对含 `__udivmodsi4` 的 bundle 增加 divmod 验收项；旧 active 的既有验收仍通过，模拟候选缺 divmod 报告时明确拒绝。完整发布回归目前仍在运行。
- 正式候选 `20261027-171858-19176840-5dfa55ed` 完成 13 项发布验收（runtime、divmod、memory 五组、ABI、core A/B/B2/C/D/E、三个 Cargo/Fresh/真机）并激活。C/D active 指针及根目录、app、independent 三份 Cargo pin 均指向新包；bundle SHA256 `1D9A6E008E16B3BD2632DAC580B843B3E21099EBAA7A29A4EFBB3D61566301F5`。验收目录 `build/release-acceptance/20261028-divmod-5dfa55ed/`。Flash 未测。发布后对更新过的 divmod 验证脚本额外运行 BuildOnly PASS。
- 实验 size-core 格式化程序真机未通过：输出乱码且完成标记为 0xdead，DSS 进程虽然 exit 0，但无 PASS 标记，故不能以 exit 0 判通过。相同 writer 的 `sink-only` 固定字符串真机输出正确，表明该控制样例的字节迭代/写入路径可用，不能推断数值格式化正确。继续拆分十进制与十六进制检查。证据为 `format-size-hardware.log`、`format-sink-hardware-2.log`；实验包不切换 active。
- 继续拆分实验：`decimal-only` 和 `hex-only` 均可链接但均在 RAM/JTAG 输出错误、返回 0xdead；十进制的 writer 诊断为调用一次、字符串长度 192、起始位置 0，期望总输出 `12345` 只有 5 字符。不能仅凭这一现象确定错误是在格式化数据、ABI 或其他中间过程。证据 `format-decimal-diag-hardware.log`、`format-hex-only-hardware.log`。
- `sink-indirect` 以 `dyn Write` 写固定字符串的源码在真机得到正确内容及长度 18，但对象反汇编 `format-sink-indirect.dis` 显示编译器把该特例去虚化为直接调用，所以这不构成虚表间接调用覆盖。早期控制组日志中 PASS 文案曾写成 core fmt；已修正脚本，并以 `format-sink-hardware-2.log` 的固定字符串专用标记复核。

## 2026-10-28 继续定位 B-1 动态格式化（进行中）

- 沿用当前 active 5dfa55ed 与独立 size-core 实验；检查数字转换、pad_integral、writer 调用边界，以真实寄存器和栈值区分算法值错误与调用错误。暂未修改编译器或切换 active。
- 后端检查定位：i16 SHL/SRL/SRA 的共同 custom lowering 原先全部 ANY_EXTEND 到 i32，SRA 未传播 bit15，SRL 可能把未指定的高位移入低位；修改为 SRA=SIGN_EXTEND、SRL=ZERO_EXTEND、SHL=ANY_EXTEND。
- 首次 llc 最小回归明确报 `Cannot select sign_extend_inreg ... i16`；补 `SIGN_EXTEND_INREG i16 Expand` 后，shift16-extension.ll 的机器指令选择/FileCheck、verify-machineinstrs 和对象生成全部通过。保留首次失败与后续成功日志。
- 断点核查：main 命中，Display 数字转换入口未命中，程序已在写入器报错后结束；core 文本格式模板以 0xC0 表示占位符，把这个字节误判成正数会解释长度 192。此时尚属待硬件确认的因果假设。内部 local 符号不导出，后续不能只用 symbol.getAddress 定位；trace/trace-2 失败日志保留。
- 新增 Rust-only c28x-cargo-shifts 和 verify-cargo-shifts.ps1，64 项覆盖有符号字节扩展、i16/u16 右移和格式模板字节分类，旧 active 负向运行和重链 rustc 正在执行。新包未发布。
- 旧 5dfa55ed 的新 64 项真机回归明确失败：0x80/0xc0 模板分类错误、字节符号扩展错误，多组变量移位为 0。检查反汇编另外发现变量移位 pseudo 在 Src=ACC/Amt=XT 时先把 XT 搬进 ACC，覆盖待移位源；在暂存计数前后保存/恢复 ACC，新增 shift-acc-xt.mir 固定物理寄存器验证，postrapseudos/FileCheck PASS。
- 第一次 rustc 候选 20261028-110711-972c1108 只包含扩展类型修复，未构建 sysroot 或发布；继续重链以纳入 ACC/XT 修复。独立 llc 诊断对象仅用于提前验证，不替代最终 B-1 rustc/Cargo 真机验收。
- sysroot 构建增加显式 -CoreOptLevel（默认仍 0），构建参数随 manifest 绑定；新 manifest 要求 shifts 验收，size=s 额外要求 format。verify-b1-release 和激活门禁识别这些必须项目，未知项目拒绝；历史包保持原回退规则。新增 verify-cargo-format 供严格 PASS 标记及 Cargo Fresh 验收。
- 修复后的独立 llc 诊断对象（每函数/数据独立 section，与正常 B-1 一致）先达 63/64：最后一项是 trunc i16 0x8000 -> i8 传参，16 位 ABI 槽仍带上位残留。LowerCall 根据原始 ArgVT 对窄参数显式零扩展或按 sext 标志符号扩展，新增调用边界 IR/FileCheck；合并三处修复后，诊断对象 F28035 RAM/JTAG 64/64 PASS。最终 B-1 rustc 正在第三次重链，前两个未构建 sysroot/激活。
- 诊断过程一次忘记 llc 的 function-sections/data-sections，出现对象函数地址非零 section offset 的单位问题，真机超时；已用与 B-1 一致的独立 section 重做，证据分别保留在 shifts-fixed* 与 shifts-fixed-sections*。这次额外现象未宣布修复，不能把诊断工具组合误作正式 B-1 发布。
- 含全部三处后端修复的新 compiler 为 20261028-111803-1ced7f30，已完成同版 host std/proc_macro 构建和 compiler candidate 校验；正在通过正常 rebuild-core-sysroot -CoreOptLevel s -SkipInstall 构建匹配 sysroot，未复用手工实验包。
- LLVM 额外对象回归 abi-mixed、abi-pointer、call-four-args、arithmetic32、shift32、shift16-extension 的 verify-machineinstrs/object 全 PASS。新 build 参数也由 publish-b1 转发，包清单要求新 shifts/format 验收后才能激活。
- 第一轮正常 B-1 sysroot 候选 20261028-111803-1ced7f30-60498fb4（coreOptLevel=s，必须 shifts/format）已生成；144 项扩展前的 64 项实际 Cargo/Fresh/真机 PASS，但格式化仍错，故不激活。
- 后续边界追踪证实 Formatter 标志输入正确，write_prefix 的 Option<char> None 哨兵却从 0xffffffff 截成 0x0000ffff。定位 SELECT_CC 的指令选择强制 i16 返回；新增 32 位结果/16 或 32 位比较的 pseudo，沿用 CFG/PHI custom inserter，保留完整 i32。新 wide select IR/FileCheck PASS；旧候选扩展到 96 项时完整读回复现高半字丢失。
- 宽 select 修复的诊断映像十进制已正确、hex 数字正确但补零仍错。硬件单步 oracle 证实 LSL ACC,T=ff50 仅取 T(3:0)，16 -> 0 位、24 -> 8 位；LSRL/ASRL 取 5 位。TI cl2000 生成 LSLL ACC,T=563b。修改 wide SHL 使用 LSLL，增加指令选择/编码对照；诊断格式化映像正确输出 n=12345 x=00003039，marker=0xb1f4、明确 PASS。
- LLVM 诊断 core 的 -verify-machineinstrs 另外在 slice::align_to 的 PUSH_ACC 报 undefined ACC；普通诊断编译（与正常 rustc 相同无该额外开关）可生成对象并上板。正在对修复前的正常 B-1 compiler 做同开关对照，尚不宣称全 core 机器验证通过。该问题保留，不以关闭 verifier 作为其修复结论。
- 测试扩展为 144 项，覆盖宽 select 完整高/低半字及变量左移 16/24/31；最终 rustc 再次重链中。build/format-20261028 保留所有失败、阶段候选和单步/编码证据。

## 2026-10-28 优化 core B2 误编译（进行中）

- 用户要求修复 opt=s core 的 B2 104/90 问题。当前 active 为 D:/c28x-toolchain/b1-release/bundles/20261028-143932-84804e8a-b27f23d4（core opt=0）；先用同 compiler 的 opt=s 包 8fe5a872 重现，拆分三段迭代器。保留原测试和期望 90，不激活未验收包。
- 原始 opt=s B2 复现 104/90。复制原 crate 到隔离 scratch 并加入三段诊断函数，真机读回 `[104,40,44,20,104,179]`，锁定 zip/skip/map/sum。优化 LLVM IR 的算法正确；机器码在 ADD16_PSEUDO 的 Dst=AR0、Lhs=AR0、Rhs=AL 组合先 MOV AL,AR0，再 ADD AL,AL，错误地把已累加值翻倍，三轮得到 4、16、44。
- 修改共用 16 位 ALU 展开：根据真正工作寄存器（Dst 为 AL/AH 时用 Dst，否则用 AL）判断右操作数是否需要先暂存 AR7。加/减/与/或/异或共用修复；新增 alu16-rhs-al.mir 五种固定寄存器 FileCheck 均 PASS。
- 独立 llc 的修复诊断对象真机读回 `[90,40,30,20,90,179]`，保留原始期望不变。全 scratch IR 加 -verify-machineinstrs 触发既有 undefined ACC PUSH 问题（先在未用到的 core_ex_slice_search，裁剪 B2 后也能触发其 32 位立即数展开），日志保留；按正常 rustc 同策略编译诊断对象取得上板证据，不把这个额外 verifier 问题记成已修复。
- 使用 D:/c28x-toolchain/b1-release 作为正式发布根重链 rustc/同版 host std，接着将通过正常脚本重建 opt=s core/builtins，候选通过完整验收后才可切换 active；当前 active b27f23d4 保持。
- 补充隔离诊断的 7 组向量（长度 0/1/2/3/4、u16 溢出值、非均匀值）共 28 项均在真机正确；原样例 `[2,4,6,8]` 的分量仍为 40/30/20，总和 90。证据 boundary-hardware.log。该阶段独立 llc 诊断尚不替代正式新 rustc/Cargo 发布验收。
- 复跑 shift-acc-xt.mir 与新增 alu16-rhs-al.mir 均 FileCheck PASS；旧 repair-20260930.mir 因缺隐式 XT def 的过期 fixture 在解析时失败，未计作通过，未为本次缺陷修改它。
- 新 compiler 20261028-154958-af95c9d8 和正常脚本生成的匹配 bundle 20261028-154958-af95c9d8-6c02958c 已生成；coreOptLevel=s，requiredReleaseChecks=[shifts,format]。原始 B2 用该包直接 rustc --emit=obj 重建，真机 `[90,179]` PASS；同新 rustc 编译的拆分/边界映像 28 项全部 PASS。
- 新 core-dual.o=829720 字节，原 active opt=0 对象=3344800 字节。该数字是未最终裁剪对象大小，不等于上板占用。完整 verify-b1-release 15 项在隔离证据目录运行中，当前 active 未切换。
- 完成并激活：bundle 20261028-154958-af95c9d8-6c02958c，compiler 20261028-154958-af95c9d8，core opt=s。完整 15 项发布验收全部 PASS：runtime（含入口/中断宏、签名负向）、divmod、144 项 shifts、动态数字 format、五组 memory、ABI、core A/B/B2/C/D/E、三个 Cargo/Fresh/真机。正式 B2=90/179；额外新 rustc 边界映像 28 项 PASS。证据 `build/release-acceptance/20261028-154958-af95c9d8-6c02958c/` 与 `build/core-opt-b2-20261028/`。
- 包实际位置 D:/c28x-toolchain/b1-release/bundles/20261028-154958-af95c9d8-6c02958c；bundle.json SHA256=90301C8F59FEF83973217D533F97E5EAAFBC543CA9841317C2B6337C13068EC7。先经 D 根 select 验收激活，再复制同一验收记录到 C 根并经 select 激活；C/D active、candidate、三个 Cargo pin 和历史 D:/c28x-toolchain/b1-toolchains 镜像同步。最后验证包清单、15 项日志/映像 SHA、所有镜像和 Cargo pin 均 PASS。旧 b27f23d4 包仍存在供回退。
- 格式化样例 `n=12345 x=00003039` 正确；RAMCODE 占用 0x1dd9/0x2000 字，不能外推更大格式化闭包都能放入 RAM。core 对象从 3344800 字节到 829720 字节，属于对象大小比较，未测运行周期。Flash 未运行。
- 已同步 PATH_B 的维护记录、当前包路径/哈希、core 参数、复现命令、15 项矩阵及遗留边界，并更新 B-1 README。`publish-b1/rebuild-core-sysroot` 参数默认仍 0；重建该优化配置需显式传 -CoreOptLevel s。额外机器 verifier 的 undefined ACC PUSH 与过期旧 MIR fixture 未在本轮关闭；未宣称完整 core/任意 Rust crate 已验收。

## 2026-10-28 B-1 SharedCell 安全共享接口修复与验收

- 用户要求关闭安全代码可重入制造多个 `&mut T` 的漏洞。读取现有运行库、启动
  汇编和 Cargo 回归后，确认旧 SharedCell 没有借用检查，主机临界区为空却实现
  Sync；公开临界区 guard 还允许乱序释放、遗忘和跨线程移动。
- SharedCell 增加目标借用标志/主机 acquire-release 原子锁，以及非阻塞
  try_with 错误接口；冲突在构造引用前拒绝，不执行回调、不清除外层标志。
  with/replace 冲突 panic；私有借用 guard 处理 unwind。临界区改为闭包 API，
  私有中断 guard 在闭包退出恢复；不对主机空临界区声称线程同步。
- 对照 vendor DSP2803x_DisInt.asm 和 Exit_Boot.asm 发现辅助函数的额外错误：
  INTM 实为 ST1 bit0，旧代码使用 bit11；PUSH ST1 后错误从 *SP 读两字。
  c28x-rt/asm.s 及独立 GPIO Safe HAL 支持汇编改用 MOV AL,*--SP 和 AND AL,#1。
- 首次主机 cargo +stable/MSVC 测试因缺 link.exe 无法启动，改用本机已有 GNU
  rustc/链接器执行：7 项测试和 2 项编译负向全部 PASS，覆盖递归拒绝、外层
  借用保留、replace/panic 释放、不同 cell 嵌套、确定性线程争用和四线程 8000
  次一致性更新。证据 build/shared-cell-20261028/host-tests.log。
- 目标验收接入既有 Cargo runtime 及宏正向 fixture，新增独立 ST1/SP 观察器、
  HW_RT_SHARED 邮箱和独立 PASS 门禁。active 读取为 ee53e7b7，不重链编译器、
  不改写 bundle、不切换 active。
- 首轮 Cargo 构建/Fresh PASS，但硬件在进入上下文 probe 前超时；读回前十项
  SharedCell/INTM/栈检查全为 1，PC 在 ROM，Timer0 尚未运行。反汇编发现把全部
  检查内联进 main 后，后续配置出现常量/寄存器异常。保留失败证据在 B-1
  build/shared-cell-runtime-20261028；将独立 API 检查设为 inline(never) 隔离
  验证，并用静态 panic 消息减少 expect 的格式化引入；第二轮验收进行中。
- 第二、三轮仍超时。独立断点证实定时器实际配置正确且进入 ISR，但随后进
  panic；反汇编中借用字节旧值被写入新值时覆盖，条件检查误用新值。改用
  Cell<u16> 的版本仍被优化窄化、生成同一映像，不能当成缓存或重新链接失败。
  最终目标标志使用 UnsafeCell<u16> 的 volatile 读/写保持原生字宽，在检查为
  空闲后才置位；仍由 INTM 和借用标志提供排他。一般字节读改写的编译器问题
  另外保留，未在本次修复后端。
- 第四轮完整 verify-cargo-runtime PASS：直接/宏入口均 Cargo 二次 Fresh，
  HW_RT_SHARED 前 12 项全为 1，完成标记 0xb1c5；主循环各 390 次、IRQ 各
  48 次，两种栈奇偶寄存器检查零错，默认向量 PASS，9 项宏签名负向 PASS。
  证据 B-1/build/shared-cell-runtime-20261028-r4/report.json，应用 SHA256=
  EDFB15502785D64224278B9C79CB4EBDA8AD6C59CB07FBCD33FAE1F58254AB90。
- 最终源码主机 7 项/2 项编译负向再次 PASS，日志 host-tests-final.log。
  独立 GPIO -Exclusive 重新构建并上板 PASS，重复领取和 GPIO34 回读正确，
  日志 build/shared-cell-20261028/gpio-exclusive-final.log；TI 链接器的无匹配
  空 section 警告保留，不记为错误。
- 新增 verify-shared-cell-host.ps1，把主机测试和哈希报告接入 runtime 门禁。
  首次集成清除环境 wrapper 后 Cargo 又读到 B-1 配置 wrapper，将 GNU host
  rustc 当 bundle 拒绝；增加显式空 build.rustc-wrapper/workspace-wrapper 配置。
  首次失败记录保留于 final-gate，修正版在 final-gate2 验证。
- 本轮未改变 active。实际 C 入口/三个 Cargo pin 为 ee53e7b7，两个 D 根镜像
  仍为 6c02958c；已在 PATH_B 记明，不能继续声称所有发布镜像一致。未做 Flash，
  不将本轮共享接口验收扩大为任意编译器字节操作或 NMI/DMA 的同步保证。
- 收尾：新增主机门禁集成后 final-gate2 的完整 BuildOnly PASS，主机 7+2、宏
  签名负向 9 项、Cargo 二次 Fresh 均通过。与 r4 上板映像 SHA 一致，现存映像
  再次 Get-FileHash 匹配；该目录 hardware=NOT_RUN，硬件证据仍是 r4 的两份
  PASS 日志，不冒充再上板。新主机报告绑定最终 lib.rs SHA256=
  0C0AD0FE5F932B6828A5493C542F389D6BAC55107C26F865B1C8C05260105244。
  本轮相关已跟踪文件 git diff --check 通过；保留全部失败轮次和诊断日志。

## 2026-11-02 字节读改写与 HAL 方法路径编译器回归（进行中）

- 用户要求推进编译器正确性。读取 B-1 当前包、源码和业务绕行说明，新增
  c28x-cargo-codegen 和 verify-cargo-codegen.ps1，真实 Cargo 对象/rlib 链路以
  独立主机 oracle 检查 84 个结果，覆盖全局/间接字节交换、奇偶字节相邻哨兵、
  存储时保留 u32 ACC、bool 一次性标志、带观察 self 地址的零尺寸 const 泛型
  sample/set/mixed/inline 方法。计划 O0/O2/Os 各编译、Fresh 和真机。
- 旧 active ee53e7b7 的 Os 负向真机明确 10/84 FAIL，其中 32 项泛型方法检查
  均正确；不能把旧业务现象直接定性为通用 ZST ABI 缺陷。失败日志位于 B-1
  build/codegen-correctness-20261102-before/Os-hardware.log。
- 发现 STORE8_GLOBAL 与间接 STORE8 先 MOV AL,src 再保存临时 ACC，未保留
  AL 上仍活跃的旧值；全局 LOAD8 向 AH 出结果时误认为与 ACC 重叠就无需保护，
  覆盖 AL 中待存的新参数。修为先保存再暂存，并按目标半字只保护另一活跃半字。
- 新 byte-store-live-acc.mir 原实现 FileCheck 明确失败；修后 5 项固定寄存器
  检查及 byte-store-live-acc.ll/verifier 正确。初次 fixture 漏 implicit-def XAR0、
  检查顺序及汇编大小写不符，已修 fixture，未当作编译器问题。原 alu16 fixture
  期待保存 AL 却未使 AL 活跃，补充真实后继使用后，与 shift-acc-xt 一并 PASS。
  abi-mixed/abi-pointer/call-four-args/arithmetic32/shift32/shift16-extension
  的 machine verifier/object 均 PASS。
- 通过源码 junction 增量重建 llc，并启动标准 build-rustc-c28x -BuildHostStd
  重链。active 不变，不改写 bundle；新编译器通过后再建匹配 opt=s sysroot。
- 业务例程恢复 typed ADC/PWM/SCI 方法作为正常路径，旧 FFI 调用保留为显式
  -DirectCalls 对照；将使用相同外围配置对照，不顺带更改 SCI/ADC 硬件语义。
  新方法路径尚待真机验收，未将本轮编译/离线通过写成发布完成。
- 第一轮独立 llc 诊断将 84 项失败从 10 降为 2；nm 证实单字节全局 CODEGEN_BYTE、
  BOOL_FLAG 与 HW_CODEGEN_RESULT 都被 TI 放到 0x400。增加 AsmPrinter 的全局
  首尾 2 字节边界及 common/local-common 最小完整字分配，保留单个对象内部的
  紧密字节布局；byte-global-extent.ll 检查 1/3 字节全局节为 2/4 字节通过。
  第二轮诊断真机 84/84 PASS。该独立诊断不替代最终 B-1 Cargo 验收。
- 真实 HAL 方法路径也用同一 Rust 前端 IR/修后 LLVM 诊断对象复核：1217 拍、
  ADC_ERR=0、raw=3086 与结果寄存器一致、duty=CMPA=753、发送就绪检查 305/0，
  三项判据均 PASS。旧包正常方法负向为 600/1202 ADC 超时、300/300 发送检查失败。
  撤回文档中通用 ZST ABI 根因断言，保留历史观察表。
- 发现业务 PowerShell 脚本仅靠 DSS 退出码会在 EOC/LINK FAIL 后仍打印 VERIFY=PASS。
  改用 Invoke-NativeCapture 留存日志并强制完整短时/长时 PASS 标记。
- 完整 LLVM 门禁最初命中 4 份既有过期 XAR 复制字节基线和 sret 复制字符串：旧
  MOVL XARn,@ARm 已被 10-28 修为栈复制。TI 独立组装确认新序列 bd3abec5/bdc3be8e，
  仅替换这两种旧编码及对应 sret 文本断言；完整 MC 层门禁随后通过。证据
  llvm-gate-checked.log、xar-copy-oracle.*，未通过从新编译器直接抄整段基线放宽门禁。
- 首个重链 compiler 121951-1d9e6141 不含后发现的全局布局修复，未建 sysroot/激活。
  第二次 compiler 20261102-122629-cf4b3949 含全部修复，同版 host std/proc_macro
  构建完成，匹配 opt=s 包 20261102-122629-cf4b3949-7bc20a44 已验证生成，尚未激活。
  一次 sysroot 启动撞到仍在发布 compiler 的锁而被拒，等待完成后重试成功，未绕锁。
- 探针再加 Result<u16,u16> 的 tag/载荷和 bool 方法返回，扩至每级优化 108 项。
  新 bundle requiredReleaseChecks 加 codegen，verify-b1-release 和激活检查识别
  此强制项；旧包保留原回滚契约。codegen 包含三种优化与 Fresh，并实际运行
  typed HAL ISR；不能只用纯方法 mock 代替真实硬件路径。候选矩阵正在运行。
- 旧包 O0 探针在 TI 链接时触发奇数 rodata 写越界内部错误，保留 before-O0 日志；
  未把其编译失败记成真机失败或通过，新包将重建所有匹配 core 产物后重跑。
- 候选 108 项首轮 O0 已成功链接，但在探针 harness 的 index*13 处进 panic：
  仅覆盖 opt-level=0 而 Cargo 仍按 release opt=s 生成选项，rustc 默认检查策略
  随最后 opt-level 改变，额外启用了溢出检查并走 __muldi3。该检查开启路径的
  异常保留，不宣布修复；探针明确固定 debug-assertions=no/overflow-checks=no，
  与本轮生产 release 策略一致。此后 O0/O2 各 108 项硬件 PASS（Os 进行中）。

## 2026-11-02 B-1 Rust 自编应用入门

- 用户准备自己编写 Rust，要求教学。新增 B-1 独立工程
  `crates/c28x-user-app`，不修改 runtime/codegen 回归样例。应用使用
  `#[entry]`、Peripherals::take 与 GPIO34 安全输出，主循环交替高低电平；
  pause 为未校准软件循环，不声称精确延时，应用 main.rs 无 unsafe。
- Cargo.toml 接共享原生输入 build script，依赖 c28x-rt macros 和
  direct-obj-mmio HAL；显式采用 release opt=s、panic=abort、单 CGU、
  关闭 overflow/debug assertions，与当前验证策略一致。c28x-link.json
  复用 Rust runtime 管理的启动和 TI RAM 脚本，不添加 C main。
  Cargo.lock 固定首次解析的宏依赖版本。PATH_B 维护表与 §3.5 同步使用说明。
- 在当前 active 20261102-122629-cf4b3949-7bc20a44 下执行真实 Cargo
  build --release --target c28x-none-elf：成功，首次约 68 秒（含宏依赖）。
  HAL 输出 494 项既有警告，另有链接提示，未将其隐藏或扩大修改范围。
  再次用 Cargo JSON 构建检查 compiler-artifact.fresh=true，成功。
- 产物为 B-1 build/cargo/20261102-122629-cf4b3949-7bc20a44/
  c28x-none-elf/release/c28x-user-app.out，文件大小 9200 字节，SHA256
  D7B06A4022D8479DAC12ED671BE8DE534AC69DDC76ED6058F7E536929DE197C8。
  provenance 确认 direct 链路，原生源仅 c28x-rt/asm.s，无应用 C 驱动。
  再次构建证据 B-1 build/user-app-20261102/report.json、cargo.jsonl、cargo.log。
- 未下载运行、未做 GPIO 真机检查、未写 Flash、未切换或重建工具链；
  GPIO34 接线/LED 极性需按板卡确认，RAM 断电不保留。已区分构建与硬件验收。
