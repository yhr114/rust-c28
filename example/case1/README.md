# case1：调用 F28035 安全 HAL

这是独立的 Rust 项目。应用源码只写在 `src/main.rs`；`Cargo.toml` 通过相对路径依赖 `../../f28035-rust-bridge/sdk/f28035-safe-hal`。构建脚本直接读取这个文件，不会复制到 `crates/rust-api`。

## 如何使用底层库

在 `src/main.rs` 中导入安全接口：

```rust
#![no_std]
use f28035_safe_hal::{Peripherals, delay_us, system_init};

#[unsafe(no_mangle)]
pub extern "C" fn rust_main() {
    system_init();
    let mut peripherals = Peripherals::take().unwrap();
    let button = peripherals.gpio.input::<34>().expect("GPIO34 input rejected");
    let mut gpio39 = peripherals.gpio.output::<39>().expect("GPIO39 output rejected");
    let mut adc0 = peripherals.adc.into_soc0::<0, 7>().expect("ADC0 setup rejected");

    loop {
        let adc = adc0.sample();
        let button_high = button.read();
        if button_high || adc > 2048 {
            gpio39.set_low();
        }
        delay_us(50_000);
    }
}
```

`system_init()` 初始化芯片；`Peripherals::take()` 取得唯一的外设所有权。`input::<34>()` 取得 GPIO34 输入句柄，`output::<39>()` 取得 GPIO39 输出句柄。`into_soc0::<0, 7>()` 将 ADC SOC0 配为通道 0、采样窗口 7，并生成绑定通道 0 的句柄；之后 `adc0.sample()` 每轮采样，不能误采其他通道。GPIO34 为高或 ADC 读数大于 2048 时，GPIO39 拉低；每轮再通过 `delay_us(50_000)` 延时约 50 ms。`rust_main` 是 TI 启动代码调用的入口，名称和 `extern "C"` 声明需保留。

安全 HAL 的 API 可在 `../../f28035-rust-bridge/sdk/f28035-safe-hal/src/lib.rs` 查签名。目标端的 `rust-to-ti-c` 现在识别本例的 GPIO 输入/输出、ADC 配置与采样、`if button_high || adc > 常量`、`loop` 和常量微秒延时。可以改引脚、ADC 通道、采样窗口、阈值和延时常量，但目前要保留这些调用的结构与顺序。它仍是受限转换器；增加其他 Rust 写法后，需要运行 `build.ps1` 确认目标端支持。**Cargo 检查通过本身不等于固件能生成。**

安全约束：同一 GPIO 引脚只能有一个输入、输出或外部中断句柄；持有句柄时 `set_mux` 会拒绝改动该引脚的复用功能。ADC 推荐使用 `into_soc0::<通道, 采样窗口>()` 取得通道绑定句柄，再调用不带通道参数的 `sample()`。旧的 `configure_soc0` 与 `sample::<通道>()` 仍保留给现有代码，但不会在 Rust 类型层阻止通道不匹配。

SPI、I²C、SCI 中的部分方法仍执行固定的 C 自检用例。目标端现在会校验 SPI 自检必须使用 8 位字符、I²C 自检地址必须为 `0x36`；SCI 的带波特率或字符长度参数的旧方法会报错，请改用 `baud_program_self_test()`、`internal_loopback_self_test()` 或 `loopback_data_pattern_self_test()`。这些方法是自检，不能当作可传入任意数据的通信接口。

## 构建

在 PowerShell 中运行：

```powershell
cd C:\Users\61987\Desktop\28035\example\case1
.\build.ps1
```

脚本先用 Cargo 检查 SDK API，再通过现有 C 桥、TI 启动代码及 TI 编译器生成 `build/case1_ram.out`。单独运行 `cargo check` 只检查 Rust 类型，`cargo run` 不能在 Windows 主机运行 F28035 固件。如已连接目标板，可运行 `.\build.ps1 -Verify`，经 XDS100v1 将 RAM 固件下载并检查 GPIO34/39 与 ADC 采样计数；不会写入 Flash。需要的 TI/Cargo 路径在 `../../f28035-rust-bridge/tools/toolchain.ps1` 中配置。
