// rustc-wrapper.rs - cargo RUSTC_WRAPPER (compiled exe).
//
// Build once with system rustc:
//   rustc -O tools/rustc-wrapper.rs -o tools/rustc-wrapper.exe
//
// cargo invokes:  rustc-wrapper.exe <real-rustc-path> <rustc-args...>
//
// Routing:
//   --target c28x-none-elf                       -> patched C28x rustc
//   --target x86_64-pc-windows-gnu (host probe) -> system MSVC rustc, --target stripped
//   no --target + .rs input (build script)        -> system MSVC rustc
//   no --target + probe (-vV / --print / `-`)    -> patched rustc
//
// The patched rustc's host std produces broken Windows exes
// (STATUS_ENTRYPOINT_NOT_FOUND), so it must not compile host-runnable binaries.

use std::env;
use std::path::PathBuf;
use std::process::Command;

fn main() {
    let mut args: Vec<String> = env::args().collect();
    // args[0] = this exe; args[1] = real rustc path cargo passed; drop both.
    if args.len() < 2 {
        eprintln!("rustc-wrapper: expected at least a rustc path arg");
        std::process::exit(1);
    }
    args.drain(0..2);

    let patched = r"D:\c28x-toolchain\rust-build-gcc14fix\host\stage1\bin\rustc.exe".to_string();
    let system  = r"C:\Users\61987\.cargo\bin\rustc.exe".to_string();
    let mingw_bin = r"D:\c28x-toolchain\rust-build-gcc14fix\x86_64-pc-windows-gnu\stage0-sysroot\lib\rustlib\x86_64-pc-windows-gnu\bin".to_string();
    let llvm_bin = r"D:\c28x-toolchain\build-c28x-clang\bin".to_string();

    // Detect --target value.
    let mut target_arg = String::new();
    let mut i = 0;
    while i < args.len() {
        if args[i] == "--target" && i + 1 < args.len() {
            target_arg = args[i + 1].clone();
        } else if args[i].starts_with("--target=") {
            target_arg = args[i]["--target=".len()..].to_string();
        }
        i += 1;
    }

    // Detect positional .rs input.
    let has_rs_input = args.iter().any(|a| !a.starts_with("--") && a.ends_with(".rs"));
    let is_vv = args.iter().any(|a| a == "-vV");

    let log = PathBuf::from(r"C:\Users\61987\Desktop\28035\f28035-rust-bridge\build\rustc-wrapper.log");
    let _ = std::fs::create_dir_all(log.parent().unwrap());

    let branch: &str;

    let (exe, pass_args, prepend_mingw): (String, Vec<String>, bool) = if target_arg.eq_ignore_ascii_case("c28x-none-elf") {
        branch = "c28x";
        (patched, args.clone(), true)
    } else if target_arg.eq_ignore_ascii_case("x86_64-pc-windows-gnu") {
        branch = "host-gnu->msvc";
        let mut new: Vec<String> = Vec::new();
        let mut skip_next = false;
        for a in &args {
            if skip_next { skip_next = false; continue; }
            if a == "--target" { skip_next = true; continue; }
            if a.starts_with("--target=") { continue; }
            new.push(a.clone());
        }
        (system, new, false)
    } else if is_vv {
        branch = "vv->patched";
        (patched, args.clone(), true)
    } else if has_rs_input {
        branch = "host-build->msvc";
        (system, args.clone(), false)
    } else {
        branch = "probe->patched";
        (patched, args.clone(), true)
    };

    let _ = ();
    // Append log entry.
    use std::io::Write;
    if let Ok(mut f) = std::fs::OpenOptions::new().create(true).append(true).open(&log) {
        let _ = writeln!(f, "[{branch}] {}", pass_args.join(" "));
    }

    let mut cmd = Command::new(&exe);
    cmd.args(&pass_args);
    if prepend_mingw {
        if let Ok(path) = env::var("PATH") {
            cmd.env("PATH", format!("{llvm_bin};{mingw_bin};{path}"));
        }
    }
    match cmd.status() {
        Ok(st) => std::process::exit(st.code().unwrap_or(1)),
        Err(e) => {
            eprintln!("rustc-wrapper: failed to spawn {exe}: {e}");
            std::process::exit(1);
        }
    }
}
