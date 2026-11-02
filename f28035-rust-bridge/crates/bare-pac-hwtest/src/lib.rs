#![no_std]

// c28x-pac 校准位图的 B-1 真机验证（RAM 映像，零 C 运行时）。
// 寄存器地址/位域与 crates/c28x-pac/src/lib.rs 一致（2026-10-27 对表 DSP2803x_*.h）。
// MIR 后端只支持直线型 MMIO 序列：本探针无循环无分支，所有延时用 MMIO 空转
// 填充（filler），全部结果为原始观测值，由 dss 脚本读邮箱后精确比对。
//
// 邮箱 0x9E00 起（word）：
//   [0] 0xC001 起始
//   [1] GPBDAT&bit2 after SET  -> 0x0004
//   [2] GPBDAT&bit2 after CLEAR-> 0x0000
//   [3] TCR&0x8000 after 填充  -> 0x8000 (TIF bit15 置位)
//   [4] TCR&0x8000 after 0x8010-> 0x0000 (TIF w1c 清除+停止)
//   [5] SCIRXBUF&0xFF after 填充 -> 0x5A (SCI 环回, TXENA/RXENA/RXRDY 校准)
//   [6] SPIRXBUF&0xFF after 填充 -> 0xA5 (SPI 环回, INT_FLAG bit6)
//   [7] 0xC003 完成

struct Reg(u16);

impl Reg {
    #[inline(always)]
    fn read(&self) -> u16 {
        unsafe { (usize::from(self.0) as *const u16).read_volatile() }
    }

    #[inline(always)]
    fn write(&self, value: u16) {
        unsafe { (usize::from(self.0) as *mut u16).write_volatile(value) }
    }
}

const MAILBOX: u16 = 0x9E00;

#[inline(always)]
fn mark(index: u16, value: u16) {
    Reg(MAILBOX + index).write(value);
}

#[inline(always)]
fn filler(n: u16) {
    let mut i = n;
    while i != 0 {
        let _ = Reg(0x0C00).read(); // Timer0 TIM，读之无副作用
        i -= 1;
    }
}

// ---- 统一寄存器映射（= c28x-pac 校准后地址） ----
const GPB_MUX1: Reg = Reg(0x6F96);
const GPB_DIR: Reg = Reg(0x6F9A);
const GPB_DAT: Reg = Reg(0x6FC8);
const GPB_SET: Reg = Reg(0x6FCA);
const GPB_CLEAR: Reg = Reg(0x6FCC);

const TIMER0_TIM: Reg = Reg(0x0C00);
const TIMER0_PRD: Reg = Reg(0x0C02);
const TIMER0_TCR: Reg = Reg(0x0C04);
const TIMER0_TPR: Reg = Reg(0x0C06);

const SCIA_CCR: Reg = Reg(0x7050);
const SCIA_CTL1: Reg = Reg(0x7051);
const SCIA_HBAUD: Reg = Reg(0x7052);
const SCIA_LBAUD: Reg = Reg(0x7053);
const SCIA_CTL2: Reg = Reg(0x7054);
const SCIA_RXBUF: Reg = Reg(0x7057);
const SCIA_TXBUF: Reg = Reg(0x7059);
const SCIA_FFTX: Reg = Reg(0x705A);
const SCIA_FFRX: Reg = Reg(0x705B);
const SCIA_FFCT: Reg = Reg(0x705C);

const SPIA_CCR: Reg = Reg(0x7040);
const SPIA_CTL: Reg = Reg(0x7041);
const SPIA_STS: Reg = Reg(0x7042);
const SPIA_BRR: Reg = Reg(0x7044);
const SPIA_RXBUF: Reg = Reg(0x7047);
const SPIA_DAT: Reg = Reg(0x7049);

const GPIO34_BIT: u16 = 1 << 2;
const GPIO34_MUX_MASK: u16 = 3 << 4;

