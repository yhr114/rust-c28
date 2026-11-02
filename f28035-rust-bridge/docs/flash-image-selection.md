# 烧录映像选择门禁（image buildstamp）

日期：2026-10-27
问题：切 features（如 rust-api `one-file-main`）、改源码或换编译器后，固定 `.out`
别名仍是旧输入的产物；带 `-SkipBuild` 的上板脚本会静默加载/重链接旧程序。

## 机制

共享门禁 `tools/_internal/image-stamp.ps1`（fail-closed）：

- **构建方**：链接 + 审计成功后 `Set-ImageStamp`，把全部构建输入指纹写入
  `<image>.buildstamp`（纯文本 SHA256）。
- **上板方**：加载/重链接前 `Assert-ImageFresh`；指纹不匹配、无戳、映像缺失
  一律抛错拒绝。显式传 `-Force`（上游转 `-AllowStale`）才放行，且必须打印警告
  ——加载旧程序永远是"有意识的行为"。
- 指纹覆盖：Rust 源（rust-api lib.rs / case 源）、harness C、C 桥 **源码 + obj
  二进制**（覆盖 `-BridgeObject` 预构建旁路）、TI 公共源、链接命令、MIR 翻译器
  源码树、编译器标识、features/mirArgs 等 tag。任何一个输入变化 → 旧映像立即过期。

算法与 `verify-case-ram.ps1` 已有的 buildstamp 一致（该机制已在 RAM case 验证中
长期使用）；注意含中文注释的 ps1 必须带 UTF-8 BOM，否则 PowerShell 5.1 按 GBK
误读会破坏解析。

## 已接入的构建/上板对

| 构建脚本（写戳） | 上板脚本（断言） | 映像 |
|---|---|---|
| `Build-StandardFirmware`（mir-common，142 个标准 case） | `Invoke-StandardRamVerify` ← `verify-mir.ps1` | `build\mir-*\*_mir.out` |
| `run-user-main.ps1` | `verify-user-main-flash.ps1`（RAM 对象由 build-user-main-flash 复用） | `build\user-main\user_main_ram.out` |
| `build-user-main-flash.ps1` | `verify-user-main-flash.ps1` | `build\user-main-flash\user_main_flash.out` |
| `build-gpio30-low.ps1` | `flash-and-verify-gpio30-low.ps1` | `build\gpio30-low\gpio30_low_test.out` |
| `build-gpio39-low.ps1` | `flash-and-verify-gpio39-low.ps1` | `build\gpio39-low\gpio39_low_test.out` |
| `build-native-arithmetic.ps1` | `flash-and-verify-native-arithmetic.ps1` / `-mir-arithmetic.ps1` | `build\native-arithmetic\*_test.out` |

`verify-mir.ps1` 新增 `-Force`；四个 `flash-and-verify-*` 与
`verify-user-main-flash.ps1` 同样新增 `-Force`。

## 语义要点

1. **MIR case 的断言点在 RAM 重链接前**：`-SkipBuild` 时脚本仍会用磁盘上的旧
   `.obj` 重链接出"时间戳新、内容旧"的映像——门禁比较的是构建输入指纹，能识破。
2. **桥 obj 二进制进指纹**：多个 case 共享 `build\c28x\f28035_bridge.obj`，
   任何 case 重建桥后，其余 case 的旧映像全部自动过期（保守但安全）。
3. **兜底**：`program-user-main-flash.ps1` 链路先无条件重建再烧录，未受影响；
   hw_validation 各 case 自带 `case.out`，不在本门禁范围。
4. **尚未接入**：15 个 custom MIR case 的 legacy 脚本（verify-mir 自定义分支
   直接委托）、`flash-and-verify-mir-control-loop.ps1` / `-gpio34-output.ps1`。
   它们走各自 legacy 流程，行为不变；后续可按同一模式补。

## 验证记录（2026-10-27）

