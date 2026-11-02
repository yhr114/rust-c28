//! F28035 B-1 RAM runtime: TI startup, PIE vectors and compiler interrupt ABI.
//!
//! Applications use `#![no_std]`, `#![no_main]`, and
//! `#![feature(abi_c28x_interrupt)]`, then `#[entry] fn boot() -> !` and
//! `#[interrupt] fn TINT0()`. See docs/PATH_B.md in the main repository.
//! Peripheral flags and PIE acknowledgements must be cleared by the handler.
//! This RAM profile does not configure Flash boot or nested interrupts.
#![no_std]
#![deny(missing_docs)]

use core::cell::UnsafeCell;
#[cfg(not(target_arch = "c28x"))]
use core::sync::atomic::{AtomicBool, Ordering};

/// Startup/interrupt attributes with checked signatures.
#[cfg(feature = "macros")]
pub use c28x_rt_macros::{entry, interrupt, pre_init};
/// F28035 has 32 CPU/reserved slots plus 12 groups of 8 PIE slots.
pub const NUM_VECTORS: usize = 128;
/// Physical TI word address of the PIE vector RAM.
pub const PIE_VECTOR_BASE: u32 = 0x0d00;
/// Timer0 is PIE INT1.7: vector 38, at TI word address 0x0d4c.
pub const TIMER0_VECTOR: usize = 38;

#[cfg(target_arch = "c28x")]
extern "C" {
    fn c28x_rt_enable_interrupts();
    fn c28x_rt_disable_interrupts();
    fn c28x_rt_set_ier(mask: u16);
    fn c28x_rt_enter_critical() -> u16;
    fn c28x_rt_exit_critical(saved: u16);
}
/// Enable maskable CPU interrupts after vectors and peripheral state are ready.
///
/// # Safety
/// Every enabled interrupt must have a valid handler and synchronized shared data.
#[cfg(target_arch = "c28x")]
#[inline]
pub unsafe fn enable_interrupts() { unsafe { c28x_rt_enable_interrupts() } }
/// Mask CPU interrupts. This does not return the previous state for nesting.
///
/// # Safety
/// The caller must restore the appropriate interrupt state for its context.
#[cfg(target_arch = "c28x")]
#[inline]
pub unsafe fn disable_interrupts() { unsafe { c28x_rt_disable_interrupts() } }
/// Replace the CPU IER mask (bit 0 enables PIE group 1, bit 12 Timer1).
///
/// # Safety
/// Update this with interrupts masked; all enabled vectors must be initialized.
#[cfg(target_arch = "c28x")]
pub unsafe fn set_cpu_interrupt_mask(mask: u16) { unsafe { c28x_rt_set_ier(mask) } }

#[cfg(target_arch = "c28x")]
struct InterruptGuard(u16);

#[cfg(target_arch = "c28x")]
impl Drop for InterruptGuard {
    #[inline]
    fn drop(&mut self) { unsafe { c28x_rt_exit_critical(self.0) } }
}

/// Runs `f` with maskable interrupts disabled on the single-core C28x target.
///
/// The previous INTM state is restored on return (or unwinding). Nested calls
/// restore in stack order; the private guard cannot escape, be forgotten or be
/// dropped out of order by safe application code. This does not mask NMI or
/// synchronize DMA. On hosts the closure runs directly: this function alone
/// provides no thread synchronization. [`SharedCell`] supplies its own host lock.
#[inline]
pub fn critical_section<R>(f: impl FnOnce() -> R) -> R {
    #[cfg(target_arch = "c28x")]
    let _interrupts = InterruptGuard(unsafe { c28x_rt_enter_critical() });
    f()
}

/// A shared cell is already borrowed, either recursively or by another host thread.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct SharedCellBorrowError;

