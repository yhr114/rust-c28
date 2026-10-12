#![no_std]
#![no_main]

// Gap-4 smoke: exercise the core modules that matter for embedded code so the
// build proves core/compiler_builtins actually compiled them:
//   Option, Result, iter::Iterator, slice, cmp, mem.
// Only codegen success matters here; linking is gap 5.

#[panic_handler]
fn panic(_info: &core::panic::PanicInfo) -> ! {
    loop {}
}

fn classify(x: i32) -> Result<&'static str, &'static str> {
    match x.cmp(&0) {
        core::cmp::Ordering::Less => Err("negative"),
        core::cmp::Ordering::Equal => Ok("zero"),
        core::cmp::Ordering::Greater => Ok("positive"),
    }
}

#[no_mangle]
pub extern "C" fn rust_main() -> i32 {
    let values: [i32; 5] = [3, -1, 4, 1, 5];

    // slice + iterator + sum
    let sum: i32 = values.iter().sum();

    // Option + map + and_then over a slice element
    let first = values.first().copied();
    let doubled: Option<i32> = first.map(|v| v * 2);

    // Result combinators
    let label = classify(sum).unwrap_or("unknown");

    // mem::size_of as a compile-time-ish value
    let word = core::mem::size_of::<i32>();

    // Use everything so the optimizer can't delete it all
    let d = doubled.unwrap_or(0);
    let label_len = label.len();

    sum + d + word as i32 + label_len as i32
}
