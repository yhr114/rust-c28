#![feature(rustc_private)]

extern crate rustc_abi;
extern crate rustc_driver;
extern crate rustc_hir;
extern crate rustc_interface;
extern crate rustc_middle;
extern crate rustc_span;

use std::env;
use std::fs::File;
use std::io::Write;
use std::path::PathBuf;

use rustc_driver::{Callbacks, Compilation};
use rustc_hir::def::DefKind;
use rustc_interface::interface;
use rustc_middle::mir::{
    BasicBlock, BinOp, Body, CastKind, Operand, Rvalue, StatementKind, TerminatorKind, UnOp,
};
use rustc_middle::ty::{self, TyCtxt};
use rustc_span::def_id::DefId;

struct C28xCallbacks {
    mir_output: File,
    asm_output: Option<File>,
    only_export: Option<String>,
}

fn operand_local(operand: &Operand<'_>) -> Option<usize> {
    match operand {
        Operand::Copy(place) | Operand::Move(place) if place.projection.is_empty() => {
            Some(place.local.as_usize())
        }
        _ => None,
    }
}

#[derive(Clone, Copy)]
enum BranchArith {
    Add,
    Sub,
    Mul,
    Div,
    Rem,
    Shl,
    Shr,
    And,
    Or,
    Xor,
}

#[derive(Clone)]
enum MirOperation {
    BareWordMmio(Vec<WordMmioStep>),
    OnceAcquire,
    OwnershipApplication,
    UserMainCfg {
        blocks: Vec<UserBlock>,
        slots: Vec<(usize, u16)>,
    },
    Add,
    Sub,
    Mul,
    Div,
    Rem,
    Shl,
    Shr,
    BitAnd,
    BitOr,
    BranchBinary {
        cmp: BinOp,
        then_op: BranchArith,
        else_op: BranchArith,
    },
    AddImmediate(u16),
    SubImmediate(u16),
    Max,
    Min,
    UnpackLowByte,
    UnpackHighByte,
    WriteLowByte,
    WriteHighByte,
    Xor,
    Not,
    CallChain {
        steps: Vec<CallStep>,
        slots: Vec<(usize, u16)>,
    },
    ControlLoop {
        system_init: String,
        adc_result: String,
        pin: u16,
        result_index: u16,
        threshold: u16,
    },
    PlatformControlLoop {
        system_init: String,
        gpio_status_pin: u16,
        gpio_interrupt_pin: u16,
        adc_result_index: u16,
        pwm_period: u16,
        timer_period_ms: u16,
        threshold: u16,
    },
    AdcSampleBasic {
        system_init: String,
        take_peripherals: String,
        channel: u16,
    },
    EpwmCompareBasic {
        system_init: String,
        take_peripherals: String,
        period: u16,
        compare: u16,
    },
    /// Generic ePWM1 configure call: LCR system_init -> board_init -> take ->
    /// MOVB AL,#period / MOVB AH,#compare -> LCR <func> -> CMP AL,#0 -> trap.
    Epwm1ConfigureCall {
        system_init: String,
        take_peripherals: String,
        func: String,
        period: u16,
        compare: u16,
    },
    /// ePWM1 deadband (epwm_deadband_basic).
    EpwmDeadbandSetup {
        system_init: String,
        take_peripherals: String,
    },
    /// ePWM1 software trip-zone force (epwm_tripzone_swforce_basic).
    EpwmTripzoneSwforce {
        system_init: String,
        take_peripherals: String,
    },
    /// Generic void call: LCR system_init -> LCR <func> -> LRETR.
    /// Covers i2c/sci/spi C bridge wrappers with no return value.
    VoidCall {
        system_init: String,
        func: String,
    },
    /// GPIO pin walk (gpio_pin_walk_basic).
    GpioPinWalk {
        system_init: String,
    },
    /// CAN pin mux (can_pin_mux_basic).
    CanPinMux {
        system_init: String,
        take_peripherals: String,
    },
    /// ePWM1 up-down count + AQ (epwm_updown_aq_smoke).
    EpwmUpdownAq {
        system_init: String,
        take_peripherals: String,
    },
    /// ePWM1 external trip-zone (epwm_tz_external_basic).
    EpwmTzExternal {
        system_init: String,
        take_peripherals: String,
    },
    /// ePWM1 up-count + INT+SOCA event (epwm_event_int_soca_smoke).
    EpwmEventIntSocaSetup {
        system_init: String,
        take_peripherals: String,
        period: u16,
        compare: u16,
    },
    /// ePWM1 up-count + SOCB event (epwm_event_socb_smoke).
    EpwmEventSocbSetup {
        system_init: String,
        take_peripherals: String,
        period: u16,
        compare: u16,
    },
    Timer0PeriodicBasic {
        system_init: String,
        take_peripherals: String,
        period_ms: u16,
        interrupt_pin: u16,
    },
    GpioLow {
        system_init: String,
        take_peripherals: String,
        make_output: String,
        gpio_write: String,
        gpio_toggle: String,
        pins: Vec<u16>,
        actions: Vec<GpioOutputAction>,
    },
    /// A Safe HAL GPIO sequence that interleaves output/input direction
    /// configuration with write/toggle actions in straight-line order, e.g.
    /// gpio_direction_switch_basic: make_output -> write high -> make_input
    /// -> make_output -> write low.  This extends the pure-output
    /// [MirOperation::GpioLow] with the input-direction bridge and
    /// same-pin reconfiguration.
    GpioSequence {
        system_init: String,
        take_peripherals: String,
        make_output: String,
        make_input: String,
        gpio_write: String,
        gpio_toggle: String,
        steps: Vec<GpioStep>,
    },
    GpioOutputReadback {
        system_init: String,
        take_peripherals: String,
        pin: u16,
        expected: Vec<u16>,
    },
    /// A straight-line Safe HAL GPIO MUX-routing sequence, e.g.
    /// gpio_mux_basic: set_mux(0,0) -> set_mux(0,1) -> set_mux(0,0).  Each
    /// step is one 28035_gpio_set_mux(pin, function) call guarded by its
    /// SwitchInt expect check.
    GpioMux {
        system_init: String,
        take_peripherals: String,
        set_mux: String,
        steps: Vec<GpioMuxStep>,
    },
    InterruptCallback {
        pin: u16,
    },
    /// A straight-line sequence of MMIO word writes recognized from
    /// `<B as MmioBus>::write_word(bus, const TiWordAddress(addr), val)`
    /// calls in one optimized MIR body.  This is the seed of generic MMIO
    /// lowering: any PAC `apply` whose register addresses rustc has already
    /// constant-propagated into `write_word` calls can be lowered to direct
    /// C28x word stores, without hardcoding the symbol names.
    MmioWriteSequence(Vec<MmioWrite>),
}

#[derive(Clone)]
enum UserOperand {
    Local(usize),
    Immediate(u16),
}

#[derive(Clone)]
enum UserStatement {
    Assign {
        destination: usize,
        value: UserOperand,
    },
    Binary {
        destination: usize,
        operation: BinOp,
        left: UserOperand,
        right: UserOperand,
    },
}

#[derive(Clone)]
enum UserTerminator {
    Goto(usize),
    SwitchValue {
        value: UserOperand,
        expected: u16,
        matched: usize,
        otherwise: usize,
    },
    Call {
        name: String,
        args: Vec<UserOperand>,
        destination: Option<usize>,
        next: usize,
    },
    Return,
    Trap,
}

#[derive(Clone)]
struct UserBlock {
    statements: Vec<UserStatement>,
    terminator: UserTerminator,
}

#[derive(Clone)]
enum WordMmioStep {
    Modify { addr: u16, op: BinOp, mask: u16 },
    Write { addr: u16, value: u16 },
}

#[derive(Clone, Copy)]
enum GpioOutputAction {
    Write { pin: u16, value: u16 },
    Toggle { pin: u16 },
}

/// One ordered step of a Safe HAL GPIO direction/action sequence.
#[derive(Clone, Copy)]
enum GpioStep {
    /// Configure a pin as a push-pull output (f28035_gpio_make_output).
    MakeOutput {
        pin: u16,
    },
    /// Configure a pin as an input with pull-up and qualification
    /// (f28035_gpio_make_input).  pullup: 1 = enable internal pull-up,
    /// 0 = disable; qualification: Sync=0 / Sample3=1 / Sample6=2 / Async=3.
    MakeInput {
        pin: u16,
        pullup: u16,
        qualification: u16,
    },
    Write {
        pin: u16,
        value: u16,
    },
    Toggle {
        pin: u16,
    },
}

/// One ordered step of a Safe HAL GPIO MUX-routing sequence.
#[derive(Clone, Copy)]
enum GpioMuxStep {
    /// Route pin to unction (0 = GPIO, 1..3 = peripheral).
    SetMux { pin: u16, function: u16 },
}

#[derive(Clone, Copy)]
enum MmioWrite {
    /// Write an immediate 16-bit value to a fixed physical word address.
    Imm { addr: u16, val: u16 },
    /// Write the 16-bit value already present in the ACC register (the
    /// function's `self.0` first parameter, per C28x calling convention)
    /// to a fixed physical word address.
    Acc { addr: u16 },
    /// Read-modify-write one word: `(current & !mask) | bits`.
    Modify { addr: u16, mask: u16, bits: u16 },
    /// Write a 32-bit value (in ACC, AH:AL) to two adjacent words `addr`
    /// and `addr + 1`.
    WriteU32 { addr: u16 },
    /// Read one word from the address already loaded into XAR4 (indirect
    /// load).  Result lands in AL.  Used by InputConfig::read / adc_result
    /// where the address is computed at runtime.
    ReadIndirect,
}

#[derive(Clone)]
struct CallStep {
    callee: String,
    right: CallRight,
    destination: usize,
    save_result: bool,
}

#[derive(Clone, Copy)]
enum CallRight {
    InputB,
    Immediate(u16),
    SavedLocal(usize),
}

fn is_binary_u16_alu(operation: &MirOperation) -> bool {
    matches!(
        operation,
        MirOperation::Add | MirOperation::Sub | MirOperation::Mul | MirOperation::Xor
    )
}

fn classify_linear_call_chain<'tcx>(tcx: TyCtxt<'tcx>, body: &Body<'tcx>) -> Option<MirOperation> {
    if body.arg_count != 2 {
        return None;
    }
    let mut block_id = body.basic_blocks.indices().next()?;
    let mut visited = Vec::new();
    let mut previous_destination = None;
    let mut steps = Vec::new();

    loop {
        if visited.contains(&block_id) {
            return None;
        }
        visited.push(block_id);
        let block = &body.basic_blocks[block_id];
        if !block.statements.is_empty() {
            return None;
        }
        match &block.terminator().kind {
            TerminatorKind::Call {
                func,
                args,
                destination,
                target: Some(target),
                ..
            } => {
                let ty::FnDef(callee, _) = *func.ty(body, tcx).kind() else {
                    return None;
                };
                if args.len() != 2 || !destination.projection.is_empty() {
                    return None;
                }
                let right = if steps.is_empty() {
                    if operand_local(&args[0].node) != Some(1)
                        || operand_local(&args[1].node) != Some(2)
                    {
                        return None;
                    }
                    CallRight::InputB
                } else {
                    if operand_local(&args[0].node) != previous_destination {
                        return None;
                    }
                    if let Some(value) = constant_u16(&args[1].node) {
                        CallRight::Immediate(value)
                    } else {
                        CallRight::SavedLocal(operand_local(&args[1].node)?)
                    }
                };
                if tcx.is_foreign_item(callee) {
                    return None;
                }
                let callee_operation =
                    classify_mir_function(tcx, callee, tcx.optimized_mir(callee))?;
                if !is_binary_u16_alu(&callee_operation) {
                    return None;
                }
                steps.push(CallStep {
                    callee: tcx.item_name(callee).as_str().to_owned(),
                    right,
                    destination: destination.local.as_usize(),
                    save_result: false,
                });
                previous_destination = Some(destination.local.as_usize());
                block_id = *target;
            }
            TerminatorKind::Return => {
                if steps.len() < 2 || previous_destination != Some(0) {
                    return None;
                }
                let mut slots = Vec::new();
                for index in 0..steps.len() {
                    let destination = steps[index].destination;
                    let future_uses = steps[index + 1..]
                        .iter()
                        .filter(|step| matches!(step.right, CallRight::SavedLocal(local) if local == destination))
                        .count();
                    if future_uses != 0 {
                        steps[index].save_result = true;
                        let offset = u16::try_from(slots.len() + 1).ok()?;
                        if offset > u8::MAX as u16 {
                            return None;
                        }
                        slots.push((destination, offset));
                    }
                }
                if steps.iter().any(|step| {
                    matches!(step.right, CallRight::SavedLocal(local) if !slots.iter().any(|(saved, _)| *saved == local))
                }) {
                    return None;
                }
                return Some(MirOperation::CallChain { steps, slots });
            }
            _ => return None,
        }
    }
}

fn returned_local(body: &Body<'_>, block: BasicBlock) -> Option<usize> {
    let data = &body.basic_blocks[block];
    let statement = data.statements.first()?;
    let StatementKind::Assign(assignment) = &statement.kind else {
        return None;
    };
    let (destination, Rvalue::Use(value, _)) = assignment.as_ref() else {
        return None;
    };
    if destination.local.as_usize() != 0 || !destination.projection.is_empty() {
        return None;
    }
    operand_local(value)
}

fn constant_u16(operand: &Operand<'_>) -> Option<u16> {
    let Operand::Constant(constant) = operand else {
        return None;
    };
    if !matches!(constant.const_.ty().kind(), ty::Uint(ty::UintTy::U16)) {
        return None;
    }
    Some(constant.const_.try_to_scalar_int()?.to_u16())
}

fn direct_callee<'tcx>(
    tcx: TyCtxt<'tcx>,
    body: &Body<'tcx>,
    operand: &Operand<'tcx>,
) -> Option<DefId> {
    let ty::FnDef(callee, _) = *operand.ty(body, tcx).kind() else {
        return None;
    };
    Some(callee)
}

fn is_expect_or_panic_block<'tcx>(
    tcx: TyCtxt<'tcx>,
    body: &Body<'tcx>,
    block: &rustc_middle::mir::BasicBlockData<'tcx>,
) -> Option<()> {
    let TerminatorKind::Call {
        func, target: None, ..
    } = &block.terminator().kind
    else {
        return None;
    };
    let callee = direct_callee(tcx, body, func)?;
    let path = tcx.def_path_str(callee);
    (path.ends_with("::option::expect_failed") || path.ends_with("::panicking::panic"))
        .then_some(())
}

fn discriminant_source_local(
    statement: &rustc_middle::mir::Statement<'_>,
) -> Option<(usize, usize)> {
    let StatementKind::Assign(assignment) = &statement.kind else {
        return None;
    };
    let (destination, Rvalue::Discriminant(source)) = assignment.as_ref() else {
        return None;
    };
    if !destination.projection.is_empty() || !source.projection.is_empty() {
        return None;
    }
    Some((destination.local.as_usize(), source.local.as_usize()))
}

fn mut_ref_source_local(statement: &rustc_middle::mir::Statement<'_>) -> Option<usize> {
    let StatementKind::Assign(assignment) = &statement.kind else {
        return None;
    };
    let (_, Rvalue::Ref(_, _, source)) = assignment.as_ref() else {
        return None;
    };
    if !source.projection.is_empty() {
        return None;
    }
    Some(source.local.as_usize())
}

fn output_pin_ty_pin<'tcx>(ty: ty::Ty<'tcx>) -> Option<u16> {
    let ty_text = format!("{ty:?}");
    let start = ty_text.find("OutputPin<")? + "OutputPin<".len();
    let digits = ty_text[start..]
        .chars()
        .skip_while(|ch| !ch.is_ascii_digit())
        .take_while(|ch| ch.is_ascii_digit())
        .collect::<String>();
    let pin = digits.parse::<u16>().ok()?;
    (pin <= 44).then_some(pin)
}

fn is_diverging_panic<'tcx>(
    tcx: TyCtxt<'tcx>,
    body: &Body<'tcx>,
    block: &rustc_middle::mir::BasicBlockData<'tcx>,
) -> bool {
    let TerminatorKind::Call {
        func, target: None, ..
    } = &block.terminator().kind
    else {
        return false;
    };
    let Some(callee) = direct_callee(tcx, body, func) else {
        return false;
    };
    let path = tcx.def_path_str(callee);
    path.ends_with("::panicking::panic") || path.ends_with("::option::unwrap_failed")
}

fn success_guard(
    block: &rustc_middle::mir::BasicBlockData<'_>,
    result_local: usize,
    failure: BasicBlock,
    success: BasicBlock,
) -> bool {
    let TerminatorKind::SwitchInt { discr, targets } = &block.terminator().kind else {
        return false;
    };
    operand_local(discr) == Some(result_local)
        && targets.target_for_value(0) == failure
        && targets.otherwise() == success
}

fn local_constant_u16(statement: &rustc_middle::mir::Statement<'_>) -> Option<(usize, u16)> {
    let StatementKind::Assign(assignment) = &statement.kind else {
        return None;
    };
    let (destination, Rvalue::Use(value, _)) = assignment.as_ref() else {
        return None;
    };
    if !destination.projection.is_empty() {
        return None;
    }
    Some((destination.local.as_usize(), constant_u16(value)?))
}

fn local_copy(statement: &rustc_middle::mir::Statement<'_>) -> Option<(usize, usize)> {
    let StatementKind::Assign(assignment) = &statement.kind else {
        return None;
    };
    let (destination, Rvalue::Use(value, _)) = assignment.as_ref() else {
        return None;
    };
    if !destination.projection.is_empty() {
        return None;
    }
    Some((destination.local.as_usize(), operand_local(value)?))
}

fn classify_platform_control_loop<'tcx>(
    tcx: TyCtxt<'tcx>,
    body: &Body<'tcx>,
) -> Option<MirOperation> {
    if body.arg_count != 0 || !body.local_decls.iter().next()?.ty.is_never() {
        return None;
    }
    let blocks = body.basic_blocks.iter_enumerated().collect::<Vec<_>>();

    #[derive(Clone, Copy)]
    enum PwmCompareShape<'a, 'tcx> {
        Direct,
        Clamped {
            decision: &'a rustc_middle::mir::BasicBlockData<'tcx>,
            high: &'a rustc_middle::mir::BasicBlockData<'tcx>,
            sample: &'a rustc_middle::mir::BasicBlockData<'tcx>,
            high_bb: BasicBlock,
            sample_bb: BasicBlock,
            update_bb: BasicBlock,
        },
    }

    let (
        init,
        bb1,
        sample,
        bb2,
        take,
        bb3,
        take_guard,
        bb4,
        status_gpio,
        bb5,
        take_rejected,
        bb6,
        interrupt_gpio,
        bb7,
        status_guard,
        bb8,
        status_rejected,
        bb9,
        pwm_configure,
        bb10,
        interrupt_guard,
        bb11,
        interrupt_rejected,
        bb12,
        timer_start,
        bb13,
        pwm_guard,
        bb14,
        pwm_rejected,
        bb15,
        timer_guard,
        bb16,
        timer_rejected,
        bb17,
        pwm_update,
        bb18,
        gpio_update,
        bb19,
        loop_back,
        pwm_compare_shape,
    ) = match blocks.as_slice() {
        [
            (_bb0, init),
            (bb1, sample),
            (bb2, take),
            (bb3, take_guard),
            (bb4, status_gpio),
            (bb5, take_rejected),
            (bb6, interrupt_gpio),
            (bb7, status_guard),
            (bb8, status_rejected),
            (bb9, pwm_configure),
            (bb10, interrupt_guard),
            (bb11, interrupt_rejected),
            (bb12, timer_start),
            (bb13, pwm_guard),
            (bb14, pwm_rejected),
            (bb15, timer_guard),
            (bb16, timer_rejected),
            (bb17, pwm_update),
            (bb18, gpio_update),
            (bb19, loop_back),
        ] => (
            init,
            *bb1,
            sample,
            *bb2,
            take,
            *bb3,
            take_guard,
            *bb4,
            status_gpio,
            *bb5,
            take_rejected,
            *bb6,
            interrupt_gpio,
            *bb7,
            status_guard,
            *bb8,
            status_rejected,
            *bb9,
            pwm_configure,
            *bb10,
            interrupt_guard,
            *bb11,
            interrupt_rejected,
            *bb12,
            timer_start,
            *bb13,
            pwm_guard,
            *bb14,
            pwm_rejected,
            *bb15,
            timer_guard,
            *bb16,
            timer_rejected,
            *bb17,
            pwm_update,
            *bb18,
            gpio_update,
            *bb19,
            loop_back,
            PwmCompareShape::Direct,
        ),
        [
            (_bb0, init),
            (bb1, sample),
            (bb2, take),
            (bb3, take_guard),
            (bb4, status_gpio),
            (bb5, take_rejected),
            (bb6, interrupt_gpio),
            (bb7, status_guard),
            (bb8, status_rejected),
            (bb9, pwm_configure),
            (bb10, interrupt_guard),
            (bb11, interrupt_rejected),
            (bb12, timer_start),
            (bb13, pwm_guard),
            (bb14, pwm_rejected),
            (bb15, timer_guard),
            (bb16, timer_rejected),
            (bb17, pwm_decision),
            (bb18, pwm_update),
            (bb19, pwm_high),
            (bb20, pwm_sample),
            (bb21, gpio_update),
            (bb22, loop_back),
        ] => (
            init,
            *bb1,
            sample,
            *bb2,
            take,
            *bb3,
            take_guard,
            *bb4,
            status_gpio,
            *bb5,
            take_rejected,
            *bb6,
            interrupt_gpio,
            *bb7,
            status_guard,
            *bb8,
            status_rejected,
            *bb9,
            pwm_configure,
            *bb10,
            interrupt_guard,
            *bb11,
            interrupt_rejected,
            *bb12,
            timer_start,
            *bb13,
            pwm_guard,
            *bb14,
            pwm_rejected,
            *bb15,
            timer_guard,
            *bb16,
            timer_rejected,
            *bb17,
            pwm_update,
            *bb21,
            gpio_update,
            *bb22,
            loop_back,
            PwmCompareShape::Clamped {
                decision: pwm_decision,
                high: pwm_high,
                sample: pwm_sample,
                high_bb: *bb19,
                sample_bb: *bb20,
                update_bb: *bb18,
            },
        ),
        _ => return None,
    };

    if blocks.iter().enumerate().any(|(index, (_, block))| {
        let allowed = match pwm_compare_shape {
            PwmCompareShape::Direct => index == 18,
            PwmCompareShape::Clamped { .. } => matches!(index, 17 | 19 | 20 | 21),
        };
        !allowed && !block.statements.is_empty()
    }) || gpio_update.statements.len() != 2
        || !matches!(loop_back.terminator().kind, TerminatorKind::Goto { target } if target == bb1)
    {
        return None;
    }

    let TerminatorKind::Call {
        func: init_func,
        args: init_args,
        target: Some(init_target),
        ..
    } = &init.terminator().kind
    else {
        return None;
    };
    let init_callee = direct_callee(tcx, body, init_func)?;
    if !init_args.is_empty()
        || *init_target != bb2
        || tcx.item_name(init_callee).as_str() != "f28035_system_init"
    {
        return None;
    }

    let TerminatorKind::Call {
        func: take_func,
        args: take_args,
        destination: take_destination,
        target: Some(take_target),
        ..
    } = &take.terminator().kind
    else {
        return None;
    };
    let take_callee = direct_callee(tcx, body, take_func)?;
    if !take_args.is_empty()
        || *take_target != bb3
        || tcx.item_name(take_callee).as_str() != "f28035_take_peripherals"
        || !success_guard(take_guard, take_destination.local.as_usize(), bb5, bb4)
        || !is_diverging_panic(tcx, body, take_rejected)
    {
        return None;
    }

    let TerminatorKind::Call {
        func: status_func,
        args: status_args,
        destination: status_destination,
        target: Some(status_target),
        ..
    } = &status_gpio.terminator().kind
    else {
        return None;
    };
    let gpio_make_callee = direct_callee(tcx, body, status_func)?;
    let gpio_status_pin = constant_u16(&status_args.first()?.node)?;
    if status_args.len() != 1
        || gpio_status_pin > 44
        || *status_target != bb7
        || tcx.item_name(gpio_make_callee).as_str() != "f28035_gpio_make_output"
        || !success_guard(status_guard, status_destination.local.as_usize(), bb8, bb6)
        || !is_diverging_panic(tcx, body, status_rejected)
    {
        return None;
    }

    let TerminatorKind::Call {
        func: interrupt_func,
        args: interrupt_args,
        destination: interrupt_destination,
        target: Some(interrupt_target),
        ..
    } = &interrupt_gpio.terminator().kind
    else {
        return None;
    };
    let interrupt_gpio_callee = direct_callee(tcx, body, interrupt_func)?;
    let gpio_interrupt_pin = constant_u16(&interrupt_args.first()?.node)?;
    if interrupt_args.len() != 1
        || gpio_interrupt_pin > 44
        || gpio_interrupt_pin == gpio_status_pin
        || *interrupt_target != bb10
        || interrupt_gpio_callee != gpio_make_callee
        || !success_guard(
            interrupt_guard,
            interrupt_destination.local.as_usize(),
            bb11,
            bb9,
        )
        || !is_diverging_panic(tcx, body, interrupt_rejected)
    {
        return None;
    }

    let TerminatorKind::Call {
        func: pwm_configure_func,
        args: pwm_configure_args,
        destination: pwm_destination,
        target: Some(pwm_target),
        ..
    } = &pwm_configure.terminator().kind
    else {
        return None;
    };
    let pwm_configure_callee = direct_callee(tcx, body, pwm_configure_func)?;
    let pwm_period = constant_u16(&pwm_configure_args.first()?.node)?;
    if pwm_configure_args.len() != 1
        || pwm_period == 0
        || *pwm_target != bb13
        || tcx.item_name(pwm_configure_callee).as_str() != "f28035_epwm1_configure"
        || !success_guard(pwm_guard, pwm_destination.local.as_usize(), bb14, bb12)
        || !is_diverging_panic(tcx, body, pwm_rejected)
    {
        return None;
    }

    let TerminatorKind::Call {
        func: timer_func,
        args: timer_args,
        destination: timer_destination,
        target: Some(timer_target),
        ..
    } = &timer_start.terminator().kind
    else {
        return None;
    };
    let timer_callee = direct_callee(tcx, body, timer_func)?;
    let timer_period_ms = constant_u16(&timer_args.first()?.node)?;
    if timer_args.len() != 1
        || !(1..=1000).contains(&timer_period_ms)
        || *timer_target != bb15
        || tcx.item_name(timer_callee).as_str() != "f28035_timer0_start_periodic_ms"
        || !success_guard(timer_guard, timer_destination.local.as_usize(), bb16, bb1)
        || !is_diverging_panic(tcx, body, timer_rejected)
    {
        return None;
    }

    let TerminatorKind::Call {
        func: sample_func,
        args: sample_args,
        destination: sample_destination,
        target: Some(sample_target),
        ..
    } = &sample.terminator().kind
    else {
        return None;
    };
    let sample_callee = direct_callee(tcx, body, sample_func)?;
    let adc_result_index = constant_u16(&sample_args.first()?.node)?;
    if sample_args.len() != 1
        || adc_result_index > 15
        || *sample_target != bb17
        || tcx.item_name(sample_callee).as_str() != "f28035_adc_sample"
    {
        return None;
    }

    let sample_local = sample_destination.local.as_usize();
    let pwm_compare_local = match pwm_compare_shape {
        PwmCompareShape::Direct => sample_local,
        PwmCompareShape::Clamped {
            decision,
            high,
            sample,
            high_bb,
            sample_bb,
            update_bb,
        } => {
            if decision.statements.len() != 1
                || high.statements.len() != 1
                || sample.statements.len() != 1
            {
                return None;
            }
            let (condition_local, operation, left, right) =
                binary_assignment(&decision.statements[0])?;
            if operation != BinOp::Gt
                || operand_local(left) != Some(sample_local)
                || constant_u16(right) != Some(pwm_period)
            {
                return None;
            }
            let TerminatorKind::SwitchInt { discr, targets } = &decision.terminator().kind else {
                return None;
            };
            if operand_local(discr) != Some(condition_local)
                || targets.target_for_value(0) != sample_bb
                || targets.otherwise() != high_bb
            {
                return None;
            }
            let (high_local, high_value) = local_constant_u16(&high.statements[0])?;
            let (sample_compare_local, copied_local) = local_copy(&sample.statements[0])?;
            if high_value != pwm_period
                || sample_compare_local != high_local
                || copied_local != sample_local
            {
                return None;
            }
            if !matches!(high.terminator().kind, TerminatorKind::Goto { target } if target == update_bb)
                || !matches!(sample.terminator().kind, TerminatorKind::Goto { target } if target == update_bb)
            {
                return None;
            }
            high_local
        }
    };

    let TerminatorKind::Call {
        func: pwm_update_func,
        args: pwm_update_args,
        target: Some(pwm_update_target),
        ..
    } = &pwm_update.terminator().kind
    else {
        return None;
    };
    let pwm_update_callee = direct_callee(tcx, body, pwm_update_func)?;
    if pwm_update_args.len() != 1
        || operand_local(&pwm_update_args[0].node) != Some(pwm_compare_local)
        || *pwm_update_target != bb18
        || tcx.item_name(pwm_update_callee).as_str() != "f28035_epwm1_set_compare"
    {
        return None;
    }

    let (condition_local, operation, left, right) = binary_assignment(&gpio_update.statements[0])?;
    let threshold = constant_u16(right)?;
    if operation != BinOp::Ge || operand_local(left) != Some(sample_destination.local.as_usize()) {
        return None;
    }
    let StatementKind::Assign(cast_assignment) = &gpio_update.statements[1].kind else {
        return None;
    };
    let (cast_destination, Rvalue::Cast(CastKind::IntToInt, cast_operand, cast_ty)) =
        cast_assignment.as_ref()
    else {
        return None;
    };
    if operand_local(cast_operand) != Some(condition_local) || *cast_ty != tcx.types.u16 {
        return None;
    }
    let TerminatorKind::Call {
        func: gpio_write_func,
        args: gpio_write_args,
        target: Some(gpio_write_target),
        ..
    } = &gpio_update.terminator().kind
    else {
        return None;
    };
    let gpio_write_callee = direct_callee(tcx, body, gpio_write_func)?;
    if gpio_write_args.len() != 2
        || constant_u16(&gpio_write_args[0].node) != Some(gpio_status_pin)
        || operand_local(&gpio_write_args[1].node) != Some(cast_destination.local.as_usize())
        || *gpio_write_target != bb19
        || tcx.item_name(gpio_write_callee).as_str() != "f28035_gpio_write"
    {
        return None;
    }

    Some(MirOperation::PlatformControlLoop {
        system_init: tcx.item_name(init_callee).as_str().to_owned(),
        gpio_status_pin,
        gpio_interrupt_pin,
        adc_result_index,
        pwm_period,
        timer_period_ms,
        threshold,
    })
}

