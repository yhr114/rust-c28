#![cfg_attr(not(test), no_std)]
#![cfg_attr(not(test), no_main)]

//! Broad `core` exercise for the B-1 patched-rustc direct-object route.
//!
//! HARDWARE STATUS (2026-10-22, F28035 RAM/JTAG): Group A now fully passes,
//! including pattern=223; Group E passes 16/16, C=132 and D=42967. Active
//! bundle 20261022-180241-07b9d869-83f8a0e3 contains the validated compiler
//! and sysroot. The current host source passes 14/14 with the GNU linker.
//! B/B2 iterator-adaptor hardware coverage remains open; see PATH_B.md.
//!
//! The old sret diagnosis was wrong: tracing proves iter() returns the correct
//! start/end pointers. NonNull::eq lost flags to PHI copies/spills between
//! SUBL and B EQ; atomic compare/branch fixes whilelet (pattern 148 -> 163).
//! MOVL immediate encoding also truncated upper bits (0x50001 -> 1), losing
//! enum payloads. Extracting those bits before narrowing fixes shapes and
//! completes pattern (163 -> 223). Both regressions are covered by MC tests.
//!
//! Earlier history (all resolved or superseded):
//! 1. `core_ex_option` returning 138 was the AND32/OR32/XOR32_PSEUDO
//!    post-RA expansion losing Lhs (and an XAR0/AR0 subregister clobber);
//!    fixed 2026-10-21 evening, oracle in verify-llvm-c28x.ps1 (`and32.ll`).
//! 2. `core_ex_pattern` used to die in `rust_begin_unwind`: core's
//!    `Iter::next` instantiations carried `-Zub-checks` preconditions that
//!    mis-evaluate on this backend.  The core sysroot is now built with
//!    `-Zub-checks=no` (matching the route policy of this script); the panic
//!    is gone.
//! 3. LLVM constant-folds small pure argument-free entries (result, mem,
//!    cmp, closure, convert, arith, index) into `MOVB AL,#imm; LRETR`
//!    two-word bodies, so those results are compile-time constants, not
//!    evidence of working codegen.  Only entries that call into `core`'s
//!    object (option, pattern, iter_slice, slice_search, str) exercise real
//!    machine code.
//!
//! Every `core_ex_*` function is a separate `#[no_mangle] extern "C"` entry so
//! the TI C driver (`tools/hw_rust_core_ex_driver.c`) can call it, store the
//! u16 result in `HW_CORE_RESULT`, and the DSS readback script
//! (`tools/dss-read-rust-core-ex.js`) can compare against the host-computed
//! expected values.  The `tests` module below runs on the host via
//! `rustc --test` and pins the same expected values, so host and hardware
//! assertions cannot drift apart.
//!
//! Coverage: Option/Result combinators, iterator adaptors, slice search and
//! windowed ops, comparisons, mem, wrapping/overflowing arithmetic and bit
//! tricks, pattern matching (enum/slice/if-let/while-let/let-else/or-patterns),
//! str/UTF-8/parse, bounds-checked indexing (safe indexing), conversions,
//! closures/fn pointers/recursion, and a C-supplied slice through the frozen
//! logical-byte pointer ABI.

use core::num::Wrapping;

// ---------- 1. Option combinators ----------
#[no_mangle]
#[inline(never)]
pub extern "C" fn core_ex_option() -> u16 {
    let mapped = Some(21u16)
        .map(|x| x.wrapping_mul(2))
        .and_then(|x| Some(x.wrapping_add(1)));
    let fallback = None::<u16>.unwrap_or(77);
    let filtered = Some(5u16).filter(|x| *x > 3).map(|x| x.wrapping_mul(2));
    let from_result = Some(5u16).ok_or(9u16).unwrap_or(0);
    let flags = (Some(1u16).is_some() as u16) * 2 + (None::<u16>.is_none() as u16) * 3;
    mapped
        .unwrap_or(0)
        .wrapping_add(fallback)
        .wrapping_add(filtered.unwrap_or(0))
        .wrapping_add(from_result)
        .wrapping_add(flags)
}

