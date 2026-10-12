#![no_std]

use core::sync::atomic::{AtomicU16, Ordering};

#[cfg(feature = "ownership-negative")]
const FREE: u16 = 1;
#[cfg(not(feature = "ownership-negative"))]
const FREE: u16 = 0;

#[repr(transparent)]
pub struct Once(AtomicU16);

impl Once {
    pub const fn new() -> Self {
        Self(AtomicU16::new(0))
    }

    #[inline(never)]
    #[unsafe(no_mangle)]
    pub extern "C" fn rust_once_acquire(&self) -> u16 {
        u16::from(
            self.0
                .compare_exchange(FREE, 1, Ordering::SeqCst, Ordering::SeqCst)
                .is_ok(),
        )
    }
}

pub struct Peripherals<'a> {
    pub gpio: Gpio<'a>,
}

pub struct Gpio<'a> {
    pin34: &'a Once,
}

pub struct OutputPin34(());

#[derive(Clone, Copy)]
struct WordAddress(u16);

impl WordAddress {
    unsafe fn read(self) -> u16 {
        unsafe { (usize::from(self.0) as *const u16).read_volatile() }
    }

    unsafe fn write(self, value: u16) {
        unsafe { (usize::from(self.0) as *mut u16).write_volatile(value) }
    }
}

impl OutputPin34 {
    #[inline(never)]
    #[unsafe(no_mangle)]
    pub extern "C" fn rust_gpio34_set_low(&mut self) {
        let mux = WordAddress(0x6f96);
        let direction = WordAddress(0x6f9a);
        let clear = WordAddress(0x6fcc);
        unsafe {
            mux.write(mux.read() & !0x30);
            direction.write(direction.read() | 4);
            #[cfg(not(feature = "gpio-negative"))]
            clear.write(4);
            #[cfg(feature = "gpio-negative")]
            clear.write(0);
        }
    }
}

impl<'a> Peripherals<'a> {
    #[inline(always)]
    pub fn take(root: &Once, pin34: &'a Once) -> Option<Self> {
        (root.rust_once_acquire() != 0).then_some(Self {
            gpio: Gpio { pin34 },
        })
    }
}

impl Gpio<'_> {
    #[inline(always)]
    pub fn claim34(&mut self) -> Option<OutputPin34> {
        (self.pin34.rust_once_acquire() != 0).then_some(OutputPin34(()))
    }
}

static ROOT: Once = Once::new();
static GPIO34: Once = Once::new();

#[unsafe(no_mangle)]
pub extern "C" fn rust_ownership_application() -> u16 {
    let Some(mut peripherals) = Peripherals::take(&ROOT, &GPIO34) else {
        return 0;
    };
    #[cfg(not(feature = "application-negative"))]
    if Peripherals::take(&ROOT, &GPIO34).is_some() {
        return 0;
    }
    #[cfg(feature = "application-negative")]
    if Peripherals::take(&ROOT, &GPIO34).is_none() {
        return 0;
    }
    let Some(mut pin) = peripherals.gpio.claim34() else {
        return 0;
    };
    if peripherals.gpio.claim34().is_some() {
        return 0;
    }
    pin.rust_gpio34_set_low();
    1
}

#[cfg(test)]
mod tests {
    use super::Once;

    #[test]
    fn independent_resources_can_each_be_taken_once() {
        let peripherals = Once::new();
        let gpio34 = Once::new();
        assert_eq!(peripherals.rust_once_acquire(), 1);
        assert_eq!(peripherals.rust_once_acquire(), 0);
        assert_eq!(gpio34.rust_once_acquire(), 1);
        assert_eq!(gpio34.rust_once_acquire(), 0);
    }

    #[test]
    fn safe_application_rejects_second_take_and_claim() {
        let root = Once::new();
        let gpio34 = Once::new();
        let mut peripherals = super::Peripherals::take(&root, &gpio34).unwrap();
        assert!(super::Peripherals::take(&root, &gpio34).is_none());
        assert!(peripherals.gpio.claim34().is_some());
        assert!(peripherals.gpio.claim34().is_none());
    }
}
