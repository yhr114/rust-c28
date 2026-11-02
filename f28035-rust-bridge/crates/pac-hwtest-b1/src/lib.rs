//! c28x-pac 校准位图的 B-1 真机验证（LLVM 后端路径）。
//!
//! 与 crates/bare-pac-hwtest（MIR 路径）不同，本探针直接依赖**真身**
//! c28x-pac crate，由 active B-1 bundle rustc（c28x-none-elf 目标）编译，
//! 与 C 启动壳（platform/runtime/pac_hwtest_ram_start.asm，保持 EALLOW）
//! 经 TI cl2000 链接进 RAM 映像。dss 读 RAM 邮箱 0x9E00 判 PASS：
//!
//!   [0] 0xC001 起始
//!   [1] GPBDAT&bit2 after GPBSET  -> 0x0004（GPIO34 输出高回读）
//!   [2] GPBDAT&bit2 after GPBCLEAR-> 0x0000
//!   [3] TCR&0x8000 after 延时     -> 0x8000（TIF=bit15 置位，校准点）
//!   [4] TCR&0x8000 after 0x8010   -> 0x0000（TIF w1c 清除 + TSS 停止）
//!   [5] SCIRXBUF&0xFF after 延时  -> 0x005A（SCI 内部环回，TXENA/RXENA/SWRESET 校准）
//!   [6] SPIRXBUF&0xFF after 延时  -> 0x00A5（SPI SPILBK 环回，INT_FLAG=bit6）
//!   [7] 0xC003 完成
//!
//! EALLOW 由启动壳保持常开（与 c28x-pac 启动约定一致），Peripherals::eallow
//! 的 EALLOW/EDIS 指令对在保护区写期间成对执行。

#![no_std]
#![no_main]

use c28x_pac::{Peripherals, Reg};

const MAILBOX: Reg = Reg::at(0x9E00);
const TIF: u16 = 1 << 15; // TCR bit15, w1c
const GPIO34_BIT: u16 = 1 << 2; // GPB bit2 = GPIO34
const GPIO34_MUX_MASK: u16 = 3 << 4; // GPBMUX1 bits 5:4

#[inline(always)]
fn mark(index: u16, value: u16) {
    unsafe { Reg::at(0x9E00 + index).write(value) }
}

#[inline(always)]
fn filler(n: u16) {
    let mut i = n;
    while i != 0 {
        let _ = unsafe { Reg::at(0x0C00).read() }; // Timer0 TIM，读之无副作用
        i -= 1;
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn rust_pac_hwtest() {
    let p = unsafe { Peripherals::steal() };

    mark(0, 0xC001);

    // ===== 0. 外设时钟门（复位值全关）：SCIAENCLK=bit10、SPIAENCLK=bit8 =====
    // Timer0/GPIO 不经 PCLKCR0 门控，SCI/SPI 必须显式开时钟
    {
        let ea = p.eallow();
        unsafe { p.sysctrl.pclkcr0.set_bits((1 << 10) | (1 << 9) | (1 << 8), &ea) }
    }
    filler(20);

    // ===== 1. GPIO34：GPBSET/GPBCLEAR 驱动 + GPBDAT 回读 =====
    {
        let ea = p.eallow();
        unsafe {
            p.gpio
                .gpbmux1
                .clear_bits(GPIO34_MUX_MASK, &ea); // GPIO 功能
            p.gpio.gpbdir.set_bits(4, &ea); // GPIO34 输出（32 位 GPBDIR，校准点）
        }
    }
    unsafe { p.gpio.gpbset.write(4) };
    filler(20);
    mark(1, (unsafe { p.gpio.gpbdat.read() } & (GPIO34_BIT as u32)) as u16);
    unsafe { p.gpio.gpbclear.write(4) };
    filler(20);
    mark(2, (unsafe { p.gpio.gpbdat.read() } & (GPIO34_BIT as u32)) as u16);

    // ===== 2. Timer0：TIF=TCR bit15（w1c），TSS=bit4，TRB=bit5 =====
    unsafe {
        p.cputimer0.tcr.write(1 << 4); // 停止
        p.cputimer0.prd.write(0x0000_0002); // 2 ticks（32 位 PRD，校准位宽）
        p.cputimer0.tpr.write(0x000F); // TDDR=15 -> 16 cycles/tick
        p.cputimer0.tcr.write((1 << 4) | (1 << 5)); // 停止+重装
        p.cputimer0.tcr.write(0x0000); // 启动
    }
    filler(60);
    mark(3, unsafe { p.cputimer0.tcr.read() } & TIF); // 期望 0x8000
    unsafe {
        p.cputimer0.tcr.write(TIF | (1 << 4)); // w1c 清 TIF + 停止
    }
    filler(20);
    mark(4, unsafe { p.cputimer0.tcr.read() } & TIF); // 期望 0x0000

    // ===== 3. SCI-A 内部环回（FIFO）：TXENA/RXENA/SWRESET 校准 =====
    unsafe {
        p.scia.scictl1.write(0x0000); // SWRESET=0
        p.scia.sciccr.write((1 << 4) | 0x0007); // LOOPBKENA + 8-bit
        p.scia.scihbaud.write(0x0000);
        p.scia.scilbaud.write(0x0000); // BRR=0 最快
        p.scia
            .scifftx
            .write((1 << 15) | (1 << 14) | (1 << 13)); // SCIRST+SCIFFENA+TXFIFORESET
        p.scia.sciffrx.write(1 << 13); // RXFIFORESET
        p.scia.sciffct.write(0x0000);
        p.scia.scictl2.write(0x0000);
        p.scia.scictl1.write((1 << 5) | (1 << 1) | (1 << 0)); // SWRESET+TXENA+RXENA
    }
    filler(200);
    unsafe { p.scia.scitxbuf.write(0x005A) };
    filler(150);
    mark(5, unsafe { p.scia.scirxbuf.read() } & 0x00FF); // 期望 0x5A

    // ===== 4. SPI-B 内部环回：逐字对齐桥 f28035_spi_internal_loopback_basic
    //         （该序列已在此板通过真机验证）。SPI-B 避开 SPI-A 引脚复用，
    //         SPITXBUF 左对齐（RXBUF 取 >>8）。
    {
        let ea = p.eallow();
        unsafe {
            p.spib.spiccr.write(0x0017); // SWRESET=0 + SPILBK + 8-bit
            p.spib.spictl.write(0x000E); // CLK_PHASE|MASTER|TALK|SPIINTENA
            p.spib.spibrr.write(0x0003);
        }
        let _ea = ea; // EALLOW 区间结束（Drop → EDIS）
    }
    unsafe {
        p.spib.spifftx.write(0xA000); // SPIRST + TXFIFORESET
        p.spib.spiffrx.write(0x2000); // RXFIFORESET
    }
    {
        let ea = p.eallow();
        unsafe { p.spib.spiccr.write(0x0097) } // SWRESET 释放
        let _ = ea;
    }
    unsafe { p.spib.spitxbuf.write(0x003C) };
    filler(150); // > 8.5µs 字节时间（BRR=3）
    mark(6, (unsafe { p.spib.spirxbuf.read() } >> 8) & 0x00FF); // 期望 0x3C

    mark(7, 0xC003);
}

#[panic_handler]
fn pac_hwtest_panic(_info: &core::panic::PanicInfo) -> ! {
    loop {
        core::hint::spin_loop();
    }
}