// ---------- 2. Result combinators ----------
#[no_mangle]
#[inline(never)]
pub extern "C" fn core_ex_result() -> u16 {
    let ok = Ok::<u16, u16>(30)
        .map(|x| x.wrapping_add(2))
        .map_err(|e| e.wrapping_add(100));
    let recovered: Result<u16, u16> = Err::<u16, u16>(7).or_else(|e| Ok(e.wrapping_mul(3)));
    let as_ok = Err::<u16, u16>(7).ok();
    let as_err = Ok::<u16, u16>(7).err();
    ok.unwrap_or(0)
        .wrapping_add(recovered.unwrap_or(0))
        .wrapping_add(as_ok.unwrap_or(1))
        .wrapping_add(as_err.unwrap_or(0))
}

// ---------- 3. Iterator adaptors over a C-supplied slice ----------
// The TI C driver supplies a word pointer; the frozen ABI makes Rust pointers
// logical byte addresses, so the driver doubles the word address before the
// call (same contract as b1-hw-control.rs rust_sum_slice).
#[no_mangle]
#[inline(never)]
pub extern "C" fn core_ex_iter_slice(ptr: *const u16, len: u16) -> u16 {
    let values: &[u16] = unsafe { core::mem::transmute((ptr, len as usize)) };
    let map_filter_sum: u16 = values
        .iter()
        .map(|x| x.wrapping_mul(3))
        .filter(|x| *x > 9)
        .sum();
    let counted = values.iter().filter(|x| **x % 2 == 0).count() as u16;
    let positioned = values.iter().position(|x| *x == 6).unwrap_or(99) as u16;
    let any = values.iter().any(|x| *x > 7) as u16;
    let all = values.iter().all(|x| *x > 0) as u16;
    let find = values.iter().find(|x| **x == 4).copied().unwrap_or(0);
    let nth = values.iter().nth(2).copied().unwrap_or(0);
    let last = values.iter().last().copied().unwrap_or(0);
    map_filter_sum
        .wrapping_add(counted)
        .wrapping_add(positioned)
        .wrapping_add(any)
        .wrapping_add(all)
        .wrapping_add(find)
        .wrapping_add(nth)
        .wrapping_add(last)
}

// Second half of the iterator-adaptor coverage, split into its own group (B2)
// so each image fits the 0x2000-word F28035 program RAM.  core_ex_iter_slice
// above and this function together reproduce the original 170 result
// (80 + 90).  Both are compiled into core_ex.obj; the per-group C driver
// references only one, and --unused_section_elimination drops the other.
#[no_mangle]
#[inline(never)]
pub extern "C" fn core_ex_iter_slice2(ptr: *const u16, len: u16) -> u16 {
    let values: &[u16] = unsafe { core::mem::transmute((ptr, len as usize)) };
    let enumerate_fold: u16 = values
        .iter()
        .enumerate()
        .fold(0u16, |acc, (i, x)| acc.wrapping_add((i as u16).wrapping_mul(*x)));
    let zip_sum: u16 = values
        .iter()
        .zip(values.iter().skip(1))
        .map(|(a, b)| a.wrapping_add(*b))
        .sum();
    let rev_sum: u16 = values.iter().rev().copied().sum();
    enumerate_fold
        .wrapping_add(zip_sum)
        .wrapping_add(rev_sum)
}