fn classify_interrupt_callback<'tcx>(tcx: TyCtxt<'tcx>, body: &Body<'tcx>) -> Option<MirOperation> {
    if body.arg_count != 0 || body.local_decls.iter().next()?.ty != tcx.types.unit {
        return None;
    }
    let blocks = body.basic_blocks.iter_enumerated().collect::<Vec<_>>();
    let [(_bb0, toggle), (bb1, ack), (bb2, done)] = blocks.as_slice() else {
        return None;
    };
    if blocks.iter().any(|(_, block)| !block.statements.is_empty())
        || !matches!(done.terminator().kind, TerminatorKind::Return)
    {
        return None;
    }
    let TerminatorKind::Call {
        func: toggle_func,
        args: toggle_args,
        target: Some(toggle_target),
        ..
    } = &toggle.terminator().kind
    else {
        return None;
    };
    let toggle_callee = direct_callee(tcx, body, toggle_func)?;
    let pin = constant_u16(&toggle_args.first()?.node)?;
    if toggle_args.len() != 1
        || pin > 44
        || *toggle_target != *bb1
        || tcx.item_name(toggle_callee).as_str() != "f28035_gpio_toggle"
    {
        return None;
    }
    let TerminatorKind::Call {
        func: ack_func,
        args: ack_args,
        target: Some(ack_target),
        ..
    } = &ack.terminator().kind
    else {
        return None;
    };
    let ack_callee = direct_callee(tcx, body, ack_func)?;
    if !ack_args.is_empty()
        || *ack_target != *bb2
        || tcx.item_name(ack_callee).as_str() != "f28035_timer0_ack"
    {
        return None;
    }
    Some(MirOperation::InterruptCallback { pin })
}

fn classify_high_level_safe_gpio<'tcx>(
    tcx: TyCtxt<'tcx>,
    body: &Body<'tcx>,
) -> Option<MirOperation> {
    if body.arg_count != 0 || body.local_decls.iter().next()?.ty != tcx.types.unit {
        return None;
    }

    let init_bb = body.basic_blocks.indices().next()?;
    let init = &body.basic_blocks[init_bb];
    let TerminatorKind::Call {
        func: init_func,
        args: init_args,
        target: Some(take_bb),
        ..
    } = &init.terminator().kind
    else {
        return None;
    };
    let init_callee = direct_callee(tcx, body, init_func)?;
    if !init_args.is_empty() || tcx.item_name(init_callee).as_str() != "system_init" {
        return None;
    }

    let take = &body.basic_blocks[*take_bb];
    let TerminatorKind::Call {
        func: take_func,
        args: take_args,
        destination: take_destination,
        target: Some(take_guard_bb),
        ..
    } = &take.terminator().kind
    else {
        return None;
    };
    let take_callee = direct_callee(tcx, body, take_func)?;
    if !take_args.is_empty()
        || !take_destination.projection.is_empty()
        || tcx.item_name(take_callee).as_str() != "take"
    {
        return None;
    }

    let take_guard = &body.basic_blocks[*take_guard_bb];
    if take_guard.statements.len() != 1 {
        return None;
    }
    let (discriminant_local, option_local) = discriminant_source_local(&take_guard.statements[0])?;
    if option_local != take_destination.local.as_usize() {
        return None;
    }
    let TerminatorKind::SwitchInt {
        discr: take_discr,
        targets: take_targets,
    } = &take_guard.terminator().kind
    else {
        return None;
    };
    if operand_local(take_discr) != Some(discriminant_local) {
        return None;
    }
    is_expect_or_panic_block(
        tcx,
        body,
        &body.basic_blocks[take_targets.target_for_value(0)],
    )?;

    let mut cur = take_targets.target_for_value(1);
    let mut pins = Vec::new();
    let mut output_locals: Vec<(usize, u16)> = Vec::new();
    loop {
        let block = &body.basic_blocks[cur];
        let TerminatorKind::Call {
            func,
            destination,
            target: Some(next),
            ..
        } = &block.terminator().kind
        else {
            break;
        };
        let callee = direct_callee(tcx, body, func)?;
        if tcx.item_name(callee).as_str() != "output" {
            break;
        }
        if block.statements.len() != 1
            || mut_ref_source_local(&block.statements[0]).is_none()
            || !destination.projection.is_empty()
        {
            return None;
        }
        let pin = output_pin_ty_pin(body.local_decls[destination.local].ty)?;
        if pins.contains(&pin)
            || output_locals
                .iter()
                .any(|(local, _)| *local == destination.local.as_usize())
        {
            return None;
        }
        pins.push(pin);
        output_locals.push((destination.local.as_usize(), pin));
        cur = *next;
    }
    if pins.is_empty() {
        return None;
    }

    let mut actions = Vec::new();
    loop {
        let block = &body.basic_blocks[cur];
        if matches!(block.terminator().kind, TerminatorKind::Return) {
            break;
        }
        if block.statements.len() != 1 {
            return None;
        }
        let pin_local = mut_ref_source_local(&block.statements[0])?;
        let pin = output_locals
            .iter()
            .find_map(|(local, pin)| (*local == pin_local).then_some(*pin))?;
        let TerminatorKind::Call {
            func,
            target: Some(next),
            ..
        } = &block.terminator().kind
        else {
            return None;
        };
        let callee = direct_callee(tcx, body, func)?;
        let action = match tcx.item_name(callee).as_str() {
            "set_low" => GpioOutputAction::Write { pin, value: 0 },
            "set_high" => GpioOutputAction::Write { pin, value: 1 },
            "toggle" => GpioOutputAction::Toggle { pin },
            _ => return None,
        };
        actions.push(action);
        cur = *next;
    }
    if actions.is_empty() {
        return None;
    }

    Some(MirOperation::GpioLow {
        system_init: "f28035_system_init".to_owned(),
        take_peripherals: "f28035_take_peripherals".to_owned(),
        make_output: "f28035_gpio_make_output".to_owned(),
        gpio_write: "f28035_gpio_write".to_owned(),
        gpio_toggle: "f28035_gpio_toggle".to_owned(),
        pins,
        actions,
    })
}

fn classify_safe_gpio_low<'tcx>(tcx: TyCtxt<'tcx>, body: &Body<'tcx>) -> Option<MirOperation> {
    if let Some(operation) = classify_high_level_safe_gpio(tcx, body) {
        return Some(operation);
    }

    if body.arg_count != 0 || body.local_decls.iter().next()?.ty != tcx.types.unit {
        return None;
    }
    let blocks = body.basic_blocks.iter_enumerated().collect::<Vec<_>>();
    if blocks.len() < 7 {
        return None;
    }
    let [(_, init), (_, take), (_, take_guard), ..] = &blocks[..] else {
        return None;
    };

    // Strict straight-line template: no optimized statements anywhere.
    if blocks.iter().any(|(_, block)| !block.statements.is_empty()) {
        return None;
    }

    let TerminatorKind::Call {
        func: init_func,
        args: init_args,
        target: Some(init_target),
        ..
    } = &init.terminator().kind
    else {
        return None;
    };
    let init_callee = direct_callee(tcx, body, init_func)?;
    if !init_args.is_empty()
        || *init_target != blocks[1].0
        || tcx.item_name(init_callee).as_str() != "f28035_system_init"
    {
        return None;
    }

    let TerminatorKind::Call {
        func: take_func,
        args: take_args,
        destination: take_destination,
        target: Some(take_target),
        ..
    } = &take.terminator().kind
    else {
        return None;
    };
    let take_callee = direct_callee(tcx, body, take_func)?;
    if !take_args.is_empty()
        || *take_target != blocks[2].0
        || !take_destination.projection.is_empty()
        || body.local_decls[take_destination.local].ty != tcx.types.u16
        || tcx.item_name(take_callee).as_str() != "f28035_take_peripherals"
    {
        return None;
    }

    let TerminatorKind::SwitchInt {
        discr: take_discr,
        targets: take_targets,
    } = &take_guard.terminator().kind
    else {
        return None;
    };
    if operand_local(take_discr) != Some(take_destination.local.as_usize())
        || take_targets.otherwise() != blocks[3].0
    {
        return None;
    }

    let is_expect_or_panic = |block: &rustc_middle::mir::BasicBlockData<'tcx>| -> Option<()> {
        let TerminatorKind::Call {
            func, target: None, ..
        } = &block.terminator().kind
        else {
            return None;
        };
        let callee = direct_callee(tcx, body, func)?;
        let path = tcx.def_path_str(callee);
        (path.ends_with("::option::expect_failed") || path.ends_with("::panicking::panic"))
            .then_some(())
    };

    is_expect_or_panic(blocks[take_targets.target_for_value(0).index()].1)?;

    let mut pins = Vec::new();
    let mut make_output_name: Option<String> = None;
    let mut cur = take_targets.otherwise();
    loop {
        let block = blocks[cur.index()].1;
        let TerminatorKind::Call {
            func,
            args,
            destination,
            target: Some(guard_idx),
            ..
        } = &block.terminator().kind
        else {
            break;
        };
        let callee = direct_callee(tcx, body, func)?;
        if tcx.item_name(callee).as_str() != "f28035_gpio_make_output" {
            break;
        }
        let pin = constant_u16(&args.first()?.node)?;
        if args.len() != 1
            || pin > 44
            || pins.contains(&pin)
            || !destination.projection.is_empty()
            || body.local_decls[destination.local].ty != tcx.types.u16
        {
            return None;
        }
        if let Some(existing) = &make_output_name {
            if existing != tcx.item_name(callee).as_str() {
                return None;
            }
        } else {
            make_output_name = Some(tcx.item_name(callee).as_str().to_owned());
        }

        let guard = blocks[guard_idx.index()].1;
        let TerminatorKind::SwitchInt {
            discr: guard_discr,
            targets: guard_targets,
        } = &guard.terminator().kind
        else {
            return None;
        };
        if operand_local(guard_discr) != Some(destination.local.as_usize()) {
            return None;
        }
        is_expect_or_panic(blocks[guard_targets.target_for_value(0).index()].1)?;
        pins.push(pin);
        cur = guard_targets.otherwise();
    }
    if pins.is_empty() {
        return None;
    }

    // Walk the straight-line action chain. Each visited non-terminal block is a
    // write(pin,0|1) or toggle(pin); the final block is Return.  This accepts
    // any number of actions over any previously configured output pin.
    let mut actions: Vec<GpioOutputAction> = Vec::new();
    loop {
        let block = blocks[cur.index()].1;
        if matches!(block.terminator().kind, TerminatorKind::Return) {
            break;
        }
        let TerminatorKind::Call {
            func,
            args,
            target: Some(next),
            ..
        } = &block.terminator().kind
        else {
            return None;
        };
        let callee = direct_callee(tcx, body, func)?;
        let action_name = tcx.item_name(callee);
        let action = match action_name.as_str() {
            "f28035_gpio_write" => {
                let write_pin = constant_u16(&args[0].node);
                let write_value = constant_u16(&args[1].node);
                if args.len() != 2
                    || !write_pin.is_some_and(|pin| pins.contains(&pin))
                    || (write_value != Some(0) && write_value != Some(1))
                {
                    return None;
                }
                GpioOutputAction::Write {
                    pin: write_pin.expect("validated gpio write pin is configured"),
                    value: write_value.expect("validated gpio write constant is 0 or 1"),
                }
            }
            "f28035_gpio_toggle" => {
                let toggle_pin = constant_u16(&args[0].node);
                if args.len() != 1 || !toggle_pin.is_some_and(|pin| pins.contains(&pin)) {
                    return None;
                }
                GpioOutputAction::Toggle {
                    pin: toggle_pin.expect("validated gpio toggle pin is configured"),
                }
            }
            _ => return None,
        };
        actions.push(action);
        cur = *next;
    }
    if actions.is_empty() {
        return None;
    }

    Some(MirOperation::GpioLow {
        system_init: tcx.item_name(init_callee).as_str().to_owned(),
        take_peripherals: tcx.item_name(take_callee).as_str().to_owned(),
        make_output: make_output_name.expect("validated at least one GPIO output configure"),
        gpio_write: "f28035_gpio_write".to_owned(),
        gpio_toggle: "f28035_gpio_toggle".to_owned(),
        pins,
        actions,
    })
}

/// Extract the const-generic scalar values of a monomorphized FnDef callee
/// type in declaration order.  For the un-inlined `InputPin::<PIN>::take::
/// <PULLUP, QUALIFICATION>` call the optimized MIR still carries the FnDef
/// with its const args, e.g. `InputPin::<34>::take::<true, 0>()` yields
/// `[34, 1, 0]` (PIN, PULLUP, QUALIFICATION).
fn fn_def_const_u16s<'tcx>(
    tcx: TyCtxt<'tcx>,
    body: &Body<'tcx>,
    func: &Operand<'tcx>,
) -> Option<Vec<u16>> {
    let ty::FnDef(_, generic_args) = *func.ty(body, tcx).kind() else {
        return None;
    };
    let mut values = Vec::new();
    for arg in generic_args.skip_binder().iter() {
        if let ty::GenericArgKind::Const(constant) = arg.kind() {
            values.push(
                constant
                    .try_to_scalar()?
                    .to_scalar_int()
                    .discard_err()?
                    .to_bits_unchecked() as u16,
            );
        }
    }
    Some(values)
}

fn fn_def_const_u16s_from_debug<'tcx>(
    tcx: TyCtxt<'tcx>,
    body: &Body<'tcx>,
    func: &Operand<'tcx>,
) -> Option<Vec<u16>> {
    let text = format!("{:?}", func.ty(body, tcx));
    let start = text.find("::<")? + 3;
    let end = text[start..].find('>')? + start;
    let mut values = Vec::new();
    for part in text[start..end].split(',') {
        let trimmed = part.trim();
        if trimmed.chars().all(|ch| ch.is_ascii_digit()) {
            values.push(trimmed.parse::<u16>().ok()?);
        }
    }
    (!values.is_empty()).then_some(values)
}

/// Classify a Safe HAL GPIO function that interleaves output/input direction
/// configuration with write/toggle actions in straight-line order (e.g.
/// `gpio_direction_switch_basic`: make_output -> write high -> make_input ->
/// make_output -> write low).  Unlike [`classify_safe_gpio_low`], the
/// configuration blocks (make_output / make_input, each carrying its own
/// SwitchInt guard plus a diverging panic block) and action blocks (write /
/// toggle, no guard) may interleave, and the un-inlined
/// `InputPin::<PIN>::take::<PULLUP, QUALIFICATION>()` call is recognized from
/// its FnDef const-generic arguments.
fn classify_gpio_sequence<'tcx>(tcx: TyCtxt<'tcx>, body: &Body<'tcx>) -> Option<MirOperation> {
    if body.arg_count != 0 || body.local_decls.iter().next()?.ty != tcx.types.unit {
        return None;
    }
    let blocks = body.basic_blocks.iter_enumerated().collect::<Vec<_>>();
    if blocks.len() < 7 {
        return None;
    }
    let [(_, init), (_, take), (_, take_guard), ..] = &blocks[..] else {
        return None;
    };

    // Strict straight-line template: no optimized statements anywhere.  The
    // un-inlined InputPin::take appears as a plain call terminator, so this
    // holds for the direction-switch shape too.
    if blocks.iter().any(|(_, block)| !block.statements.is_empty()) {
        return None;
    }

    let TerminatorKind::Call {
        func: init_func,
        args: init_args,
        target: Some(init_target),
        ..
    } = &init.terminator().kind
    else {
        return None;
    };
    let init_callee = direct_callee(tcx, body, init_func)?;
    if !init_args.is_empty()
        || *init_target != blocks[1].0
        || tcx.item_name(init_callee).as_str() != "f28035_system_init"
    {
        return None;
    }

    let TerminatorKind::Call {
        func: take_func,
        args: take_args,
        destination: take_destination,
        target: Some(take_target),
        ..
    } = &take.terminator().kind
    else {
        return None;
    };
    let take_callee = direct_callee(tcx, body, take_func)?;
    if !take_args.is_empty()
        || *take_target != blocks[2].0
        || !take_destination.projection.is_empty()
        || body.local_decls[take_destination.local].ty != tcx.types.u16
        || tcx.item_name(take_callee).as_str() != "f28035_take_peripherals"
    {
        return None;
    }

    let TerminatorKind::SwitchInt {
        discr: take_discr,
        targets: take_targets,
    } = &take_guard.terminator().kind
    else {
        return None;
    };
    if operand_local(take_discr) != Some(take_destination.local.as_usize())
        || take_targets.otherwise() != blocks[3].0
    {
        return None;
    }
    is_expect_or_panic_block(
        tcx,
        body,
        blocks[take_targets.target_for_value(0).index()].1,
    )?;

    let mut configured_pins: Vec<u16> = Vec::new();
    let mut steps: Vec<GpioStep> = Vec::new();
    let mut make_output_name: Option<String> = None;
    let mut make_input_name: Option<String> = None;
    let mut cur = take_targets.otherwise();
    loop {
        let block = blocks[cur.index()].1;
        if matches!(block.terminator().kind, TerminatorKind::Return) {
            break;
        }
        let TerminatorKind::Call {
            func,
            args,
            destination,
            target: Some(next),
            ..
        } = &block.terminator().kind
        else {
            return None;
        };
        let callee = direct_callee(tcx, body, func)?;
        let callee_name = tcx.item_name(callee).as_str().to_owned();
        if callee_name == "f28035_gpio_make_output" {
            let pin = constant_u16(&args.first()?.node)?;
            if args.len() != 1
                || pin > 44
                || !destination.projection.is_empty()
                || body.local_decls[destination.local].ty != tcx.types.u16
            {
                return None;
            }
            if let Some(existing) = &make_output_name {
                if existing != &callee_name {
                    return None;
                }
            } else {
                make_output_name = Some(callee_name.clone());
            }
            if !configured_pins.contains(&pin) {
                configured_pins.push(pin);
            }
            let guard = blocks[next.index()].1;
            let TerminatorKind::SwitchInt {
                discr: guard_discr,
                targets: guard_targets,
            } = &guard.terminator().kind
            else {
                return None;
            };
            if operand_local(guard_discr) != Some(destination.local.as_usize()) {
                return None;
            }
            is_expect_or_panic_block(
                tcx,
                body,
                blocks[guard_targets.target_for_value(0).index()].1,
            )?;
            steps.push(GpioStep::MakeOutput { pin });
            cur = guard_targets.otherwise();
            continue;
        }
        if callee_name == "f28035_gpio_make_input" {
            let pin = constant_u16(&args[0].node)?;
            let pullup = constant_u16(&args[1].node)?;
            let qualification = constant_u16(&args[2].node)?;
            if args.len() != 3
                || pin > 44
                || pullup > 1
                || qualification > 3
                || !destination.projection.is_empty()
                || body.local_decls[destination.local].ty != tcx.types.u16
            {
                return None;
            }
            if let Some(existing) = &make_input_name {
                if existing != &callee_name {
                    return None;
                }
            } else {
                make_input_name = Some(callee_name.clone());
            }
            if !configured_pins.contains(&pin) {
                configured_pins.push(pin);
            }
            let guard = blocks[next.index()].1;
            let TerminatorKind::SwitchInt {
                discr: guard_discr,
                targets: guard_targets,
            } = &guard.terminator().kind
            else {
                return None;
            };
            if operand_local(guard_discr) != Some(destination.local.as_usize()) {
                return None;
            }
            is_expect_or_panic_block(
                tcx,
                body,
                blocks[guard_targets.target_for_value(0).index()].1,
            )?;
            steps.push(GpioStep::MakeInput {
                pin,
                pullup,
                qualification,
            });
            cur = guard_targets.otherwise();
            continue;
        }
        // Un-inlined `InputPin::<PIN>::take::<PULLUP, QUALIFICATION>()`:
        // recognize it from the FnDef const-generic args (PIN, PULLUP, QUAL).
        if callee_name == "take" && tcx.def_path_str(callee).contains("InputPin") {
            let consts = fn_def_const_u16s(tcx, body, func)?;
            let [pin, pullup, qualification] = consts.as_slice() else {
                return None;
            };
            if *pin > 44 || *pullup > 1 || *qualification > 3 {
                return None;
            }
            if !configured_pins.contains(pin) {
                configured_pins.push(*pin);
            }
            steps.push(GpioStep::MakeInput {
                pin: *pin,
                pullup: *pullup,
                qualification: *qualification,
            });
            cur = *next;
            continue;
        }
        if callee_name == "f28035_gpio_write" {
            let pin = constant_u16(&args[0].node)?;
            let value = constant_u16(&args[1].node)?;
            if args.len() != 2 || !configured_pins.contains(&pin) || (value != 0 && value != 1) {
                return None;
            }
            steps.push(GpioStep::Write { pin, value });
            cur = *next;
            continue;
        }
        if callee_name == "f28035_gpio_toggle" {
            let pin = constant_u16(&args.first()?.node)?;
            if args.len() != 1 || !configured_pins.contains(&pin) {
                return None;
            }
            steps.push(GpioStep::Toggle { pin });
            cur = *next;
            continue;
        }
        return None;
    }
    if steps.is_empty()
        || !steps
            .iter()
            .any(|step| matches!(step, GpioStep::MakeInput { .. }))
    {
        return None;
    }

    Some(MirOperation::GpioSequence {
        system_init: tcx.item_name(init_callee).as_str().to_owned(),
        take_peripherals: tcx.item_name(take_callee).as_str().to_owned(),
        make_output: make_output_name.expect("validated at least one GPIO output configure"),
        make_input: make_input_name.unwrap_or_else(|| "f28035_gpio_make_input".to_owned()),
        gpio_write: "f28035_gpio_write".to_owned(),
        gpio_toggle: "f28035_gpio_toggle".to_owned(),
        steps,
    })
}

