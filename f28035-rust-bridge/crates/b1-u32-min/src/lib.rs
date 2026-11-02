#![no_std]

// 极小复现：两个 u16 合成 u32 后与 32 位字面量比较。
//
// 由 crates/b1-u32-compose 收窄而来，只保留一条表达式，便于逐条单步定位。
// 邮箱 0x9E00（word）：
//   [0] composed 低半字   期望 0x5678
//   [1] composed 高半字   期望 0x1234
//   [2] (k == 0x12345678) 期望 1
//   [3] (k != 0x12345678) 期望 0
//   [4] 0xC0DE 完成

struct Reg(u16);

impl Reg {
    #[inline(always)]
    // B-1 后端把指针当 BYTE 地址（间接访问时 ROR ÷2），故字地址 ×2。
    fn read(&self) -> u16 {
        unsafe { ((u32::from(self.0) * 2) as *const u16).read_volatile() }
    }
    #[inline(always)]
    fn write(&self, value: u16) {
        unsafe { ((u32::from(self.0) * 2) as *mut u16).write_volatile(value) }
    }
}

const MAILBOX: u16 = 0x9E00;
const IN_LO: u16 = 0x9F00;
const IN_HI: u16 = 0x9F01;

#[inline(always)]
fn mark(i: u16, v: u16) {
    Reg(MAILBOX + i).write(v);
}

#[unsafe(no_mangle)]
pub extern "C" fn rust_u32_probe() {
    Reg(IN_LO).write(0x5678);
    Reg(IN_HI).write(0x1234);

    let lo: u16 = Reg(IN_LO).read();
    let hi: u16 = Reg(IN_HI).read();

    let k: u32 = (lo as u32) | ((hi as u32) << 16);

    mark(0, (k & 0xFFFF) as u16);
    mark(1, (k >> 16) as u16);
    mark(2, if k == 0x12345678 { 1 } else { 0 });
    mark(3, if k != 0x12345678 { 1 } else { 0 });
    mark(4, 0xC0DE);
}
