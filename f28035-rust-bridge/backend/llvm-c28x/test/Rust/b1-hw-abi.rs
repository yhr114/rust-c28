#![cfg_attr(not(test), no_std)]
#![cfg_attr(not(test), no_main)]

// Hardware RAM/JTAG sample for the B-1 direct-object route: argument ABI
// closure for the cases PATH_B lists as still open (sret, stack arguments,
// mixed (i16, ptr, i32) placement).
//
//   1. pointer pool      - pointer arguments arrive in XAR4 (oracle: TI too)
//   2. sret in XAR6      - a #[repr(C)] aggregate return uses the hidden
//                          return-buffer pointer in XAR6 on both sides
//                          (exercised Rust->Rust: the TI C ABI hands the
//                          hidden pointer over as a raw word address while
//                          the Rust callee halves it, so a cross-language
//                          struct return is NOT equivalent)
//   3. indirect calls    - a function-pointer argument is called through
//                          LCR *XARn (logical byte -> word conversion)
//   4. stack arguments   - 5 u16 + 1 u32 forces e onto the first stack word
//                          and f onto the next two; cross-basic-block reads,
//                          nested calls and the 32-bit word order are pinned
//                          by weighted checksums that cannot cancel.
//
// The TI C driver uses the same cl2000 EABI, so every check below doubles as
// a Rust<->TI C interop check.

#[repr(C)]
pub struct AbiPair {
    pub ptr: u32,
    pub len: u32,
}

/// Aggregate return through the hidden sret pointer (XAR6), exercised on the
/// Rust->Rust path: `rust_sret_self_check` calls the private callee, so both
/// sides agree on the logical-byte pointer convention.
#[no_mangle]
#[inline(never)]
fn make_pair(ptr: u32, len: u32) -> AbiPair {
    AbiPair { ptr, len }
}

#[no_mangle]
#[inline(never)]
pub extern "C" fn rust_sret_self_check(ptr: u32, len: u32) -> u32 {
    // Weighted so a swapped field pair cannot produce the same checksum:
    // ptr*3+len = 0x5555, len*3+ptr = 0x7777.
    let pair = make_pair(ptr, len);
    pair.ptr.wrapping_mul(3).wrapping_add(pair.len)
}

/// Pointer argument: must arrive in XAR4 as a logical byte address.
#[no_mangle]
#[inline(never)]
pub extern "C" fn rust_read_ptr(data: *const u32) -> u32 {
    unsafe { core::ptr::read_volatile(data) }
}

/// Mixed (i16, ptr, i32) -> a=AR5, p=XAR4, b=ACC (TI EABI oracle rule).
#[no_mangle]
#[inline(never)]
pub extern "C" fn rust_mixed(a: u16, data: *const u16, b: u32) -> u32 {
    // Weighted so a mis-selected operand cannot cancel out:
    // 1 + 7*4 + 2*16 = 61 (b swapped with *p would give 121).
    let pinned = unsafe { core::ptr::read_volatile(data) };
    u32::from(a)
        .wrapping_add(u32::from(pinned).wrapping_mul(4))
        .wrapping_add(b.wrapping_mul(16))
}

/// Indirect call through a function pointer (LCR *XARn).
#[no_mangle]
#[inline(never)]
pub extern "C" fn rust_apply(apply: extern "C" fn(u32) -> u32, value: u32) -> u32 {
    apply(value)
}

/// Stack-argument path: 5 u16 + 1 u32 forces e onto the first stack word and
/// f onto the next two.  Sum is 21 when every word lands where the callee
/// reads it.
#[no_mangle]
#[inline(never)]
pub extern "C" fn rust_stack_args(a: u16, b: u16, c: u16, d: u16, e: u16, f: u32) -> u32 {
    u32::from(a)
        .wrapping_add(u32::from(b))
        .wrapping_add(u32::from(c))
        .wrapping_add(u32::from(d))
        .wrapping_add(u32::from(e))
        .wrapping_add(f)
}

/// Cross-basic-block stack access: the successor blocks read the spilled
/// stack arguments, and the inner call makes this function non-leaf so the
/// prologue saves a callee-saved register.  Frame-index addressing must
/// compensate that push for accesses in EVERY block, not just the entry
/// block (a per-block scan used to miss it and read one word off).
/// Weighted per branch so the two paths cannot cancel:
///   odd  (sel=3): (a + e + f) + inner = (1 + 5 + 6) + 21 = 33
///   even (sel=4): (b + c + f) + inner = (2 + 3 + 6) + 21 = 32
#[no_mangle]
#[inline(never)]
pub extern "C" fn rust_bb_args(a: u16, b: u16, c: u16, d: u16, e: u16, f: u32,
                              sel: u16) -> u32 {
    let branch_sum = if sel & 1 != 0 {
        u32::from(a).wrapping_add(e as u32).wrapping_add(f)
    } else {
        u32::from(b).wrapping_add(c as u32).wrapping_add(f)
    };
    // Inner call: outgoing stack arguments are written while the branch's
    // reads are already done, and the call forces the prologue push.
    rust_stack_args(a, b, c, d, e, f).wrapping_add(branch_sum)
}

/// Nested calls: this function receives stack arguments AND makes two
/// successive calls, each with its own outgoing stack argument area.  The
/// incoming arguments (read after both calls below) and the locals must
/// survive both outgoing areas.
///   first  = rust_stack_args(1,2,3,4,5,6)      = 21
///   second = rust_stack_args(5,4,3,2,1,6)      = 21
///   result = first*3 + second + f = 63 + 21 + 6 = 90
#[no_mangle]
#[inline(never)]
pub extern "C" fn rust_nested(a: u16, b: u16, c: u16, d: u16, e: u16, f: u32) -> u32 {
    let first = rust_stack_args(a, b, c, d, e, f);
    let second = rust_stack_args(e, d, c, b, a, f);
    first.wrapping_mul(3)
        .wrapping_add(second)
        .wrapping_add(f)
}

/// C->Rust 32-bit stack-argument word order: `b` arrives on the stack (two
/// words) while `a` takes ACC.  Returning it intact proves the two halves
/// land where the callee reads them -- a swapped pair would come back as
/// 0x56781234 instead of 0x12345678.
#[no_mangle]
#[inline(never)]
pub extern "C" fn rust_stk32_echo(_a: u32, b: u32) -> u32 {
    b
}

#[cfg(not(test))]
#[panic_handler]
fn panic(_info: &core::panic::PanicInfo) -> ! {
    loop {}
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn abi_shapes_behave_on_host() {
        assert_eq!(rust_sret_self_check(0x1111, 0x2222), 0x5555);

        let data = [0x1234u32];
        assert_eq!(rust_read_ptr(data.as_ptr()), 0x1234);

        let words = [7u16];
        assert_eq!(rust_mixed(1, words.as_ptr(), 2), 61);

        extern "C" fn double(v: u32) -> u32 {
            v.wrapping_mul(2)
        }
        assert_eq!(rust_apply(double, 21), 42);
        assert_eq!(rust_stack_args(1, 2, 3, 4, 5, 6), 21);
        assert_eq!(rust_bb_args(1, 2, 3, 4, 5, 6, 3), 33);
        assert_eq!(rust_bb_args(1, 2, 3, 4, 5, 6, 4), 32);
        assert_eq!(rust_nested(1, 2, 3, 4, 5, 6), 90);
        assert_eq!(rust_stk32_echo(0, 0x12345678), 0x12345678);
    }
}