/// Classify a Safe HAL GPIO MUX-routing function that calls
/// 28035_gpio_set_mux(pin, function) in straight-line order, e.g.
/// gpio_mux_basic: set_mux(0,0) -> set_mux(0,1) -> set_mux(0,0).  Each call
/// carries a SwitchInt guard plus a diverging expect/panic block, mirroring
/// the make_output shape already recognized by [classify_gpio_sequence].
fn classify_high_level_gpio_mux<'tcx>(
    tcx: TyCtxt<'tcx>,
    body: &Body<'tcx>,
) -> Option<MirOperation> {
    if body.arg_count != 0 || body.local_decls.iter().next()?.ty != tcx.types.unit {
        return None;
    }

    let mut saw_init = false;
    let mut saw_take = false;
    let mut mux_step = None;
    for block in body.basic_blocks.iter() {
        let TerminatorKind::Call { func, .. } = &block.terminator().kind else {
            continue;
        };
        let callee = direct_callee(tcx, body, func)?;
        match tcx.item_name(callee).as_str() {
            "system_init" | "f28035_system_init" => saw_init = true,
            "take" | "f28035_take_peripherals" => saw_take = true,
            "set_mux" => {
                let consts = fn_def_const_u16s(tcx, body, func)
                    .or_else(|| fn_def_const_u16s_from_debug(tcx, body, func))?;
                let [pin, function] = consts.as_slice() else {
                    return None;
                };
                if *pin > 44 || *function > 3 || mux_step.is_some() {
                    return None;
                }
                mux_step = Some(GpioMuxStep::SetMux {
                    pin: *pin,
                    function: *function,
                });
            }
        _ => {}
        }
    }
    if saw_init && saw_take {
        if let Some(step) = mux_step {
            return Some(MirOperation::GpioMux {
                system_init: "f28035_system_init".to_owned(),
                take_peripherals: "f28035_take_peripherals".to_owned(),
                set_mux: "f28035_gpio_set_mux".to_owned(),
                steps: vec![step],
            });
        }
    }

    let init_bb = body.basic_blocks.indices().next()?;
    let init = &body.basic_blocks[init_bb];
    let TerminatorKind::Call {
        func: init_func,
        args: init_args,
        target: Some(take_bb),
        ..
    } = &init.terminator().kind
    else {
        return None;
    };
    let init_callee = direct_callee(tcx, body, init_func)?;
    if !init_args.is_empty()
        || !matches!(
            tcx.item_name(init_callee).as_str(),
            "system_init" | "f28035_system_init"
        )
    {
        return None;
    }

    let take = &body.basic_blocks[*take_bb];
    let TerminatorKind::Call {
        func: take_func,
        args: take_args,
        destination: take_destination,
        target: Some(take_guard_bb),
        ..
    } = &take.terminator().kind
    else {
        return None;
    };
    let take_callee = direct_callee(tcx, body, take_func)?;
    if !take_args.is_empty()
        || !take_destination.projection.is_empty()
        || !matches!(
            tcx.item_name(take_callee).as_str(),
            "take" | "f28035_take_peripherals"
        )
    {
        return None;
    }

    let take_guard = &body.basic_blocks[*take_guard_bb];
    let TerminatorKind::SwitchInt {
        discr: take_discr,
        targets: take_targets,
    } = &take_guard.terminator().kind
    else {
        return None;
    };
    if operand_local(take_discr) != Some(take_destination.local.as_usize()) {
        return None;
    }
    is_expect_or_panic_block(
        tcx,
        body,
        &body.basic_blocks[take_targets.target_for_value(0)],
    )?;

    let set_mux_bb = take_targets.otherwise();
    let set_mux = &body.basic_blocks[set_mux_bb];
    if set_mux.statements.len() != 1 {
        return None;
    }
    let TerminatorKind::Call {
        func: set_mux_func,
        args: set_mux_args,
        target: Some(expect_bb),
        ..
    } = &set_mux.terminator().kind
    else {
        return None;
    };
    let set_mux_callee = direct_callee(tcx, body, set_mux_func)?;
    if !set_mux_args.is_empty() || tcx.item_name(set_mux_callee).as_str() != "set_mux" {
        return None;
    }
    let consts = fn_def_const_u16s(tcx, body, set_mux_func)?;
    let [pin, function] = consts.as_slice() else {
        return None;
    };
    if *pin > 44 || *function > 3 {
        return None;
    }

    let expect = &body.basic_blocks[*expect_bb];
    let TerminatorKind::Call {
        func: expect_func,
        target: Some(return_bb),
        ..
    } = &expect.terminator().kind
    else {
        return None;
    };
    let expect_callee = direct_callee(tcx, body, expect_func)?;
    if tcx.item_name(expect_callee).as_str() != "expect"
        || !matches!(
            body.basic_blocks[*return_bb].terminator().kind,
            TerminatorKind::Return
        )
    {
        return None;
    }

    Some(MirOperation::GpioMux {
        system_init: "f28035_system_init".to_owned(),
        take_peripherals: "f28035_take_peripherals".to_owned(),
        set_mux: "f28035_gpio_set_mux".to_owned(),
        steps: vec![GpioMuxStep::SetMux {
            pin: *pin,
            function: *function,
        }],
    })
}

fn classify_gpio_mux<'tcx>(tcx: TyCtxt<'tcx>, body: &Body<'tcx>) -> Option<MirOperation> {
    if let Some(operation) = classify_high_level_gpio_mux(tcx, body) {
        return Some(operation);
    }

    if body.arg_count != 0 || body.local_decls.iter().next()?.ty != tcx.types.unit {
        return None;
    }
    let blocks = body.basic_blocks.iter_enumerated().collect::<Vec<_>>();
    if blocks.len() < 6 {
        return None;
    }
    let [(_, init), (_, take), (_, take_guard), ..] = &blocks[..] else {
        return None;
    };
    if blocks.iter().any(|(_, block)| !block.statements.is_empty()) {
        return None;
    }

    let TerminatorKind::Call {
        func: init_func,
        args: init_args,
        target: Some(init_target),
        ..
    } = &init.terminator().kind
    else {
        return None;
    };
    let init_callee = direct_callee(tcx, body, init_func)?;
    if !init_args.is_empty()
        || *init_target != blocks[1].0
        || tcx.item_name(init_callee).as_str() != "f28035_system_init"
    {
        return None;
    }

    let TerminatorKind::Call {
        func: take_func,
        args: take_args,
        destination: take_destination,
        target: Some(take_target),
        ..
    } = &take.terminator().kind
    else {
        return None;
    };
    let take_callee = direct_callee(tcx, body, take_func)?;
    if !take_args.is_empty()
        || *take_target != blocks[2].0
        || !take_destination.projection.is_empty()
        || body.local_decls[take_destination.local].ty != tcx.types.u16
        || tcx.item_name(take_callee).as_str() != "f28035_take_peripherals"
    {
        return None;
    }

    let TerminatorKind::SwitchInt {
        discr: take_discr,
        targets: take_targets,
    } = &take_guard.terminator().kind
    else {
        return None;
    };
    if operand_local(take_discr) != Some(take_destination.local.as_usize())
        || take_targets.otherwise() != blocks[3].0
    {
        return None;
    }
    is_expect_or_panic_block(
        tcx,
        body,
        blocks[take_targets.target_for_value(0).index()].1,
    )?;

    let mut steps: Vec<GpioMuxStep> = Vec::new();
    let mut set_mux_name: Option<String> = None;
    let mut cur = take_targets.otherwise();
    loop {
        let block = blocks[cur.index()].1;
        if matches!(block.terminator().kind, TerminatorKind::Return) {
            break;
        }
        let TerminatorKind::Call {
            func,
            args,
            destination,
            target: Some(next),
            ..
        } = &block.terminator().kind
        else {
            return None;
        };
        let callee = direct_callee(tcx, body, func)?;
        let callee_name = tcx.item_name(callee).as_str().to_owned();
        if callee_name != "f28035_gpio_set_mux" {
            return None;
        }
        let pin = constant_u16(&args.first()?.node)?;
        let function = constant_u16(&args.get(1)?.node)?;
        if args.len() != 2 || pin > 44 || function > 3 {
            return None;
        }
        if !destination.projection.is_empty()
            || body.local_decls[destination.local].ty != tcx.types.u16
        {
            return None;
        }
        if let Some(existing) = &set_mux_name {
            if existing != &callee_name {
                return None;
            }
        } else {
            set_mux_name = Some(callee_name.clone());
        }
        let guard = blocks[next.index()].1;
        let TerminatorKind::SwitchInt {
            discr: guard_discr,
            targets: guard_targets,
        } = &guard.terminator().kind
        else {
            return None;
        };
        if operand_local(guard_discr) != Some(destination.local.as_usize()) {
            return None;
        }
        is_expect_or_panic_block(
            tcx,
            body,
            blocks[guard_targets.target_for_value(0).index()].1,
        )?;
        steps.push(GpioMuxStep::SetMux { pin, function });
        cur = guard_targets.otherwise();
    }
    if steps.is_empty() {
        return None;
    }

    Some(MirOperation::GpioMux {
        system_init: tcx.item_name(init_callee).as_str().to_owned(),
        take_peripherals: tcx.item_name(take_callee).as_str().to_owned(),
        set_mux: set_mux_name.expect("validated at least one set_mux call"),
        steps,
    })
}

fn classify_gpio_output_readback<'tcx>(
    tcx: TyCtxt<'tcx>,
    body: &Body<'tcx>,
) -> Option<MirOperation> {
    if body.arg_count != 0 || body.local_decls.iter().next()?.ty != tcx.types.unit {
        return None;
    }

    let mut saw_system_init = false;
    let mut saw_take_peripherals = false;
    let mut output_pin = None;
    let mut writes = Vec::new();
    let mut reads = Vec::new();
    for block in body.basic_blocks.iter() {
        let TerminatorKind::Call { func, args, .. } = &block.terminator().kind else {
            continue;
        };
        let callee = direct_callee(tcx, body, func)?;
        match tcx.item_name(callee).as_str() {
            "system_init" | "f28035_system_init" => {
                if !args.is_empty() {
                    return None;
                }
                saw_system_init = true;
            }
            "take" | "f28035_take_peripherals" => {
                if !args.is_empty() {
                    return None;
                }
                saw_take_peripherals = true;
            }
            "f28035_gpio_make_output" => {
                let pin = constant_u16(&args.first()?.node)?;
                if args.len() != 1
                    || pin > 44
                    || !(pin < 16 || pin >= 32)
                    || output_pin.replace(pin).is_some()
                {
                    return None;
                }
            }
            "f28035_gpio_write" => {
                if args.len() != 2 {
                    return None;
                }
                let pin = constant_u16(&args[0].node)?;
                let value = constant_u16(&args[1].node)?;
                if value > 1 {
                    return None;
                }
                if output_pin.is_some_and(|configured| configured != pin) {
                    return None;
                }
                writes.push(value);
            }
            "f28035_gpio_read" => {
                let pin = constant_u16(&args.first()?.node)?;
                if args.len() != 1 {
                    return None;
                }
                if output_pin.is_some_and(|configured| configured != pin) {
                    return None;
                }
                reads.push(pin);
            }
        _ => {}
        }
    }

    let pin = output_pin.filter(|_| saw_system_init && saw_take_peripherals)?;
    if writes.len() != 3
        || writes.iter().filter(|value| **value == 1).count() != 2
        || writes.iter().filter(|value| **value == 0).count() != 1
        || reads.len() != 3
        || reads.iter().any(|read| *read != pin)
    {
        return None;
    }

    Some(MirOperation::GpioOutputReadback {
        system_init: "f28035_system_init".to_owned(),
        take_peripherals: "f28035_take_peripherals".to_owned(),
        pin,
        expected: vec![1, 0, 1],
    })
}

fn classify_inlined_safe_control_loop<'tcx>(
    tcx: TyCtxt<'tcx>,
    body: &Body<'tcx>,
) -> Option<MirOperation> {
    if body.arg_count != 0 || !body.local_decls.iter().next()?.ty.is_never() {
        return None;
    }
    let blocks = body.basic_blocks.iter_enumerated().collect::<Vec<_>>();
    let [
        (_bb0, init),
        (bb1, sample),
        (bb2, configure),
        (bb3, guard),
        (bb4, rejected),
        (bb5, write),
    ] = blocks.as_slice()
    else {
        return None;
    };
    if [init, sample, configure, guard, rejected]
        .iter()
        .any(|block| !block.statements.is_empty())
        || write.statements.len() != 2
    {
        return None;
    }

    let TerminatorKind::Call {
        func: init_func,
        args: init_args,
        target: Some(init_target),
        ..
    } = &init.terminator().kind
    else {
        return None;
    };
    let init_callee = direct_callee(tcx, body, init_func)?;
    if !init_args.is_empty()
        || *init_target != *bb2
        || tcx.item_name(init_callee).as_str() != "f28035_system_init"
    {
        return None;
    }

    let TerminatorKind::Call {
        func: configure_func,
        args: configure_args,
        destination: configure_destination,
        target: Some(configure_target),
        ..
    } = &configure.terminator().kind
    else {
        return None;
    };
    let configure_callee = direct_callee(tcx, body, configure_func)?;
    let pin = constant_u16(&configure_args.first()?.node)?;
    if configure_args.len() != 1
        || pin > 44
        || *configure_target != *bb3
        || !configure_destination.projection.is_empty()
        || body.local_decls[configure_destination.local].ty != tcx.types.u16
        || tcx.item_name(configure_callee).as_str() != "f28035_gpio_make_output"
    {
        return None;
    }

    let TerminatorKind::SwitchInt { discr, targets } = &guard.terminator().kind else {
        return None;
    };
    if operand_local(discr) != Some(configure_destination.local.as_usize())
        || targets.target_for_value(0) != *bb4
        || targets.otherwise() != *bb1
    {
        return None;
    }
    let TerminatorKind::Call {
        func: rejected_func,
        target: None,
        ..
    } = &rejected.terminator().kind
    else {
        return None;
    };
    let rejected_callee = direct_callee(tcx, body, rejected_func)?;
    if !tcx
        .def_path_str(rejected_callee)
        .ends_with("::panicking::panic")
    {
        return None;
    }

    let TerminatorKind::Call {
        func: sample_func,
        args: sample_args,
        destination: sample_destination,
        target: Some(sample_target),
        ..
    } = &sample.terminator().kind
    else {
        return None;
    };
    let sample_callee = direct_callee(tcx, body, sample_func)?;
    let result_index = constant_u16(&sample_args.first()?.node)?;
    if sample_args.len() != 1
        || result_index > 15
        || *sample_target != *bb5
        || !sample_destination.projection.is_empty()
        || body.local_decls[sample_destination.local].ty != tcx.types.u16
        || tcx.item_name(sample_callee).as_str() != "f28035_adc_result"
    {
        return None;
    }

    let (condition_local, operation, left, right) = binary_assignment(&write.statements[0])?;
    let threshold = constant_u16(right)?;
    if operation != BinOp::Ge
        || operand_local(left) != Some(sample_destination.local.as_usize())
        || body.local_decls[rustc_middle::mir::Local::from_usize(condition_local)].ty
            != tcx.types.bool
    {
        return None;
    }
    let StatementKind::Assign(cast_assignment) = &write.statements[1].kind else {
        return None;
    };
    let (cast_destination, Rvalue::Cast(CastKind::IntToInt, cast_operand, cast_ty)) =
        cast_assignment.as_ref()
    else {
        return None;
    };
    if operand_local(cast_operand) != Some(condition_local)
        || *cast_ty != tcx.types.u16
        || !cast_destination.projection.is_empty()
    {
        return None;
    }

    let TerminatorKind::Call {
        func: write_func,
        args: write_args,
        target: Some(write_target),
        ..
    } = &write.terminator().kind
    else {
        return None;
    };
    let write_callee = direct_callee(tcx, body, write_func)?;
    if write_args.len() != 2
        || constant_u16(&write_args[0].node) != Some(pin)
        || operand_local(&write_args[1].node) != Some(cast_destination.local.as_usize())
        || *write_target != *bb1
        || tcx.item_name(write_callee).as_str() != "f28035_gpio_write"
    {
        return None;
    }

    Some(MirOperation::ControlLoop {
        system_init: tcx.item_name(init_callee).as_str().to_owned(),
        adc_result: tcx.item_name(sample_callee).as_str().to_owned(),
        pin,
        result_index,
        threshold,
    })
}

fn classify_direct_control_loop<'tcx>(
    tcx: TyCtxt<'tcx>,
    body: &Body<'tcx>,
) -> Option<MirOperation> {
    if body.arg_count != 0 || !body.local_decls.iter().next()?.ty.is_never() {
        return None;
    }
    let blocks = body.basic_blocks.iter_enumerated().collect::<Vec<_>>();
    if blocks.len() != 5 {
        return None;
    }
    let [
        (_bb0, init),
        (bb1, configure),
        (bb2, sample),
        (bb3, convert),
        (bb4, write),
    ] = blocks.as_slice()
    else {
        return None;
    };
    if [init, configure, sample, write]
        .iter()
        .any(|block| !block.statements.is_empty())
        || convert.statements.len() != 1
    {
        return None;
    }

    let TerminatorKind::Call {
        func: init_func,
        args: init_args,
        target: Some(init_target),
        ..
    } = &init.terminator().kind
    else {
        return None;
    };
    let init_callee = direct_callee(tcx, body, init_func)?;
    if !init_args.is_empty()
        || *init_target != *bb1
        || tcx.item_name(init_callee).as_str() != "f28035_system_init"
    {
        return None;
    }

    let TerminatorKind::Call {
        func: configure_func,
        args: configure_args,
        destination: configure_destination,
        target: Some(configure_target),
        ..
    } = &configure.terminator().kind
    else {
        return None;
    };
    let configure_callee = direct_callee(tcx, body, configure_func)?;
    let pin = constant_u16(&configure_args.first()?.node)?;
    if configure_args.len() != 1
        || pin > 44
        || *configure_target != *bb2
        || !configure_destination.projection.is_empty()
        || body.local_decls[configure_destination.local].ty != tcx.types.u16
        || tcx.item_name(configure_callee).as_str() != "f28035_gpio_make_output"
    {
        return None;
    }

    let TerminatorKind::Call {
        func: sample_func,
        args: sample_args,
        destination: sample_destination,
        target: Some(sample_target),
        ..
    } = &sample.terminator().kind
    else {
        return None;
    };
    let sample_callee = direct_callee(tcx, body, sample_func)?;
    let result_index = constant_u16(&sample_args.first()?.node)?;
    if sample_args.len() != 1
        || result_index > 15
        || *sample_target != *bb3
        || !sample_destination.projection.is_empty()
        || body.local_decls[sample_destination.local].ty != tcx.types.u16
        || tcx.item_name(sample_callee).as_str() != "f28035_adc_result"
    {
        return None;
    }

    let (condition_local, operation, left, right) = binary_assignment(convert.statements.first()?)?;
    let threshold = constant_u16(right)?;
    if operation != BinOp::Ge
        || operand_local(left) != Some(sample_destination.local.as_usize())
        || body.local_decls[rustc_middle::mir::Local::from_usize(condition_local)].ty
            != tcx.types.bool
    {
        return None;
    }
    let TerminatorKind::Call {
        func: convert_func,
        args: convert_args,
        destination: converted_destination,
        target: Some(convert_target),
        ..
    } = &convert.terminator().kind
    else {
        return None;
    };
    let convert_callee = direct_callee(tcx, body, convert_func)?;
    if convert_args.len() != 1
        || operand_local(&convert_args[0].node) != Some(condition_local)
        || *convert_target != *bb4
        || !converted_destination.projection.is_empty()
        || body.local_decls[converted_destination.local].ty != tcx.types.u16
        || !tcx
            .def_path_str(convert_callee)
            .ends_with("::convert::From::from")
    {
        return None;
    }

    let TerminatorKind::Call {
        func: write_func,
        args: write_args,
        target: Some(write_target),
        ..
    } = &write.terminator().kind
    else {
        return None;
    };
    let write_callee = direct_callee(tcx, body, write_func)?;
    if write_args.len() != 2
        || constant_u16(&write_args[0].node) != Some(pin)
        || operand_local(&write_args[1].node) != Some(converted_destination.local.as_usize())
        || *write_target != *bb2
        || tcx.item_name(write_callee).as_str() != "f28035_gpio_write"
    {
        return None;
    }

    Some(MirOperation::ControlLoop {
        system_init: tcx.item_name(init_callee).as_str().to_owned(),
        adc_result: tcx.item_name(sample_callee).as_str().to_owned(),
        pin,
        result_index,
        threshold,
    })
}

fn classify_control_loop<'tcx>(tcx: TyCtxt<'tcx>, body: &Body<'tcx>) -> Option<MirOperation> {
    classify_inlined_safe_control_loop(tcx, body)
        .or_else(|| classify_direct_control_loop(tcx, body))
}

fn binary_assignment<'a, 'tcx>(
    statement: &'a rustc_middle::mir::Statement<'tcx>,
) -> Option<(usize, BinOp, &'a Operand<'tcx>, &'a Operand<'tcx>)> {
    let StatementKind::Assign(assignment) = &statement.kind else {
        return None;
    };
    let (destination, Rvalue::BinaryOp(operation, operands)) = assignment.as_ref() else {
        return None;
    };
    if !destination.projection.is_empty() {
        return None;
    }
    Some((
        destination.local.as_usize(),
        *operation,
        &operands.0,
        &operands.1,
    ))
}

/// Parse a `then`/`else` block of the 5-block if/else pattern:
///   _tmp = CheckedBinaryOp(Add|Sub, _1, _2); assert -> ret
///   ret: _0 = _tmp.0; return
/// Returns Some(true) for Add, Some(false) for Sub.
fn parse_checked_arithmetic_block(body: &Body<'_>, bb: BasicBlock) -> Option<BranchArith> {
    let mut block = &body.basic_blocks[bb];

    /* Skip a leading div-by-zero or overflow assert block:
     *   _tmp = Eq(_2, 0); assert -> next  (for Div)
     *   _tmp = OpWithOverflow(_1,_2); assert -> next  (for Add/Sub/Mul) */
    if block.statements.len() == 1
        && let TerminatorKind::Assert { target, .. } = &block.terminator().kind
    {
        /* Overflow form: statement is _tmp = OpWithOverflow(_1,_2), then assert -> ret */
        let StatementKind::Assign(assign) = &block.statements[0].kind else {
            return None;
        };
        if let (_, Rvalue::BinaryOp(op, operands)) = assign.as_ref()
            && operand_local(&operands.0) == Some(1)
            && operand_local(&operands.1) == Some(2)
        {
            let ret_block = &body.basic_blocks[*target];
            if ret_block.statements.len() == 1 {
                let StatementKind::Assign(ret_assign) = &ret_block.statements[0].kind else {
                    return None;
                };
                let (ret_dest, _) = ret_assign.as_ref();
                if ret_dest.local.as_usize() == 0 && ret_dest.projection.is_empty() {
                    return branch_arith_from_op(*op);
                }
            }
        }
        /* Div-by-zero form: statement is _tmp = Eq(_2, 0), then assert -> next_op */
        block = &body.basic_blocks[*target];
    }

    /* Direct form: _0 = Op(_1, _2); return */
    if block.statements.len() == 1
        && let TerminatorKind::Return = block.terminator().kind
    {
        let StatementKind::Assign(assign) = &block.statements[0].kind else {
            return None;
        };
        let (dest, Rvalue::BinaryOp(op, operands)) = assign.as_ref() else {
            return None;
        };
        if dest.local.as_usize() != 0
            || !dest.projection.is_empty()
            || operand_local(&operands.0) != Some(1)
            || operand_local(&operands.1) != Some(2)
        {
            return None;
        }
        return branch_arith_from_op(*op);
    }

    None
}

fn branch_arith_from_op(op: BinOp) -> Option<BranchArith> {
    match op {
        BinOp::AddWithOverflow | BinOp::Add => Some(BranchArith::Add),
        BinOp::SubWithOverflow | BinOp::Sub => Some(BranchArith::Sub),
        BinOp::MulWithOverflow | BinOp::Mul => Some(BranchArith::Mul),
        BinOp::Div => Some(BranchArith::Div),
        BinOp::Rem => Some(BranchArith::Rem),
        BinOp::Shl => Some(BranchArith::Shl),
        BinOp::Shr => Some(BranchArith::Shr),
        BinOp::BitAnd => Some(BranchArith::And),
        BinOp::BitOr => Some(BranchArith::Or),
        BinOp::BitXor => Some(BranchArith::Xor),
        _ => None,
    }
}

fn classify_byte_function(body: &Body<'_>) -> Option<MirOperation> {
    let blocks = body.basic_blocks.iter().collect::<Vec<_>>();
    if body.arg_count == 1 && blocks.len() == 1 && blocks[0].statements.len() == 1 {
        let (destination, operation, left, right) = binary_assignment(&blocks[0].statements[0])?;
        if destination == 0 && operand_local(left) == Some(1) {
            if operation == BinOp::BitAnd && constant_u16(right) == Some(0x00ff) {
                return Some(MirOperation::UnpackLowByte);
            }
        }
    }
    if body.arg_count == 1 && blocks.len() == 2 {
        let statement = blocks[1].statements.first()?;
        let (destination, operation, left, right) = binary_assignment(statement)?;
        if destination == 0
            && operation == BinOp::Shr
            && operand_local(left) == Some(1)
            && constant_u16(right) == Some(8)
            && matches!(blocks[0].terminator().kind, TerminatorKind::Assert { .. })
        {
            return Some(MirOperation::UnpackHighByte);
        }
    }
    if body.arg_count == 2 && blocks.len() == 1 && blocks[0].statements.len() == 3 {
        let first = binary_assignment(&blocks[0].statements[0])?;
        let second = binary_assignment(&blocks[0].statements[1])?;
        let third = binary_assignment(&blocks[0].statements[2])?;
        if first.1 == BinOp::BitAnd
            && operand_local(first.2) == Some(1)
            && constant_u16(first.3) == Some(0xff00)
            && second.1 == BinOp::BitAnd
            && operand_local(second.2) == Some(2)
            && constant_u16(second.3) == Some(0x00ff)
            && third.0 == 0
            && third.1 == BinOp::BitOr
            && operand_local(third.2) == Some(first.0)
            && operand_local(third.3) == Some(second.0)
        {
            return Some(MirOperation::WriteLowByte);
        }
    }
    if body.arg_count == 2
        && blocks.len() == 2
        && blocks[0].statements.len() == 3
        && blocks[1].statements.len() == 2
    {
        let word_mask = binary_assignment(&blocks[0].statements[0])?;
        let value_mask = binary_assignment(&blocks[0].statements[1])?;
        let shift = binary_assignment(&blocks[1].statements[0])?;
        let combine = binary_assignment(&blocks[1].statements[1])?;
        if word_mask.1 == BinOp::BitAnd
            && operand_local(word_mask.2) == Some(1)
            && constant_u16(word_mask.3) == Some(0x00ff)
            && value_mask.1 == BinOp::BitAnd
            && operand_local(value_mask.2) == Some(2)
            && constant_u16(value_mask.3) == Some(0x00ff)
            && shift.1 == BinOp::Shl
            && operand_local(shift.2) == Some(value_mask.0)
            && constant_u16(shift.3) == Some(8)
            && combine.0 == 0
            && combine.1 == BinOp::BitOr
            && operand_local(combine.2) == Some(word_mask.0)
            && operand_local(combine.3) == Some(shift.0)
            && matches!(blocks[0].terminator().kind, TerminatorKind::Assert { .. })
        {
            return Some(MirOperation::WriteHighByte);
        }
    }
    None
}

