#![no_std]

use core::sync::atomic::{AtomicU16, Ordering};

static FLAG: AtomicU16 = AtomicU16::new(0);

#[unsafe(no_mangle)]
pub extern "C" fn rust_user_main() {
    if FLAG.load(Ordering::Relaxed) != 0 {
        core::hint::spin_loop();
    }
}
