# 缺口5 + 缺口6：cargo 项目结构构建 + 路径2产物上板验证

日期：2026-10-08
状态：**构建/链接/反汇编全部 PASS；上板未执行（无 XDS100 连接），待硬件验证**

---

## 1. 结果总览

| 项 | 结果 |
|---|---|
| cargo 项目结构 | `crates/c28x-gpio-blink/`（Cargo.toml + .cargo/config.toml + src/main.rs + cargo_blink_start.asm）|
| cargo build（patched rustc） | PASS，产出 `gpio-blink.o`（520 字节，release profile）|
| TI cl2000 链接 | PASS，产出 `build/c28x-gpio-blink/gpio_blink.out`（3928 字节）|
| 反汇编 GPIO 指令 | PASS：0x6F96(GPBMUX1) / 0x6F9A(GPBDIR) / 0x6FCE(GPBTOGGLE) 读改写 + 翻转循环 |
| 上板加载（DSS/JTAG） | **未执行**：`xds100serial` 报告 "No XDS100 emulators were found" |

---

## 2. 关键技术决策（踩坑记录）

### 2.1 自定义 sysroot（不用 -Zbuild-std）
host sysroot 没有 host std，`-Zbuild-std` 会失败。采用预编译 core 方案：
```
build/c28x-sysroot/lib/rustlib/c28x-none-elf/lib/
    libcore.rlib              (43.2 MB, 来自 build/c28x-std/)
    libcompiler_builtins.rlib (17.5 KB)
```
`.cargo/config.toml` 里 `[target.c28x-none-elf] rustflags = ["--sysroot", ".../build/c28x-sysroot", ...]`。

### 2.2 rlib 里的 .o 需要抽出来给 TI 链接器
Rust rlib 是 GNU ar 归档，内含 `core-cgu.0.rcgu.o`（ELF 目标）+ `lib.rmeta`（元数据）。
TI lnk2000 不能直接吃 rlib，所以用 `tools/extract-rlib-o.py` 抽出 .o：
```
build/c28x-std/objs/core-cgu.0.rcgu.o          (2.8 MB)
build/c28x-std/objs/builtins-cgu.0.rcgu.o     (13 KB)
```
链接时把这两个 .o 直接放在 cl2000 命令行上。

### 2.3 必须用 core::intrinsics::volatile_load/store，不能用 core::ptr::read_volatile
`core::ptr::read_volatile` 在 1.100-dev 里会走 `precondition_check` → `check_language_ub` → `maybe_is_aligned`，
把这些泛型函数实例化到我们的 crate 里。C28x 后端在这些函数的重定位扩展上触发 **TI 链接器内部错误**：
```
illegal operation: writing 0x70 bytes to offset 0 in section
".text....maybe_is_aligned..." exceeds its formatted size (0x44)
INTERNAL ERROR: lnk2000.exe had an internal inconsistency
```
绕过方法：`#![feature(core_intrinsics)]`，直接调 `core::intrinsics::volatile_load/store`，不进 precondition wrapper。
改用后 .text.main 从 0x270 缩到 0x100，链接器错误消失。

### 2.4 dev profile（未优化）会触发同一个链接器内部错误
即使去掉了 UB 检查段，未优化的 `.text.main`（0x270 字节）仍触发段扩展错误
（writing 0x4dc > formatted 0x270）。`--release`（opt-level=s）下 .text.main = 0x100，链接通过。
因此构建脚本固定用 `cargo rustc --release`。

### 2.5 段消除必须开（与任务书 `--unused_section_elimination=off` 不同）
整个 core-cgu.0.rcgu.o 有 2.8 MB，含 grisu 浮点格式化等 15KB+ 的段。RAM 链接只有 12K RAML0L1，
`off` 会让所有段塞进去放不下。每个函数都在独立 `.text.<符号>` 段，开 `--unused_section_elimination=on`
后 TI 链接器丢弃未引用的 core 函数，最终 .out 仅 3.9 KB。**这是对任务书约束的有意偏离**，原因如上。

### 2.6 GPIO 地址用 F28035 实际字地址（不是任务书给的 0x7044）
任务书给的 0x7044/0x7048/0x704E 是别的型号地址。F28035 实际（与已上板验证的 `crates/bare-gpio34` 一致）：
| 寄存器 | 字地址 |
|---|---|
| GPBMUX1 | 0x6F96 |
| GPBDIR | 0x6F9A |
| GPBDAT | 0x6FC8 |
| GPBSET | 0x6FCA |
| GPBCLEAR | 0x6FCC |
| GPBTOGGLE | 0x6FCE |

GPIO34 = GPIOB bit2；GPBMUX1 bits 5:4 清 0 即 GPIO 功能。

### 2.7 cargo 需要 no-op 链接器
cargo 对 bin crate 总会调链接器。c28x-none-elf 没有 host 链接器，用 `tools/noop-link.cmd`（exit 0）
占位，真实链接交给 cl2000。最终用 `cargo rustc -- --emit=obj` 拿 .o。