/// Extracts the raw u16 out of a `const TiWordAddress(addr)` operand, or a
/// bare `const u16` operand.  rustc constant-propagates the newtype away in
/// optimized MIR, so the underlying scalar is directly readable.
fn tiword_const_u16(operand: &Operand<'_>) -> Option<u16> {
    let Operand::Constant(constant) = operand else {
        return None;
    };
    constant.const_.try_to_scalar_int().map(|s| s.to_u16())
}

// Lower a straight-line sequence of fixed physical-word MMIO operations.
// Every MIR block and data dependency is consumed; unknown shapes fail closed.
fn classify_bare_word_mmio<'tcx>(tcx: TyCtxt<'tcx>, body: &Body<'tcx>) -> Option<MirOperation> {
    use rustc_middle::mir::TerminatorKind;

    if body.arg_count > 1 || body.local_decls.iter().next()?.ty != tcx.types.unit {
        return None;
    }
    let mut steps = Vec::new();
    let mut index = 0;
    loop {
        let block = &body.basic_blocks[rustc_middle::mir::BasicBlock::from_usize(index)];
        if matches!(block.terminator().kind, TerminatorKind::Return) {
            return (!steps.is_empty() && block.statements.is_empty()
                && index + 1 == body.basic_blocks.len())
                .then_some(MirOperation::BareWordMmio(steps));
        }
        if !block.statements.is_empty() { return None; }
        let TerminatorKind::Call { func, args, destination, target: Some(next), .. } =
            &block.terminator().kind else { return None; };
        let callee = direct_callee(tcx, body, func)?;
        let path = tcx.def_path_str(callee);
        let address = tiword_const_u16(&args.first()?.node)?;
        if next.as_usize() != index + 1 { return None; }
        if path.ends_with("WordAddress::write") && args.len() == 2 {
            let value = constant_u16(&args[1].node)?;
            steps.push(WordMmioStep::Write { addr: address, value });
            index += 1;
            continue;
        }
        if !path.ends_with("WordAddress::read") || args.len() != 1 { return None; }
        let update = &body.basic_blocks[*next];
        if update.statements.len() != 1 { return None; }
        let (result, op, lhs, rhs) = binary_assignment(&update.statements[0])?;
        if !matches!(op, BinOp::BitAnd | BinOp::BitOr)
            || operand_local(lhs) != Some(destination.local.as_usize()) {
            return None;
        }
        let mask = constant_u16(rhs)?;
        let TerminatorKind::Call { func: write_func, args: write_args,
            target: Some(after), .. } = &update.terminator().kind else { return None; };
        let write_callee = direct_callee(tcx, body, write_func)?;
        if !tcx.def_path_str(write_callee).ends_with("WordAddress::write")
            || write_args.len() != 2
            || tiword_const_u16(&write_args[0].node) != Some(address)
            || operand_local(&write_args[1].node) != Some(result)
            || after.as_usize() != index + 2 {
            return None;
        }
        steps.push(WordMmioStep::Modify { addr: address, op, mask });
        index += 2;
    }
}

// A single 16-bit compare_exchange(0, 1) on the word addressed by `self`.
// This pilot runs with INTM set from startup; it is not a general atomic ABI.
fn classify_once_acquire<'tcx>(tcx: TyCtxt<'tcx>, body: &Body<'tcx>) -> Option<MirOperation> {
    use rustc_middle::mir::TerminatorKind;

    if body.arg_count != 1 || body.basic_blocks.len() != 2
        || body.local_decls.iter().next()?.ty != tcx.types.u16 {
        return None;
    }
    let entry = &body.basic_blocks[BasicBlock::from_usize(0)];
    let done = &body.basic_blocks[BasicBlock::from_usize(1)];
    if entry.statements.len() != 2 || done.statements.len() != 3
        || !matches!(done.terminator().kind, TerminatorKind::Return) {
        return None;
    }
    let raw_pointer = format!("{:?}", entry.statements[0].kind);
    if !raw_pointer.contains("&raw const (((*_1).0: core::sync::atomic::Atomic<u16>)") {
        return None;
    }
    let StatementKind::Assign(pointer_cast) = &entry.statements[1].kind else { return None; };
    let (pointer_place, Rvalue::Cast(CastKind::PtrToPtr, pointer_operand, _)) =
        pointer_cast.as_ref() else { return None; };
    if pointer_place.local.as_usize() != 4 || operand_local(pointer_operand) != Some(5) {
        return None;
    }
    let TerminatorKind::Call { func, args, destination, target: Some(next), .. } =
        &entry.terminator().kind else { return None; };
    let callee = direct_callee(tcx, body, func)?;
    if !tcx.def_path_str(callee).ends_with("::atomic_compare_exchange")
        || args.len() != 5 || destination.local.as_usize() != 3
        || next.as_usize() != 1 || operand_local(&args[0].node) != Some(4)
        || constant_u16(&args[1].node) != Some(0)
        || constant_u16(&args[2].node) != Some(1)
        || !format!("{:?}", args[3].node).contains("Ordering::SeqCst")
        || !format!("{:?}", args[4].node).contains("Ordering::SeqCst") {
        return None;
    }
    let StatementKind::Assign(discriminant) = &done.statements[0].kind else { return None; };
    let (discriminant_place, Rvalue::Discriminant(result_place)) = discriminant.as_ref() else {
        return None;
    };
    if discriminant_place.local.as_usize() != 6 || result_place.local.as_usize() != 3 {
        return None;
    }
    let (comparison, BinOp::Eq, left, right) = binary_assignment(&done.statements[1])? else {
        return None;
    };
    if comparison != 2 || operand_local(left) != Some(6)
        || !format!("{right:?}").contains("0_isize") {
        return None;
    }
    let StatementKind::Assign(return_cast) = &done.statements[2].kind else { return None; };
    let (return_place, Rvalue::Cast(CastKind::IntToInt, value, result_ty)) =
        return_cast.as_ref() else { return None; };
    if return_place.local.as_usize() != 0 || operand_local(value) != Some(2)
        || *result_ty != tcx.types.u16 {
        return None;
    }
    Some(MirOperation::OnceAcquire)
}

fn classify_ownership_application<'tcx>(
    tcx: TyCtxt<'tcx>,
    body: &Body<'tcx>,
) -> Option<MirOperation> {
    use rustc_middle::mir::TerminatorKind;

    if body.arg_count != 0 || body.basic_blocks.len() != 14
        || body.local_decls.iter().next()?.ty != tcx.types.u16 {
        return None;
    }
    let blocks = &body.basic_blocks;
    let calls = [(0, 5, 2), (3, 8, 5), (7, 9, 8), (9, 10, 11)];
    let mut root_operand = None;
    for (block_index, destination_local, target_index) in calls {
        let block = &blocks[BasicBlock::from_usize(block_index)];
        let TerminatorKind::Call { func, args, destination, target: Some(target), .. } =
            &block.terminator().kind else { return None; };
        let callee = direct_callee(tcx, body, func)?;
        if tcx.item_name(callee).as_str() != "rust_once_acquire"
            || args.len() != 1 || destination.local.as_usize() != destination_local
            || target.as_usize() != target_index {
            return None;
        }
        if block_index <= 3 {
            let operand = format!("{:?}", args[0].node);
            if !operand.contains("&Once") || !operand.contains("alloc") {
                return None;
            }
            if let Some(first) = &root_operand {
                if first != &operand { return None; }
            } else {
                root_operand = Some(operand);
            }
        } else if operand_local(&args[0].node) != Some(11) {
            return None;
        }
    }
    if !blocks[BasicBlock::from_usize(0)].statements.is_empty()
        || blocks[BasicBlock::from_usize(2)].statements.len() != 2
        || blocks[BasicBlock::from_usize(3)].statements.len() != 2
        || !format!("{:?}", blocks[BasicBlock::from_usize(2)].statements[0].kind)
            .contains("Gpio::<'_> { pin34: const {alloc")
        || !format!("{:?}", blocks[BasicBlock::from_usize(3)].statements[1].kind)
            .contains("_11 = move")
        || !blocks[BasicBlock::from_usize(5)].statements.is_empty()
        || !blocks[BasicBlock::from_usize(7)].statements.is_empty()
        || !blocks[BasicBlock::from_usize(8)].statements.is_empty()
        || !blocks[BasicBlock::from_usize(9)].statements.is_empty()
        || !blocks[BasicBlock::from_usize(11)].statements.is_empty() {
        return None;
    }
    for (block_index, discr_local, zero_target, other_target) in
        [(2, 5, 4, 3), (5, 8, 7, 6), (8, 9, 10, 9), (11, 10, 13, 12)] {
        let TerminatorKind::SwitchInt { discr, targets } =
            &blocks[BasicBlock::from_usize(block_index)].terminator().kind else { return None; };
        if operand_local(discr) != Some(discr_local)
            || targets.target_for_value(0).as_usize() != zero_target
            || targets.otherwise().as_usize() != other_target {
            return None;
        }
    }
    for (block_index, expected) in [(4, 0), (6, 0), (10, 0), (12, 0), (1, 1)] {
        let block = &blocks[BasicBlock::from_usize(block_index)];
        if block.statements.len() != 1 || !matches!(block.terminator().kind, TerminatorKind::Return)
            || !format!("{:?}", block.statements[0].kind)
                .contains(&format!("_0 = const {expected}_u16")) {
            return None;
        }
    }
    let gpio_call = &blocks[BasicBlock::from_usize(13)];
    let TerminatorKind::Call { func, args, target: Some(target), .. } =
        &gpio_call.terminator().kind else { return None; };
    if gpio_call.statements.len() != 1
        || !format!("{:?}", gpio_call.statements[0].kind).contains("_4 = &mut _2")
        || tcx.item_name(direct_callee(tcx, body, func)?).as_str() != "rust_gpio34_set_low"
        || args.len() != 1 || operand_local(&args[0].node) != Some(4)
        || target.as_usize() != 1 {
        return None;
    }
    Some(MirOperation::OwnershipApplication)
}

fn classify_safe_hal_bare_gpio34<'tcx>(tcx: TyCtxt<'tcx>, body: &Body<'tcx>) -> Option<MirOperation> {
    use rustc_middle::mir::TerminatorKind;

    if body.arg_count != 0 || body.local_decls.iter().next()?.ty != tcx.types.unit
        || body.basic_blocks.len() != 7 { return None; }
    let blocks = &body.basic_blocks;
    let entry = &blocks[BasicBlock::from_usize(0)];
    let TerminatorKind::Call { func: take_func, args: take_args, destination: take_dest,
        target: Some(take_guard), .. } = &entry.terminator().kind else { return None; };
    let take_callee = direct_callee(tcx, body, take_func)?;
    if !entry.statements.is_empty() || !take_args.is_empty()
        || tcx.item_name(take_callee).as_str() != "f28035_take_peripherals"
        || take_guard.as_usize() != 3 { return None; }

    let guard = &blocks[*take_guard];
    let TerminatorKind::SwitchInt { discr, targets } = &guard.terminator().kind else { return None; };
    if guard.statements.len() != 3
        || !format!("{:?}", guard.statements[0].kind).contains("[const 0_u16; 3]")
        || !format!("{:?}", guard.statements[1].kind).contains("Gpio { used: move")
        || !format!("{:?}", guard.statements[2].kind).contains("Peripherals { gpio: move")
        || targets.target_for_value(0).as_usize() != 5
        || targets.otherwise().as_usize() != 4
        || operand_local(discr) != Some(take_dest.local.as_usize()) { return None; }
    let failure = &blocks[BasicBlock::from_usize(5)];
    let TerminatorKind::Call { func: failure_func, .. } = &failure.terminator().kind else { return None; };
    if !failure.statements.is_empty()
        || tcx.item_name(direct_callee(tcx, body, failure_func)?).as_str() != "expect_failed" {
        return None;
    }
    let output = &blocks[BasicBlock::from_usize(4)];
    let TerminatorKind::Call { func: output_func, target: Some(expect_block), .. } =
        &output.terminator().kind else { return None; };
    if output.statements.len() != 3
        || tcx.item_name(direct_callee(tcx, body, output_func)?).as_str() != "output"
        || expect_block.as_usize() != 1 { return None; }
    let expect = &blocks[*expect_block];
    let TerminatorKind::Call { func: expect_func, target: Some(write_block), .. } =
        &expect.terminator().kind else { return None; };
    if !expect.statements.is_empty()
        || tcx.item_name(direct_callee(tcx, body, expect_func)?).as_str() != "expect"
        || write_block.as_usize() != 2 { return None; }
    let write = &blocks[*write_block];
    let TerminatorKind::Call { func: write_func, args: write_args,
        target: Some(done), .. } = &write.terminator().kind else { return None; };
    if !write.statements.is_empty() || write_args.len() != 2
        || tcx.item_name(direct_callee(tcx, body, write_func)?).as_str() != "f28035_gpio_write"
        || constant_u16(&write_args[0].node) != Some(34)
        || constant_u16(&write_args[1].node) != Some(0)
        || done.as_usize() != 6
        || !matches!(blocks[*done].terminator().kind, TerminatorKind::Return)
        || !blocks[*done].statements.is_empty() { return None; }

    Some(MirOperation::BareWordMmio(vec![
        WordMmioStep::Modify { addr: 0x6f96, op: BinOp::BitAnd, mask: 0xffcf },
        WordMmioStep::Modify { addr: 0x6f9a, op: BinOp::BitOr, mask: 4 },
        WordMmioStep::Write { addr: 0x6fcc, value: 4 },
    ]))
}

/// Walks a straight-line MIR body whose blocks are chained by
/// `<B as MmioBus>::write_word(bus, const TiWordAddress(addr), val)` calls
/// and lowers each call to a direct C28x word store.
fn classify_mmio_write_sequence<'tcx>(
    tcx: TyCtxt<'tcx>,
    def_id: rustc_span::def_id::DefId,
    body: &Body<'tcx>,
) -> Option<MirOperation> {
    use rustc_middle::mir::{START_BLOCK, TerminatorKind};

    // Only lower PAC internal `apply`/helper functions this way.  The f28035_*
    // entry symbols are either inlined by the strict platform shape match or
    // provided by the C bridge; re-emitting them here would redefine them.
    if tcx.item_name(def_id).as_str().starts_with("f28035_") {
        return None;
    }

    let mut steps = Vec::new();
    let mut block = START_BLOCK;
    loop {
        let data = &body.basic_blocks[block];
        // Every block on the chain must end in a single write_word call.
        let TerminatorKind::Call {
            func,
            args,
            target: Some(target),
            ..
        } = &data.terminator().kind
        else {
            return None;
        };
        let callee = direct_callee(tcx, body, func)?;
        let path = tcx.def_path_str(callee);

        // Three terminator shapes are recognized:
        //   1. <B as MmioBus>::write_word(bus, const TiWordAddress(addr), val)
        //   2. pac::TiWordAddress::modify(const TiWordAddress(addr), bus, mask, bits)
        if path.ends_with("MmioBus::write_word") {
            // args: (bus, address, value)
            if args.len() != 3 {
                return None;
            }
            let addr = tiword_const_u16(&args[1].node)?;
            let step = if let Some(val) = constant_u16(&args[2].node) {
                MmioWrite::Imm { addr, val }
            } else if operand_local(&args[2].node).is_some() {
                MmioWrite::Acc { addr }
            } else {
                return None;
            };
            steps.push(step);
        } else if path.ends_with("TiWordAddress::modify") {
            // args: (address, bus, mask, bits)
            if args.len() != 4 {
                return None;
            }
            let addr = tiword_const_u16(&args[0].node)?;
            let mask = constant_u16(&args[2].node)?;
            let bits = constant_u16(&args[3].node)?;
            steps.push(MmioWrite::Modify { addr, mask, bits });
        } else if path.ends_with("Register32::write_u32") {
            // args: (Register32{address}, bus, value: u32)
            if args.len() != 3 {
                return None;
            }
            let addr = tiword_const_u16(&args[0].node)?;
            // The u32 value is always the function's `self.0` (copied into a
            // local by rustc), so it arrives in ACC on entry.
            steps.push(MmioWrite::WriteU32 { addr });
        } else if path.ends_with("MmioBus::read_word") {
            // args: (bus, address)
            // The address is already loaded into XAR4 by the caller
            // (runtime-computed, e.g. index*2 + base).  Emit a single
            // indirect load; result lands in AL.
            if args.len() != 2 {
                return None;
            }
            steps.push(MmioWrite::ReadIndirect);
        } else {
            return None;
        }
        block = *target;
        // Stop when we reach a return block.
        if matches!(
            body.basic_blocks[block].terminator().kind,
            TerminatorKind::Return
        ) {
            break;
        }
    }
    if steps.is_empty() {
        return None;
    }
    Some(MirOperation::MmioWriteSequence(steps))
}

fn classify_safe_hal_adc_sample_basic<'tcx>(
    tcx: TyCtxt<'tcx>,
    body: &Body<'tcx>,
) -> Option<MirOperation> {
    let return_ty = body.local_decls.iter().next()?.ty;
    if body.arg_count != 0 || !(return_ty == tcx.types.u16 || return_ty == tcx.types.unit) {
        return None;
    }

    let mut saw_system_init = false;
    let mut saw_take_peripherals = false;
    let mut sample_channel = None;
    for block in body.basic_blocks.iter() {
        let TerminatorKind::Call { func, args, .. } = &block.terminator().kind else {
            continue;
        };
        let callee = direct_callee(tcx, body, func)?;
        match tcx.item_name(callee).as_str() {
            "system_init" | "f28035_system_init" => {
                if !args.is_empty() {
                    return None;
                }
                saw_system_init = true;
            }
            "take" | "f28035_take_peripherals" => {
                if !args.is_empty() {
                    return None;
                }
                saw_take_peripherals = true;
            }
            "f28035_adc_sample" => {
                let channel = constant_u16(&args.first()?.node)?;
                if args.len() != 1 || channel > 15 || sample_channel.replace(channel).is_some() {
                    return None;
                }
            }
            "sample" => {
                let consts = fn_def_const_u16s(tcx, body, func)
                    .or_else(|| fn_def_const_u16s_from_debug(tcx, body, func))?;
                let [channel] = consts.as_slice() else {
                    return None;
                };
                if *channel > 15 || sample_channel.replace(*channel).is_some() {
                    return None;
                }
            }
        _ => {}
        }
    }

    Some(MirOperation::AdcSampleBasic {
        system_init: "f28035_system_init".to_owned(),
        take_peripherals: "f28035_take_peripherals".to_owned(),
        channel: sample_channel.filter(|_| saw_system_init && saw_take_peripherals)?,
    })
}

fn classify_safe_hal_epwm_compare_basic<'tcx>(
    tcx: TyCtxt<'tcx>,
    body: &Body<'tcx>,
) -> Option<MirOperation> {
    if body.arg_count != 0 || body.local_decls.iter().next()?.ty != tcx.types.unit {
        return None;
    }

    let mut saw_system_init = false;
    let mut saw_take_peripherals = false;
    let mut period = None;
    let mut compare = None;
    for block in body.basic_blocks.iter() {
        let TerminatorKind::Call { func, args, .. } = &block.terminator().kind else {
            continue;
        };
        let callee = direct_callee(tcx, body, func)?;
        match tcx.item_name(callee).as_str() {
            "system_init" | "f28035_system_init" => {
                if !args.is_empty() {
                    return None;
                }
                saw_system_init = true;
            }
            "take" | "f28035_take_peripherals" => {
                if !args.is_empty() {
                    return None;
                }
                saw_take_peripherals = true;
            }
            "f28035_epwm1_configure" => {
                let configured_period = constant_u16(&args.first()?.node)?;
                if args.len() != 1
                    || configured_period == 0
                    || period.replace(configured_period).is_some()
                {
                    return None;
                }
            }
            "configure" => {
                let consts = fn_def_const_u16s(tcx, body, func)
                    .or_else(|| fn_def_const_u16s_from_debug(tcx, body, func))?;
                let [configured_period] = consts.as_slice() else {
                    return None;
                };
                if *configured_period == 0 || period.replace(*configured_period).is_some() {
                    return None;
                }
            }
            "f28035_epwm1_set_compare" => {
                let compare_ticks = constant_u16(&args.first()?.node)?;
                if args.len() != 1 || compare.replace(compare_ticks).is_some() {
                    return None;
                }
            }
            "set_compare" => {
                if args.len() != 2 {
                    return None;
                }
                let compare_ticks = constant_u16(&args[1].node)?;
                if compare.replace(compare_ticks).is_some() {
                    return None;
                }
                if period.is_none() {
                    let consts = fn_def_const_u16s(tcx, body, func)
                        .or_else(|| fn_def_const_u16s_from_debug(tcx, body, func))?;
                    if let [configured_period] = consts.as_slice() {
                        if *configured_period == 0 {
                            return None;
                        }
                        period = Some(*configured_period);
                    }
                }
            }
        _ => {}
        }
    }

    Some(MirOperation::EpwmCompareBasic {
        system_init: "f28035_system_init".to_owned(),
        take_peripherals: "f28035_take_peripherals".to_owned(),
        period: period.filter(|_| saw_system_init && saw_take_peripherals)?,
        compare: compare?,
    })
}

fn classify_safe_hal_timer0_periodic_basic<'tcx>(
    tcx: TyCtxt<'tcx>,
    body: &Body<'tcx>,
) -> Option<MirOperation> {
    if body.arg_count != 0 || body.local_decls.iter().next()?.ty != tcx.types.unit {
        return None;
    }

    let mut saw_system_init = false;
    let mut saw_take_peripherals = false;
    let mut period_ms = None;
    for block in body.basic_blocks.iter() {
        let TerminatorKind::Call { func, args, .. } = &block.terminator().kind else {
            continue;
        };
        let callee = direct_callee(tcx, body, func)?;
        match tcx.item_name(callee).as_str() {
            "system_init" | "f28035_system_init" => {
                if !args.is_empty() {
                    return None;
                }
                saw_system_init = true;
            }
            "take" | "f28035_take_peripherals" => {
                if !args.is_empty() {
                    return None;
                }
                saw_take_peripherals = true;
            }
            "f28035_timer0_start_periodic_ms" => {
                let configured_period_ms = constant_u16(&args.first()?.node)?;
                if args.len() != 1
                    || configured_period_ms == 0
                    || configured_period_ms > 1000
                    || period_ms.replace(configured_period_ms).is_some()
                {
                    return None;
                }
            }
            "start_periodic" => {
                let consts = fn_def_const_u16s(tcx, body, func)
                    .or_else(|| fn_def_const_u16s_from_debug(tcx, body, func))?;
                let [configured_period_ms] = consts.as_slice() else {
                    return None;
                };
                if *configured_period_ms == 0
                    || *configured_period_ms > 1000
                    || period_ms.replace(*configured_period_ms).is_some()
                {
                    return None;
                }
            }
        _ => {}
        }
    }

    Some(MirOperation::Timer0PeriodicBasic {
        system_init: "f28035_system_init".to_owned(),
        take_peripherals: "f28035_take_peripherals".to_owned(),
        period_ms: period_ms.filter(|_| saw_system_init && saw_take_peripherals)?,
        interrupt_pin: 30,
    })
}

fn user_operand<'tcx>(
    tcx: TyCtxt<'tcx>,
    body: &Body<'tcx>,
    operand: &Operand<'tcx>,
) -> Option<UserOperand> {
    let ty = operand.ty(body, tcx);
    if ty != tcx.types.u16 && ty != tcx.types.bool {
        return None;
    }
    if let Some(local) = operand_local(operand) {
        return Some(UserOperand::Local(local));
    }
    let Operand::Constant(constant) = operand else {
        return None;
    };
    let value = constant.const_.try_to_scalar_int()?.to_bits_unchecked() as u16;
    Some(UserOperand::Immediate(value))
}