- 15 个改动脚本 PSParser 语法全绿（补 UTF-8 BOM 后）。
- 单元冒烟：写戳/回读、输入变化→key 变化、断言拒绝无戳与过期映像、
  `-AllowStale` 放行并警告——全 PASS（其中发现并修复 `Write-Warning "a" + "b"`
  参数绑定 bug：拼接必须加括号，`-f` 优先级高于 `+`）。
- 集成：`verify-mir.ps1 -Case adc-eoc-irq -SkipBuild`（无 -Force）在 JTAG 之前
  报 `STALE IMAGE REFUSED`——fail-closed 生效。
- 正向写戳：单测级 PASS（T1/T5）。端到端正向（构建→写戳→断言→重链）受限于
  下方环境问题，需在真实 shell 复核。

## 环境发现与修复（2026-10-27 同日，验证门禁时暴露）

管线在 10 月中旬后实际已断，靠 cargo 缓存"假活"。本轮修复/降级：

1. **rustup 全局默认被切成 stable** → `dump-c28x-mir.ps1`（故意在 TEMP 运行以
   逃出仓库 rust-toolchain.toml）继承默认，translator 编不过 E0463。
   修复：脚本内显式钉住 `+nightly-2026-09-14`（回退 `+nightly`）。
2. **nightly-2026-09-14-x86_64-pc-windows-msvc 曾被删除**（指纹路径失效）。
   已重装（rustc 1.100.0-nightly 4b6d04e70 2026-09-13 + rustc-dev/rust-src）。
3. **c28x-mir 与滚动 nightly 1.101 API 不兼容**（`TerminatorKind::Goto` 增
   `loop_hint_attrs`、`rustc_driver::run_compiler` 移除 → `compiler_entrypoint`、
   `ConstExt` trait 需导入）。适配补丁：`docs/c28x-mir-nightly-1.101-adaptation.patch`
   （已验证可使 1.101 编译通过，但见第 4 条无法链接）。
4. **本机没有 Windows SDK 导入库**（kernel32.lib 全盘缺失，Kits 目录只有
   Catalogs/Debuggers）——任何 MSVC host 链接（宿主测试、c28x-mir 重编）都不可能。
   缓解：宿主 cargo 统一切到 **D 盘 GNU 自含工具链**（`toolchain.ps1` 新增
   `GnuCargo/HostTestCargo/HostTestTarget/MirCargo`，rust-mingw 自含链接器无需
   SDK；`rustc-dev` 已补装到该工具链）。已实测：c28x-mir 与 rust-api 测试
   编译+链接 PASS。
5. **rust-api 的 `rust_timer0_isr_callback` 空桩（零使用方）让 c28x-mir 对
   100 个无 -OnlyExport 的标准 case 全部报 "not implemented"**（10-13 提交后
   管线已断）。已移除；补丁存档 `docs/rust-api-remove-isr-stub.patch`。
6. **遗留（沙箱无法验证）**：GNU 测试可执行文件在 agent 沙箱内启动报
   0xC0000139（DLL 入口点；hello world 亦然，导入表全是标准系统 DLL），
   疑为沙箱 DLL 加载限制。需在用户真实 shell 跑一次
   `cargo +nightly-2026-09-14 test --target x86_64-pc-windows-gnu`（或直接跑
   任一 GNU 测试 exe）复核。若真实 shell 仍失败，则需安装 Windows SDK
   （VS Installer → "Windows 11 SDK" 组件）后走回 MSVC 路径。

## 工具链使用小结（改动后）

| 用途 | 工具链 | 说明 |
|---|---|---|
| MIR 翻译器 c28x-mir | `$Toolchain.MirCargo`（GNU 2026-09-14 + rustc-dev） | 免 SDK |
| 宿主测试 / rust-to-ti-c | `$Toolchain.HostTestCargo` + `--target $Toolchain.HostTestTarget`（GNU） | 免 SDK；运行待真实 shell 复核 |
| C28x 目标编译 | cl2000 / B-1 bundle rustc（不变） | 与本轮无关 |
| 滚动 nightly 1.101 | 暂不用于 c28x-mir | 应用补丁后可用，但仍需 SDK 才能链接 |
