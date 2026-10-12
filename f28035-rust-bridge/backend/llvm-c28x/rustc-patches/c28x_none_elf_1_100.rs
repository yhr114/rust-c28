use crate::spec::{
    Arch, Cc, LinkerFlavor, PanicStrategy, RelocModel, Target, TargetMetadata,
    TargetOptions,
};

pub(crate) fn target() -> Target {
    Target {
        llvm_target: "c28x-ti-none".into(),
        metadata: TargetMetadata {
            description: Some("TI C2000 C28x bare-metal targets".into()),
            tier: Some(3),
            host_tools: Some(false),
            std: Some(false),
        },
        // FROZEN ABI: 32-bit logical byte pointers (see ABI_FREEZE.md).
        pointer_width: 32,
        data_layout:
            "e-m:e-p:32:32-i1:8:8-i32:32-i64:32-f32:32-f64:32-a:8:8-n8:16-S16".into(),
        arch: Arch::Other("c28x".into()),
        options: TargetOptions {
            c_int_width: 16,
            cpu: "c28x".into(),
            linker: None,
            linker_flavor: LinkerFlavor::Unix(Cc::No),
            max_atomic_width: Some(0),
            atomic_cas: false,
            panic_strategy: PanicStrategy::Abort,
            relocation_model: RelocModel::Static,
            default_codegen_units: Some(1),
            trap_unreachable: false,
            emit_debug_gdb_scripts: false,
            eh_frame_header: false,
            singlethread: true,
            ..Default::default()
        },
    }
}