// ---------- 4. slice search / windows / chunks ----------
// The array is a literal (already sorted) rather than sorted at runtime:
// `sort_unstable` pulls the sort panicking path, and the live panic/formatting
// closure exceeds the 12K F28035 RAM program region on this backend (recorded
// in docs/PATH_B.md).  binary_search still exercises the real search path.
#[no_mangle]
#[inline(never)]
pub extern "C" fn core_ex_slice_search() -> u16 {
    let a = [1u16, 3, 5, 7, 9];
    let found = a.binary_search(&5).unwrap_or(99) as u16;
    let missing = a.binary_search(&4).unwrap_or(99) as u16;
    let sorted = a.is_sorted() as u16;
    let first = *a.first().unwrap_or(&0);
    let last = *a.last().unwrap_or(&0);
    let (head, tail) = a.split_first().unwrap_or((&0, &[]));
    let split = a.split_at(2);
    let windows: u16 = a.windows(2).map(|w| w[0].wrapping_add(w[1])).sum();
    let chunks: u16 = a.chunks(2).map(|c| c[0]).sum();
    let contains = a.contains(&7) as u16;
    let starts = a.starts_with(&[1, 3]) as u16;
    let ends = a.ends_with(&[7, 9]) as u16;
    found
        .wrapping_add(missing)
        .wrapping_add(sorted)
        .wrapping_add(first)
        .wrapping_add(last)
        .wrapping_add(*head)
        .wrapping_add(tail.len() as u16)
        .wrapping_add(split.0.len() as u16)
        .wrapping_add(split.1.len() as u16)
        .wrapping_add(windows)
        .wrapping_add(chunks)
        .wrapping_add(contains)
        .wrapping_add(starts)
        .wrapping_add(ends)
}

// ---------- 5. comparisons ----------
#[no_mangle]
#[inline(never)]
pub extern "C" fn core_ex_cmp() -> u16 {
    let a = 12u16;
    let b = 20u16;
    let min = a.min(b);
    let max = a.max(b);
    let clamped = 250u16.clamp(0, 200);
    let cmp = match a.cmp(&b) {
        core::cmp::Ordering::Less => 1,
        core::cmp::Ordering::Equal => 2,
        core::cmp::Ordering::Greater => 3,
    };
    let then = match a.cmp(&b).then(b.cmp(&b)) {
        core::cmp::Ordering::Less => 1,
        core::cmp::Ordering::Equal => 2,
        core::cmp::Ordering::Greater => 3,
    };
    let then_with = match a.cmp(&b).then_with(|| b.cmp(&a)) {
        core::cmp::Ordering::Less => 1,
        core::cmp::Ordering::Equal => 2,
        core::cmp::Ordering::Greater => 3,
    };
    let tuple_cmp = match (1u16, 2u16).cmp(&(1u16, 3u16)) {
        core::cmp::Ordering::Less => 1,
        core::cmp::Ordering::Equal => 2,
        core::cmp::Ordering::Greater => 3,
    };
    let reverse = (core::cmp::Reverse(a) < core::cmp::Reverse(b)) as u16;
    let eq = (a == b) as u16;
    let ne = (a != b) as u16;
    let abs_diff = a.abs_diff(b);
    min.wrapping_add(max)
        .wrapping_add(clamped)
        .wrapping_add(cmp)
        .wrapping_add(then)
        .wrapping_add(then_with)
        .wrapping_add(tuple_cmp)
        .wrapping_add(reverse)
        .wrapping_add(eq)
        .wrapping_add(ne)
        .wrapping_add(abs_diff)
}

// ---------- 6. mem ----------
#[no_mangle]
#[inline(never)]
pub extern "C" fn core_ex_mem() -> u16 {
    let mut x = 11u16;
    let mut y = 22u16;
    core::mem::swap(&mut x, &mut y);
    let taken = core::mem::take(&mut x);
    let replaced = core::mem::replace(&mut y, 9);
    let size_u16 = core::mem::size_of::<u16>() as u16;
    let size_arr = core::mem::size_of::<[u16; 5]>() as u16;
    let size_tuple = core::mem::size_of::<(u16, u16)>() as u16;
    let size_u8arr = core::mem::size_of::<[u8; 7]>() as u16;
    taken
        .wrapping_add(replaced)
        .wrapping_add(size_u16)
        .wrapping_add(size_arr)
        .wrapping_add(x)
        .wrapping_add(y)
        .wrapping_add(size_tuple)
        .wrapping_add(size_u8arr)
}