fn classify_user_main_cfg<'tcx>(tcx: TyCtxt<'tcx>, body: &Body<'tcx>) -> Option<MirOperation> {
    let return_ty = body.local_decls.iter().next()?.ty;
    if body.arg_count != 0 || (return_ty != tcx.types.unit && return_ty != tcx.types.u16) {
        return None;
    }
    let mut slots = Vec::new();
    for (local, declaration) in body.local_decls.iter_enumerated() {
        let ty = declaration.ty;
        if ty == tcx.types.u16 || ty == tcx.types.bool {
            slots.push((local.as_usize(), (slots.len() + 1) as u16));
        } else if ty == tcx.types.f32 {
            // f32: 占 2 个字，分配 2 个槽
            slots.push((local.as_usize(), (slots.len() + 1) as u16));
            slots.push((local.as_usize(), (slots.len() + 1) as u16));
        } else if ty != tcx.types.unit && !matches!(ty.kind(), ty::Never) {
            return None;
        }
    }
    if slots.len() > 32 {
        return None;
    }

    let mut blocks = Vec::new();
    for (_, block) in body.basic_blocks.iter_enumerated() {
        let mut statements = Vec::new();
        for statement in &block.statements {
            let StatementKind::Assign(assignment) = &statement.kind else {
                return None;
            };
            let (place, rvalue) = assignment.as_ref();
            if !place.projection.is_empty()
                || !slots.iter().any(|(local, _)| *local == place.local.as_usize())
            {
                return None;
            }
            let destination = place.local.as_usize();
            let lowered = match rvalue {
                Rvalue::Use(value, _) => UserStatement::Assign {
                    destination,
                    value: user_operand(tcx, body, value)?,
                },
                Rvalue::Cast(CastKind::IntToInt, value, target)
                    if value.ty(body, tcx) == tcx.types.bool && *target == tcx.types.u16 =>
                {
                    UserStatement::Assign {
                        destination,
                        value: user_operand(tcx, body, value)?,
                    }
                }
                Rvalue::BinaryOp(operation, operands)
                    if matches!(
                        operation,
                        BinOp::Add | BinOp::Sub | BinOp::Mul | BinOp::BitAnd | BinOp::BitOr
                            | BinOp::BitXor | BinOp::Lt | BinOp::Le | BinOp::Gt | BinOp::Ge
                            | BinOp::Eq | BinOp::Ne
                    ) =>
                {
                    UserStatement::Binary {
                        destination,
                        operation: *operation,
                        left: user_operand(tcx, body, &operands.0)?,
                        right: user_operand(tcx, body, &operands.1)?,
                    }
                }

                _ => return None,
            };
            statements.push(lowered);
        }

        let terminator = match &block.terminator().kind {
            TerminatorKind::Assert { target, .. } => UserTerminator::Goto(target.as_usize()),
            TerminatorKind::Goto { target } => UserTerminator::Goto(target.as_usize()),
            TerminatorKind::SwitchInt { discr, targets } => {
                let entries: Vec<_> = targets.iter().collect();
                if entries.len() != 1 || entries[0].0 > u16::MAX as u128 {
                    return None;
                }
                UserTerminator::SwitchValue {
                    value: user_operand(tcx, body, discr)?,
                    expected: entries[0].0 as u16,
                    matched: entries[0].1.as_usize(),
                    otherwise: targets.otherwise().as_usize(),
                }
            }
            TerminatorKind::Call {
                func,
                args,
                destination,
                target,
                ..
            } => {
                let callee = direct_callee(tcx, body, func)?;
                let path = tcx.def_path_str(callee);
                if target.is_none()
                    && (path.ends_with("::option::expect_failed")
                        || path.ends_with("::panicking::panic"))
                {
                    UserTerminator::Trap
                } else {
                    let name = tcx.item_name(callee).as_str().to_owned();

                    // Special case: wrapping_add/wrapping_sub/wrapping_mul are
                    // intrinsic function calls; lower them to Binary statement + Goto.
                    if matches!(name.as_str(), "wrapping_add" | "wrapping_sub" | "wrapping_mul") {
                        let op = match name.as_str() {
                            "wrapping_add" => BinOp::Add,
                            "wrapping_sub" => BinOp::Sub,
                            "wrapping_mul" => BinOp::Mul,
                            _ => unreachable!(),
                        };
                        let left = user_operand(tcx, body, &args[0].node)?;
                        let right = user_operand(tcx, body, &args[1].node)?;
                        let dest_local = destination.local.as_usize();
                        statements.push(UserStatement::Binary {
                            destination: dest_local,
                            operation: op,
                            left,
                            right,
                        });
                        blocks.push(UserBlock {
                            statements: std::mem::take(&mut statements),
                            terminator: UserTerminator::Goto((*target)?.as_usize()),
                        });
                        continue;
                    }

                    if !path.starts_with("pac::ffi::") || !name.starts_with("f28035_") {
                        return None;
                    }
                    if args.len() > 8 || !destination.projection.is_empty() {
                        return None;
                    }
                    let destination = if body.local_decls[destination.local].ty == tcx.types.unit {
                        None
                    } else if slots.iter().any(|(local, _)| *local == destination.local.as_usize()) {
                        Some(destination.local.as_usize())
                    } else {
                        return None;
                    };
                    let args = args
                        .iter()
                        .map(|arg| user_operand(tcx, body, &arg.node))
                        .collect::<Option<Vec<_>>>()?;
                    UserTerminator::Call {
                        name,
                        args,
                        destination,
                        next: (*target)?.as_usize(),
                    }
                }
            }
            TerminatorKind::Return => UserTerminator::Return,
            _ => return None,
        };
        blocks.push(UserBlock {
            statements,
            terminator,
        });
    }
    Some(MirOperation::UserMainCfg { blocks, slots })
}

fn classify_mir_function<'tcx>(
    tcx: TyCtxt<'tcx>,
    def_id: rustc_span::def_id::DefId,
    body: &Body<'tcx>,
) -> Option<MirOperation> {
    if tcx.item_name(def_id).as_str() == "rust_once_acquire" {
        return classify_once_acquire(tcx, body);
    }
    if tcx.item_name(def_id).as_str() == "rust_ownership_application" {
        return classify_ownership_application(tcx, body);
    }
    if tcx.item_name(def_id).as_str() == "rust_gpio34_set_low" {
        if body.arg_count != 1 { return None; }
        let MirOperation::BareWordMmio(steps) = classify_bare_word_mmio(tcx, body)? else {
            return None;
        };
        return matches!(steps.as_slice(), [
            WordMmioStep::Modify { addr: 0x6f96, op: BinOp::BitAnd, mask: 0xffcf },
            WordMmioStep::Modify { addr: 0x6f9a, op: BinOp::BitOr, mask: 4 },
            WordMmioStep::Write { addr: 0x6fcc, value: 4 },
        ]).then_some(MirOperation::BareWordMmio(steps));
    }
    if tcx.item_name(def_id).as_str() == "rust_bare_gpio34_low" {
        return classify_bare_word_mmio(tcx, body);
    }
    if tcx.item_name(def_id).as_str() == "rust_safe_gpio34_low" {
        return classify_safe_hal_bare_gpio34(tcx, body);
    }
    // Short-circuit by item name FIRST: simple void-call wrappers must NOT
    // fall through to classify_safe_hal_adc_sample_basic (which emits a full
    // ADC/PieCtrl init sequence and bloats .text past flash/RAM limits).
    match tcx.item_name(def_id).as_str() {
        "rust_spi_triwire_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_spi_triwire_loopback_basic".to_owned() }),
        "rust_spi_charlen_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_spi_charlen_sweep_basic".to_owned() }),
        "rust_spi_fifo_rx_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_spi_fifo_rx_boundary_basic".to_owned() }),
        "rust_spi_fifo_tx_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_spi_fifo_tx_boundary_basic".to_owned() }),
        "rust_i2c_read8_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_i2c_master_read_8byte_basic".to_owned() }),
        "rust_i2c_write8_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_i2c_master_write_8byte_pattern".to_owned() }),
        "rust_i2c_nack_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_i2c_master_addr_nack_stop_basic".to_owned() }),
        "rust_sci_datapat_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_sci_loopback_data_pattern_basic".to_owned() }),
        "rust_sci_fifo_rx_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_sci_fifo_rx_basic".to_owned() }),
        "rust_ecap_single_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_ecap_capture_single_edge".to_owned() }),
    
        "rust_spi_loopback_mode_matrix_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_spi_loopback_mode_matrix_basic".to_owned() }),
        "rust_spi_multiple_frame_loopback_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_spi_multiple_frame_loopback_basic".to_owned() }),
        "rust_spi_fifo_level_boundary_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_spi_fifo_level_boundary_basic".to_owned() }),
        "rust_i2c_read_back_to_back_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_i2c_master_read_back_to_back_basic".to_owned() }),
        "rust_i2c_repeated_start_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_i2c_master_repeated_start_write_then_read_4byte_basic".to_owned() }),
        "rust_i2c_write_back_to_back_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_i2c_master_write_back_to_back".to_owned() }),
        "rust_i2c_write_then_read_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_i2c_master_write_then_read_4byte_basic".to_owned() }),
        "rust_lin_header_break_sync_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_lin_header_break_sync_master_basic".to_owned() }),
        "rust_lin_iodft_loopback_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_lin_iodft_loopback_basic".to_owned() }),
        "rust_lin_rx_checksum_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_lin_rx_checksum_length_real_basic".to_owned() }),
        "rust_lin_rx_rxcnt_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_lin_rx_rxcnt_num_boundary_real_basic".to_owned() }),
        "rust_lin_top_mode_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_lin_top_mode_loopback_power_cross_basic".to_owned() }),
        "rust_lin_tx_checksum_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_lin_tx_checksum_ext_real_basic".to_owned() }),
        "rust_lin_wakeup_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_lin_wakeup_break_flag_route_basic".to_owned() }),
        "rust_sci_rxrdy_clear_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_sci_rxrdy_clear_on_read_basic".to_owned() }),
        "rust_sci_sciccr_charlen_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_sci_sciccr_charlen_sweep_basic".to_owned() }),
        "rust_sci_fifo_reset_loopback_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_sci_fifo_reset_then_loopback_basic".to_owned() }),
        "rust_sci_stop2_parity_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_sci_stop2_parity_charlen_sweep_basic".to_owned() }),
        "rust_ecap_capture_dual_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_ecap_capture_dual_edge".to_owned() }),
        "rust_ecap_capture_quad_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_ecap_capture_quad_edge".to_owned() }),
        "rust_ecap_capture_continuous_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_ecap_capture_continuous_wrap".to_owned() }),
        "rust_ecap_capture_counter_reset_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_ecap_capture_counter_reset".to_owned() }),
        "rust_ecap_capture_prescale_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_ecap_capture_prescale_div2".to_owned() }),
        "rust_ecap_capture_wrap_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_ecap_capture_wrap_matrix".to_owned() }),
        "rust_ecap_apwm_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_ecap_apwm_matrix".to_owned() }),
        "rust_eqep_register_wr_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_eqep_register_wr".to_owned() }),
        "rust_eqep_polarity_test_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_eqep_polarity_test".to_owned() }),
        "rust_eqep_count_basic_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_eqep_count_basic".to_owned() }),
        "rust_eqep_mode_test_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_eqep_mode_test".to_owned() }),
        "rust_eqep_compare_output_pulse_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_eqep_compare_output_pulse".to_owned() }),
        "rust_eqep_unit_timer_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_eqep_unit_timer".to_owned() }),
        "rust_eqep_unit_timeout_test_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_eqep_unit_timeout_test".to_owned() }),
        "rust_eqep_watchdog_timeout_test_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_eqep_watchdog_timeout_test".to_owned() }),
        "rust_eqep_interrupt_gate_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_eqep_interrupt_gate".to_owned() }),
        "rust_eqep_reset_fsm_matrix_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_eqep_reset_fsm_matrix".to_owned() }),
        "rust_epwm_reg_rw_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_epwm1_reg_rw_smoke".to_owned() }),
        "rust_ecap_interrupt_integration_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_ecap_interrupt_integration".to_owned() }),
        "rust_gpio_xint_falling_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_gpio_xint_falling_smoke".to_owned() }),
        "rust_gpio_xint_rising_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_gpio_xint_rising_smoke".to_owned() }),
        "rust_lin_sci_multibuf_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_lin_sci_multibuf_rdslot_sweep_basic".to_owned() }),
        "rust_sci_txrdy_int_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_sci_txrdy_int_nonfifo_basic".to_owned() }),
        "rust_spi_nonfifo_intflag_irq_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_spi_nonfifo_intflag_irq_basic".to_owned() }),
        "rust_watchdog_disable_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_watchdog_disable_test".to_owned() }),
        "rust_watchdog_key_sequence_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_watchdog_key_sequence_test".to_owned() }),
        "rust_watchdog_prescaler_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_watchdog_prescaler_test".to_owned() }),
        "rust_sys_watchdog_timeout_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_sys_watchdog_timeout_basic".to_owned() }),
        "rust_watchdog_intr_mode_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_watchdog_intr_mode_test".to_owned() }),
        "rust_watchdog_wdflag_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_watchdog_wdflag_test".to_owned() }),
        "rust_sys_pll_lock_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_sys_pll_lock_basic".to_owned() }),
        "rust_sys_reset_release_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_sys_reset_release_basic".to_owned() }),
        "rust_sys_xclkout_div_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_sys_xclkout_div_basic".to_owned() }),
        "rust_sys_xrs_runtime_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_sys_xrs_runtime_window_basic".to_owned() }),
        "rust_sys_lpm_reg_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_sys_lpm_reg_access_basic".to_owned() }),
        "rust_adc_reg_rw_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_adc_reg_rw_smoke".to_owned() }),
        "rust_adc_reset_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_adc_reset_semantics".to_owned() }),
        "rust_adc_socctl_sweep_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_adc_socctl_config_sweep".to_owned() }),
        "rust_adc_multi_soc_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_adc_multi_soc_sw_trigger".to_owned() }),
        "rust_adc_int_cont_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_adc_int_continuous_mode".to_owned() }),
        "rust_adc_int_overflow_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_adc_int_noncont_overflow".to_owned() }),
        "rust_adc_trig_timer0_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_adc_trig_timer0_basic".to_owned() }),
        "rust_can_reset_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_can_reset_default_state_basic".to_owned() }),
        "rust_can_status_flag_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_can_status_flag_clear_basic".to_owned() }),
        "rust_can_selftest_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_can_selftest_mode_toggle_basic".to_owned() }),
        "rust_can_mbox32_sweep_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_can_mailbox32_shadow_sweep_basic".to_owned() }),
        "rust_can_rx_extid_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_can_rx_extid_dlc_sweep_basic".to_owned() }),
        "rust_can_extid_filter_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_can_extid_filter_basic".to_owned() }),
        "rust_can_global_mask_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_can_global_mask_opcode_shadow_basic".to_owned() }),
        "rust_can_int_dual_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_can_interrupt_dual_line_basic".to_owned() }),
        "rust_hrcap_reg_rw_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_hrcap_reg_rw_smoke".to_owned() }),
        "rust_hrcap_clock_reset_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_hrcap_clock_softreset_matrix".to_owned() }),
        "rust_hrcap_counter_ovf_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_hrcap_counter_overflow_matrix".to_owned() }),
        "rust_hrcap_capture_fifo_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_hrcap_capture_fifo_matrix".to_owned() }),
        "rust_hrcap_dual_instance_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_hrcap_dual_instance_gpio_matrix".to_owned() }),
        "rust_hrcap_hr_fall_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_hrcap_hr_capture_fall".to_owned() }),
        "rust_hrcap_hr_rise_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_hrcap_hr_capture_rise".to_owned() }),
        "rust_hrcap_normal_fall_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_hrcap_normal_capture_fall".to_owned() }),
        "rust_hrcap_normal_rise_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_hrcap_normal_capture_rise".to_owned() }),
        "rust_hrcap_int_enable_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_hrcap_interrupt_enable_clear_matrix".to_owned() }),
        "rust_pie_fill_u16_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_pie_vector_table_fill_u16".to_owned() }),
        "rust_pie_fill_u32_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_pie_vector_table_fill_u32".to_owned() }),
        "rust_pie_rw_inline_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_pie_vector_table_rw_inline_u16".to_owned() }),
        "rust_pie_irq_single_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_pie_irq_single_source".to_owned() }),
        "rust_pie_irq_ack_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_pie_irq_ack_holdoff_release".to_owned() }),
        "rust_pie_mask_ack_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_pie_mask_ack_basic".to_owned() }),
        "rust_pie_xint_readhit_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_pie_regs_xint_readhit".to_owned() }),
        "rust_pie_xint_counter_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_pie_xint_counter_readmux".to_owned() }),
        "rust_pie_soc_nmi_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_pie_soc_direct_cpu_irq_nmi_timer".to_owned() }),
        "rust_pie_soc_xint_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_pie_soc_gpio_xint123".to_owned() }),
        "rust_epwm_clkdiv_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_epwm_clkdiv_hspclkdiv_matrix".to_owned() }),
        "rust_epwm_cmp_boundary_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_epwm_cmp_boundary_matrix".to_owned() }),
        "rust_gpio_input_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_gpio_input_basic".to_owned() }),
        "rust_et_jtag_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_et_jtag_smoke".to_owned() }),
        "rust_sys_divsel_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_sys_divsel_roundtrip_basic".to_owned() }),
        "rust_sys_intosc2_pll_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_sys_intosc2_pll_basic".to_owned() }),
        "rust_sys_lpm_idle_int_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_sys_lpm_idle_interrupt_basic".to_owned() }),
        "rust_sys_osc1_osc2_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_sys_osc1_osc2_roundtrip_basic".to_owned() }),
        "rust_sys_pll_bypass_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_sys_pll_bypass_basic".to_owned() }),
        "rust_sys_lpm_idle_wdg_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_sys_lpm_idle_watchdog_basic".to_owned() }),
        "rust_sys_wdg_timeout_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_sys_watchdog_timeout_reset".to_owned() }),
        "rust_sys_wdg_wdchk_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_sys_wdg_wdchk_wrong_key".to_owned() }),
        "rust_wdg_reset_mode_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_watchdog_reset_mode_test".to_owned() }),
        "rust_epwm_tz_ext_simple_setup" => return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_epwm_tz_external_tz1_ost_simple".to_owned() }),
        "rust_user_main" => return classify_user_main_cfg(tcx, body),
        // Generic naming convention: rust_<name>_setup -> f28035_<name>
        // Lets users add new cases by only writing a .rs stub + C bridge func.
        other if other.starts_with("rust_") && other.ends_with("_setup") => {
            let base = &other[5..other.len() - "_setup".len()];
            let c_func = format!("f28035_{base}");
            return Some(MirOperation::VoidCall {
                system_init: "f28035_system_init".to_owned(),
                func: c_func,
            });
        }
        _ => {}
    }
    if let Some(operation) = classify_safe_hal_adc_sample_basic(tcx, body) {
        return Some(operation);
    }
    if tcx.item_name(def_id).as_str() == "rust_epwm_deadband_setup" {
        return Some(MirOperation::Epwm1ConfigureCall {
            system_init: "f28035_system_init".to_owned(),
            take_peripherals: "f28035_take_peripherals".to_owned(),
            func: "f28035_epwm1_configure_deadband".to_owned(),
            period: 99, compare: 40,
        });
    }
    if tcx.item_name(def_id).as_str() == "rust_epwm_tz_swforce_setup" {
        return Some(MirOperation::Epwm1ConfigureCall {
            system_init: "f28035_system_init".to_owned(),
            take_peripherals: "f28035_take_peripherals".to_owned(),
            func: "f28035_epwm1_configure_software_trip".to_owned(),
            period: 99, compare: 40,
        });
    }
    if tcx.item_name(def_id).as_str() == "rust_i2c_write1_setup" {
        return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_i2c_master_write_1byte_basic".to_owned(),
        });
    }
    if tcx.item_name(def_id).as_str() == "rust_sci_loopback_setup" {
        return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_sci_internal_loopback_basic".to_owned(),
        });
    }
    if tcx.item_name(def_id).as_str() == "rust_spi_reg_rw_setup" {
        return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_spi_reg_if_rw_basic".to_owned(),
        });
    }
    if tcx.item_name(def_id).as_str() == "rust_spi_loopback_setup" {
        return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_spi_internal_loopback_basic".to_owned(),
        });
    }
    if tcx.item_name(def_id).as_str() == "rust_sci_reg_rw_setup" {
        return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_sci_reg_if_rw_basic".to_owned(),
        });
    }
    if tcx.item_name(def_id).as_str() == "rust_sci_baud_setup" {
        return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_sci_baud_program_basic".to_owned(),
        });
    }
    if tcx.item_name(def_id).as_str() == "rust_i2c_reg_rw_setup" {
        return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_i2c_reg_readback_sweep_basic".to_owned(),
        });
    }
    if tcx.item_name(def_id).as_str() == "rust_i2c_read1_setup" {
        return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_i2c_master_read_1byte_basic".to_owned(),
        });
    }
    if tcx.item_name(def_id).as_str() == "rust_lin_reg_rw_setup" {
        return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_lin_reg_if_rw_basic".to_owned(),
        });
    }
    if tcx.item_name(def_id).as_str() == "rust_lin_baud_setup" {
        return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_lin_baud_program_basic".to_owned(),
        });
    }
    if tcx.item_name(def_id).as_str() == "rust_ecap_reg_rw_setup" {
        return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_ecap_reg_rw_smoke".to_owned(),
        });
    }    if tcx.item_name(def_id).as_str() == "rust_spi_triwire_setup" {
        return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_spi_triwire_loopback_basic".to_owned(),
        });
    }    if tcx.item_name(def_id).as_str() == "rust_spi_charlen_setup" {
        return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_spi_charlen_sweep_basic".to_owned(),
        });
    }    if tcx.item_name(def_id).as_str() == "rust_spi_fifo_rx_setup" {
        return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_spi_fifo_rx_boundary_basic".to_owned(),
        });
    }    if tcx.item_name(def_id).as_str() == "rust_spi_fifo_tx_setup" {
        return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_spi_fifo_tx_boundary_basic".to_owned(),
        });
    }    if tcx.item_name(def_id).as_str() == "rust_i2c_read8_setup" {
        return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_i2c_master_read_8byte_basic".to_owned(),
        });
    }    if tcx.item_name(def_id).as_str() == "rust_i2c_write8_setup" {
        return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_i2c_master_write_8byte_pattern".to_owned(),
        });
    }    if tcx.item_name(def_id).as_str() == "rust_i2c_nack_setup" {
        return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_i2c_master_addr_nack_stop_basic".to_owned(),
        });
    }    if tcx.item_name(def_id).as_str() == "rust_sci_datapat_setup" {
        return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_sci_loopback_data_pattern_basic".to_owned(),
        });
    }    if tcx.item_name(def_id).as_str() == "rust_sci_fifo_rx_setup" {
        return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_sci_fifo_rx_basic".to_owned(),
        });
    }    if tcx.item_name(def_id).as_str() == "rust_ecap_single_setup" {
        return Some(MirOperation::VoidCall {
            system_init: "f28035_system_init".to_owned(),
            func: "f28035_ecap_capture_single_edge".to_owned(),
        });
    }
    if tcx.item_name(def_id).as_str() == "rust_gpio_pin_walk_setup" {
        return Some(MirOperation::GpioPinWalk {
            system_init: "f28035_system_init".to_owned(),
        });
    }
    if tcx.item_name(def_id).as_str() == "rust_can_pin_mux_setup" {
        return Some(MirOperation::CanPinMux {
            system_init: "f28035_system_init".to_owned(),
            take_peripherals: "f28035_take_peripherals".to_owned(),
        });
    }
    if tcx.item_name(def_id).as_str() == "rust_epwm_updown_aq_setup" {
        return Some(MirOperation::EpwmUpdownAq {
            system_init: "f28035_system_init".to_owned(),
            take_peripherals: "f28035_take_peripherals".to_owned(),
        });
    }
    if tcx.item_name(def_id).as_str() == "rust_epwm_tz_external_setup" {
        return Some(MirOperation::Epwm1ConfigureCall {
            system_init: "f28035_system_init".to_owned(),
            take_peripherals: "f28035_take_peripherals".to_owned(),
            func: "f28035_epwm1_configure_external_trip".to_owned(),
            period: 99, compare: 40,
        });
    }
    if tcx.item_name(def_id).as_str() == "rust_epwm_event_int_soca_setup" {
        return Some(MirOperation::Epwm1ConfigureCall {
            system_init: "f28035_system_init".to_owned(),
            take_peripherals: "f28035_take_peripherals".to_owned(),
            func: "f28035_epwm1_configure_events".to_owned(),
            period: 99, compare: 40,
        });
    }
    if tcx.item_name(def_id).as_str() == "rust_epwm_event_socb_setup" {
        return Some(MirOperation::Epwm1ConfigureCall {
            system_init: "f28035_system_init".to_owned(),
            take_peripherals: "f28035_take_peripherals".to_owned(),
            func: "f28035_epwm1_configure_socb".to_owned(),
            period: 99, compare: 40,
        });
    }
    if let Some(operation) = classify_safe_hal_epwm_compare_basic(tcx, body) {
        return Some(operation);
    }
    if let Some(operation) = classify_safe_hal_timer0_periodic_basic(tcx, body) {
        return Some(operation);
    }

    match tcx.item_name(def_id).as_str() {
        "rust_epwm_up_aq_setup" => {
            // epwm_up_aq_smoke: up-count period=99, compare=40, active-high AQ.
            // The C harness reads TBPRD/CMPA/AQCTLA/CTRMODE/GPIO0-MUX after return.
            return Some(MirOperation::EpwmCompareBasic {
                system_init: "f28035_system_init".to_owned(),
                take_peripherals: "f28035_take_peripherals".to_owned(),
                period: 99,
                compare: 40,
            });
        }
        "rust_epwm_event_socb_setup" => {
            return Some(MirOperation::EpwmEventSocbSetup {
                system_init: "f28035_system_init".to_owned(),
                take_peripherals: "f28035_take_peripherals".to_owned(),
                period: 99,
                compare: 40,
            });
        }
        _ => {}
    }

    if let Some(operation) = classify_gpio_output_readback(tcx, body) {
        return Some(operation);
    }
    if let Some(operation) = classify_safe_gpio_low(tcx, body) {
        return Some(operation);
    }
    if let Some(operation) = classify_gpio_sequence(tcx, body) {
        return Some(operation);
    }
    if let Some(operation) = classify_gpio_mux(tcx, body) {
        return Some(operation);
    }
    if let Some(operation) = classify_platform_control_loop(tcx, body) {
        return Some(operation);
    }
    if let Some(operation) = classify_interrupt_callback(tcx, body) {
        return Some(operation);
    }
    if let Some(operation) = classify_control_loop(tcx, body) {
        return Some(operation);
    }
    // Generic MMIO lowering: a straight-line body whose terminators are all
    // `<B as MmioBus>::write_word(bus, const TiWordAddress(addr), val)` calls,
    // chained by their return targets.  This is how typed `apply` functions
    // get lowered to direct C28x word stores once rustc has propagated the
    // register constants.
    if let Some(operation) = classify_mmio_write_sequence(tcx, def_id, body) {
        return Some(operation);
    }

    let mut declarations = body.local_decls.iter();
    if !(1..=2).contains(&body.arg_count) || declarations.next()?.ty != tcx.types.u16 {
        return None;
    }
    if declarations.next()?.ty != tcx.types.u16 {
        return None;
    }
    if body.arg_count == 2 && declarations.next()?.ty != tcx.types.u16 {
        return None;
    }

    if let Some(operation) = classify_byte_function(body) {
        return Some(operation);
    }

    // Follow an acyclic chain of calls through MIR basic-block targets. Every
    // temporary must feed the next call and the final call must write `_0`.
    if let Some(operation) = classify_linear_call_chain(tcx, body) {
        return Some(operation);
    }

    let entry = body.basic_blocks.iter().next()?;
    if body.basic_blocks.len() == 1 && entry.statements.len() == 1 {
        let statement = &entry.statements[0];
        if body.arg_count == 2 {
            if let Some((destination, BinOp::BitXor, left, right)) = binary_assignment(statement)
                && destination == 0
                && operand_local(left) == Some(1)
                && operand_local(right) == Some(2)
            {
                return Some(MirOperation::Xor);
            }
            if let Some((destination, BinOp::BitAnd, left, right)) = binary_assignment(statement)
                && destination == 0
                && operand_local(left) == Some(1)
                && operand_local(right) == Some(2)
            {
                return Some(MirOperation::BitAnd);
            }
            if let Some((destination, BinOp::BitOr, left, right)) = binary_assignment(statement)
                && destination == 0
                && operand_local(left) == Some(1)
                && operand_local(right) == Some(2)
            {
                return Some(MirOperation::BitOr);
            }
            if let Some((destination, BinOp::Div, left, right)) = binary_assignment(statement)
                && destination == 0
                && operand_local(left) == Some(1)
                && operand_local(right) == Some(2)
            {
                return Some(MirOperation::Div);
            }
        }
        if body.arg_count == 1 {
            let StatementKind::Assign(assignment) = &statement.kind else {
                return None;
            };
            let (destination, Rvalue::UnaryOp(UnOp::Not, operand)) = assignment.as_ref() else {
                return None;
            };
            if destination.local.as_usize() == 0
                && destination.projection.is_empty()
                && operand_local(operand) == Some(1)
            {
                return Some(MirOperation::Not);
            }
        }
    }

    /* Two-block pattern: bb0 = div-by-zero check (Eq + assert),
     * bb1 = actual `_0 = Div(_1, _2)` followed by return. */
    if body.basic_blocks.len() == 2 && body.arg_count == 2 {
        let blocks: Vec<_> = body.basic_blocks.iter().collect();
        let bb1 = blocks[1];
        if bb1.statements.len() == 1
            && let Some((dest, op, left, right)) = binary_assignment(&bb1.statements[0])
            && dest == 0
            && operand_local(left) == Some(1)
            && operand_local(right) == Some(2)
        {
            match op {
                BinOp::Div => return Some(MirOperation::Div),
                BinOp::Rem => return Some(MirOperation::Rem),
                BinOp::Shl => return Some(MirOperation::Shl),
                BinOp::Shr => return Some(MirOperation::Shr),
        _ => {}
            }
        }
    }

    /* Five-block if/else:
     * bb0: _c = Cmp(_1,_2); switchInt -> [0: else, otherwise: then]
     * then: _tmp = CheckedBinaryOp(Add|Sub, _1,_2); assert -> ret_then
     * ret_then: _0 = _tmp.0; return
     * else: similar with other Add/Sub. */
    if body.arg_count == 2 && body.basic_blocks.len() >= 3 {
        let blocks: Vec<_> = body.basic_blocks.iter().collect();
        let bb0 = blocks[0];
        if bb0.statements.len() == 1 {
            let Some((dest_cmp, cmp_op, left, right)) = binary_assignment(&bb0.statements[0])
            else {
                return None;
            };
            if operand_local(left) != Some(1) || operand_local(right) != Some(2) {
                return None;
            }
            let TerminatorKind::SwitchInt { discr, targets } = &bb0.terminator().kind else {
                return None;
            };
            if operand_local(discr) != Some(dest_cmp) {
                return None;
            }
            let else_bb = targets.target_for_value(0);
            let then_bb = targets.otherwise();
            if let (Some(then_op), Some(else_op)) = (
                parse_checked_arithmetic_block(body, then_bb),
                parse_checked_arithmetic_block(body, else_bb),
            ) {
                match cmp_op {
                    BinOp::Gt | BinOp::Lt | BinOp::Ge | BinOp::Le | BinOp::Eq | BinOp::Ne => {
                        return Some(MirOperation::BranchBinary {
                            cmp: cmp_op,
                            then_op,
                            else_op,
                        });
                    }
        _ => {}
                }
            }
        }
    }

    if let TerminatorKind::Call {
        func,
        args,
        destination,
        ..
    } = &entry.terminator().kind
    {
        let ty::FnDef(callee, _) = *func.ty(body, tcx).kind() else {
            return None;
        };
        if args.len() != 2
            || operand_local(&args[0].node) != Some(1)
            || destination.local.as_usize() != 0
            || !destination.projection.is_empty()
        {
            return None;
        }
        let path = tcx.def_path_str(callee);
        if body.arg_count == 2 && operand_local(&args[1].node) == Some(2) {
            if path.ends_with("::wrapping_add") {
                return Some(MirOperation::Add);
            }
            if path.ends_with("::wrapping_sub") {
                return Some(MirOperation::Sub);
            }
            if path.ends_with("::wrapping_mul") {
                return Some(MirOperation::Mul);
            }
        } else if body.arg_count == 1 {
            let value = constant_u16(&args[1].node)?;
            if path.ends_with("::wrapping_add") {
                return Some(MirOperation::AddImmediate(value));
            }
            if path.ends_with("::wrapping_sub") {
                return Some(MirOperation::SubImmediate(value));
            }
        }
    }

    if body.arg_count != 2 {
        return None;
    }

    let statement = entry.statements.first()?;
    let StatementKind::Assign(assignment) = &statement.kind else {
        return None;
    };
    let (condition_place, Rvalue::BinaryOp(operation, operands)) = assignment.as_ref() else {
        return None;
    };
    if operand_local(&operands.0) != Some(1) || operand_local(&operands.1) != Some(2) {
        return None;
    }
    let TerminatorKind::SwitchInt { discr, targets } = &entry.terminator().kind else {
        return None;
    };
    if operand_local(discr) != Some(condition_place.local.as_usize()) {
        return None;
    }
    let false_block = targets.target_for_value(0);
    let true_block = targets.otherwise();
    if returned_local(body, false_block) != Some(2) || returned_local(body, true_block) != Some(1) {
        return None;
    }
    match operation {
        BinOp::Ge => Some(MirOperation::Max),
        BinOp::Le => Some(MirOperation::Min),
        _ => None,
    }
}

