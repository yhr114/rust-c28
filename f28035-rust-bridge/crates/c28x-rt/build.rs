use std::{env, fs, path::{Path, PathBuf}};
fn write_if_changed(path: &Path, contents: &[u8]) {
    if fs::read(path).ok().as_deref() != Some(contents) { fs::write(path,contents).unwrap(); }
}
fn json_path(path: &Path) -> String {
    format!("\"{}\"",path.display().to_string().replace('\\',"\\\\").replace('"',"\\\""))
}
fn main() {
    println!("cargo:rerun-if-changed=build.rs");
    if env::var("CARGO_CFG_TARGET_ARCH").as_deref()!=Ok("c28x") {return;}
    let source=PathBuf::from(env::var_os("CARGO_MANIFEST_DIR").unwrap());
    let out=PathBuf::from(env::var_os("OUT_DIR").unwrap());
    let command=out.join("c28x-rt-ram.cmd");
    write_if_changed(&command, &fs::read(source.join("ram.cmd")).unwrap());
    let manifest=out.join("c28x-rt.json");
    let text=format!("{{\"schema\":1,\"runtime\":\"c28x-rt\",\"entry\":\"code_start\",\"sources\":[{}],\"linkerCommands\":[{}],\"inputs\":[{},{}]}}",
        json_path(&source.join("asm.s")),json_path(&command),json_path(&source.join("asm.s")),json_path(&source.join("ram.cmd")));
    write_if_changed(&manifest,text.as_bytes());
    println!("cargo:runtime_manifest={}",manifest.display());
    println!("cargo:rerun-if-changed=asm.s");
    println!("cargo:rerun-if-changed=ram.cmd");
}