// ---------- 7. arithmetic and bit tricks ----------
#[no_mangle]
#[inline(never)]
pub extern "C" fn core_ex_arith() -> u16 {
    let wadd = 60000u16.wrapping_add(10000);
    let oadd = 40000u16.overflowing_add(30000);
    let omul = 300u16.overflowing_mul(300);
    let cdiv = 100u16.checked_div(4).unwrap_or(0);
    let cdiv0 = 100u16.checked_div(0).unwrap_or(7);
    let rot = 0x1234u16.rotate_left(4);
    let lz = 1u16.leading_zeros() as u16;
    let tz = 8u16.trailing_zeros() as u16;
    let ones = 0xFFu16.count_ones() as u16;
    let pow = 3u16.pow(4);
    let wrapping_add = (Wrapping(300u16) + Wrapping(100u16)).0;
    wadd.wrapping_add(oadd.0)
        .wrapping_add(omul.0)
        .wrapping_add(cdiv)
        .wrapping_add(cdiv0)
        .wrapping_add(rot)
        .wrapping_add(lz)
        .wrapping_add(tz)
        .wrapping_add(ones)
        .wrapping_add(pow)
        .wrapping_add(wrapping_add)
        .wrapping_add((oadd.1 as u16) * 5)
        .wrapping_add((omul.1 as u16) * 6)
}

// ---------- 8. pattern matching ----------
enum CoreShape {
    Dot,
    Circle(u16),
    Rect(u16, u16),
    Labeled(&'static str, u16),
}

struct CorePt {
    x: u16,
    y: u16,
}

#[no_mangle]
#[inline(never)]
pub extern "C" fn core_ex_pattern() -> u16 {
    let shapes = [
        CoreShape::Dot,
        CoreShape::Circle(5),
        CoreShape::Rect(6, 7),
        CoreShape::Labeled("a", 3),
    ];
    let mut total = 0u16;
    for s in &shapes {
        total = total.wrapping_add(match s {
            CoreShape::Dot => 1,
            CoreShape::Circle(r) => r.wrapping_mul(3),
            CoreShape::Rect(w, h) => w.wrapping_mul(*h),
            CoreShape::Labeled(_, v) => *v,
        });
    }
    let arr = [1u16, 2, 3, 4, 5];
    let slice_pat = match arr {
        [first, .., last] => first.wrapping_add(last),
    };
    let slice_if = match arr {
        [a, b, ..] if a.wrapping_add(b) == 3 => 10,
        _ => 0,
    };
    let mut iflet = 0u16;
    if let Some(v) = Some(9u16) {
        iflet = v;
    }
    let mut whilelet = 0u16;
    let mut walk = arr.iter();
    while let Some(v) = walk.next() {
        whilelet = whilelet.wrapping_add(*v);
    }
    let letelse = 'blk: {
        let Some(v) = Some(4u16) else {
            break 'blk 0;
        };
        v
    };
    let orp = match 2u16 {
        1 | 2 | 3 => 100,
        _ => 0,
    };
    let matches_macro = matches!(arr[0], 1 | 2) as u16;
    let CorePt { x, y } = CorePt { x: 8, y: 9 };
    total
        .wrapping_add(slice_pat)
        .wrapping_add(slice_if)
        .wrapping_add(iflet)
        .wrapping_add(whilelet)
        .wrapping_add(letelse)
        .wrapping_add(orp)
        .wrapping_add(matches_macro)
        .wrapping_add(x)
        .wrapping_add(y)
}

// ---------- 9. str / UTF-8 ----------
// Kept to panic-free paths (from_utf8 validation, prefix/suffix, ascii, byte
// view).  parse/split/trim/chars each pull the integer-formatting or unicode
// table closure that does not fit the 12K RAM program region; see the group
// notes in docs/PATH_B.md.
#[no_mangle]
#[inline(never)]
pub extern "C" fn core_ex_str() -> u16 {
    let bytes = [0x41u8, 0x42, 0x43];
    let s = core::str::from_utf8(&bytes).unwrap_or("?");
    let bad = core::str::from_utf8(&[0xFFu8]).is_err() as u16;
    let starts = s.starts_with("AB") as u16;
    let ends = s.ends_with('C') as u16;
    let len = s.len() as u16;
    let ascii = s.is_ascii() as u16;
    let concat_bytes: u16 = s.as_bytes().iter().map(|b| *b as u16).sum();
    let valid_up_to = match core::str::from_utf8(&[0x41u8, 0xFF, 0x42]) {
        Ok(_) => 0,
        Err(e) => e.valid_up_to() as u16,
    };
    len.wrapping_add(bad)
        .wrapping_add(starts)
        .wrapping_add(ends)
        .wrapping_add(ascii)
        .wrapping_add(concat_bytes)
        .wrapping_add(valid_up_to)
}