const TIF: u16 = 1 << 15; // TCR bit15, w1c（校准点：旧实现误写 bit4=TSS）

#[unsafe(no_mangle)]
pub extern "C" fn rust_pac_hwtest() {
    unsafe {
        mark(0, 0xC001);

        // ===== 1. GPIO34：GPBSET/GPBCLEAR 驱动 + GPBDAT 回读 =====
        GPB_MUX1.write(GPB_MUX1.read() & !GPIO34_MUX_MASK);
        GPB_DIR.write(GPB_DIR.read() | GPIO34_BIT);
        GPB_SET.write(GPIO34_BIT);
        filler(20);
        mark(1, GPB_DAT.read() & GPIO34_BIT);
        GPB_CLEAR.write(GPIO34_BIT);
        filler(20);
        mark(2, GPB_DAT.read() & GPIO34_BIT);

        // ===== 2. Timer0：TIF=TCR bit15（w1c），TSS=bit4，TRB=bit5 =====
        TIMER0_TCR.write(1 << 4); // 停止
        TIMER0_PRD.write(0x0002); // 2 ticks
        TIMER0_TPR.write(0x000F); // TDDR=15 -> 每 16 cycles 一 tick
        TIMER0_TCR.write((1 << 4) | (1 << 5)); // 停止+重装
        TIMER0_TCR.write(0x0000); // 启动
        filler(60); // > 2*16 cycles，TIF 必已置位
        mark(3, TIMER0_TCR.read() & TIF); // 期望 0x8000
        TIMER0_TCR.write(TIF | (1 << 4)); // w1c 清 TIF + 停止（=桥 timer0_ack 语义 0x8010）
        filler(20);
        mark(4, TIMER0_TCR.read() & TIF); // 期望 0x0000

        // ===== 3. SCI-A 内部环回（FIFO）：TXENA(bit1)/RXENA(bit0)/SWRESET(bit5) =====
        // RXRDY=FIFO RXFFST；校准点：旧实现 SCICTL1 未开 TXENA/RXENA，
        // 且非 FIFO RXRDY 误轮询保留位 bit0（实际 bit6）
        SCIA_CTL1.write(0x0000);
        SCIA_CCR.write((1 << 4) | 0x0007); // LOOPBKENA + 8-bit
        SCIA_HBAUD.write(0x0000);
        SCIA_LBAUD.write(0x0000); // BRR=0 最快波特率，缩短字节时间
        SCIA_FFTX.write((1 << 15) | (1 << 14) | (1 << 13)); // SCIRST+SCIFFENA+TXFIFORESET
        SCIA_FFRX.write(1 << 13); // RXFIFORESET
        SCIA_FFCT.write(0x0000);
        SCIA_CTL2.write(0x0000);
        SCIA_CTL1.write((1 << 5) | (1 << 1) | (1 << 0)); // SWRESET+TXENA+RXENA
        filler(200); // FIFO 复位 + SWRESET 释放
        SCIA_TXBUF.write(0x005A);
        filler(150); // >10 bit 时间
        mark(5, SCIA_RXBUF.read() & 0x00FF); // 期望 0x5A

        // ===== 4. SPI-A 内部环回（SPILBK bit4）：INT_FLAG = SPISTS bit6 =====
        SPIA_CTL.write(0x0000);
        SPIA_CCR.write(0x0007); // 复位态 + 8-bit
        SPIA_BRR.write(0x0000);
        SPIA_CTL.write((1 << 2) | (1 << 1)); // MASTER + TALK
        SPIA_CCR.write((1 << 7) | (1 << 6) | (1 << 4) | 0x0007); // SWRESET+CLKPOL+SPILBK
        let _ = SPIA_RXBUF.read(); // 清残留标志
        SPIA_DAT.write(0x00A5);
        filler(150);
        mark(6, SPIA_RXBUF.read() & 0x00FF); // 期望 0xA5

        mark(7, 0xC003);
    }
}
