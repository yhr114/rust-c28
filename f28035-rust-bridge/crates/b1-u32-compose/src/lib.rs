#![no_std]

// 最小复现：两个 u16 合成 u32 后与字面量比较。
//
// 背景：c28x-cargo-runtime 的 context_errors() 用
//   let low = read(p.add(i)) as u32;
//   let high = read(p.add(i+1)) as u32;
//   if low | (high << 16) != 0x12345678 { errors += 1 }
// 在真机上 10/10 全部判错，而同一数组被 dss 逐字读回完全正确；
// 改为逐半字比较后通过。本探针把中间量与比较结果全部落到邮箱，
// 由 dss 精确读回，判定退化发生在「合成」还是「比较」。
//
// 邮箱 0x9E00（word）：
//   [0] IN_LO 回读         期望 0x5678
//   [1] IN_HI 回读         期望 0x1234
//   [2] composed 低半字     期望 0x5678
//   [3] composed 高半字     期望 0x1234
//   [4] (composed == 0x12345678)  期望 1
//   [5] (composed != 0x12345678)  期望 0
//   [6] (hi32 << 16) 高半字 期望 0x1234
//   [7] mul 合成的高半字    期望 0x1234   ((lo as u32) + (hi as u32) * 65536)
//   [8] composed == composed2     期望 1（运行期 vs 运行期）
//   [9] (lo as u32) 高半字  期望 0x0000（零扩展是否正确）
//  [10] 0xC0DE 完成

struct Reg(u16);

impl Reg {
    #[inline(always)]
    // B-1 LLVM 后端把指针视为 BYTE 地址（每次间接访问 ROR ÷2），
    // 故字地址必须 ×2（与 c28x-pac 的 Reg 一致）。
    fn read(&self) -> u16 {
        unsafe { ((u32::from(self.0) * 2) as *const u16).read_volatile() }
    }
    #[inline(always)]
    fn write(&self, value: u16) {
        unsafe { ((u32::from(self.0) * 2) as *mut u16).write_volatile(value) }
    }
}

const MAILBOX: u16 = 0x9E00;
const IN_LO: u16 = 0x9F00; // 输入暂存（volatile 写入后读，避免常量折叠）
const IN_HI: u16 = 0x9F01;

#[inline(always)]
fn mark(i: u16, v: u16) {
    Reg(MAILBOX + i).write(v);
}

#[unsafe(no_mangle)]
pub extern "C" fn rust_u32_probe() {
    // 写入输入（volatile），确保合成走真实的内存加载路径
    Reg(IN_LO).write(0x5678);
    Reg(IN_HI).write(0x1234);

    let lo: u16 = Reg(IN_LO).read();
    let hi: u16 = Reg(IN_HI).read();
    mark(0, lo);
    mark(1, hi);

    // ---- 原表达式：两个 u16 合成 u32 ----
    let composed: u32 = (lo as u32) | ((hi as u32) << 16);
    mark(2, (composed & 0xFFFF) as u16);
    mark(3, (composed >> 16) as u16);
    mark(4, if composed == 0x12345678 { 1 } else { 0 });
    mark(5, if composed != 0x12345678 { 1 } else { 0 });

    // ---- 对照：只做移位 ----
    let shifted: u32 = (hi as u32) << 16;
    mark(6, (shifted >> 16) as u16);

    // ---- 对照：乘法合成 ----
    let composed2: u32 = (lo as u32) + (hi as u32) * 65536;
    mark(7, (composed2 >> 16) as u16);
    mark(8, if composed == composed2 { 1 } else { 0 });

    // ---- 对照：u16 -> u32 零扩展 ----
    mark(9, ((lo as u32) >> 16) as u16);

    // ---- 判别实验 ----
    // 从内存读一份"常量"（volatile），避免任何常量折叠
    Reg(0x9F02).write(0x5678);
    Reg(0x9F03).write(0x1234);
    let lo2: u16 = Reg(0x9F02).read();
    let hi2: u16 = Reg(0x9F03).read();
    let ref_val: u32 = (lo2 as u32) | ((hi2 as u32) << 16); // 运行期同值

    mark(11, if composed == ref_val { 1 } else { 0 }); // 运行期相等 → 期望 1
    mark(12, if composed != ref_val { 1 } else { 0 }); // 期望 0
    let diff: u32 = composed.wrapping_sub(ref_val);
    mark(13, (diff & 0xFFFF) as u16);                  // 期望 0
    mark(14, (diff >> 16) as u16);                     // 期望 0
    mark(15, if diff == 0 { 1 } else { 0 });           // 期望 1

    // ---- 常量物化语义实验：反推"字面量"实际被物化成什么 ----
    // k 从内存读出，确保是运行期值；再与字面量做减法，差值的两个半字
    // 精确揭示编译器为该字面量物化出的 32 位值。
    Reg(0x9F04).write(0x5678);
    Reg(0x9F05).write(0x1234);
    let lo3: u16 = Reg(0x9F04).read();
    let hi3: u16 = Reg(0x9F05).read();
    let k: u32 = (lo3 as u32) | ((hi3 as u32) << 16); // 运行期 0x12345678
    // 判别：把 k 及输入直接落到邮箱，定位合成到底在哪一步错
    mark(25, (k & 0xFFFF) as u16); // 期望 0x5678
    mark(26, (k >> 16) as u16);    // 期望 0x1234
    mark(27, lo3);                 // 期望 0x5678
    mark(28, hi3);                 // 期望 0x1234
    let sh3: u32 = (hi3 as u32) << 16;
    mark(29, (sh3 & 0xFFFF) as u16); // 期望 0x0000
    mark(30, (sh3 >> 16) as u16);    // 期望 0x1234

    // 对照：u32 直接来自内存（不是算出来的），与同一字面量比较
    Reg(0x9F08).write(0x5678);
    Reg(0x9F09).write(0x1234);
    let v: u32 = unsafe { ((u32::from(0x9F08u16) * 2) as *const u32).read_volatile() };
    mark(31, (v & 0xFFFF) as u16);                 // 期望 0x5678
    mark(32, (v >> 16) as u16);                    // 期望 0x1234
    mark(33, if v == 0x12345678 { 1 } else { 0 }); // 期望 1
    let d: u32 = k.wrapping_sub(0x12345678);
    mark(16, (d & 0xFFFF) as u16); // 差值低半字
    mark(17, (d >> 16) as u16);    // 差值高半字
    mark(18, if k == 0x12345678 { 1 } else { 0 }); // 与字面量比较
    mark(19, if k == 0x12340000 { 1 } else { 0 }); // 高半字字面量比较
    mark(20, if k == 0x00005678 { 1 } else { 0 }); // 低半字字面量比较

    // ---- 字面量物化真值实验：c ^ 1（one 为运行期，防常量折叠）----
    Reg(0x9F06).write(0x0001);
    let one: u16 = Reg(0x9F06).read();
    let c: u32 = 0x12345678;
    let probe: u32 = c ^ (one as u32);
    mark(21, (probe & 0xFFFF) as u16); // 期望 0x5679
    mark(22, (probe >> 16) as u16);    // 期望 0x1234
    let probe2: u32 = (one as u32).wrapping_sub(c); // 1 - c
    mark(23, (probe2 & 0xFFFF) as u16); // 期望 0xA989 (0xEDCBA988 低半字)
    mark(24, (probe2 >> 16) as u16);    // 期望 0xEDCB

    mark(10, 0xC0DE);
}