// ---------- 10. bounds-checked (safe) indexing ----------
#[no_mangle]
#[inline(never)]
pub extern "C" fn core_ex_index() -> u16 {
    let s: &[u16] = &[10, 20, 30, 40];
    let get_ok = s.get(2).copied().unwrap_or(0);
    let get_none = s.get(4).copied().unwrap_or(7);
    let direct = s[1];
    let (left, right) = s.split_at(2);
    let first = *s.first().unwrap_or(&0);
    let last = *s.last().unwrap_or(&0);
    let sub_len = s[2..3].len() as u16;
    let arr_index = [7u16, 8, 9][2];
    let mut c = [1u16, 2];
    if let Some(v) = c.get_mut(1) {
        *v = 5;
    }
    let get_mut_ok = c[1];
    let oob_guarded = if s.get(99).is_none() { 6 } else { 0 };
    get_ok
        .wrapping_add(get_none)
        .wrapping_add(direct)
        .wrapping_add(left.len() as u16)
        .wrapping_add(right.len() as u16)
        .wrapping_add(first)
        .wrapping_add(last)
        .wrapping_add(sub_len)
        .wrapping_add(arr_index)
        .wrapping_add(get_mut_ok)
        .wrapping_add(oob_guarded)
}

// ---------- 11. conversions ----------
#[no_mangle]
#[inline(never)]
pub extern "C" fn core_ex_convert() -> u16 {
    let try_ok = u8::try_from(200u16).unwrap_or(0);
    let try_err = u8::try_from(300u16).unwrap_or(9);
    let from_true = u16::from(true);
    let from_false = u16::from(false);
    let cast = 0x0102u16 as u8;
    let le = u16::to_le_bytes(0x0102);
    let from_le = u16::from_le_bytes([2, 1]);
    let be = u16::to_be_bytes(0x0102);
    let swap = 0x0102u16.swap_bytes();
    let reverse_bits = 1u16.reverse_bits();
    (try_ok as u16)
        .wrapping_add(try_err as u16)
        .wrapping_add(from_true)
        .wrapping_add(from_false)
        .wrapping_add(cast as u16)
        .wrapping_add(le[0] as u16)
        .wrapping_add(le[1] as u16)
        .wrapping_add(from_le)
        .wrapping_add(be[0] as u16)
        .wrapping_add(be[1] as u16)
        .wrapping_add(swap)
        .wrapping_add(reverse_bits)
}

// ---------- 12. closures, fn pointers, recursion ----------
#[no_mangle]
#[inline(never)]
pub extern "C" fn core_ex_closure() -> u16 {
    fn apply(f: impl Fn(u16) -> u16, x: u16) -> u16 {
        f(x)
    }
    fn fact(n: u16) -> u16 {
        let mut acc = 1u16;
        let mut i = 2u16;
        while i <= n {
            acc = acc.wrapping_mul(i);
            i = i.wrapping_add(1);
        }
        acc
    }
    let double = |x: u16| x.wrapping_mul(2);
    let capture = 5u16;
    let add_capture = |x: u16| x.wrapping_add(capture);
    let fp: fn(u16) -> u16 = double;
    let chained = double(double(3));
    let applied = apply(double, 21);
    let captured = add_capture(10);
    let via_fp = fp(7);
    let fact5 = fact(5);
    let nested = apply(|x| apply(double, x).wrapping_add(1), 4);
    chained
        .wrapping_add(applied)
        .wrapping_add(captured)
        .wrapping_add(via_fp)
        .wrapping_add(fact5)
        .wrapping_add(nested)
}

#[cfg(not(test))]
#[panic_handler]
fn panic(_info: &core::panic::PanicInfo) -> ! {
    loop {}
}