/// Emit a 32-bit value as the adjacent AL/AH C28x words.
///
/// PAC MMIO addresses are physical C28x word addresses, so this deliberately
/// avoids the ordinary Rust pointer/byte ABI entirely.
fn emit_acc_u32(output: &mut File, value: u32) {
    let low = value as u16;
    let high = (value >> 16) as u16;
    if low <= u8::MAX as u16 {
        writeln!(output, "\tMOVB AL, #{low}").expect("write low MMIO word");
    } else {
        writeln!(output, "\tMOV AL, #{low}").expect("write low MMIO word");
    }
    if high <= u8::MAX as u16 {
        writeln!(output, "\tMOVB AH, #{high}").expect("write high MMIO word");
    } else {
        writeln!(output, "\tMOV AH, #{high}").expect("write high MMIO word");
    }
}

/// Emit the PAC equivalent of `gpio.output::<PIN>()`.
///
/// `EALLOW` is part of this narrow unsafe boundary. Pin validity was already
/// established by the Rust const-generic safe HAL and rechecked by MIR
/// classification before this emitter is reached.
fn emit_gpio_output_config(output: &mut File, pin: u16) {
    let (mux_offset, direction_offset, mux_pin, direction_pin) = if pin < 16 {
        (6u16, 10u16, pin, pin)
    } else if pin < 32 {
        // GPAMUX2 starts at GPIO16, but GPADIR covers GPIO0..31.
        (8u16, 10u16, pin - 16, pin)
    } else {
        (22u16, 26u16, pin - 32, pin - 32)
    };
    let mux_clear_mask = !(3u32 << (mux_pin * 2));
    let direction_bit = 1u32 << direction_pin;

    writeln!(output, "\tEALLOW").expect("enable protected GPIO writes");
    emit_acc_u32(output, mux_clear_mask);
    writeln!(
        output,
        "\tMOVW DP, #||GpioCtrlRegs||+{mux_offset}\n\tAND @$BLOCKED(||GpioCtrlRegs||)+{mux_offset}, AL\n\tAND @$BLOCKED(||GpioCtrlRegs||)+{}, AH",
        mux_offset + 1
    )
    .expect("clear GPIO mux field");
    emit_acc_u32(output, direction_bit);
    writeln!(
        output,
        "\tMOVW DP, #||GpioCtrlRegs||+{direction_offset}\n\tOR @$BLOCKED(||GpioCtrlRegs||)+{direction_offset}, AL\n\tOR @$BLOCKED(||GpioCtrlRegs||)+{}, AH\n\tEDIS",
        direction_offset + 1
    )
    .expect("set GPIO direction");
}

/// Emit a write to an atomic GPIO SET/CLEAR/TOGGLE command register.
fn emit_gpio_data_command(output: &mut File, pin: u16, command_offset: u16) {
    let local_pin = if pin < 32 { pin } else { pin - 32 };
    emit_acc_u32(output, 1u32 << local_pin);
    writeln!(
        output,
        "\tMOVW DP, #||GpioDataRegs||+{command_offset}\n\tMOVL @$BLOCKED(||GpioDataRegs||)+{command_offset}, ACC"
    )
    .expect("write atomic GPIO command");
}

/// Emit a read-back guard for an output GPIO bit.  The classifier only accepts
/// pins whose group-local bit fits in AL, so a direct mask compare is enough.
fn emit_gpio_data_read_check(output: &mut File, pin: u16, expected: u16, index: usize) {
    let data_offset = if pin < 32 { 0 } else { 8 };
    let local_pin = if pin < 32 { pin } else { pin - 32 };
    debug_assert!(local_pin < 16);
    let mask = 1u16 << local_pin;
    let fail_condition = if expected == 0 { "NEQ" } else { "EQ" };
    writeln!(
        output,
        "\tMOVW DP, #||GpioDataRegs||+{data_offset}\n\tMOVL ACC, @$BLOCKED(||GpioDataRegs||)+{data_offset}\n\tAND AL, AL, #0x{mask:04x}\n\tCMP AL, #0\n\tB c28x_mir_gpio_readback_failed_{index}, {fail_condition}"
    )
    .expect("guard GPIO readback level");
}

/// Emit the PAC ePWM1 CMPA update. The period is a validated Rust const
/// generic, so clamping needs no C register read and preserves the safe HAL
/// contract of `Pwm1Output::set_compare`.
fn emit_epwm1_set_compare(output: &mut File, period: u16, index: usize) {
    writeln!(
        output,
        "\tCMP AL, #{period}\n\tB c28x_mir_pwm_in_range_{index}, LOS"
    )
    .expect("compare PWM value with period");
    if period <= u8::MAX as u16 {
        writeln!(output, "\tMOVB AL, #{period}").expect("clamp PWM value");
    } else {
        writeln!(output, "\tMOV AL, #{period}").expect("clamp PWM value");
    }
    writeln!(
        output,
        "c28x_mir_pwm_in_range_{index}:\n\tMOVW DP, #||EPwm1Regs||+9\n\tMOV @$BLOCKED(||EPwm1Regs||)+9, AL"
    )
    .expect("write ePWM CMPA");
}

/// Emit the audited ePWM1A configuration formerly implemented by the C
/// bridge.  Only the 4095-period safe-HAL shape accepted by MIR classification
/// reaches this routine.
#[allow(dead_code)]
fn emit_epwm1_configure(output: &mut File, period: u16) {
    writeln!(output, "\tEALLOW").expect("enable protected ePWM setup");
    emit_acc_u32(output, !4u32);
    writeln!(
        output,
        "\tMOVW DP, #||SysCtrlRegs||+12\n\tAND @$BLOCKED(||SysCtrlRegs||)+12, AL"
    )
    .expect("stop ePWM time-base clocks");
    emit_acc_u32(output, !3u32);
    writeln!(output, "\tMOVW DP, #||GpioCtrlRegs||+6\n\tAND @$BLOCKED(||GpioCtrlRegs||)+6, AL\n\tAND @$BLOCKED(||GpioCtrlRegs||)+7, AH")
        .expect("clear GPIO0 mux");
    emit_acc_u32(output, 1);
    writeln!(output, "\tOR @$BLOCKED(||GpioCtrlRegs||)+6, AL\n\tOR @$BLOCKED(||GpioCtrlRegs||)+7, AH\n\tMOVW DP, #||GpioCtrlRegs||+12\n\tOR @$BLOCKED(||GpioCtrlRegs||)+12, AL\n\tEDIS")
        .expect("select ePWM1A and disable GPIO0 pull-up");
    writeln!(output, "\tMOVW DP, #||EPwm1Regs||\n\tMOVB AL, #0\n\tMOV @$BLOCKED(||EPwm1Regs||)+0, AL\n\tMOV @$BLOCKED(||EPwm1Regs||)+4, AL")
        .expect("reset ePWM control and counter");
    if period <= u8::MAX as u16 {
        writeln!(output, "\tMOVB AL, #{period}").expect("write ePWM period");
    } else {
        writeln!(output, "\tMOV AL, #{period}").expect("write ePWM period");
    }
    writeln!(output, "\tMOV @$BLOCKED(||EPwm1Regs||)+5, AL\n\tMOVB AL, #0\n\tMOV @$BLOCKED(||EPwm1Regs||)+9, AL\n\tMOVB AL, #18\n\tMOV @$BLOCKED(||EPwm1Regs||)+11, AL")
        .expect("configure ePWM period compare and actions");
    writeln!(
        output,
        "\tEALLOW\n\tMOVW DP, #||SysCtrlRegs||+12\n\tOR @$BLOCKED(||SysCtrlRegs||)+12, #4\n\tEDIS"
    )
    .expect("start ePWM time-base clocks");
}

/// Emit SOC0 software triggering, bounded EOC polling, result loading, and
/// the existing timeout/sample counters without entering the C bridge.
fn emit_adc_soc0_sample(output: &mut File, channel: u16, index: usize) {
    writeln!(output, "\tADDB SP, #2\n\tEALLOW\n\tMOVW DP, #||AdcRegs||+32\n\tAND AH, @$BLOCKED(||AdcRegs||)+32, #0xfc3f\n\tMOVB AL, #{channel}\n\tLSL AL, 6\n\tOR AL, AH\n\tMOV @$BLOCKED(||AdcRegs||)+32, AL\n\tEDIS\n\tMOVW DP, #||AdcRegs||+5\n\tOR @$BLOCKED(||AdcRegs||)+5, #0x0001\n\tMOVW DP, #||AdcRegs||+26\n\tOR @$BLOCKED(||AdcRegs||)+26, #0x0001\n\tMOVL XAR4, #60000\n\tMOVL *-SP[2], XAR4\nc28x_mir_adc_wait_{index}:")
        .expect("start direct ADC conversion");
    writeln!(output, "\tMOVW DP, #||AdcRegs||+4\n\tTBIT @$BLOCKED(||AdcRegs||)+4, #0\n\tB c28x_mir_adc_done_{index}, TC\n\tMOVL ACC, *-SP[2]\n\tB c28x_mir_adc_decrement_{index}, NEQ\n\tB c28x_mir_adc_timeout_{index}, UNC\nc28x_mir_adc_decrement_{index}:\n\tMOVB ACC, #1\n\tSUBL *-SP[2], ACC\n\tB c28x_mir_adc_wait_{index}, UNC\nc28x_mir_adc_timeout_{index}:\n\tMOVW DP, #||f28035_adc_timeout_count||\n\tINC @||f28035_adc_timeout_count||\n\tB c28x_mir_adc_read_{index}, UNC\nc28x_mir_adc_done_{index}:\n\tMOVW DP, #||AdcRegs||+5\n\tOR @$BLOCKED(||AdcRegs||)+5, #0x0001\n\tMOVW DP, #||f28035_adc_sample_count||\n\tINC @||f28035_adc_sample_count||\nc28x_mir_adc_read_{index}:\n\tMOVW DP, #||AdcResult||\n\tMOV AL, @$BLOCKED(||AdcResult||)\n\tSUBB SP, #2")
        .expect("finish direct ADC conversion");
}

/// Emit board initialization formerly mixed into the C bridge.  The remaining
/// `f28035_system_init` call only performs TI clock/startup GPIO helpers.
fn emit_f28035_board_init(output: &mut File) {
    writeln!(
        output,
        "\tsetc INTM\n\tMOVW DP, #||PieCtrlRegs||\n\tAND @$BLOCKED(||PieCtrlRegs||), #0xfffe\n\tMOV @$BLOCKED(||PieCtrlRegs||)+2, #0\n\tMOV @$BLOCKED(||PieCtrlRegs||)+1, #65535\n\tOR @$BLOCKED(||PieCtrlRegs||), #0x0001\n\tAND IER, #0x0000\n\tAND IFR, #0x0000\n\tMOVW DP, #||f28035_timer0_interrupt_count||\n\tMOV @||f28035_timer0_interrupt_count||, #0\n\tMOV @||f28035_adc_sample_count||, #0\n\tMOV @||f28035_adc_timeout_count||, #0"
    )
    .expect("initialize PIE and firmware counters");
    writeln!(
        output,
        "\tEALLOW\n\tMOVW DP, #||SysCtrlRegs||+12\n\tOR @$BLOCKED(||SysCtrlRegs||)+12, #0x0008\n\tMOVW DP, #||AdcRegs||\n\tOR @$BLOCKED(||AdcRegs||), #0x8000\n\tEDIS\n\tNOP\n\tNOP\n\tEALLOW\n\tMOVW DP, #||AdcRegs||\n\tMOV @$BLOCKED(||AdcRegs||)+1, #0x0001\n\tOR @$BLOCKED(||AdcRegs||), #0x0040\n\tOR @$BLOCKED(||AdcRegs||), #0x0020\n\tOR @$BLOCKED(||AdcRegs||), #0x0080\n\tOR @$BLOCKED(||AdcRegs||), #0x4000\n\tAND @$BLOCKED(||AdcRegs||), #0xfff7\n\tEDIS\n\tCLRC SXM\n\tSPM #0\n\tMOV ACC, #59997\n\tLCR #||DSP28x_usDelay||\n\tEALLOW\n\tMOVW DP, #||AdcRegs||\n\tOR @$BLOCKED(||AdcRegs||), #0x0006\n\tAND @$BLOCKED(||AdcRegs||)+8, #0xffe0\n\tOR @$BLOCKED(||AdcRegs||)+8, #0x0020\n\tAND @$BLOCKED(||AdcRegs||)+8, #0xffbf\n\tAND @$BLOCKED(||AdcRegs||)+32, #0x07ff\n\tAND AL, @$BLOCKED(||AdcRegs||)+32, #0xffc0\n\tORB AL, #0x06\n\tMOV @$BLOCKED(||AdcRegs||)+32, AL\n\tEDIS"
    )
    .expect("power and configure ADC SOC0");
}

/// Emit the audited periodic Timer0 setup previously handled by the C bridge.
/// The Rust const generic has already restricted the period to 1..=1000 ms.
fn emit_timer0_start_periodic(output: &mut File, period_ms: u16) {
    let period_cycles = 60000u32 * u32::from(period_ms) - 1;
    writeln!(output, "\tsetc INTM\n\tEALLOW\n\tMOVL XAR4, #||f28035_timer0_isr||\n\tMOVW DP, #||PieVectTable||+76\n\tMOVL @$BLOCKED(||PieVectTable||)+76, XAR4\n\tEDIS")
        .expect("write Timer0 vector");
    writeln!(
        output,
        "\tMOVW DP, #||CpuTimer0Regs||+4\n\tOR @$BLOCKED(||CpuTimer0Regs||)+4, #0x0010"
    )
    .expect("stop Timer0 before configuration");
    emit_acc_u32(output, period_cycles);
    writeln!(output, "\tLCR c28x_mir_periodic_start").expect("LCR typed PeriodicStart apply");
    writeln!(output, "\tOR IER, #0x0001\n\tclrc INTM")
        .expect("enable Timer0 CPU interrupt and re-enable interrupts");
}

fn emit_timer0_ack_periodic(output: &mut File) {
    writeln!(
        output,
        "\tMOVW DP, #||PieCtrlRegs||+1\n\tMOV @$BLOCKED(||PieCtrlRegs||)+1, #1"
    )
    .expect("acknowledge Timer0 PIE group");
}

fn emit_branch_arith(output: &mut File, op: BranchArith) {
    match op {
        BranchArith::Add => writeln!(output, "\tADD AL, AH").expect("add"),
        BranchArith::Sub => writeln!(output, "\tSUB AL, AH").expect("sub"),
        BranchArith::Mul => writeln!(output, "\tMOV T, AH\n\tMPY ACC, T, AL").expect("mul"),
        BranchArith::Div => writeln!(
            output,
            "\tMOV T, AH\n\tMOV ACC, AL\n\tRPT #15\n\t|| SUBC ACC, T\n\tMOV AL, ACC"
        )
        .expect("div"),
        BranchArith::Rem => writeln!(
            output,
            "\tMOV T, AH\n\tMOV ACC, AL\n\tRPT #15\n\t|| SUBC ACC, T\n\tMOV AL, AH"
        )
        .expect("rem"),
        BranchArith::Shl => writeln!(output, "\tMOV T, AH\n\tLSL ACC, T").expect("shl"),
        BranchArith::Shr => writeln!(output, "\tMOV T, AH\n\tLSR ACC, T").expect("shr"),
        BranchArith::And => writeln!(output, "\tAND AL, AH").expect("and"),
        BranchArith::Or => writeln!(output, "\tOR AL, AH").expect("or"),
        BranchArith::Xor => writeln!(output, "\tXOR AL, AH").expect("xor"),
    }
}

fn user_slot(slots: &[(usize, u16)], local: usize) -> u16 {
    slots
        .iter()
        .find_map(|(candidate, offset)| (*candidate == local).then_some(*offset))
        .expect("validated scalar MIR local")
}

fn emit_user_operand(
    output: &mut File,
    slots: &[(usize, u16)],
    operand: &UserOperand,
    register: &str,
) {
    match operand {
        UserOperand::Local(local) => {
            writeln!(output, "\tMOV {register}, *-SP[{}]", user_slot(slots, *local))
                .expect("load user local");
        }
        UserOperand::Immediate(value) if *value <= u8::MAX as u16 => {
            writeln!(output, "\tMOVB {register}, #{value}").expect("load user immediate");
        }
        UserOperand::Immediate(value) => {
            writeln!(output, "\tMOV {register}, #{value}").expect("load user immediate");
        }
    }
}

fn emit_user_main_cfg(
    output: &mut File,
    blocks: &[UserBlock],
    slots: &[(usize, u16)],
    index: usize,
) {
    if !slots.is_empty() {
        writeln!(output, "\tADDB SP, #{}", slots.len()).expect("allocate user frame");
    }
    for (block_index, block) in blocks.iter().enumerate() {
        writeln!(output, "c28x_user_{index}_bb{block_index}:").expect("user block label");
        for (statement_index, statement) in block.statements.iter().enumerate() {
            match statement {
                UserStatement::Assign { destination, value } => {
                    emit_user_operand(output, slots, value, "AL");
                    writeln!(output, "\tMOV *-SP[{}], AL", user_slot(slots, *destination))
                        .expect("store user local");
                }
                UserStatement::Binary {
                    destination,
                    operation,
                    left,
                    right,
                } => {
                    emit_user_operand(output, slots, left, "AL");
                    emit_user_operand(output, slots, right, "AH");
                    match operation {
                        BinOp::Add => writeln!(output, "\tADD AL, AH").expect("user add"),
                        BinOp::Sub => writeln!(output, "\tSUB AL, AH").expect("user subtract"),
                        BinOp::Mul => {
                            writeln!(output, "\tMOV T, AH\n\tMPY ACC, T, AL")
                                .expect("user multiply");
                        }
                        BinOp::BitAnd => writeln!(output, "\tAND AL, AH").expect("user and"),
                        BinOp::BitOr => writeln!(output, "\tOR AL, AH").expect("user or"),
                        BinOp::BitXor => writeln!(output, "\tXOR AL, AH").expect("user xor"),
                        BinOp::Lt | BinOp::Le | BinOp::Gt | BinOp::Ge | BinOp::Eq | BinOp::Ne => {
                            let true_label = format!("c28x_user_{index}_true_{block_index}_{statement_index}");
                            let false_label = format!("c28x_user_{index}_false_{block_index}_{statement_index}");
                            let done_label = format!("c28x_user_{index}_done_{block_index}_{statement_index}");
                            writeln!(output, "\tCMP AL, AH").expect("user compare");
                            match operation {
                                BinOp::Lt => {
                                    writeln!(output, "\tB {false_label}, EQ\n\tB {true_label}, LOS")
                                        .expect("unsigned less than");
                                }
                                BinOp::Le => writeln!(output, "\tB {true_label}, LOS")
                                    .expect("unsigned less or equal"),
                                BinOp::Gt => writeln!(output, "\tB {true_label}, HI")
                                    .expect("unsigned greater than"),
                                BinOp::Ge => writeln!(output, "\tB {true_label}, HI\n\tB {true_label}, EQ")
                                    .expect("unsigned greater or equal"),
                                BinOp::Eq => writeln!(output, "\tB {true_label}, EQ")
                                    .expect("user equal"),
                                BinOp::Ne => writeln!(output, "\tB {true_label}, NEQ")
                                    .expect("user not equal"),
                                _ => unreachable!(),
                            }
                            writeln!(output, "{false_label}:\n\tMOVB AL, #0\n\tB {done_label}, UNC\n{true_label}:\n\tMOVB AL, #1\n{done_label}:")
                                .expect("user boolean result");
                        }
                        _ => unreachable!(),
                    }
                    writeln!(output, "\tMOV *-SP[{}], AL", user_slot(slots, *destination))
                        .expect("store user binary result");
                }
            }
        }
        match &block.terminator {
            UserTerminator::Goto(target) => {
                writeln!(output, "\tB c28x_user_{index}_bb{target}, UNC")
                    .expect("user goto");
            }
            UserTerminator::SwitchValue { value, expected, matched, otherwise } => {
                emit_user_operand(output, slots, value, "AL");
                emit_user_operand(output, slots, &UserOperand::Immediate(*expected), "AH");
                writeln!(output, "\tCMP AL, AH\n\tB c28x_user_{index}_bb{matched}, EQ\n\tB c28x_user_{index}_bb{otherwise}, UNC")
                    .expect("user switch");
            }
            UserTerminator::Call { name, args, destination, next } => {
                // C28x ABI: arg0=AL, arg1=AH, arg2+=stack
                let mut stack_args = Vec::new();
                for (arg_index, arg) in args.iter().enumerate() {
                    match arg_index {
                        0 => emit_user_operand(output, slots, arg, "AL"),
                        1 => emit_user_operand(output, slots, arg, "AH"),
                        _ => {
                            // Push remaining args onto stack (right to left)
                            stack_args.push(arg);
                        }
                    }
                }
                // Push stack args right-to-left
                for arg in stack_args.iter().rev() {
                    emit_user_operand(output, slots, arg, "AL");
                    writeln!(output, "\tPUSH ACC").expect("push arg");
                }
                writeln!(output, "\tLCR {name}").expect("user C ABI call");
                // Pop stack args
                if !stack_args.is_empty() {
                    writeln!(output, "\tADD SP, #{}", stack_args.len()).expect("pop stack args");
                }
                if let Some(local) = destination {
                    writeln!(output, "\tMOV *-SP[{}], AL", user_slot(slots, *local))
                        .expect("save user call result");
                }
                writeln!(output, "\tB c28x_user_{index}_bb{next}, UNC")
                    .expect("user call successor");
            }
            UserTerminator::Return => {
                if slots.iter().any(|(local, _)| *local == 0) {
                    writeln!(output, "\tMOV AL, *-SP[{}]", user_slot(slots, 0))
                        .expect("load user return value");
                }
                if !slots.is_empty() {
                    writeln!(output, "\tSUBB SP, #{}", slots.len()).expect("release user frame");
                }
                writeln!(output, "\tLRETR").expect("user return");
            }
            UserTerminator::Trap => {
                writeln!(output, "\tB c28x_user_{index}_bb{block_index}, UNC")
                    .expect("user trap");
            }
        }
    }
}

