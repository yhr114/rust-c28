#![feature(no_core, lang_items)]
#![no_core]

#[lang = "pointee_sized"]
pub trait PointeeSized {}
#[lang = "meta_sized"]
pub trait MetaSized: PointeeSized {}
#[lang = "sized"]
pub trait Sized: MetaSized {}
#[lang = "copy"]
pub trait Copy {}

#[unsafe(no_mangle)]
pub extern "C" fn rust_counter(n: i32) -> i32 {
    let mut sum: i32 = 0;
    let mut i: i32 = 0;
    while i < n {
        sum = sum + i;
        sum = sum ^ 0x0000FFFF;
        i = i + 1;
    }
    sum
}