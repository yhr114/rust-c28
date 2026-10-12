//===-- c28x_none_elf.rs - rustc target spec for C28x -------------------===//
//
// !!! 已过时（旧 rustc 格式参考）!!!
// 本文件使用旧版 rustc target spec 格式（abi / has_elf_div0 / 字符串
// linker_flavor），rustc 1.100 已删除这些字段，无法编译。
// 1.100 请使用：
//   - c28x_none_elf_1_100.rs（规范文件，字段已按 1.100 核验）
//   - 0001-add-c28x-target.patch（1.100 版真实补丁，含 Arch 枚举/symbols 修改）
// 校验：tools\check-rustc-patch.ps1
//
//===----------------------------------------------------------------------===//

use crate::spec::{base, Target, TargetOptions};

pub fn target() -> Target {
    let mut base = base::baremetal::opts();

    // C28x has no hardware atomic support (single-core, no LDREX/STREX).
    base.max_atomic_width = Some(0);
    base.min_atomic_width = Some(0);

    // No ELF frame pointer / unwind tables.
    base.has_elf_div0 = false;
    base.abi = "C28x".into();

    // 16-bit word size, little-endian. TI EABI: C int is 16 bits.
    base.cpu = "c28x".into();
    base.features = "+c28x".into();
    base.c_int_width = "16".into();

    // FROZEN ABI (see ABI_FREEZE.md): 32-bit logical byte pointers.
    // u16 = one C28x word; u32/i32/f32 and pointers = two words aligned to
    // 4 logical bytes. The old p:16:16 addressed only 64Ki logical bytes
    // (32K words), smaller than the F28035's 128Ki flash.
    Target {
        llvm_target: "c28x".into(),
        pointer_width: 32,
        data_layout: "e-m:e-p:32:32-i32:32-i64:32-f32:32-f64:32-a:8:8-n8:16-S16".into(),
        arch: "c28x".into(),
        options: TargetOptions {
            os: "none".into(),
            env: "".into(),
            vendor: "ti".into(),
            linker: Some("cl2000".into()),
            linker_flavor: "ti".into(),
            singlethread: true,
            disable_redzone: true,
            eh_frame_header: false,
            emit_debug_gdb_scripts: false,
            tls_model: "local-exec".into(),
            code_model: "small".into(),
            ..base
        },
    }
}