/// A cell whose value is shared between the main loop and interrupt handlers.
///
/// C28x accesses mask interrupts and check an exclusive borrow flag before
/// forming a reference. Host accesses use an acquire/release atomic lock.
/// Recursive borrowing and host contention return an error from [`Self::try_with`]
/// or panic in [`Self::with`]; neither path spins or exposes a second reference.
/// Do not use this cell from NMI or DMA, which INTM cannot exclude.
///
/// The protected reference cannot escape the callback:
/// ```compile_fail
/// let cell = c28x_rt::SharedCell::new(1u16);
/// let escaped = cell.with(|value| value);
/// *escaped = 2;
/// ```
/// A value that is not `Send` cannot be shared between threads:
/// ```compile_fail
/// use std::rc::Rc;
/// fn require_sync<T: Sync>() {}
/// require_sync::<c28x_rt::SharedCell<Rc<u16>>>();
/// ```
pub struct SharedCell<T> {
    inner: UnsafeCell<T>,
    #[cfg(target_arch = "c28x")]
    // Volatile accesses preserve the C28x native 16-bit synchronization width;
    // INTM, rather than volatile itself, excludes other maskable contexts.
    borrowed: UnsafeCell<u16>,
    #[cfg(not(target_arch = "c28x"))]
    borrowed: AtomicBool,
}

// SAFETY: every reference is protected by an exclusive borrow. C28x check/set
// and release execute with INTM set; hosts use an acquire/release atomic lock.
// The borrow guard releases on unwind and cannot be manipulated by callers.
// Moving access between contexts requires T: Send, just as for a mutex.
unsafe impl<T: Send> Sync for SharedCell<T> {}

struct BorrowGuard<'a, T>(&'a SharedCell<T>);

impl<T> Drop for BorrowGuard<'_, T> {
    fn drop(&mut self) {
        #[cfg(target_arch = "c28x")]
        unsafe { core::ptr::write_volatile(self.0.borrowed.get(), 0) };
        #[cfg(not(target_arch = "c28x"))]
        self.0.borrowed.store(false, Ordering::Release);
    }
}

impl<T> SharedCell<T> {
    /// Creates a shared cell holding `value`.
    pub const fn new(value: T) -> Self {
        Self {
            inner: UnsafeCell::new(value),
            #[cfg(target_arch = "c28x")]
            borrowed: UnsafeCell::new(0),
            #[cfg(not(target_arch = "c28x"))]
            borrowed: AtomicBool::new(false),
        }
    }

    /// Tries one exclusive access, without waiting or calling `f` on conflict.
    ///
    /// C28x keeps maskable interrupts disabled for the whole callback. Hosts
    /// return `Err` on contention; callers may retry after doing other work.
    #[inline]
    pub fn try_with<R>(&self, f: impl FnOnce(&mut T) -> R) -> Result<R, SharedCellBorrowError> {
        critical_section(|| {
            #[cfg(target_arch = "c28x")]
            let acquired = unsafe { core::ptr::read_volatile(self.borrowed.get()) } == 0;
            #[cfg(not(target_arch = "c28x"))]
            let acquired = self.borrowed
                .compare_exchange(false, true, Ordering::Acquire, Ordering::Relaxed).is_ok();
            if !acquired {
                return Err(SharedCellBorrowError);
            }
            #[cfg(target_arch = "c28x")]
            // SAFETY: INTM excludes maskable handlers; no reference to the
            // protected value exists until this flag has been set.
            unsafe { core::ptr::write_volatile(self.borrowed.get(), 1) };
            let _borrow = BorrowGuard(self);
            // SAFETY: only the successful borrower reaches this expression.
            // The private guard outlives the callback reference and is dropped
            // before the enclosing critical section restores interrupts.
            Ok(f(unsafe { &mut *self.inner.get() }))
        })
    }

    /// Runs `f` exclusively. Panics on recursive borrowing or host contention.
    /// Use [`Self::try_with`] when a conflict should be recoverable. A panic
    /// unwinds and releases the borrow on hosts; panic=abort firmware stops.
    #[inline]
    pub fn with<R>(&self, f: impl FnOnce(&mut T) -> R) -> R {
        match self.try_with(f) {
            Ok(value) => value,
            Err(_) => panic!("SharedCell is already borrowed"),
        }
    }