// ---------- group E: boolean comparison / Option tag probes ----------
// Every entry takes its operands from the TI C driver so LLVM cannot
// constant-fold the body; these are the direct regression for the
// "boolean comparison" defect recorded in docs/PATH_B.md.
#[no_mangle]
#[inline(never)]
pub extern "C" fn beq(a: u16, b: u16) -> u16 {
    (a == b) as u16
}

#[no_mangle]
#[inline(never)]
pub extern "C" fn blt(a: u16, b: u16) -> u16 {
    (a < b) as u16
}

#[no_mangle]
#[inline(never)]
pub extern "C" fn beq8(a: u16, b: u16) -> u16 {
    ((a as u8) == (b as u8)) as u16
}

#[no_mangle]
#[inline(never)]
pub extern "C" fn beq1(a: u16) -> u16 {
    (a == 1) as u16
}

#[no_mangle]
#[inline(never)]
pub extern "C" fn some_of(tag: u16) -> u16 {
    let o: Option<u16> = if tag == 0 { None } else { Some(5u16) };
    o.is_some() as u16
}

#[no_mangle]
#[inline(never)]
pub extern "C" fn none_of(tag: u16) -> u16 {
    let o: Option<u16> = if tag == 0 { None } else { Some(5u16) };
    o.is_none() as u16
}

#[no_mangle]
#[inline(never)]
pub extern "C" fn unwrap_of(tag: u16) -> u16 {
    let o: Option<u16> = if tag == 0 { None } else { Some(5u16) };
    o.unwrap_or(9)
}

#[no_mangle]
#[inline(never)]
pub extern "C" fn not_of(tag: u16) -> u16 {
    (!(tag == 0)) as u16
}

// ---------- group F: u32/i32 boundary and variable-shift regression ----------
// Operands come from the TI C driver so LLVM cannot fold the bodies to a
// constant.  These directly regress the LSL ACC,T defect: a 32-bit variable
// left shift by 16..31 must move the value (LSLL uses T(4:0)); the old
// LSL ACC,T consumed only T(3:0) and left a shift of 16..31 in place.
#[no_mangle]
#[inline(never)]
pub extern "C" fn bnd_shl(a: u16, n: u16) -> u16 {
    (((a as u32) << (n as u32)) >> 16) as u16
}

#[no_mangle]
#[inline(never)]
pub extern "C" fn bnd_shl_lo(a: u16, n: u16) -> u16 {
    (((a as u32) << (n as u32)) & 0xFFFF) as u16
}

#[no_mangle]
#[inline(never)]
pub extern "C" fn bnd_shr(a: u16, n: u16) -> u16 {
    (((a as u32) << 16) >> (n as u32)) as u16
}

#[no_mangle]
#[inline(never)]
pub extern "C" fn bnd_u32_addhi(a: u16, b: u16) -> u16 {
    ((((a as u32) << 16) | (b as u32)).wrapping_add(1) >> 16) as u16
}

#[no_mangle]
#[inline(never)]
pub extern "C" fn bnd_u32_subhi(a: u16, b: u16) -> u16 {
    (((a as u32) << 16).wrapping_sub(b as u32) >> 16) as u16
}

#[no_mangle]
#[inline(never)]
pub extern "C" fn bnd_u32_cmp(a: u16, b: u16) -> u16 {
    ((((a as u32) << 16) | 0xFFFF) > (((b as u32) << 16) | 0x8000)) as u16
}

#[no_mangle]
#[inline(never)]
pub extern "C" fn bnd_i16_cmp(a: u16, b: u16) -> u16 {
    ((a as i16) < (b as i16)) as u16
}

#[cfg(test)]
mod tests {
    use super::*;