---

## 3. 产物清单

```
crates/c28x-gpio-blink/
    Cargo.toml
    .cargo/config.toml          # RUSTC=patched rustc, sysroot, rustflags
    src/main.rs                  # no_std/no_main, GPIO34 toggle loop
    cargo_blink_start.asm        # RAM 启动：关WD, LCR main
    gpio-blink.o                 # cargo 产出（520 B）

build/c28x-gpio-blink/
    cargo_blink_start.obj        # 启动层 obj
    gpio_blink.out               # 最终固件（3928 B）
    gpio_blink.map
    gpio_blink-dis.txt           # dis2000 反汇编

tools/
    build-cargo-gpio-blink.ps1   # 一键构建（cargo + asm + cl2000 link）
    extract-rlib-o.py            # rlib -> .o 抽取
    list-ar.py                   # ar 成员列表（调试用）
    noop-link.cmd                # cargo no-op 链接器
    verify-cargo-gpio-blink-ram.js  # DSS 上板验证脚本（待硬件）
```

---

## 4. 一键构建命令

```powershell
. C:\Users\61987\Desktop\28035\f28035-rust-bridge\tools\llvm-c28x-env.ps1
& C:\Users\61987\Desktop\28035\f28035-rust-bridge\tools\build-cargo-gpio-blink.ps1
# 期望最后一行：CARGO_GPIO_BLINK_BUILD=PASS ...\build\c28x-gpio-blink\gpio_blink.out
```

---

## 5. 反汇编验证（已确认）

启动层（0x8001 起）：
```
MOV  SP, #0x0400
MOVL XAR4, #0x007029     ; WDCR
MOVB AL, #0x68           ; 关看门狗
MOV  *+XAR4[0], AL
LCR  main
```

main（0x800C 起）：
```
MOVL XAR0, #0x006f96     ; GPBMUX1 读改写（清 bits 5:4）
...
MOVL XAR0, #0x006f9a     ; GPBDIR，MOVB AL,#0x4（bit2=输出）
...
MOVL XAR0, #0x006fce     ; GPBTOGGLE，写 0x4（翻转 GPIO34）
...
B    -7, UNC             ; 回到 toggle 循环
```

---

## 6. 上板验证（待硬件连接后执行）

### 6.1 现状
```
> xds100serial.exe
Scanning for XDS100 emulators...
No XDS100 emulators were found on the system.
```
FTDI/XDS100 未插，或 USB 线未连。本次未烧录。

### 6.2 连接硬件后执行
```powershell
. C:\Users\61987\Desktop\28035\f28035-rust-bridge\tools\llvm-c28x-env.ps1
& D:\ti\ccstheia141\ccs\ccs_base\scripting\bin\dss.bat `
    C:\Users\61987\Desktop\28035\f28035-rust-bridge\tools\verify-cargo-gpio-blink-ram.js `
    C:\Users\61987\Desktop\28035\f28035-rust-bridge\targetConfigs\TMS320F28035_XDS100v1.ccxml `
    C:\Users\61987\Desktop\28035\f28035-rust-bridge\build\c28x-gpio-blink\gpio_blink.out
```

### 6.3 预期输出（PASS 判据）
```
RAM_LOAD=PASS ...
GPBMUX1(0x6f96)=0x....       ; bits 5:4 应为 00
GPBDIR(0x6f9a)=0x....         ; bit2 应为 1（0x4000 范围内 bit2=1）
GPBDAT(0x6fc8)=0x....         ; bit2 在 0/1 间翻转
PC=0x80.. main=0x800c blink_idle=0x800b
MUX34_GPIO=True DIR34_OUT=True PC_IN_MAIN_LOOP=True
CARGO_GPIO_BLINK_RAM=PASS
```

### 6.4 硬件观测
- GPIO34 引脚用万用表/示波器应测到方波翻转（频率由 delay loop `d<30000` 决定）。
- GPBDIR(0x6F9A) 读回应含 bit2=1；GPBMUX1(0x6F96) bits 5:4=00。

---

## 7. 遗留问题 / 后续

1. **dev profile 链接器内部错误**：C28x 后端在未优化代码的重定位扩展上有 bug，需要后端层修
   （section sh_size 与 relocation 展开后大小不一致）。临时绕过：固定 --release。
2. **任务书 `--unused_section_elimination=off` 约束**：因 core 体积过大，实测必须开段消除。
   若后续把 core 裁剪成最小集合（只含 panic + ptr intrinsic），可回到 off。
3. **c28x-rt/asm.s 启动层未用**：本次用了更简单的 RAM-only 启动 stub（同 bare_gpio34_ram_start.asm 模式）。
   c28x-rt/asm.s 的 .bss/.data/PIE 拷贝版本需要配套 cmd 符号，本次 RAM 验证用不到。