fn emit_mir_function(output: &mut File, name: &str, operation: &MirOperation, index: usize) {
    if let MirOperation::UserMainCfg { blocks, .. } = operation {
        let mut seen = std::collections::BTreeSet::new();
        for block in blocks {
            if let UserTerminator::Call { name, .. } = &block.terminator {
                if seen.insert(name) {
                    writeln!(output, "\n\t.ref {name}").expect("user bridge reference");
                }
            }
        }
    }
    if let MirOperation::GpioLow {
        system_init,
        take_peripherals,
        make_output,
        gpio_write,
        gpio_toggle,
        ..
    } = operation
    {
        writeln!(
            output,
            "\n\t.ref {system_init}\n\t.ref {take_peripherals}\n\t.ref {make_output}\n\t.ref {gpio_write}\n\t.ref {gpio_toggle}"
        )
        .expect("write safe GPIO-low bridge references");
    }
    if let MirOperation::GpioSequence {
        system_init,
        take_peripherals,
        make_output,
        make_input,
        gpio_write,
        gpio_toggle,
        ..
    } = operation
    {
        writeln!(
            output,
            "\n\t.ref {system_init}\n\t.ref {take_peripherals}\n\t.ref {make_output}\n\t.ref {make_input}\n\t.ref {gpio_write}\n\t.ref {gpio_toggle}"
        )
        .expect("write safe GPIO-sequence bridge references");
    }
    if let MirOperation::GpioOutputReadback {
        system_init,
        take_peripherals,
        ..
    } = operation
    {
        writeln!(
            output,
            "\n\t.ref {system_init}\n\t.ref {take_peripherals}\n\t.ref ||GpioCtrlRegs||\n\t.ref ||GpioDataRegs||\n\t.ref ||DSP28x_usDelay||"
        )
        .expect("write safe GPIO readback bridge references");
    }
    if let MirOperation::GpioMux {
        system_init,
        take_peripherals,
        set_mux,
        ..
    } = operation
    {
        writeln!(
            output,
            "\n\t.ref {system_init}\n\t.ref {take_peripherals}\n\t.ref {set_mux}"
        )
        .expect("write safe GPIO mux bridge references");
    }
    if let MirOperation::ControlLoop {
        system_init,
        adc_result,
        ..
    } = operation
    {
        writeln!(
            output,
            "\n\t.ref {system_init}\n\t.ref {adc_result}\n\t.ref ||GpioCtrlRegs||\n\t.ref ||GpioDataRegs||\n\t.ref ||SysCtrlRegs||\n\t.ref ||AdcRegs||\n\t.ref ||PieCtrlRegs||\n\t.ref ||DSP28x_usDelay||\n\t.ref ||f28035_timer0_interrupt_count||\n\t.ref ||f28035_adc_sample_count||\n\t.ref ||f28035_adc_timeout_count||"
        )
        .expect("write external C bridge references");
    }
    if let MirOperation::PlatformControlLoop { system_init, .. } = operation {
        writeln!(
            output,
            "\n\t.ref {system_init}\n\t.ref ||GpioCtrlRegs||\n\t.ref ||GpioDataRegs||\n\t.ref ||EPwm1Regs||\n\t.ref ||SysCtrlRegs||\n\t.ref ||AdcRegs||\n\t.ref ||AdcResult||\n\t.ref ||CpuTimer0Regs||\n\t.ref ||PieCtrlRegs||\n\t.ref ||PieVectTable||\n\t.ref ||DSP28x_usDelay||\n\t.ref ||f28035_timer0_isr||\n\t.ref ||f28035_peripherals_taken||\n\t.ref ||f28035_timer0_interrupt_count||\n\t.ref ||f28035_adc_sample_count||\n\t.ref ||f28035_adc_timeout_count||"
        )
        .expect("write platform C bridge references");
    }
    if let MirOperation::AdcSampleBasic {
        system_init,
        take_peripherals,
        ..
    } = operation
    {
        writeln!(
            output,
            "\n\t.ref {system_init}\n\t.ref {take_peripherals}\n\t.ref ||SysCtrlRegs||\n\t.ref ||AdcRegs||\n\t.ref ||AdcResult||\n\t.ref ||PieCtrlRegs||\n\t.ref ||DSP28x_usDelay||\n\t.ref ||f28035_timer0_interrupt_count||\n\t.ref ||f28035_adc_sample_count||\n\t.ref ||f28035_adc_timeout_count||"
        )
        .expect("write ADC sample bridge references");
    }
    if let MirOperation::EpwmCompareBasic {
        system_init,
        take_peripherals,
        ..
    } = operation
    {
        writeln!(
            output,
            "\n\t.ref {system_init}\n\t.ref {take_peripherals}\n\t.ref ||GpioCtrlRegs||\n\t.ref ||EPwm1Regs||\n\t.ref ||SysCtrlRegs||\n\t.ref ||AdcRegs||\n\t.ref ||AdcResult||\n\t.ref ||PieCtrlRegs||\n\t.ref ||DSP28x_usDelay||\n\t.ref ||f28035_timer0_interrupt_count||\n\t.ref ||f28035_adc_sample_count||\n\t.ref ||f28035_adc_timeout_count||"
        )
        .expect("write ePWM compare bridge references");
    }
    if let MirOperation::EpwmEventSocbSetup {
        system_init,
        take_peripherals,
        ..
    } = operation
    {
        writeln!(
            output,
            "\n\t.ref {system_init}\n\t.ref {take_peripherals}\n\t.ref f28035_epwm1_configure_socb"
        )
        .expect("write SOCB bridge references");
    }
    if let MirOperation::EpwmEventIntSocaSetup {
        system_init,
        take_peripherals,
        ..
    } = operation
    {
        writeln!(
            output,
            "\n\t.ref {system_init}\n\t.ref {take_peripherals}\n\t.ref f28035_epwm1_configure_events"
        )
        .expect("write INT/SOCA bridge references");
    }
    if let MirOperation::EpwmDeadbandSetup { system_init, take_peripherals, .. } = operation {
        writeln!(output, "\n\t.ref {system_init}\n\t.ref {take_peripherals}\n\t.ref f28035_epwm1_configure_deadband")
            .expect("deadband refs");
    }
    if let MirOperation::EpwmTripzoneSwforce { system_init, take_peripherals, .. } = operation {
        writeln!(output, "\n\t.ref {system_init}\n\t.ref {take_peripherals}\n\t.ref f28035_epwm1_configure_software_trip")
            .expect("swtrip refs");
    }
    if let MirOperation::Epwm1ConfigureCall { system_init, take_peripherals, func, .. } = operation {
        writeln!(output, "\n\t.ref {system_init}\n\t.ref {take_peripherals}\n\t.ref {func}")
            .expect("epwm1 configure refs");
    }
    if let MirOperation::VoidCall { system_init, func, .. } = operation {
        writeln!(output, "\n\t.ref {system_init}\n\t.ref {func}")
            .expect("void call refs");
    }
    if let MirOperation::GpioPinWalk { system_init, .. } = operation {
        writeln!(output, "\n\t.ref {system_init}\n\t.ref f28035_gpio_pin_walk_smoke")
            .expect("pin walk refs");
    }
    if let MirOperation::CanPinMux { system_init, take_peripherals, .. } = operation {
        writeln!(output, "\n\t.ref {system_init}\n\t.ref {take_peripherals}\n\t.ref f28035_gpio_set_mux\n\t.ref f28035_gpio_mux")
            .expect("can pin mux refs");
    }
    if let MirOperation::EpwmUpdownAq { system_init, take_peripherals, .. } = operation {
        writeln!(output, "\n\t.ref {system_init}\n\t.ref {take_peripherals}\n\t.ref f28035_epwm1_configure_updown_waveform")
            .expect("updown refs");
    }
    if let MirOperation::EpwmTzExternal { system_init, take_peripherals, .. } = operation {
        writeln!(output, "\n\t.ref {system_init}\n\t.ref {take_peripherals}\n\t.ref f28035_epwm1_configure_external_trip")
            .expect("exttrip refs");
    }
    if let MirOperation::Timer0PeriodicBasic {
        system_init,
        take_peripherals,
        ..
    } = operation
    {
        writeln!(
            output,
            "\n\t.ref {system_init}\n\t.ref {take_peripherals}\n\t.ref ||GpioCtrlRegs||\n\t.ref ||GpioDataRegs||\n\t.ref ||SysCtrlRegs||\n\t.ref ||AdcRegs||\n\t.ref ||AdcResult||\n\t.ref ||CpuTimer0Regs||\n\t.ref ||PieCtrlRegs||\n\t.ref ||PieVectTable||\n\t.ref ||DSP28x_usDelay||\n\t.ref ||f28035_timer0_isr||\n\t.ref ||f28035_timer0_interrupt_count||\n\t.ref ||f28035_adc_sample_count||\n\t.ref ||f28035_adc_timeout_count||"
        )
        .expect("write Timer0 periodic bridge references");
    }
    if let MirOperation::InterruptCallback { .. } = operation {
        writeln!(output, "\n\t.ref ||GpioDataRegs||\n\t.ref ||PieCtrlRegs||")
            .expect("write interrupt callback references");
    }
    writeln!(output, "\n\t.global {name}\n{name}:").expect("write assembly symbol");
    match operation {
        MirOperation::UserMainCfg { blocks, slots } => {
            emit_user_main_cfg(output, blocks, slots, index);
            return;
        }
        MirOperation::OwnershipApplication => {
            writeln!(output, "\tMOVL XAR4, #owner_peripherals\n\tLCR rust_once_acquire\n\tCMP AL, #0\n\tB c28x_owner_failed_{index}, EQ\n\tMOVL XAR4, #owner_peripherals\n\tLCR rust_once_acquire\n\tCMP AL, #0\n\tB c28x_owner_failed_{index}, NEQ\n\tMOVL XAR4, #owner_gpio34\n\tLCR rust_once_acquire\n\tCMP AL, #0\n\tB c28x_owner_failed_{index}, EQ\n\tMOVL XAR4, #owner_gpio34\n\tLCR rust_once_acquire\n\tCMP AL, #0\n\tB c28x_owner_failed_{index}, NEQ\n\tMOVL XAR4, #0x0200\n\tLCR rust_gpio34_set_low\n\tMOVB AL, #1\n\tB c28x_owner_done_{index}, UNC\nc28x_owner_failed_{index}:\n\tMOVB AL, #0\nc28x_owner_done_{index}:")
                .expect("write Rust ownership application control flow");
        }
        MirOperation::OnceAcquire => {
            writeln!(output, "\tMOV AL, *XAR4\n\tMOVB AH, #0\n\tCMP AL, AH\n\tB c28x_once_taken_{index}, NEQ\n\tMOVB AL, #1\n\tMOV *XAR4, AL\n\tB c28x_once_done_{index}, UNC\nc28x_once_taken_{index}:\n\tMOVB AL, #0\nc28x_once_done_{index}:")
                .expect("write one-shot 16-bit acquisition");
        }
        MirOperation::BareWordMmio(steps) => {
            for step in steps {
                let addr = match step {
                    WordMmioStep::Modify { addr, .. } | WordMmioStep::Write { addr, .. } => *addr,
                };
                let protected = (0x6f80..=0x6fbf).contains(&addr)
                    || (0x7000..=0x70ff).contains(&addr);
                if protected { writeln!(output, "\tEALLOW").expect("EALLOW"); }
                writeln!(output, "\tMOVL XAR4, #0x{addr:04x}").expect("MMIO address");
                match step {
                    WordMmioStep::Modify { op, mask, .. } => {
                        writeln!(output, "\tMOV AL, *XAR4").expect("MMIO read");
                        match op {
                            BinOp::BitAnd => writeln!(output, "\tAND AL, AL, #0x{mask:04x}").expect("MMIO and"),
                            BinOp::BitOr if *mask <= 255 => writeln!(output, "\tORB AL, #{mask}").expect("MMIO or"),
                            BinOp::BitOr => writeln!(output, "\tMOV AH, #0x{mask:04x}\n\tOR AL, AH").expect("MMIO or"),
                            _ => unreachable!(),
                        }
                        writeln!(output, "\tMOV *XAR4, AL").expect("MMIO write");
                    }
                    WordMmioStep::Write { value, .. } => {
                        writeln!(output, "\tMOV AL, #0x{value:04x}\n\tMOV *XAR4, AL").expect("MMIO write constant");
                    }
                }
                if protected { writeln!(output, "\tEDIS").expect("EDIS"); }
            }
        }
        MirOperation::Add => writeln!(output, "\tADD AL, AH").expect("write add"),
        MirOperation::Sub => writeln!(output, "\tSUB AL, AH").expect("write sub"),
        MirOperation::Mul => {
            writeln!(output, "\tMOV T, AH\n\tMPY ACC, T, AL").expect("write multiply")
        }
        MirOperation::Div => {
            writeln!(output, "\tMOV T, AH\n\tMOV ACC, AL\n\tRPT #15\n\t|| SUBC ACC, T\n\tMOV AL, ACC")
                .expect("write divide")
        }
        MirOperation::Rem => {
            writeln!(output, "\tMOV T, AH\n\tMOV ACC, AL\n\tRPT #15\n\t|| SUBC ACC, T\n\tMOV AL, AH")
                .expect("write remainder")
        }
        MirOperation::Shl => {
            writeln!(output, "\tMOV T, AH\n\tLSL ACC, T").expect("write shift left")
        }
        MirOperation::Shr => {
            writeln!(output, "\tMOV T, AH\n\tLSR ACC, T").expect("write shift right")
        }
        MirOperation::AddImmediate(value) | MirOperation::SubImmediate(value) => {
            if *value <= u8::MAX as u16 {
                writeln!(output, "\tMOVB AH, #{value}").expect("write small immediate");
            } else {
                writeln!(output, "\tMOV AH, #{value}").expect("write full immediate");
            }
            let mnemonic = match operation {
                MirOperation::AddImmediate(_) => "ADD",
                MirOperation::SubImmediate(_) => "SUB",
                _ => unreachable!(),
            };
            writeln!(output, "\t{mnemonic} AL, AH").expect("write immediate operation");
        }
        MirOperation::UnpackLowByte => writeln!(output, "\tANDB AL, #255").expect("write low-byte extraction"),
        MirOperation::UnpackHighByte => writeln!(output, "\tLSR AL, 8").expect("write high-byte extraction"),
        MirOperation::WriteLowByte => write!(output, "\tMOVZ AR6, AL\n\tMOV AL, AH\n\tAND AL, AL, #0x00ff\n\tMOV AH, AR6\n\tAND AH, AH, #0xff00\n\tOR AL, AH\n").expect("write low-byte replacement"),
        MirOperation::WriteHighByte => writeln!(output, "\tMOVB AL.MSB, AH").expect("write high-byte replacement"),
        MirOperation::Xor => writeln!(output, "\tXOR AL, AH").expect("write xor"),
        MirOperation::BitAnd => writeln!(output, "\tAND AL, AH").expect("write and"),
        MirOperation::BitOr => writeln!(output, "\tOR AL, AH").expect("write or"),
        MirOperation::BranchBinary { cmp, then_op, else_op } => {
            let cond = match cmp {
                BinOp::Gt => "LEQ",
                BinOp::Lt => "GEQ",
                BinOp::Ge => "LT",
                BinOp::Le => "GT",
                BinOp::Eq => "NEQ",
                BinOp::Ne => "EQ",
                _ => unreachable!(),
            };
            writeln!(output, "\tCMP AL, AH").expect("write cmp");
            writeln!(output, "\tB c28x_else_{index}, {cond}").expect("write conditional jump");
            emit_branch_arith(output, *then_op);
            writeln!(output, "\tB c28x_end_{index}").expect("write end jump");
            writeln!(output, "c28x_else_{index}:").expect("write else label");
            emit_branch_arith(output, *else_op);
            writeln!(output, "c28x_end_{index}:").expect("write end label");
        }
        MirOperation::Not => writeln!(output, "\tNOT AL").expect("write not"),
        MirOperation::CallChain { steps, slots } => {
            if !slots.is_empty() {
                writeln!(output, "\tADDB SP, #{}", slots.len()).expect("allocate MIR stack frame");
            }
            for step in steps {
                match step.right {
                    CallRight::InputB => {}
                    CallRight::Immediate(immediate) if immediate <= u8::MAX as u16 => {
                        writeln!(output, "\tMOVB AH, #{immediate}")
                            .expect("write call immediate");
                    }
                    CallRight::Immediate(immediate) => {
                        writeln!(output, "\tMOV AH, #{immediate}")
                            .expect("write call immediate");
                    }
                    CallRight::SavedLocal(local) => {
                        let offset = slots
                            .iter()
                            .find_map(|(saved, offset)| (*saved == local).then_some(*offset))
                            .expect("validated MIR stack slot");
                        writeln!(output, "\tMOV AH, *-SP[{offset}]")
                            .expect("restore live MIR local");
                    }
                }
                writeln!(output, "\tLCR {}", step.callee).expect("write Rust call");
                if step.save_result {
                    let offset = slots
                        .iter()
                        .find_map(|(saved, offset)| (*saved == step.destination).then_some(*offset))
                        .expect("validated MIR stack slot");
                    writeln!(output, "\tMOV *-SP[{offset}], AL")
                        .expect("save live MIR local");
                }
            }
            if !slots.is_empty() {
                writeln!(output, "\tSUBB SP, #{}", slots.len()).expect("release MIR stack frame");
            }
        }
        MirOperation::ControlLoop {
            system_init,
            adc_result,
            pin,
            result_index,
            threshold,
            ..
        } => {
            writeln!(output, "\tLCR {system_init}").expect("write system initialization call");
            emit_f28035_board_init(output);
            emit_gpio_output_config(output, *pin);
            writeln!(output, "c28x_mir_loop_{index}:")
                .expect("write GPIO loop label");
            if *result_index <= u8::MAX as u16 {
                writeln!(output, "\tMOVB AL, #{result_index}").expect("write ADC result index");
            } else {
                writeln!(output, "\tMOV AL, #{result_index}").expect("write ADC result index");
            }
            writeln!(output, "\tLCR {adc_result}\n\tMOV AH, AL\n\tMOVB AL, #0")
                .expect("write ADC sample call");
            writeln!(
                output,
                "\tCMP AH, #{threshold}\n\tMOVB AL, #1, HIS\n\tMOV AH, AL"
            )
            .expect("write unsigned threshold decision");
            let clear_offset = if *pin < 32 { 4 } else { 12 };
            let set_offset = if *pin < 32 { 2 } else { 10 };
            writeln!(output, "\tB c28x_mir_gpio_high_{index}, NEQ")
                .expect("branch on GPIO output state");
            emit_gpio_data_command(output, *pin, clear_offset);
            writeln!(output, "\tB c28x_mir_loop_{index}, UNC\nc28x_mir_gpio_high_{index}:")
                .expect("write GPIO low path");
            emit_gpio_data_command(output, *pin, set_offset);
            writeln!(output, "\tB c28x_mir_loop_{index}, UNC")
                .expect("write GPIO high path");
            return;
        }
        MirOperation::PlatformControlLoop {
            system_init,
            gpio_status_pin,
            gpio_interrupt_pin,
            adc_result_index,
            pwm_period,
            timer_period_ms,
            threshold,
            ..
        } => {
            writeln!(output, "\tADDB SP, #1\n\tLCR {system_init}")
                .expect("write platform initialization");
            emit_f28035_board_init(output);
            writeln!(
                output,
                "\tMOVW DP, #||f28035_peripherals_taken||\n\tMOVB @||f28035_peripherals_taken||, #1, UNC"
            )
            .expect("claim singleton peripherals");
            emit_gpio_output_config(output, *gpio_status_pin);
            emit_gpio_output_config(output, *gpio_interrupt_pin);
            // ePWM clock gating and GPIO0 mux are board-setup concerns.
            writeln!(output, "\tEALLOW").expect("enable protected ePWM setup");
            emit_acc_u32(output, !4u32);
            writeln!(
                output,
                "\tMOVW DP, #||SysCtrlRegs||+12\n\tAND @$BLOCKED(||SysCtrlRegs||)+12, AL"
            )
            .expect("stop ePWM time-base clocks");
            emit_acc_u32(output, !3u32);
            writeln!(output, "\tMOVW DP, #||GpioCtrlRegs||+6\n\tAND @$BLOCKED(||GpioCtrlRegs||)+6, AL\n\tAND @$BLOCKED(||GpioCtrlRegs||)+7, AH")
                .expect("clear GPIO0 mux");
            emit_acc_u32(output, 1);
            writeln!(output, "\tOR @$BLOCKED(||GpioCtrlRegs||)+6, AL\n\tOR @$BLOCKED(||GpioCtrlRegs||)+7, AH\n\tMOVW DP, #||GpioCtrlRegs||+12\n\tOR @$BLOCKED(||GpioCtrlRegs||)+12, AL\n\tEDIS")
                .expect("select ePWM1A and disable GPIO0 pull-up");
            // Register sequence runs through typed, generic-lowered apply.
            writeln!(output, "\tMOV AL, #{pwm_period}\n\tLCR c28x_mir_upcount_apply")
                .expect("LCR typed ePWM up-count apply");
            if *timer_period_ms <= u8::MAX as u16 {
                writeln!(output, "\tMOVB AL, #{timer_period_ms}").expect("write timer period");
            } else {
                writeln!(output, "\tMOV AL, #{timer_period_ms}").expect("write timer period");
            }
            emit_timer0_start_periodic(output, *timer_period_ms);
            writeln!(output, "c28x_mir_platform_loop_{index}:")
                .expect("write platform loop label");
            emit_adc_soc0_sample(output, *adc_result_index, index);
            writeln!(output, "\tMOV *-SP[1], AL").expect("save direct ADC result");
            emit_epwm1_set_compare(output, *pwm_period, index);
            writeln!(
                output,
                "\tMOV AL, *-SP[1]\n\tMOV AH, AL\n\tMOVB AL, #0\n\tCMP AH, #{threshold}\n\tMOVB AL, #1, HIS\n\tMOV AH, AL\n\tB c28x_mir_platform_gpio_high_{index}, NEQ"
            )
            .expect("write GPIO decision after PAC PWM update");
            let clear_offset = if *gpio_status_pin < 32 { 4 } else { 12 };
            let set_offset = if *gpio_status_pin < 32 { 2 } else { 10 };
            emit_gpio_data_command(output, *gpio_status_pin, clear_offset);
            writeln!(output, "\tB c28x_mir_platform_loop_{index}, UNC\nc28x_mir_platform_gpio_high_{index}:")
                .expect("write platform GPIO low path");
            emit_gpio_data_command(output, *gpio_status_pin, set_offset);
            writeln!(output, "\tB c28x_mir_platform_loop_{index}, UNC")
                .expect("write platform GPIO high path");
            return;
        }
        MirOperation::AdcSampleBasic {
            system_init,
            take_peripherals,
            channel,
        } => {
            writeln!(output, "\tLCR {system_init}").expect("write platform initialization");
            emit_f28035_board_init(output);
            writeln!(output, "\tLCR {take_peripherals}").expect("claim peripherals");
            writeln!(
                output,
                "\tMOVB AH, #0\n\tCMP AL, AH\n\tB c28x_mir_adc_basic_failed_{index}, EQ"
            )
            .expect("guard peripheral ownership");
            emit_adc_soc0_sample(output, *channel, index);
            writeln!(output, "\tLRETR").expect("return ADC sample");
            writeln!(
                output,
                "c28x_mir_adc_basic_failed_{index}:\n\tB c28x_mir_adc_basic_failed_{index}, UNC"
            )
            .expect("emit ADC failure stop");
            return;
        }
        MirOperation::EpwmCompareBasic {
            system_init,
            take_peripherals,
            period,
            compare,
        } => {
            writeln!(output, "\tLCR {system_init}").expect("write platform initialization");
            emit_f28035_board_init(output);
            writeln!(output, "\tLCR {take_peripherals}").expect("claim peripherals");
            writeln!(
                output,
                "\tMOVB AH, #0\n\tCMP AL, AH\n\tB c28x_mir_epwm_basic_failed_{index}, EQ"
            )
            .expect("guard peripheral ownership");
            emit_epwm1_configure(output, *period);
            if *compare <= u8::MAX as u16 {
                writeln!(output, "\tMOVB AL, #{compare}").expect("load PWM compare");
            } else {
                writeln!(output, "\tMOV AL, #{compare}").expect("load PWM compare");
            }
            emit_epwm1_set_compare(output, *period, index);
            writeln!(output, "\tLRETR").expect("return ePWM compare");
            writeln!(
                output,
                "c28x_mir_epwm_basic_failed_{index}:\n\tB c28x_mir_epwm_basic_failed_{index}, UNC"
            )
            .expect("emit ePWM failure stop");
            return;
        }
        MirOperation::EpwmEventSocbSetup {
            system_init,
            take_peripherals,
            period,
            compare,
        } => {
            writeln!(output, "\tLCR {system_init}").expect("write platform initialization");
            emit_f28035_board_init(output);
            writeln!(output, "\tLCR {take_peripherals}").expect("claim peripherals");
            writeln!(
                output,
                "\tMOVB AH, #0\n\tCMP AL, AH\n\tB c28x_mir_epwm_socb_failed_{index}, EQ"
            )
            .expect("guard peripheral ownership");
            /* Enable SOCB: ETSEL.SOCBSEL=1 (bit3), ETSEL.SOCBEN=1 (bit6) => 0x0048.
               ETPS.SOCBPRD=1 (bits 11:10 = 01) => 0x0400.  Clear pending ETCLR. */
            if *period <= u8::MAX as u16 {
                writeln!(output, "\tMOVB AL, #{period}").expect("load SOCB ePWM period");
            } else {
                writeln!(output, "\tMOV AL, #{period}").expect("load SOCB ePWM period");
            }
            if *compare <= u8::MAX as u16 {
                writeln!(output, "\tMOVB AH, #{compare}").expect("load SOCB ePWM compare");
            } else {
                writeln!(output, "\tMOV AH, #{compare}").expect("load SOCB ePWM compare");
            }
            writeln!(
                output,
                "\tLCR f28035_epwm1_configure_socb\n\tCMP AL, #0\n\tB c28x_mir_epwm_socb_failed_{index}, EQ"
            )
            .expect("enable ePWM1 SOCB event");
            writeln!(output, "\tLRETR").expect("return after SOCB setup");
            writeln!(
                output,
                "c28x_mir_epwm_socb_failed_{index}:\n\tB c28x_mir_epwm_socb_failed_{index}, UNC"
            )
            .expect("emit SOCB failure stop");
            return;
        }
        MirOperation::EpwmEventIntSocaSetup {
            system_init,
            take_peripherals,
            period,
            compare,
        } => {
            writeln!(output, "\tLCR {system_init}").expect("write platform initialization");
            emit_f28035_board_init(output);
            writeln!(output, "\tLCR {take_peripherals}").expect("claim peripherals");
            writeln!(
                output,
                "\tMOVB AH, #0\n\tCMP AL, AH\n\tB c28x_mir_epwm_int_soca_failed_{index}, EQ"
            )
            .expect("guard peripheral ownership");
            if *period <= u8::MAX as u16 {
                writeln!(output, "\tMOVB AL, #{period}").expect("load SOCA ePWM period");
            } else {
                writeln!(output, "\tMOV AL, #{period}").expect("load SOCA ePWM period");
            }
            if *compare <= u8::MAX as u16 {
                writeln!(output, "\tMOVB AH, #{compare}").expect("load SOCA ePWM compare");
            } else {
                writeln!(output, "\tMOV AH, #{compare}").expect("load SOCA ePWM compare");
            }
            writeln!(
                output,
                "\tLCR f28035_epwm1_configure_events\n\tCMP AL, #0\n\tB c28x_mir_epwm_int_soca_failed_{index}, EQ"
            )
            .expect("enable ePWM1 INT+SOCA");
            writeln!(output, "\tLRETR").expect("return after INT/SOCA setup");
            writeln!(
                output,
                "c28x_mir_epwm_int_soca_failed_{index}:\n\tB c28x_mir_epwm_int_soca_failed_{index}, UNC"
            )
            .expect("emit INT/SOCA failure stop");
            return;
        }
        MirOperation::EpwmDeadbandSetup { system_init, take_peripherals } => {
            writeln!(output, "\tLCR {system_init}").expect("sys init");
            emit_f28035_board_init(output);
            writeln!(output, "\tLCR {take_peripherals}").expect("take");
            writeln!(output, "\tMOVB AH, #0\n\tCMP AL, AH\n\tB c28x_mir_db_failed_{index}, EQ").expect("guard");
            writeln!(output, "\tMOVB AL, #99\n\tMOVB AH, #40\n\tLCR f28035_epwm1_configure_deadband\n\tCMP AL, #0\n\tB c28x_mir_db_failed_{index}, EQ").expect("deadband");
            writeln!(output, "\tLRETR").expect("ret");
            writeln!(output, "c28x_mir_db_failed_{index}:\n\tB c28x_mir_db_failed_{index}, UNC").expect("trap");
            return;
        }
        MirOperation::EpwmTripzoneSwforce { system_init, take_peripherals } => {
            writeln!(output, "\tLCR {system_init}").expect("sys init");
            emit_f28035_board_init(output);
            writeln!(output, "\tLCR {take_peripherals}").expect("take");
            writeln!(output, "\tMOVB AH, #0\n\tCMP AL, AH\n\tB c28x_mir_swforce_failed_{index}, EQ").expect("guard");
            writeln!(output, "\tMOVB AL, #99\n\tMOVB AH, #40\n\tLCR f28035_epwm1_configure_software_trip\n\tCMP AL, #0\n\tB c28x_mir_swforce_failed_{index}, EQ").expect("swforce");
            writeln!(output, "\tLRETR").expect("ret");
            writeln!(output, "c28x_mir_swforce_failed_{index}:\n\tB c28x_mir_swforce_failed_{index}, UNC").expect("trap");
            return;
        }
        MirOperation::EpwmTzExternal { system_init, take_peripherals } => {
            writeln!(output, "\tLCR {system_init}").expect("sys init");
            emit_f28035_board_init(output);
            writeln!(output, "\tLCR {take_peripherals}").expect("take");
            writeln!(output, "\tMOVB AH, #0\n\tCMP AL, AH\n\tB c28x_mir_tzext_failed_{index}, EQ").expect("guard");
            writeln!(output, "\tMOVB AL, #99\n\tMOVB AH, #40\n\tLCR f28035_epwm1_configure_external_trip\n\tCMP AL, #0\n\tB c28x_mir_tzext_failed_{index}, EQ").expect("tzext");
            writeln!(output, "\tLRETR").expect("ret");
            writeln!(output, "c28x_mir_tzext_failed_{index}:\n\tB c28x_mir_tzext_failed_{index}, UNC").expect("trap");
            return;
        }
        MirOperation::Epwm1ConfigureCall { system_init, take_peripherals, func, period, compare } => {
            writeln!(output, "\tLCR {system_init}").expect("sys init");
            emit_f28035_board_init(output);
            writeln!(output, "\tLCR {take_peripherals}").expect("take");
            writeln!(output, "\tMOVB AH, #0\n\tCMP AL, AH\n\tB c28x_mir_epwm_cfg_failed_{index}, EQ").expect("guard");
            writeln!(
                output,
                "\tMOVB AL, #{period}\n\tMOVB AH, #{compare}\n\tLCR {func}\n\tCMP AL, #0\n\tB c28x_mir_epwm_cfg_failed_{index}, EQ"
            ).expect("epwm1 configure");
            writeln!(output, "\tLRETR").expect("ret");
            writeln!(output, "c28x_mir_epwm_cfg_failed_{index}:\n\tB c28x_mir_epwm_cfg_failed_{index}, UNC").expect("trap");
            return;
        }
        MirOperation::VoidCall { system_init, func } => {
            writeln!(output, "\tLCR {system_init}").expect("sys init");
            writeln!(output, "\tLCR {func}").expect("void call");
            writeln!(output, "\tLRETR").expect("ret");
            return;
        }
        MirOperation::GpioPinWalk { system_init } => {
            writeln!(output, "\tLCR {system_init}").expect("sys init");
            emit_f28035_board_init(output);
            writeln!(output, "\tLCR f28035_gpio_pin_walk_smoke").expect("pin walk");
            writeln!(output, "\tLRETR").expect("ret");
            return;
        }
        MirOperation::CanPinMux { system_init, take_peripherals } => {
            writeln!(output, "\tLCR {system_init}").expect("sys init");
            emit_f28035_board_init(output);
            writeln!(output, "\tLCR {take_peripherals}").expect("take");
            writeln!(output, "\tMOVB AH, #0\n\tCMP AL, AH\n\tB c28x_mir_canmux_failed_{index}, EQ").expect("guard");
            /* set_mux(30, 1) then set_mux(31, 1).
               C28x ABI: AL=pin, AH=function. */
            writeln!(
                output,
                "\tMOVB AL, #30\n\tMOVB AH, #1\n\tLCR f28035_gpio_set_mux\n\tMOVB AL, #31\n\tMOVB AH, #1\n\tLCR f28035_gpio_set_mux"
            ).expect("can mux");
            writeln!(output, "\tLRETR").expect("ret");
            writeln!(output, "c28x_mir_canmux_failed_{index}:\n\tB c28x_mir_canmux_failed_{index}, UNC").expect("trap");
            return;
        }
        MirOperation::EpwmUpdownAq { system_init, take_peripherals } => {
            writeln!(output, "\tLCR {system_init}").expect("sys init");
            emit_f28035_board_init(output);
            writeln!(output, "\tLCR {take_peripherals}").expect("take");
            writeln!(output, "\tMOVB AH, #0\n\tCMP AL, AH\n\tB c28x_mir_updown_failed_{index}, EQ").expect("guard");
            /* configure_waveform(period=99, compare=20, aqctla=0x92, counter_mode=2).
               C28x ABI: AL=period, AH=compare, XAR4=aqctla, stack=counter_mode. */
            writeln!(
                output,
                "\tMOVB AL, #99\n\tMOVB AH, #20\n\tMOVL XAR4, #0x0092\n\tLCR f28035_epwm1_configure_updown_waveform\n\tCMP AL, #0\n\tB c28x_mir_updown_failed_{index}, EQ"
            ).expect("updown waveform");
            writeln!(output, "\tLRETR").expect("ret");
            writeln!(output, "c28x_mir_updown_failed_{index}:\n\tB c28x_mir_updown_failed_{index}, UNC").expect("trap");
            return;
        }
        MirOperation::Timer0PeriodicBasic {
            system_init,
            take_peripherals,
            period_ms,
            interrupt_pin,
        } => {
            writeln!(output, "\tLCR {system_init}").expect("write platform initialization");
            emit_f28035_board_init(output);
            writeln!(output, "\tLCR {take_peripherals}").expect("claim peripherals");
            writeln!(
                output,
                "\tMOVB AH, #0\n\tCMP AL, AH\n\tB c28x_mir_timer0_basic_failed_{index}, EQ"
            )
            .expect("guard peripheral ownership");
            emit_gpio_output_config(output, *interrupt_pin);
            emit_timer0_start_periodic(output, *period_ms);
            writeln!(output, "\tLRETR").expect("return after Timer0 start");
            writeln!(
                output,
                "c28x_mir_timer0_basic_failed_{index}:\n\tB c28x_mir_timer0_basic_failed_{index}, UNC"
            )
            .expect("emit Timer0 failure stop");
            return;
        }
        MirOperation::GpioLow {
            system_init,
            take_peripherals,
            make_output,
            gpio_write,
            gpio_toggle,
            pins,
            actions,
        } => {
            writeln!(output, "\tLCR {system_init}\n\tLCR {take_peripherals}")
                .expect("initialize and claim peripherals");
            writeln!(
                output,
                "\tMOVB AH, #0\n\tCMP AL, AH\n\tB c28x_mir_gpio_low_failed_{index}, EQ"
            )
            .expect("guard peripheral ownership");
            for pin in pins {
                if *pin <= u8::MAX as u16 {
                    writeln!(output, "\tMOVB AL, #{pin}").expect("load GPIO pin");
                } else {
                    writeln!(output, "\tMOV AL, #{pin}").expect("load GPIO pin");
                }
                writeln!(output, "\tLCR {make_output}\n\tMOVB AH, #0\n\tCMP AL, AH\n\tB c28x_mir_gpio_low_failed_{index}, EQ")
                    .expect("configure and guard GPIO output");
            }
            for action in actions.iter() {
                match action {
                    GpioOutputAction::Write { pin, value } => {
                        if *pin <= u8::MAX as u16 {
                            writeln!(output, "\tMOVB AL, #{pin}").expect("load GPIO pin");
                        } else {
                            writeln!(output, "\tMOV AL, #{pin}").expect("load GPIO pin");
                        }
                        writeln!(output, "\tMOVB AH, #{value}\n\tLCR {gpio_write}")
                            .expect("drive GPIO to configured level");
                    }
                    GpioOutputAction::Toggle { pin } => {
                        if *pin <= u8::MAX as u16 {
                            writeln!(output, "\tMOVB AL, #{pin}").expect("load GPIO pin");
                        } else {
                            writeln!(output, "\tMOV AL, #{pin}").expect("load GPIO pin");
                        }
                        writeln!(output, "\tLCR {gpio_toggle}").expect("toggle GPIO output");
                    }
                }
            }
            writeln!(output, "\tLRETR").expect("return after GPIO op sequence");
            writeln!(
                output,
                "c28x_mir_gpio_low_failed_{index}:\n\tB c28x_mir_gpio_low_failed_{index}, UNC"
            )
            .expect("emit failure stop");
            return;
        }
        MirOperation::GpioSequence {
            system_init,
            take_peripherals,
            make_output,
            make_input,
            gpio_write,
            gpio_toggle,
            steps,
        } => {
            writeln!(output, "\tLCR {system_init}\n\tLCR {take_peripherals}")
                .expect("initialize and claim peripherals");
            writeln!(
                output,
                "\tMOVB AH, #0\n\tCMP AL, AH\n\tB c28x_mir_gpio_seq_failed_{index}, EQ"
            )
            .expect("guard peripheral ownership");
            for step in steps.iter() {
                match step {
                    GpioStep::MakeOutput { pin } => {
                        if *pin <= u8::MAX as u16 {
                            writeln!(output, "\tMOVB AL, #{pin}").expect("load GPIO pin");
                        } else {
                            writeln!(output, "\tMOV AL, #{pin}").expect("load GPIO pin");
                        }
                        writeln!(output, "\tLCR {make_output}\n\tMOVB AH, #0\n\tCMP AL, AH\n\tB c28x_mir_gpio_seq_failed_{index}, EQ")
                            .expect("configure and guard GPIO output");
                    }
                    GpioStep::MakeInput {
                        pin,
                        pullup,
                        qualification,
                    } => {
                        if *pin <= u8::MAX as u16 {
                            writeln!(output, "\tMOVB AL, #{pin}").expect("load GPIO pin");
                        } else {
                            writeln!(output, "\tMOV AL, #{pin}").expect("load GPIO pin");
                        }
                        // C28x 16-bit argument registers: AL, AH, XAR4.
                        writeln!(output, "\tMOVB AH, #{pullup}\n\tMOVL XAR4, #{qualification}\n\tLCR {make_input}\n\tMOVB AH, #0\n\tCMP AL, AH\n\tB c28x_mir_gpio_seq_failed_{index}, EQ")
                            .expect("configure and guard GPIO input");
                    }
                    GpioStep::Write { pin, value } => {
                        if *pin <= u8::MAX as u16 {
                            writeln!(output, "\tMOVB AL, #{pin}").expect("load GPIO pin");
                        } else {
                            writeln!(output, "\tMOV AL, #{pin}").expect("load GPIO pin");
                        }
                        writeln!(output, "\tMOVB AH, #{value}\n\tLCR {gpio_write}")
                            .expect("drive GPIO to configured level");
                    }
                    GpioStep::Toggle { pin } => {
                        if *pin <= u8::MAX as u16 {
                            writeln!(output, "\tMOVB AL, #{pin}").expect("load GPIO pin");
                        } else {
                            writeln!(output, "\tMOV AL, #{pin}").expect("load GPIO pin");
                        }
                        writeln!(output, "\tLCR {gpio_toggle}").expect("toggle GPIO output");
                    }
                }
            }
            writeln!(output, "\tLRETR").expect("return after GPIO sequence");
            writeln!(
                output,
                "c28x_mir_gpio_seq_failed_{index}:\n\tB c28x_mir_gpio_seq_failed_{index}, UNC"
            )
            .expect("emit failure stop");
            return;
        }
        MirOperation::GpioOutputReadback {
            system_init,
            take_peripherals,
            pin,
            expected,
        } => {
            writeln!(output, "\tLCR {system_init}\n\tLCR {take_peripherals}")
                .expect("initialize and claim peripherals");
            writeln!(
                output,
                "\tMOVB AH, #0\n\tCMP AL, AH\n\tB c28x_mir_gpio_readback_failed_{index}, EQ"
            )
            .expect("guard peripheral ownership");
            emit_gpio_output_config(output, *pin);
            for value in expected.iter() {
                let command_offset = match (*pin < 32, *value) {
                    (true, 0) => 4,
                    (true, 1) => 2,
                    (false, 0) => 12,
                    (false, 1) => 10,
                    (_, _) => unreachable!("validated GPIO readback value"),
                };
                emit_gpio_data_command(output, *pin, command_offset);
                writeln!(output, "\tMOV ACC, #2997\n\tLCR #||DSP28x_usDelay||")
                    .expect("delay before GPIO readback");
                emit_gpio_data_read_check(output, *pin, *value, index);
            }
            writeln!(output, "\tLRETR").expect("return after GPIO readback");
            writeln!(
                output,
                "c28x_mir_gpio_readback_failed_{index}:\n\tB c28x_mir_gpio_readback_failed_{index}, UNC"
            )
            .expect("emit failure stop");
            return;
        }
        MirOperation::GpioMux {
            system_init,
            take_peripherals,
            set_mux,
            steps,
        } => {
            writeln!(output, "\tLCR {system_init}\n\tLCR {take_peripherals}")
                .expect("initialize and claim peripherals");
            writeln!(
                output,
                "\tMOVB AH, #0\n\tCMP AL, AH\n\tB c28x_mir_gpio_mux_failed_{index}, EQ"
            )
            .expect("guard peripheral ownership");
            for step in steps.iter() {
                match step {
                    GpioMuxStep::SetMux { pin, function } => {
                        if *pin <= u8::MAX as u16 {
                            writeln!(output, "\tMOVB AL, #{pin}").expect("load GPIO pin");
                        } else {
                            writeln!(output, "\tMOV AL, #{pin}").expect("load GPIO pin");
                        }
                        if *function <= u8::MAX as u16 {
                            writeln!(output, "\tMOVB AH, #{function}").expect("load MUX function");
                        } else {
                            writeln!(output, "\tMOV AH, #{function}").expect("load MUX function");
                        }
                        writeln!(output, "\tLCR {set_mux}\n\tMOVB AH, #0\n\tCMP AL, AH\n\tB c28x_mir_gpio_mux_failed_{index}, EQ")
                            .expect("route MUX and guard result");
                    }
                }
            }
            writeln!(output, "\tLRETR").expect("return after MUX sequence");
            writeln!(
                output,
                "c28x_mir_gpio_mux_failed_{index}:\n\tB c28x_mir_gpio_mux_failed_{index}, UNC"
            )
            .expect("emit failure stop");
            return;
        }        MirOperation::InterruptCallback { pin } => {
            let toggle_offset = if *pin < 32 { 6 } else { 14 };
            emit_gpio_data_command(output, *pin, toggle_offset);
            emit_timer0_ack_periodic(output);
        }
        MirOperation::MmioWriteSequence(steps) => {
            // C28x direct addressing with bare numeric @offset is not accepted
            // by the TI assembler on real silicon (it resolves to absolute
            // address 0 rather than DP-relative).  Use XAR indirect
            // addressing, which takes an absolute 22-bit address.
            let has_acc = steps.iter().any(|s| matches!(s, MmioWrite::Acc { .. } | MmioWrite::WriteU32 { .. }));
            if has_acc {
                writeln!(output, "\tPUSH ACC").expect("save incoming ACC across immediate writes");
            }
            // EALLOW-protected registers (SysCtrl/GpioCtrl/PieCtrl) live at
            // 0x7000-0x70FF.  Auto-wrap the whole sequence in EALLOW/EDIS
            // if any step touches that range.
            let needs_eallow = steps.iter().any(|s| {
                let a = match s {
                    MmioWrite::Imm { addr, .. } => *addr,
                    MmioWrite::Acc { addr } => *addr,
                    MmioWrite::Modify { addr, .. } => *addr,
                    MmioWrite::WriteU32 { addr } => *addr,
                    MmioWrite::ReadIndirect => return false,
                };
                (0x7000..=0x70FF).contains(&a)
            });
            if needs_eallow {
                writeln!(output, "\tEALLOW").expect("auto EALLOW wrap");
            }
            for step in steps {
                let (addr, val) = match step {
                    MmioWrite::Imm { addr, val } => (*addr, Some(*val)),
                    MmioWrite::Acc { addr } => (*addr, None),
                    MmioWrite::Modify { addr, mask, bits } => {
                        let not_mask = !mask & 0xFFFF;
                        writeln!(
                            output,
                            "\tMOVL XAR4, #0x{addr:04X}\n\tMOV AL, *XAR4\n\tMOV AH, #0\n\tAND ACC, #0x{not_mask:04X}\n\tOR ACC, #0x{bits:04X}\n\tMOV *XAR4, AL"
                        )
                        .expect("write MMIO read-modify-write");
                        continue;
                    }
                    MmioWrite::WriteU32 { addr } => {
                        writeln!(
                            output,
                            "\tPOP ACC\n\tMOVL XAR4, #0x{addr:04X}\n\tMOV *XAR4, AL\n\tMOV *+XAR4[1], AH"
                        )
                        .expect("write MMIO 32-bit store from incoming ACC");
                        continue;
                    }
                    MmioWrite::ReadIndirect => {
                        // Indirect load: address already in XAR4, read to AL.
                        // Used by InputConfig::read / adc_result where the
                        // address is computed at runtime (e.g. index*2 + base).
                        writeln!(output, "\tMOV AL, *XAR4")
                            .expect("write MMIO indirect load");
                        continue;
                    }
                };
                match val {
                    Some(v) => writeln!(
                        output,
                        "\tMOVL XAR4, #0x{addr:04X}\n\tMOVB AL, #0x{v:04X}\n\tMOV *XAR4, AL"
                    )
                    .expect("write MMIO immediate store"),
                    None => writeln!(
                        output,
                        "\tPOP ACC\n\tMOVL XAR4, #0x{addr:04X}\n\tMOV *XAR4, AL"
                    )
                    .expect("write MMIO ACC store"),
                };
            }
            if needs_eallow {
                writeln!(output, "\tEDIS").expect("auto EDIS unwrap");
            }
        }
        MirOperation::Max | MirOperation::Min => {
            let condition = match operation {
                MirOperation::Max => "HI",
                MirOperation::Min => "LOS",
                _ => unreachable!(),
            };
            writeln!(
                output,
                "\tMOVZ AR6, AL\n\tMOV AL, AH\n\tCMP AL, AR6\n\tB c28x_mir_done_{index}, {condition}\n\tMOV AL, AR6\nc28x_mir_done_{index}:"
            ).expect("write comparison");
        }
    }
    writeln!(output, "\tLRETR").expect("write return");
    if matches!(operation, MirOperation::OwnershipApplication) {
        writeln!(output, "\t.sect \".data\"\n\t.global owner_peripherals\n\t.global owner_gpio34\nowner_peripherals: .word 0\nowner_gpio34: .word 0\n\t.sect \".text\"")
            .expect("write Rust ownership state words");
    }
}