    // The C driver passes HW_RUST_DATA = {2, 4, 6, 8} as a logical byte
    // pointer (word address doubled); see tools/hw_rust_core_ex_driver.c.
    fn driver_slice() -> &'static [u16] {
        &[2, 4, 6, 8]
    }

    #[test]
    fn option_combinators() {
        assert_eq!(core_ex_option(), 140);
    }

    #[test]
    fn result_combinators() {
        assert_eq!(core_ex_result(), 54);
    }

    #[test]
    fn iterator_adaptors() {
        let values = driver_slice();
        assert_eq!(core_ex_iter_slice(values.as_ptr(), values.len() as u16), 80);
    }

    #[test]
    fn iterator_adaptors2() {
        // Second half of the iterator-adaptor coverage (group B2); together
        // with iterator_adaptors this reproduces the original 170 (80 + 90).
        let values = driver_slice();
        assert_eq!(core_ex_iter_slice2(values.as_ptr(), values.len() as u16), 90);
    }

    #[test]
    fn slice_search() {
        // binary_search(&4) misses and lands on Err(2); unwrap_or then yields
        // the 99 default, so the Err path is exercised, not the index.
        assert_eq!(core_ex_slice_search(), 180);
    }

    #[test]
    fn comparisons() {
        assert_eq!(core_ex_cmp(), 245);
    }

    #[test]
    fn mem_ops() {
        assert_eq!(core_ex_mem(), 65);
    }

    #[test]
    fn arithmetic_and_bits() {
        assert_eq!(core_ex_arith(), 42967);
    }

    #[test]
    fn pattern_matching() {
        assert_eq!(core_ex_pattern(), 223);
    }

    #[test]
    fn str_and_parse() {
        assert_eq!(core_ex_str(), 206);
    }

    #[test]
    fn safe_indexing() {
        assert_eq!(core_ex_index(), 132);
    }

    #[test]
    fn conversions() {
        assert_eq!(core_ex_convert(), 33757);
    }

    #[test]
    fn closures_and_recursion() {
        assert_eq!(core_ex_closure(), 212);
    }

    // Group E: the TI C driver passes the operands; see
    // tools/hw_rust_core_ex_driver_e.c and dss-read-rust-core-ex-e.js.
    #[test]
    fn boolean_comparisons() {
        assert_eq!(beq(3, 3), 1);
        assert_eq!(beq(3, 4), 0);
        assert_eq!(blt(2, 5), 1);
        assert_eq!(blt(5, 2), 0);
        assert_eq!(beq8(0x107, 0x207), 1);
        assert_eq!(beq8(0x107, 0x208), 0);
        assert_eq!(beq1(1), 1);
        assert_eq!(beq1(2), 0);
        assert_eq!(some_of(1), 1);
        assert_eq!(some_of(0), 0);
        assert_eq!(none_of(0), 1);
        assert_eq!(none_of(1), 0);
        assert_eq!(unwrap_of(1), 5);
        assert_eq!(unwrap_of(0), 9);
        assert_eq!(not_of(0), 0);
        assert_eq!(not_of(1), 1);
    }

    // Group F: u32/i32 boundary and variable-shift regression.  The C driver
    // passes the operands; see tools/hw_rust_core_ex_driver_f.c and
    // dss-read-rust-core-ex-f.js.
    #[test]
    fn boundary_and_shifts() {
        assert_eq!(bnd_shl(0x1234, 16), 0x1234);
        assert_eq!(bnd_shl(0x1234, 17), 0x2468);
        assert_eq!(bnd_shl(0xFFFF, 31), 0x8000);
        assert_eq!(bnd_shl_lo(0x1234, 8), 0x3400);
        assert_eq!(bnd_shr(0x1234, 16), 0x1234);
        assert_eq!(bnd_shr(0x1234, 17), 0x091A);
        assert_eq!(bnd_shr(0x1234, 31), 0x0000);
        assert_eq!(bnd_u32_addhi(0x1234, 0xFFFF), 0x1235);
        assert_eq!(bnd_u32_addhi(0xFFFF, 0xFFFF), 0x0000);
        assert_eq!(bnd_u32_subhi(0x1234, 0x0001), 0x1233);
        assert_eq!(bnd_u32_cmp(1, 1), 1);
        assert_eq!(bnd_u32_cmp(1, 2), 0);
        assert_eq!(bnd_i16_cmp(0xFFFF, 0), 1);
        assert_eq!(bnd_i16_cmp(0, 0xFFFF), 0);
    }
}
