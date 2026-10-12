use std::{env, fs, io::Write, path::PathBuf};

fn main() {
    if env::var("CARGO_CFG_TARGET_ARCH").as_deref() != Ok("c28x") {
        return;
    }

    let out = PathBuf::from(env::var_os("OUT_DIR").unwrap());

    /* Copy memory.x into OUT_DIR so the linker can find it. */
    fs::copy("memory.x", out.join("memory.x")).expect("copy memory.x");

    /* Build link.x from link.x.in.  When the "device" feature is on,
     * append INCLUDE device.x so the PAC crate can supply weak aliases
     * for device-specific interrupt handlers (same mechanism as
     * msp430-rt). */
    let template = fs::read("link.x.in").expect("read link.x.in");
    let mut link_x = fs::File::create(out.join("link.x")).expect("create link.x");
    link_x.write_all(&template).unwrap();
    if env::var_os("CARGO_FEATURE_DEVICE").is_some() {
        writeln!(
            link_x,
            "\n/* Weak aliases for device interrupts (provided by PAC crate). */\nINCLUDE device.x"
        )
        .unwrap();
    }

    println!("cargo:rustc-link-search={}", out.display());
    println!("cargo:rerun-if-changed=memory.x");
    println!("cargo:rerun-if-changed=link.x.in");
}