    /// Replaces the protected value, returning the previous one.
    #[inline]
    pub fn replace(&self, value: T) -> T {
        self.with(|slot| core::mem::replace(slot, value))
    }
}

#[cfg(test)]
mod tests {
    extern crate std;
    use super::{critical_section, SharedCell, SharedCellBorrowError};
    use self::std::{panic::{catch_unwind, AssertUnwindSafe}, sync::{Arc, Barrier}, thread};

    #[test]
    fn shared_cell_serialises_updates() {
        static CELL: SharedCell<u32> = SharedCell::new(0);
        CELL.with(|v| *v += 1);
        CELL.with(|v| *v += 1);
        assert_eq!(CELL.with(|v| *v), 2);
        assert_eq!(CELL.replace(10), 2);
        assert_eq!(CELL.with(|v| *v), 10);
    }

    #[test]
    fn recursive_borrow_is_rejected_before_callback() {
        let cell = SharedCell::new(7u32);
        cell.with(|first| {
            assert_eq!(cell.try_with(|_| panic!("second reference created")), Err(SharedCellBorrowError));
            *first += 1;
            assert_eq!(cell.try_with(|_| ()), Err(SharedCellBorrowError));
        });
        assert_eq!(cell.with(|value| *value), 8);
    }

    #[test]
    fn recursive_replace_panics_and_releases_borrow() {
        let cell = SharedCell::new(3u16);
        assert!(catch_unwind(AssertUnwindSafe(|| cell.with(|_| cell.replace(9)))).is_err());
        assert_eq!(cell.replace(4), 3);
    }

    #[test]
    fn callback_panic_releases_borrow_without_poisoning() {
        let cell = SharedCell::new(0u16);
        assert!(catch_unwind(AssertUnwindSafe(|| cell.with(|value| {
            *value = 5;
            panic!("callback failed");
        }))).is_err());
        assert_eq!(cell.try_with(|value| *value), Ok(5));
    }

    #[test]
    fn different_cells_and_critical_sections_can_nest() {
        let first = SharedCell::new(1u16);
        let second = SharedCell::new(2u16);
        critical_section(|| first.with(|a| critical_section(|| second.with(|b| *a += *b))));
        assert_eq!(first.with(|value| *value), 3);
    }

    #[test]
    fn concurrent_borrow_returns_busy_without_running_callback() {
        let cell = Arc::new(SharedCell::new(0u32));
        let entered = Arc::new(Barrier::new(2));
        let release = Arc::new(Barrier::new(2));
        let worker = {
            let (cell, entered, release) = (cell.clone(), entered.clone(), release.clone());
            thread::spawn(move || cell.with(|value| {
                entered.wait();
                release.wait();
                *value = 42;
            }))
        };
        entered.wait();
        let result = cell.try_with(|_| panic!("concurrent reference created"));
        release.wait();
        worker.join().unwrap();
        assert_eq!(result, Err(SharedCellBorrowError));
        assert_eq!(cell.with(|value| *value), 42);
    }

    #[test]
    fn concurrent_updates_are_exclusive_and_visible() {
        let cell = Arc::new(SharedCell::new((0u32, !0u32)));
        let start = Arc::new(Barrier::new(4));
        let mut workers = std::vec::Vec::new();
        for _ in 0..4 {
            let (cell, start) = (cell.clone(), start.clone());
            workers.push(thread::spawn(move || {
                start.wait();
                for _ in 0..2000 {
                    loop {
                        if cell.try_with(|value| {
                            assert_eq!(value.1, !value.0);
                            value.0 += 1;
                            value.1 = !value.0;
                        }).is_ok() { break; }
                        thread::yield_now();
                    }
                }
            }));
        }
        for worker in workers { worker.join().unwrap(); }
        assert_eq!(cell.with(|value| *value), (8000, !8000u32));
    }
}