impl Callbacks for C28xCallbacks {
    fn after_analysis<'tcx>(
        &mut self,
        _compiler: &interface::Compiler,
        tcx: TyCtxt<'tcx>,
    ) -> Compilation {
        if let Some(output) = self.asm_output.as_mut() {
            writeln!(
                output,
                "; Generated from rustc optimized MIR.\n\t.sect \".text\""
            )
            .expect("write assembly header");
        }
        let mut emitted = 0usize;
        let mut unsupported_exports = Vec::new();
        for local_def_id in tcx.mir_keys(()) {
            let def_id = local_def_id.to_def_id();
            if !matches!(tcx.def_kind(def_id), DefKind::Fn | DefKind::AssocFn) {
                continue;
            }
            if tcx.is_foreign_item(def_id) {
                continue;
            }
            if let Some(only) = &self.only_export {
                if !only.split(',').any(|name| tcx.item_name(def_id).as_str() == name.trim()) {
                    continue;
                }
            }
            let body = tcx.optimized_mir(def_id);
            writeln!(self.mir_output, "function {}", tcx.def_path_str(def_id))
                .expect("write MIR function header");
            writeln!(self.mir_output, "{body:#?}").expect("write MIR body");
            if let Some(operation) = classify_mir_function(tcx, def_id, body) {
                // PAC `apply`/helper functions share the Rust item name
                // (`apply`, `ack`, ...); give each lowered MMIO sequence a
                // unique C28x symbol.  Typed up-count apply also gets a stable
                // alias so the control loop can LCR it directly.
                let path = tcx.def_path_str(def_id);
                let name = if matches!(operation, MirOperation::MmioWriteSequence(_)) {
                    if path.contains("UpCountConfig") {
                        "c28x_mir_upcount_apply".to_owned()
                    } else if path.contains("PeriodicStart") {
                        "c28x_mir_periodic_start".to_owned()
                    } else {
                        format!("c28x_mir_mmio_{emitted}")
                    }
                } else {
                    tcx.item_name(def_id).as_str().to_owned()
                };
                if let Some(output) = self.asm_output.as_mut() {
                    emit_mir_function(output, &name, &operation, emitted);
                }
                emitted += 1;
                writeln!(self.mir_output, "c28x-codegen: emitted {name}")
                    .expect("write codegen report");
            } else if tcx.codegen_fn_attrs(def_id).contains_extern_indicator() {
                let name = tcx.item_name(def_id).as_str().to_owned();
                writeln!(self.mir_output, "c28x-codegen: unsupported {name}")
                    .expect("write unsupported report");
                unsupported_exports.push(name);
            }
        }
        if let Some(output) = self.asm_output.as_mut() {
            writeln!(
                output,
                "\n\t.battr \"c28xabi\", Tag_File, 1, Tag_float_args(0)\n\t.battr \"c28xabi\", Tag_File, 1, Tag_double_args(0)\n\t.end"
            ).expect("write assembly footer");
        }
        if !unsupported_exports.is_empty() {
            tcx.dcx().err(format!(
                "C28x MIR lowering is not implemented for exported function(s): {}",
                unsupported_exports.join(", ")
            ));
        }
        // Guard: when the caller pins an export via C28X_MIR_ONLY_EXPORT but no
        // function matched that name, the loop above silently emits nothing
        // (only the .text header + .end footer land in the asm file) while
        // still exiting 0. That pushes the failure to link time, far from the
        // real mistake. Fail loudly here instead.
        if let Some(only) = &self.only_export {
            if emitted == 0 && unsupported_exports.is_empty() {
                tcx.dcx().err(format!(
                    "C28x MIR backend: requested export(s) '{}' not found in crate. \
                     Check the #[no_mangle] extern \"C\" function name in your source \
                     against C28X_MIR_ONLY_EXPORT.",
                    only
                ));
            }
        }
        Compilation::Stop
    }
}

fn main() {
    let mut driver_arguments = env::args().collect::<Vec<_>>();
    let output_path = env::var_os("C28X_MIR_OUTPUT")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("c28x.mir.txt"));
    let output = File::create(&output_path).expect("create C28X_MIR_OUTPUT file");
    let asm_output = env::var_os("C28X_MIR_ASM_OUTPUT")
        .map(|path| File::create(path).expect("create C28X_MIR_ASM_OUTPUT file"));
    let mut callbacks = C28xCallbacks {
        mir_output: output,
        asm_output,
        only_export: env::var("C28X_MIR_ONLY_EXPORT").ok(),
    };

    driver_arguments.push("--crate-type=lib".to_owned());
    driver_arguments.push("--emit=metadata".to_owned());
    rustc_driver::run_compiler(&driver_arguments, &mut callbacks);
}
