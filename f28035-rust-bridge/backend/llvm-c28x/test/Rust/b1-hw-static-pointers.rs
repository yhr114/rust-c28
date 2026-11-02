#![no_std]

extern "C" {
    fn external_value(value: u16) -> u16;
    static external_data: u16;
}

#[no_mangle]
pub static FUNCTION_POINTER: unsafe extern "C" fn(u16) -> u16 = external_value;
#[no_mangle]
pub static DATA_REFERENCE: &'static u16 = unsafe { &external_data };
#[no_mangle]
pub static LOCAL_VALUE: u16 = 0xabcd;
#[no_mangle]
pub static LOCAL_REFERENCE: &'static u16 = &LOCAL_VALUE;
#[no_mangle]
pub static ODD_REFERENCE: &'static u8 = unsafe {
    &*(core::ptr::addr_of!(external_data).cast::<u8>().add(1))
};

// Volatile loads prevent folding away the relocated pointer fields.
#[no_mangle]
pub extern "C" fn rust_static_data() -> u16 {
    unsafe {
        let p = core::ptr::read_volatile::<&u16>(&DATA_REFERENCE);
        core::ptr::read_volatile(p)
    }
}
#[no_mangle]
pub extern "C" fn rust_static_local() -> u16 {
    unsafe {
        let p = core::ptr::read_volatile::<&u16>(&LOCAL_REFERENCE);
        core::ptr::read_volatile(p)
    }
}
#[no_mangle]
pub extern "C" fn rust_static_odd() -> u16 {
    unsafe {
        let p = core::ptr::read_volatile::<&u8>(&ODD_REFERENCE);
        core::ptr::read_volatile(p) as u16
    }
}
