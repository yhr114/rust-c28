#![no_std]
// The LLVM direct-object bus (feature "direct-obj-mmio") lowers MMIO through
// `core::intrinsics::volatile_*`; the gate is scoped to that feature so host
// tests and the audited MIR route keep compiling without it.
#![cfg_attr(all(not(test), feature = "direct-obj-mmio"), feature(core_intrinsics))]

// C2000 EALLOW/EDIS leaf functions from crates/c28x-rt/asm.s, used by the
// direct-object MMIO bus in pac.rs (protected 0x7000-0x70FF writes) and by
// the PAC ffi target path.  Declared once at the crate root; pac.rs reaches
// them through `super::`.
#[cfg(all(not(test), feature = "direct-obj-mmio"))]
unsafe extern "C" {
    fn eallow_inst();
    fn edis_inst();
    /// Paints the whole RAMSTACK region (0x0100..0x0400) with a 0xBEEF
    /// sentinel using registers only, so the post-run JTAG scan can measure how
    /// deep the ISR ever pushed.  Implemented in crates/c28x-rt/asm.s.
    fn c28x_rt_fill_stack_sentinel();
    /// Reads CPU Timer0 TIML (0x0C00), used to time the ISR body.
    fn c28x_rt_read_timer0_tim() -> u16;
}

#[cfg(feature = "arithmetic")]
mod arithmetic;
pub mod pac;
use crate::pac::ffi;

/// Minimal panic handler for the standalone `bare-mmio-business` image.
///
/// With checks enabled (`-Coverflow-checks=yes -Cdebug-assertions=yes`) the
/// compiler emits panic paths (`rust_begin_unwind`); without a handler the
/// link fails with an unresolved symbol.  This handler mirrors `panic-c28x`:
/// disable interrupts and spin so the debugger can halt and inspect.  It is
/// gated to the business feature so it never clashes with `panic-c28x` in the
/// Cargo path, and off in host tests (std provides the handler there).
/// Set to a non-zero magic by the panic handler so the verifier can tell a
/// panic apart from any other hang (e.g. a lost interrupt).  Zero == no panic.
#[cfg(all(feature = "bare-mmio-business", not(test)))]
#[unsafe(no_mangle)]
pub static mut PANIC_FLAG: u16 = 0;

/// Magic written by the panic handler.
#[cfg(all(feature = "bare-mmio-business", not(test)))]
pub const PANIC_MAGIC: u16 = 0xDEAD;

#[cfg(all(feature = "bare-mmio-business", not(test)))]
#[panic_handler]
fn business_panic(_info: &core::panic::PanicInfo) -> ! {
    // Record the panic where the verifier can read it.  This target has no
    // inline asm and no formatting, so only a fixed magic is written; the PC
    // is left to the debugger.  Inline asm for DINT is unsupported here, so a
    // panic in the control ISR simply freezes it (the trampoline never returns
    // to clear TIF / ack PIE) -- the frozen ticks plus PANIC_FLAG identify it.
    unsafe {
        core::ptr::write_volatile(core::ptr::addr_of_mut!(PANIC_FLAG), PANIC_MAGIC);
    }
    loop {
        core::hint::spin_loop();
    }
}

/// RAM-only zero-C compiler experiment using the normal Safe HAL GPIO API.
#[cfg(feature = "bare-mmio")]
#[unsafe(no_mangle)]
pub extern "C" fn rust_safe_gpio34_low() {
    let Some(mut peripherals) = Peripherals::take() else { return };
    let Ok(mut pin) = peripherals.gpio.output::<34>() else { return };
    #[cfg(feature = "bare-mmio-negative")]
    pin.set_high();
    #[cfg(not(feature = "bare-mmio-negative"))]
    pin.set_low();
}

/// Exclusivity self-check for the interrupt-safe one-time take.
///
/// The second `Peripherals::take()` and the second `gpio.output::<34>()` must
/// both fail; only when they do is GPIO34 driven low.  The hardware readback
/// (GPIO34 low + program at idle) therefore proves the ownership latch rejects
/// a duplicate take and the pin claim rejects a duplicate claim.
#[cfg(feature = "bare-mmio-exclusive")]
#[unsafe(no_mangle)]
pub extern "C" fn rust_safe_gpio34_exclusive() {
    let Some(mut peripherals) = Peripherals::take() else { return };
    // A second take must be rejected by the one-time latch.
    if Peripherals::take().is_some() {
        return;
    }
    let Ok(mut pin) = peripherals.gpio.output::<34>() else { return };
    // A second claim of the same pin must be rejected.
    if peripherals.gpio.output::<34>().is_ok() {
        return;
    }
    pin.set_low();
}

/// Set by the Timer0 ISR; a 16-bit store is atomic on C28x.
#[cfg(feature = "bare-mmio-timer")]
static mut TIMER0_FIRED: u16 = 0;

/// Rust body of the Timer0 (TINT0) interrupt. The c28x-rt `TINT0_ISR`
/// trampoline (crates/c28x-rt/interrupts.s) saves the context, calls this,
/// clears TCR.TIF and acknowledges PIE group 1, then IRETs.
#[cfg(feature = "bare-mmio-timer")]
#[unsafe(no_mangle)]
pub extern "C" fn rust_timer0_isr() {
    // SAFETY: only the ISR writes this flag; the volatile store prevents the
    // main loop's volatile load from being optimised away.
    unsafe { core::ptr::write_volatile(core::ptr::addr_of_mut!(TIMER0_FIRED), 1) };
}

/// Timer0 interrupt self-check entry (runs as `main` under the c28x-rt startup).
///
/// Starts Timer0 periodic, enables the CPU interrupt line through the Safe HAL,
/// and drives GPIO34 low once the TINT0 ISR has run.  The DSS readback
/// (GPIO34 low + program at idle) proves the fully automatic interrupt path.
#[cfg(feature = "bare-mmio-timer")]
#[unsafe(no_mangle)]
pub extern "C" fn main() -> ! {
    let Some(mut peripherals) = Peripherals::take() else {
        loop {}
    };
    let Ok(timer) = peripherals.timer0.start_periodic::<1>() else {
        loop {}
    };
    timer.enable_interrupt();
    let Ok(mut pin) = peripherals.gpio.output::<34>() else {
        loop {}
    };
    loop {
        // SAFETY: a volatile 16-bit load observes the ISR's store.
        if unsafe { core::ptr::read_volatile(core::ptr::addr_of!(TIMER0_FIRED)) } != 0 {
            pin.set_low();
            loop {}
        }
    }
}

// ---------------------------------------------------------------------------
// Integrated business loop: ADC -> compute -> PWM, plus a SCI status link and
// a Timer0 interrupt that keeps the whole chain running.
// ---------------------------------------------------------------------------

/// ePWM1 period used by the integrated business loop, in TBCLK ticks.
#[cfg(feature = "bare-mmio-business")]
pub const BUSINESS_PWM_PERIOD_TICKS: u16 = 1000;

/// Full scale of the 12-bit ADC, i.e. the largest raw sample.
#[cfg(feature = "bare-mmio-business")]
pub const BUSINESS_ADC_FULL_SCALE: u16 = 4095;

/// Maps a raw 12-bit sample to a compare value: `raw * period / 4095`.
///
/// A real `u32` multiply and divide, so the control loop exercises the
/// `__udivmodsi4` runtime helper on every tick.  Out-of-range samples (the ADC
/// timeout marker `0xFFFF`) clamp to full scale instead of wrapping.
#[cfg(feature = "bare-mmio-business")]
pub fn business_duty_for(raw: u16) -> u16 {
    let clamped = if raw > BUSINESS_ADC_FULL_SCALE {
        BUSINESS_ADC_FULL_SCALE
    } else {
        raw
    };
    ((u32::from(clamped) * u32::from(BUSINESS_PWM_PERIOD_TICKS)) / u32::from(BUSINESS_ADC_FULL_SCALE))
        as u16
}

/// The closed-loop application used by the joint hardware validation.
///
/// Shape of a real motor-control program: the periodic interrupt samples the
/// ADC, derives a duty, writes the PWM compare and exchanges a status byte on
/// the SCI link, while the main loop stays alive in parallel.  Everything the
/// application touches is the safe HAL; the only unsafe code is the handle
/// hand-off to the ISR, and it is confined to this module.
#[cfg(all(feature = "bare-mmio-business", feature = "direct-obj-mmio", not(test)))]
mod business {
    use super::*;

    /// SCI divisor: LSPCLK / (8 * 35) = 107 kbaud at 30 MHz LSPCLK.
    const SCI_BAUD_DIV: u16 = 35;
    /// Send one status byte every N control ticks.
    const FRAME_EVERY: u16 = 4;

    static mut PWM: Option<Pwm1Output<BUSINESS_PWM_PERIOD_TICKS>> = None;
    static mut ADC: Option<ConfiguredAdc<0>> = None;
    /// Serial link: SCI-A 8N1 at LSPCLK/(8*35). Every frame is verified through
    /// SCICTL2.TXRDY before and after the write, which is the strongest claim
    /// available without a peer (the internal loopbacks of both SCI and SPI
    /// were measured dead on this board).
    static mut LINK: Option<SciLink<SCI_BAUD_DIV>> = None;
    static mut MAIN_LOOPS: u16 = 0;

    /// Counters read back over JTAG through one symbol.  Layout v2 (20 words)
    /// supports a long run (32-bit totals) and a host-injected fault window:
    ///
    /// ```text
    ///  [0]  ticks_lo              [1]  ticks_hi            ticks = lo + hi*65536
    ///  [2]  raw (last valid)      [3]  duty (last CMPA written)
    ///  [4]  sci_ok                [5]  sci_err
    ///  [6]  adc_err (timeouts)    [7]  main_loops_lo (liveness)
    ///  [8]  last_status           [9]  raw_this_tick
    /// [10]  ok_samples_lo        [11]  ok_samples_hi
    /// [12]  SCICTL2 (CPU read)   [13]  ADCCTL1 (CPU read)
    ///  [14]  fault_state (0 none, 1 window active, 2 recovered)
    ///  [15]  fault_window_remaining
    ///  [16]  fault_request  <- host writes 1 over JTAG to inject a fault window
    ///  [17]  fault_window_size (constant, for the verifier)
    ///  [18]  fault_count (number of windows opened; supports repeated recovery)
    ///  [19]  report_magic (0xBEEF, proves the block was read coherently)
    ///  [20]  isr_min_cycles (fastest ISR body, in SYSCLK cycles)
    ///  [21]  isr_max_cycles (worst-case ISR body, for real-time headroom)
    ///  [22]  tz_ost_count (hardware one-shot trips forced by fault injection)
    ///  [23]  tz_flags (last TZFLG read; bit2 = OST latched)
    ///  [24]  adc_clkdiv2 (ADCCTL2.CLKDIV2EN: 1 => ADCCLK = SYSCLK/2)
    ///  [25]  adc_eoc_count (samples whose EOC was observed => fresh)
    ///  [26]  sci_lb_tx (loopback self-test bytes sent)
    ///  [27]  sci_lb_rx (loopback self-test bytes received)
    ///  [28]  sci_lb_mismatch (loopback bytes that differed)
    ///  [29]  adc_offtrim_before (ADCOFFTRIM before Device_cal)
    ///  [30]  adc_offtrim_after  (ADCOFFTRIM after Device_cal)
    ///  [31]  sci_fifo_rx (FIFO-mode loopback bytes read)
    ///  [32]  sci_fifo_mismatch (FIFO-mode loopback mismatches)
    ///  [33]  sci_timeout_ok (1 = bounded RX wait timed out without hanging)
    ///  [34..41] sci_fifo_byte[0..7] (FIFO-mode received bytes, for diagnosis)
    /// ```
    ///
    /// [12]/[13] exist to compare the CPU-side peripheral read with a JTAG
    /// read of the same register: the ISR reported "not ready" while JTAG
    /// showed TXRDY/ADCBSY in the ready state, so the two paths must be
    /// measured on the same run.
    #[unsafe(no_mangle)]
    pub static mut HW_BUSINESS_REPORT: [u16; 42] = [0; 42];

    /// Timer0 period in SYSCLK cycles (PRD + 1); the ISR timing wraps at this.
    const BUSINESS_TIMER_CYCLES: i32 = 60_001;

    /// Length of the simulated sensor dropout, in control ticks.  Chosen long
    /// enough (0.2 s) to be unambiguous in the counters, short enough that the
    /// post-fault steady state dominates a 30 s run.
    const FAULT_WINDOW: u16 = 200;
    const REPORT_MAGIC: u16 = 0xBEEF;

    #[inline]
    fn store(index: usize, value: u16) {
        // SAFETY: index is a literal in this module and each slot has exactly
        // one writer (the ISR, or the main loop for MAIN_LOOPS).
        unsafe {
            core::intrinsics::volatile_store(
                core::ptr::addr_of_mut!(HW_BUSINESS_REPORT[index]),
                value,
            )
        };
    }

    #[inline]
    fn load(index: usize) -> u16 {
        // SAFETY: see store().
        unsafe { core::intrinsics::volatile_load(core::ptr::addr_of!(HW_BUSINESS_REPORT[index])) }
    }

    #[inline]
    fn bump(index: usize) {
        store(index, load(index).wrapping_add(1));
    }

    /// Read the 32-bit control-tick counter ([0] low, [1] high).
    #[inline]
    fn tick_count() -> u32 {
        u32::from(load(0)) | (u32::from(load(1)) << 16)
    }

    /// Increment the 32-bit control-tick counter without a 16-bit wrap.
    #[inline]
    fn bump_ticks() {
        let lo = load(0);
        if lo == 0xFFFF {
            store(0, 0);
            store(1, load(1).wrapping_add(1));
        } else {
            store(0, lo.wrapping_add(1));
        }
    }

    /// Increment the 32-bit successful-sample counter ([10] low, [11] high).
    #[inline]
    fn bump_ok() {
        let lo = load(10);
        if lo == 0xFFFF {
            store(10, 0);
            store(11, load(11).wrapping_add(1));
        } else {
            store(10, lo.wrapping_add(1));
        }
    }

    /// One control tick, called from the TINT0 trampoline.  The trampoline
    /// clears TCR.TIF and acknowledges PIE group 1 after this returns.
    pub(super) fn on_tick() {
        // ISR timing: snapshot the free-running Timer0 down-counter first.
        let t_entry = unsafe { c28x_rt_read_timer0_tim() };

        // 0. Fault injection.  The host writes [16] = 1 over JTAG while the
        //    target is halted; this edge opens a window of FAULT_WINDOW ticks
        //    during which the ADC is treated as a failed sample.  The control
        //    loop must keep ticking, keep the SCI link alive, and re-sync once
        //    the window closes -- that is the recovery property under test.
        //    Re-arming is allowed whenever no window is active (state 0 or 2),
        //    so the host can inject repeatedly and require N recoveries.
        if load(16) != 0 && load(14) != 1 {
            store(14, 1);
            store(15, FAULT_WINDOW);
            store(16, 0);
            store(18, load(18).wrapping_add(1));
            // Hardware fault protection: a real one-shot trip forces the PWM
            // output low (TZCTL was configured to force low in run()).
            unsafe { ffi::f28035_epwm1_tz_ost_force() };
            store(22, load(22).wrapping_add(1));
        }
        let mut fault_active = load(14) == 1;
        if fault_active {
            let rem = load(15);
            if rem == 0 {
                // Window exhausted: close it *before* sampling, so this tick is
                // already a normal one and exactly FAULT_WINDOW ticks fail.
                store(14, 2);
                fault_active = false;
                // Release the hardware trip so the output resumes tracking.
                unsafe { ffi::f28035_epwm1_tz_ost_clear() };
            } else {
                store(15, rem - 1);
            }
        }

        let ticks = tick_count();

        // 1. ADC -> raw sample.
        if fault_active {
            // Simulated sensor dropout: hold the last duty, count a timeout,
            // and mark this tick's raw invalid.  No PWM write, so the actuator
            // keeps its last good command (graceful degradation).
            store(9, 0xFFFF);
            store(2, 0xFFFF);
            bump(6);
        } else {
            // Keep the earlier FFI form as an explicit diagnostic control.
            #[cfg(feature = "business-direct-ffi")]
            let raw = unsafe { ffi::f28035_adc_sample(0) };
            #[cfg(not(feature = "business-direct-ffi"))]
            let raw = unsafe {
                match ADC.as_mut() { Some(adc) => adc.sample(), None => 0xFFFF }
            };
            // Diagnostics: the raw value of *this* tick, recorded before the
            // timeout test, so a wrong classification is visible over JTAG.
            store(9, raw);
            if raw == 0xFFFF {
                bump(6);
                store(2, raw);
            } else {
                bump_ok();
                let duty = business_duty_for(raw);
                // SAFETY: slots are initialized before enabling this ISR and
                // have no concurrent main-loop accesses after initialization.
                #[cfg(feature = "business-direct-ffi")]
                unsafe { ffi::f28035_epwm1_set_compare(duty) };
                #[cfg(not(feature = "business-direct-ffi"))]
                unsafe { if let Some(pwm) = PWM.as_mut() { pwm.set_compare(duty); } };
                store(2, raw);
                store(3, duty);
            }
        }

        // 2. Communication: one status byte every FRAME_EVERY ticks.  This is
        //    deliberately independent of the ADC path, so a sensor fault must
        //    not silence the link.
        if ticks % u32::from(FRAME_EVERY) == 0 {
            let status = (ticks & 0x00ff) as u8;
            #[cfg(feature = "business-direct-ffi")]
            let sent = sci_send_byte(status);
            #[cfg(not(feature = "business-direct-ffi"))]
            let sent = unsafe {
                match LINK.as_mut() { Some(link) => link.send(status), None => false }
            };
            if sent {
                bump(4);
            } else {
                bump(5);
            }
            store(8, u16::from(status));
        }

        // 3. Diagnostics: what the CPU sees in the peripheral frames.
        // SAFETY: fixed SCI-A / ADC status registers.
        store(12, unsafe { ffi::f28035_diag_wait_txrdy() });
        store(13, unsafe { ffi::f28035_diag_asm_scictl2() });
        // Trip-zone status: accumulate "OST ever latched" (bit2) so the
        // verifier can prove the hardware trip actually fired, while the final
        // TZFLG read proves it was released after recovery.
        store(23, load(23) | (unsafe { ffi::f28035_epwm1_tz_flags() } & 0x0004));
        // ADC clock divider and fresh-sample (EOC) accounting.
        store(24, unsafe { ffi::f28035_adc_clkdiv2_enabled() });
        store(25, unsafe { ffi::f28035_adc_eoc_count() });

        // 4. Report main-loop liveness, then count this tick.
        // SAFETY: the main loop is the only writer of MAIN_LOOPS.
        store(7, unsafe {
            core::intrinsics::volatile_load(core::ptr::addr_of!(MAIN_LOOPS))
        });
        bump_ticks();

        // ISR execution time = entry TIML - exit TIML (down-counter).  The
        // counter reloads at 0, so a wrapped measurement adds one period.
        let t_exit = unsafe { c28x_rt_read_timer0_tim() };
        let mut dur = i32::from(t_entry) - i32::from(t_exit);
        if dur < 0 {
            dur += BUSINESS_TIMER_CYCLES;
        }
        let dur = dur as u16;
        let min = load(20);
        if min == 0 || dur < min {
            store(20, dur);
        }
        if dur > load(21) {
            store(21, dur);
        }
    }

    /// Application entry: build the chain, hand the handles to the ISR, then
    /// keep the main loop alive.
    pub(super) fn run() -> ! {
        // Stack high-water instrumentation.  Paint the whole RAMSTACK region
        // (0x0100..0x0400) with 0xBEEF *before* any stack-consuming work, using
        // the register-only asm helper.  The post-run JTAG scan finds the
        // highest word that is no longer 0xBEEF, which is the deepest the
        // stack (including the ISR) ever grew.
        // SAFETY: the helper only writes the RAMSTACK window and clobbers no
        // Rust state; the region is reserved for the stack by ram.cmd.
        unsafe { c28x_rt_fill_stack_sentinel() };
        store(17, FAULT_WINDOW);
        store(19, REPORT_MAGIC);
        // Board bring-up: clocks + ADC power-up. The c28x-rt startup does not
        // do this, and an unpowered ADC never asserts EOC.
        system_init();
        // Record the ADC offset trim before/after Device_cal (run inside
        // system_init -> power_up).  They differ iff the factory calibration
        // was actually loaded.
        store(29, unsafe { ffi::f28035_adc_offtrim_before() });
        store(30, unsafe { ffi::f28035_adc_offtrim_after() });
        // Let the ADC reference/bandgap settle before the first conversion
        // (the PAC sequence deliberately leaves the settle delay to the app).
        delay_us(1000);
        delay_us(1000);
        let Some(mut peripherals) = Peripherals::take() else {
            loop {}
        };
        let Ok(adc) = peripherals.adc.into_soc0::<0, 6>() else {
            loop {}
        };
        let Ok(mut pwm) = peripherals.pwm1.configure::<BUSINESS_PWM_PERIOD_TICKS>() else {
            loop {}
        };
        pwm.set_compare(0);
        pwm.enable();
        // Fault protection: a trip forces the PWM output low (fail-safe).  The
        // ISR forces/clears the one-shot trip on fault injection/recovery.
        unsafe { ffi::f28035_epwm1_tz_force_low_config() };
        let Ok(link) = peripherals.sci_a.configure::<SCI_BAUD_DIV>() else {
            loop {}
        };
        // SCI real TX/RX: internal-loopback content self-test (send a known
        // pattern, require the exact bytes back), then restore normal 8N1 for
        // the business transmit path.
        unsafe { ffi::f28035_sci_loopback_selftest() };
        store(26, unsafe { ffi::f28035_sci_loopback_tx() });
        store(27, unsafe { ffi::f28035_sci_loopback_rx() });
        store(28, unsafe { ffi::f28035_sci_loopback_mismatch() });
        store(31, unsafe { ffi::f28035_sci_fifo_rx() });
        store(32, unsafe { ffi::f28035_sci_fifo_mismatch() });
        store(33, unsafe { ffi::f28035_sci_timeout_ok() });
        let mut fi: u16 = 0;
        while fi < 8 {
            store(34 + fi as usize, unsafe { ffi::f28035_sci_fifo_byte(fi) });
            fi += 1;
        }
        unsafe { ffi::f28035_sci_configure(SCI_BAUD_DIV) };
        let Ok(timer) = peripherals.timer0.start_periodic::<1>() else {
            loop {}
        };
        // SAFETY: the ISR cannot run before enable_interrupt(), and these are
        // the only writes to the three slots.
        unsafe {
            ADC = Some(adc);
            PWM = Some(pwm);
            LINK = Some(link);
        }
        // CPU IER group 1 + EINT: the handler needs no register access.
        timer.enable_interrupt();
        loop {
            // SAFETY: single writer; the volatile store keeps the loop alive
            // and visible to the ISR-side report.
            unsafe {
                let slot = core::ptr::addr_of_mut!(MAIN_LOOPS);
                let next = core::intrinsics::volatile_load(slot).wrapping_add(1);
                core::intrinsics::volatile_store(slot, next);
            }
        }
    }
}

/// Integrated business loop entry (runs as `main` under the c28x-rt startup).
#[cfg(all(feature = "bare-mmio-business", feature = "direct-obj-mmio", not(test)))]
#[unsafe(no_mangle)]
pub extern "C" fn main() -> ! {
    business::run()
}

/// Rust body of the TINT0 interrupt for the integrated business loop.
#[cfg(all(feature = "bare-mmio-business", feature = "direct-obj-mmio", not(test)))]
#[unsafe(no_mangle)]
pub extern "C" fn rust_timer0_isr() {
    business::on_tick();
}

/// Exercises GPIO0 MUX routing and GPIO34 input configuration/data sampling via
/// the same Safe HAL API used by applications. The caller checks register
/// snapshots; bit 4 carries the observed pin level without assuming an
/// external board strap.
#[cfg(feature = "bare-mmio")]
#[unsafe(no_mangle)]
pub extern "C" fn rust_safe_gpio_probe() -> u16 {
    let Some(mut peripherals) = Peripherals::take() else { return 0 };
    if peripherals.gpio.set_mux::<0, 1>().is_err() { return 0 }
    let mux_one = peripherals.gpio.mux::<0>();
    if peripherals.gpio.set_mux::<0, 0>().is_err() { return 0 }
    let mux_zero = peripherals.gpio.mux::<0>();
    let Ok(input) = peripherals.gpio.input_with::<34, true, 2>() else { return 0 };
    mux_one | (mux_zero << 2) | (u16::from(input.read()) << 4)
}

#[cfg(feature = "arithmetic")]
pub use arithmetic::rust_add;

/// Initializes the clocks, watchdog configuration, and GPIO defaults by
/// calling the original TI F2803x support code.
#[inline(always)]
pub fn system_init() {
    // Safety: the C bridge has no arguments and is intended to run once during
    // startup, before peripheral handles are created.
    unsafe { ffi::f28035_system_init() }
}

/// Busy-waits for the requested number of microseconds using the TI delay
/// routine. Call this only after [`system_init`] has configured the clock.
#[inline(always)]
pub fn delay_us(microseconds: u16) {
    // Safety: the C bridge takes a value, accesses no caller memory, and
    // performs a bounded delay for every u16 argument.
    unsafe { ffi::f28035_delay_us(microseconds) }
}

/// A resource-construction error returned by the safe HAL.
///
/// These are the *recoverable* failures: a caller can inspect the pin number and
/// retry or fail soft instead of aborting.  Compile-time-illegal constants
/// (e.g. `PIN > 44`) are still rejected by a checked `const` assertion at the
/// call site, so they never reach this type.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum HalError {
    /// The pin is already owned by another handle derived from the same
    /// [`Gpio`] root.  Taking it again would alias the same physical pin.
    PinAlreadyTaken(u16),
    /// The low-level implementation reported that the resource could not be configured
    /// (invalid mode, reserved encoding, or a readback mismatch).
    ConfigurationRejected(u16),
    /// A bounded hardware poll expired: no end-of-conversion flag, or no
    /// received character.  Reported instead of returning a stale value so a
    /// control loop can distinguish "sample failed" from "sample was zero".
    Timeout,
}

/// The single ownership root for F28035 peripherals.
pub struct Peripherals {
    pub gpio: Gpio,
    pub adc: AdcResults,
    pub timer0: Timer0,
    pub pwm1: Pwm1,
    pub spi_b: SpiB,
    pub sci_a: SciA,
    pub i2c_a: I2cA,
    pub lin_a: LinA,
    pub ecap1: ECap1,
    pub eqep1: EQep1,
}

impl Peripherals {
    #[inline(always)]
    pub fn take() -> Option<Self> {
        // Safety: ownership is acquired during startup, before interrupts are
        // enabled. The C bridge's flag is not a general atomic primitive.
        let available = unsafe { ffi::f28035_take_peripherals() };
        (available != 0).then_some(Self {
            gpio: Gpio { used: [0; 3] },
            adc: AdcResults(()),
            timer0: Timer0(()),
            pwm1: Pwm1(()),
            spi_b: SpiB(()),
            sci_a: SciA(()),
            i2c_a: I2cA(()),
            lin_a: LinA(()),
            ecap1: ECap1(()),
            eqep1: EQep1(()),
        })
    }
}

/// GPIO root.  Each physical pin may be derived into **exactly one** handle:
/// three 16-bit occupancy words track which of the 45 F28035 pins are claimed.
///
/// Taking a pin that is already claimed returns [`HalError::PinAlreadyTaken`]
/// instead of silently aliasing the pin — this is the resource-conflict case
/// the borrow checker cannot express, so the HAL detects it at the boundary.
pub struct Gpio {
    used: [u16; 3],
}

impl Gpio {
    /// Marks `pin` as claimed and returns true if it was free; otherwise
    /// leaves the mask unchanged and returns false.
    #[inline(always)]
    fn claim(&mut self, pin: u16) -> bool {
        let word = usize::from(pin / 16);
        let bit = 1u16 << (pin % 16);
        if self.used[word] & bit != 0 {
            return false;
        }
        self.used[word] |= bit;
        true
    }

    #[inline(always)]
    fn release(&mut self, pin: u16) {
        let word = usize::from(pin / 16);
        let bit = 1u16 << (pin % 16);
        self.used[word] &= !bit;
    }

    #[inline(always)]
    fn is_claimed(&self, pin: u16) -> bool {
        let word = usize::from(pin / 16);
        let bit = 1u16 << (pin % 16);
        self.used[word] & bit != 0
    }

    /// Claims `PIN` as an output.  Fails if `PIN` is already owned by this
    /// root, or if the low-level register configuration rejects it.
    #[inline(always)]
    pub fn output<const PIN: u16>(&mut self) -> Result<OutputPin<PIN>, HalError> {
        assert!(PIN <= 44, "PIN <= 44");
        if !self.claim(PIN) {
            return Err(HalError::PinAlreadyTaken(PIN));
        }
        #[cfg(all(not(test), feature = "direct-obj-mmio"))]
        let configured = match pac::gpio::output_config(PIN) {
            Some(config) => {
                let mut bus = pac::C28xMmio;
                // SAFETY: PIN is in range, and the PAC brackets protected writes.
                unsafe { config.apply(&mut bus) };
                1
            }
            None => 0,
        };
        #[cfg(any(test, not(feature = "direct-obj-mmio")))]
        let configured = unsafe { ffi::f28035_gpio_make_output(PIN) };
        if configured == 0 {
            self.release(PIN);
            return Err(HalError::ConfigurationRejected(PIN));
        }
        Ok(OutputPin::<PIN>(()))
    }

    /// Claims `PIN` as a plain input (sync-qualified, pull-up enabled).
    #[inline(always)]
    pub fn input<const PIN: u16>(&mut self) -> Result<InputPin<PIN>, HalError> {
        self.input_with::<PIN, true, { Qualification::Sync as u16 }>()
    }

    /// Claims `PIN` as an input with an explicit pull-up and qualification.
    #[inline(always)]
    pub fn input_with<const PIN: u16, const PULLUP: bool, const QUALIFICATION: u16>(
        &mut self,
    ) -> Result<InputPin<PIN>, HalError> {
        assert!(PIN <= 44, "PIN <= 44");
        assert!(QUALIFICATION <= 3, "QUALIFICATION <= 3");
        if !self.claim(PIN) {
            return Err(HalError::PinAlreadyTaken(PIN));
        }
        #[cfg(all(not(test), feature = "direct-obj-mmio"))]
        let configured = {
            let qualification = match QUALIFICATION {
                1 => pac::gpio::Qualification::Sample3,
                2 => pac::gpio::Qualification::Sample6,
                3 => pac::gpio::Qualification::Async,
                _ => pac::gpio::Qualification::Sync,
            };
            match pac::gpio::input_config(PIN, PULLUP, qualification) {
                Some(config) => {
                    let mut bus = pac::C28xMmio;
                    // SAFETY: PIN and qualification are checked above.
                    unsafe { config.apply(&mut bus) };
                    1
                }
                None => 0,
            }
        };
        #[cfg(any(test, not(feature = "direct-obj-mmio")))]
        let configured =
            unsafe { ffi::f28035_gpio_make_input(PIN, u16::from(PULLUP), QUALIFICATION) };
        if configured == 0 {
            self.release(PIN);
            return Err(HalError::ConfigurationRejected(PIN));
        }
        Ok(InputPin::<PIN>(()))
    }

    /// Routes `PIN` into external-interrupt line 1.  The pin is claimed so it
    /// cannot also be used as a plain output/input handle.
    #[inline(always)]
    pub fn xint1<const PIN: u16, const EDGE: u16>(
        &mut self,
    ) -> Result<ExternalInterrupt<1, PIN, EDGE>, HalError> {
        self.xint::<1, PIN, EDGE>()
    }

    /// Routes `PIN` into external-interrupt line 2.
    #[inline(always)]
    pub fn xint2<const PIN: u16, const EDGE: u16>(
        &mut self,
    ) -> Result<ExternalInterrupt<2, PIN, EDGE>, HalError> {
        self.xint::<2, PIN, EDGE>()
    }

    #[inline(always)]
    fn xint<const LINE: u16, const PIN: u16, const EDGE: u16>(
        &mut self,
    ) -> Result<ExternalInterrupt<LINE, PIN, EDGE>, HalError> {
        assert!(LINE == 1 || LINE == 2, "LINE is 1 or 2");
        assert!(PIN <= 31, "PIN <= 31");
        assert!(
            EDGE == 0 || EDGE == 1 || EDGE == 3,
            "EDGE == 0 || EDGE == 1 || EDGE == 3"
        );
        if !self.claim(PIN) {
            return Err(HalError::PinAlreadyTaken(PIN));
        }
        // Safety: XINT1/XINT2 only accept GPIO0..31 and the edge is validated.
        let configured = unsafe { ffi::f28035_gpio_configure_xint(LINE, PIN, EDGE) };
        if configured == 0 {
            self.release(PIN);
            return Err(HalError::ConfigurationRejected(PIN));
        }
        Ok(ExternalInterrupt::<LINE, PIN, EDGE>(()))
    }

    /// Selects the peripheral function for PIN via its MUX field
    /// (0 = GPIO, 1..3 = peripheral function).  The MUX routing is
    /// allowed only while `PIN` has no live GPIO or XINT handle. This does
    /// not consume a claim slot; a later input/output claim restores GPIO
    /// mode through the selected PAC or bridge path.
    #[inline(always)]
    pub fn set_mux<const PIN: u16, const FUNC: u16>(&mut self) -> Result<(), HalError> {
        assert!(PIN <= 44, "PIN <= 44");
        assert!(FUNC <= 3, "FUNC <= 3");
        if self.is_claimed(PIN) {
            return Err(HalError::PinAlreadyTaken(PIN));
        }
        #[cfg(all(not(test), feature = "direct-obj-mmio"))]
        let configured = match pac::gpio::mux_field(PIN) {
            Some(field) => {
                let mut bus = pac::C28xMmio;
                // SAFETY: the PAC brackets the protected MUX write.
                unsafe { u16::from(field.set(&mut bus, FUNC)) }
            }
            None => 0,
        };
        #[cfg(any(test, not(feature = "direct-obj-mmio")))]
        let configured = unsafe { ffi::f28035_gpio_set_mux(PIN, FUNC) };
        if configured == 0 {
            return Err(HalError::ConfigurationRejected(PIN));
        }
        Ok(())
    }

    /// Reads back the current MUX field for PIN (0 = GPIO, 1..3 = peripheral
    /// function), mirroring 28035_gpio_mux.
    #[inline(always)]
    pub fn mux<const PIN: u16>(&self) -> u16 {
        assert!(PIN <= 44, "PIN <= 44");
        #[cfg(all(not(test), feature = "direct-obj-mmio"))]
        {
            let Some(field) = pac::gpio::mux_field(PIN) else { return 0xffff };
            let mut bus = pac::C28xMmio;
            // SAFETY: the PAC field names a readable MUX register.
            unsafe { field.read(&mut bus) }
        }
        #[cfg(any(test, not(feature = "direct-obj-mmio")))]
        unsafe { ffi::f28035_gpio_mux(PIN) }
    }
}

#[repr(u16)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Qualification {
    Sync = 0,
    Sample3 = 1,
    Sample6 = 2,
    Async = 3,
}

#[repr(u16)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum InterruptEdge {
    Falling = 0,
    Rising = 1,
    Both = 3,
}

/// A typed F28035 GPIO output handle selected at compile time.
///
/// Constructed only through [`Gpio::output`], which claims the pin so no
/// second handle for the same pin can exist while this one is alive.
///
/// A handle cannot be copied or cloned:
///
/// ```compile_fail
/// use f28035_safe_hal::OutputPin;
/// fn duplicate(pin: OutputPin<34>) {
///     let other = pin;
///     pin.set_low();
///     drop(other);
/// }
/// ```
///
/// ```compile_fail
/// use f28035_safe_hal::OutputPin;
/// fn duplicate(pin: OutputPin<34>) {
///     let _other = pin.clone();
/// }
/// ```
///
/// ```compile_fail
/// use f28035_safe_hal::OutputPin;
/// let _forged = OutputPin::<34>(());
/// ```
#[derive(Debug, PartialEq, Eq)]
pub struct OutputPin<const PIN: u16>(());

impl<const PIN: u16> OutputPin<PIN> {
    #[inline(always)]
    pub fn set(&mut self, high: bool) {
        #[cfg(all(not(test), feature = "direct-obj-mmio"))]
        {
            if let Some(command) = pac::gpio::output_command(PIN) {
                let mut bus = pac::C28xMmio;
                // SAFETY: only a pin claimed by Gpio::output constructs this type.
                unsafe {
                    if high { command.set(&mut bus) } else { command.clear(&mut bus) }
                }
            }
        }
        #[cfg(any(test, not(feature = "direct-obj-mmio")))]
        unsafe { ffi::f28035_gpio_write(PIN, u16::from(high)) }
    }

    #[inline(always)]
    pub fn set_high(&mut self) {
        self.set(true);
    }

    #[inline(always)]
    pub fn set_low(&mut self) {
        self.set(false);
    }

    #[inline(always)]
    pub fn toggle(&mut self) {
        #[cfg(all(not(test), feature = "direct-obj-mmio"))]
        {
            if let Some(command) = pac::gpio::output_command(PIN) {
                let mut bus = pac::C28xMmio;
                // SAFETY: the GPIO TOGGLE register is a write-only command.
                unsafe { command.toggle(&mut bus) }
            }
        }
        #[cfg(any(test, not(feature = "direct-obj-mmio")))]
        unsafe { ffi::f28035_gpio_toggle(PIN) }
    }

    /// Reads back the output latch for this pin.  For pure GPIO (mux=0) the
    /// low-level path returns the DATA bit; the value is stable between commands.
    #[inline(always)]
    pub fn is_high(&self) -> bool {
        #[cfg(all(not(test), feature = "direct-obj-mmio"))]
        {
            let Some(sample) = pac::gpio::input_sample(PIN) else { return false };
            let mut bus = pac::C28xMmio;
            // SAFETY: the pin was validated before this handle existed.
            unsafe { sample.read(&mut bus) }
        }
        #[cfg(any(test, not(feature = "direct-obj-mmio")))]
        unsafe { ffi::f28035_gpio_read(PIN) != 0 }
    }

    #[inline(always)]
    pub fn is_low(&self) -> bool {
        !self.is_high()
    }

    /// Reconfigures this pin as an input, consuming the output handle.
    ///
    /// Releases the exclusive claim on `PIN` and re-claims it as an input
    /// (pull-up enabled, Sync qualification).  The returned [`InputPin`] is the
    /// only live handle for the pin, so no two handles ever alias it.
    #[inline(always)]
    pub fn into_input(self, gpio: &mut Gpio) -> Result<InputPin<PIN>, HalError> {
        gpio.release(PIN);
        gpio.input::<PIN>()
    }
}

/// A typed F28035 GPIO input handle selected at compile time.
///
/// Constructed only through [`Gpio::input`]/[`Gpio::input_with`].
///
/// ```compile_fail
/// use f28035_safe_hal::InputPin;
/// fn duplicate(pin: InputPin<34>) {
///     let other = pin;
///     let _ = pin.is_high();
///     drop(other);
/// }
/// ```
///
/// ```compile_fail
/// use f28035_safe_hal::InputPin;
/// let _forged = InputPin::<34>(());
/// ```
///
/// An input handle cannot drive the pin: only [`OutputPin`] exposes the
/// output commands, so a C program that writes GPBDAT through an "input"
/// handle has no Safe Rust equivalent.
///
/// ```compile_fail
/// use f28035_safe_hal::InputPin;
/// fn drive_from_input(pin: &mut InputPin<34>) {
///     pin.set_low();
/// }
/// ```
#[derive(Debug, PartialEq, Eq)]
pub struct InputPin<const PIN: u16>(());

impl<const PIN: u16> InputPin<PIN> {
    #[inline(always)]
    pub fn read(&self) -> bool {
        #[cfg(all(not(test), feature = "direct-obj-mmio"))]
        {
            let Some(sample) = pac::gpio::input_sample(PIN) else { return false };
            let mut bus = pac::C28xMmio;
            // SAFETY: only a validated GPIO pin can construct this handle.
            unsafe { sample.read(&mut bus) }
        }
        #[cfg(any(test, not(feature = "direct-obj-mmio")))]
        unsafe { ffi::f28035_gpio_read(PIN) != 0 }
    }

    #[inline(always)]
    pub fn is_high(&self) -> bool {
        self.read()
    }

    #[inline(always)]
    pub fn is_low(&self) -> bool {
        !self.read()
    }

    /// Reconfigures this pin as an output, consuming the input handle.
    ///
    /// Releases the exclusive claim on `PIN` and re-claims it as an output.
    /// The returned [`OutputPin`] is the only live handle for the pin, so no
    /// two handles ever alias it.
    #[inline(always)]
    pub fn into_output(self, gpio: &mut Gpio) -> Result<OutputPin<PIN>, HalError> {
        gpio.release(PIN);
        gpio.output::<PIN>()
    }
}

/// A claimed XINT1/XINT2 route.  Constructed only through
/// [`Gpio::xint1`]/[`Gpio::xint2`].
///
/// ```compile_fail
/// use f28035_safe_hal::ExternalInterrupt;
/// fn duplicate(route: ExternalInterrupt<1, 2, 1>) {
///     let other = route;
///     let _ = route.line();
///     drop(other);
/// }
/// ```
///
/// ```compile_fail
/// use f28035_safe_hal::ExternalInterrupt;
/// let _forged = ExternalInterrupt::<1, 2, 1>(());
/// ```
#[derive(Debug, PartialEq, Eq)]
pub struct ExternalInterrupt<const LINE: u16, const PIN: u16, const EDGE: u16>(());

impl<const LINE: u16, const PIN: u16, const EDGE: u16> ExternalInterrupt<LINE, PIN, EDGE> {
    /// The external-interrupt line number this handle owns.
    pub const fn line(&self) -> u16 {
        LINE
    }
}

/// Timer0 ownership token, available only from [`Peripherals::take`].
///
/// ```compile_fail
/// use f28035_safe_hal::Timer0;
/// let _forged = Timer0(());
/// ```
///
/// ```compile_fail
/// use f28035_safe_hal::Timer0;
/// fn duplicate(timer: Timer0) {
///     let other = timer;
///     let _again = timer;
///     drop(other);
/// }
/// ```
#[derive(Debug, PartialEq, Eq)]
pub struct Timer0(());
#[derive(Debug, PartialEq, Eq)]
pub struct ArmedTimer0<const PERIOD_MS: u16>(());
/// Active Timer0 ownership cannot be duplicated.
///
/// ```compile_fail
/// use f28035_safe_hal::PeriodicTimer0;
/// fn duplicate(timer: PeriodicTimer0<10>) {
///     let other = timer;
///     let _again = timer;
///     drop(other);
/// }
/// ```
#[derive(Debug, PartialEq, Eq)]
pub struct PeriodicTimer0<const PERIOD_MS: u16>(());
#[derive(Debug, PartialEq, Eq)]
pub struct StoppedTimer0<const PERIOD_MS: u16>(());

impl Timer0 {
    /// Starts Timer0 in one-shot mode.  The period range (1..=1000 ms) is a
    /// compile-time constant and is rejected by the const check below; a
    /// runtime configuration failure from the C bridge is surfaced as
    /// [`HalError::ConfigurationRejected`] and returns the timer so the caller
    /// keeps ownership.
    #[inline(always)]
    pub fn start_once<const PERIOD_MS: u16>(
        self,
    ) -> Result<ArmedTimer0<PERIOD_MS>, (Timer0, HalError)> {
        assert!(PERIOD_MS > 0 && PERIOD_MS <= 1000, "PERIOD_MS is 1..=1000");
        // Safety: the period is range checked and Timer0 is uniquely owned.
        let started = unsafe { ffi::f28035_timer0_start_once_ms(PERIOD_MS) };
        if started == 0 {
            return Err((self, HalError::ConfigurationRejected(PERIOD_MS)));
        }
        Ok(ArmedTimer0(()))
    }

    /// Starts Timer0 in periodic mode.  See [`Timer0::start_once`] for the
    /// error semantics: the period const is rejected at compile time, while a
    /// bridge configuration failure returns the timer to the caller.
    #[inline(always)]
    pub fn start_periodic<const PERIOD_MS: u16>(
        self,
    ) -> Result<PeriodicTimer0<PERIOD_MS>, (Timer0, HalError)> {
        assert!(PERIOD_MS > 0 && PERIOD_MS <= 1000, "PERIOD_MS is 1..=1000");
        // Safety: the period is range checked and Timer0 is uniquely owned.
        let started = unsafe { ffi::f28035_timer0_start_periodic_ms(PERIOD_MS) };
        if started == 0 {
            return Err((self, HalError::ConfigurationRejected(PERIOD_MS)));
        }
        Ok(PeriodicTimer0(()))
    }
}

impl<const PERIOD_MS: u16> PeriodicTimer0<PERIOD_MS> {
    #[inline(always)]
    pub fn interrupt_count(&self) -> u16 {
        // Safety: an aligned u16 load is atomic on C28x.
        unsafe { ffi::f28035_timer0_interrupts() }
    }

    /// Enables the Timer0 CPU interrupt line (PIE group 1) and global
    /// interrupts so the `TINT0` handler runs every period.
    ///
    /// [`Timer0::start_periodic`] already enabled PIEIER1 INT7 and the timer
    /// TIE; this only finishes the CPU-side enable, so the application never
    /// touches IER or the `EINT` instruction itself.  Call
    /// [`timer0_interrupt_ack`] at the top of the handler.
    #[inline(always)]
    pub fn enable_interrupt(&self) {
        // Safety: this handle uniquely owns Timer0 and the period was checked.
        unsafe { ffi::f28035_enable_timer0_interrupt() };
    }

    #[inline(always)]
    pub fn stop(self) -> StoppedTimer0<PERIOD_MS> {
        // Safety: this handle uniquely owns Timer0.
        unsafe { ffi::f28035_timer0_stop() }
        StoppedTimer0(())
    }
}

/// Acknowledge the Timer0 PIE group-1 line from the `TINT0` handler.
///
/// Call this once at the top of the `#[interrupt] fn TINT0()` body; it replaces
/// the manual `PieCtrlRegs.PIEACK.all = PIEACK_GROUP1` write, so the handler
/// only contains the application logic.
#[inline(always)]
pub fn timer0_interrupt_ack() {
    // Safety: acknowledging the PIE line is idempotent and only touches PIEACK.
    unsafe { ffi::f28035_timer0_ack() };
}

impl<const PERIOD_MS: u16> StoppedTimer0<PERIOD_MS> {
    /// Changes the period of a stopped timer.  A bridge configuration failure
    /// returns the (still stopped) timer to the caller.
    #[inline(always)]
    pub fn set_period<const NEW_PERIOD_MS: u16>(
        self,
    ) -> Result<StoppedTimer0<NEW_PERIOD_MS>, (StoppedTimer0<PERIOD_MS>, HalError)> {
        assert!(
            NEW_PERIOD_MS > 0 && NEW_PERIOD_MS <= 1000,
            "NEW_PERIOD_MS is 1..=1000"
        );
        // Safety: Timer0 is stopped and uniquely owned by this handle.
        let configured = unsafe { ffi::f28035_timer0_set_period_ms(NEW_PERIOD_MS) };
        if configured == 0 {
            return Err((self, HalError::ConfigurationRejected(NEW_PERIOD_MS)));
        }
        Ok(StoppedTimer0::<NEW_PERIOD_MS>(()))
    }

    #[inline(always)]
    pub fn restart(self) -> PeriodicTimer0<PERIOD_MS> {
        // Safety: only a stopped, uniquely owned timer constructs this type.
        unsafe { ffi::f28035_timer0_restart() }
        PeriodicTimer0(())
    }
}

/// ePWM1 ownership token, available only from [`Peripherals::take`].
///
/// ```compile_fail
/// use f28035_safe_hal::Pwm1;
/// let _forged = Pwm1(());
/// ```
#[derive(Debug, PartialEq, Eq)]
pub struct Pwm1(());
/// Configured ePWM1 ownership cannot be duplicated.
///
/// ```compile_fail
/// use f28035_safe_hal::Pwm1Output;
/// fn duplicate(pwm: Pwm1Output<4095>) {
///     let other = pwm;
///     let _again = pwm;
///     drop(other);
/// }
/// ```
#[derive(Debug, PartialEq, Eq)]
pub struct Pwm1Output<const PERIOD_TICKS: u16>(());

impl Pwm1 {
    /// Configures ePWM1 for up-counting with the given period.  A nonzero
    /// period is a compile-time check; a bridge configuration failure is
    /// surfaced as [`HalError::ConfigurationRejected`] and the handle is
    /// returned so the caller keeps ownership of ePWM1.
    #[inline(always)]
    pub fn configure<const PERIOD_TICKS: u16>(
        self,
    ) -> Result<Pwm1Output<PERIOD_TICKS>, (Pwm1, HalError)> {
        assert!(PERIOD_TICKS > 0, "PERIOD_TICKS > 0");
        // Safety: ePWM1 is uniquely owned and the period is nonzero.
        let configured = unsafe { ffi::f28035_epwm1_configure(PERIOD_TICKS) };
        if configured == 0 {
            return Err((self, HalError::ConfigurationRejected(PERIOD_TICKS)));
        }
        Ok(Pwm1Output(()))
    }
}

impl<const PERIOD_TICKS: u16> Pwm1Output<PERIOD_TICKS> {
    #[inline(always)]
    pub fn set_compare(&mut self, compare_ticks: u16) {
        // Safety: the bridge clamps the compare value to the configured period.
        unsafe { ffi::f28035_epwm1_set_compare(compare_ticks) }
    }

    /// Reads back the active CMPA value (clamped to the period at write time).
    #[inline(always)]
    pub fn get_compare(&self) -> u16 {
        // Safety: fixed ePWM1 register; the bridge returns the latched value.
        unsafe { ffi::f28035_epwm1_compare() }
    }

    /// Makes ePWM1 emit a start-of-conversion pulse to the ADC on every
    /// CTR = ZERO, so the sample instant is locked to the PWM period.
    ///
    /// Pair with [`ConfiguredAdc::use_pwm1_soca_trigger`]; the control ISR then
    /// only reads the finished conversion instead of forcing one.
    #[inline(always)]
    pub fn enable_adc_trigger(&mut self) {
        // Safety: this handle uniquely owns ePWM1.
        unsafe { ffi::f28035_epwm1_enable_soca_trigger() };
    }

    /// Starts driving the configured waveform on EPWM1A.
    #[inline(always)]
    pub fn enable(&mut self) {
        // Safety: ePWM1 is uniquely owned by this handle.
        unsafe { ffi::f28035_epwm1_enable() };
    }

    /// Disables the ePWM1A output and forces it to the idle state.
    #[inline(always)]
    pub fn disable(&mut self) {
        // Safety: ePWM1 is uniquely owned by this handle.
        unsafe { ffi::f28035_epwm1_disable() };
    }

    /// The configured period in ticks.  Compile-time constant.
    pub const fn period_ticks(&self) -> u16 {
        PERIOD_TICKS
    }
}

/// A handle to the ADC result registers.  Constructed only by
/// [`Peripherals::take`] so there is a single owner of the result file.
/// ADC ownership token, available only from [`Peripherals::take`].
///
/// ```compile_fail
/// use f28035_safe_hal::AdcResults;
/// let _forged = AdcResults(());
/// ```
#[derive(Debug, PartialEq, Eq)]
pub struct AdcResults(());

/// SOC0 configured for one ADC channel. The channel is carried in the type,
/// so sampling cannot accidentally select a different channel.
///
/// ```compile_fail
/// use f28035_safe_hal::Peripherals;
/// let peripherals = Peripherals::take().unwrap();
/// let mut adc0 = peripherals.adc.into_soc0::<0, 7>().unwrap();
/// let _ = adc0.sample::<1>(); // The configured handle has no channel argument.
/// ```
///
/// ```compile_fail
/// use f28035_safe_hal::Peripherals;
/// let peripherals = Peripherals::take().unwrap();
/// let adc0 = peripherals.adc.into_soc0::<0, 7>().unwrap();
/// let _ = adc0.sample(); // Sampling requires exclusive mutable access.
/// ```
#[derive(Debug, PartialEq, Eq)]
pub struct ConfiguredAdc<const CHANNEL: u16>(AdcResults);

impl AdcResults {
    /// Consumes the unconfigured ADC owner and returns a channel-bound SOC0
    /// handle. On configuration failure, ownership is returned to the caller.
    #[inline(always)]
    pub fn into_soc0<const CHANNEL: u16, const ACQPS: u16>(
        mut self,
    ) -> Result<ConfiguredAdc<CHANNEL>, (Self, HalError)> {
        match self.configure_soc0::<CHANNEL, ACQPS>() {
            Ok(()) => Ok(ConfiguredAdc(self)),
            Err(error) => Err((self, error)),
        }
    }

    /// Configures SOC0 for a channel. Prefer [`Self::into_soc0`] when the
    /// application can transfer ownership into a channel-bound handle.
    #[inline(always)]
    pub fn configure_soc0<const CHANNEL: u16, const ACQPS: u16>(&mut self) -> Result<(), HalError> {
        assert!(CHANNEL <= 15, "CHANNEL <= 15");
        assert!(ACQPS <= 63, "ACQPS <= 63");
        // Safety: both constants are checked and this handle uniquely owns ADC.
        let configured = unsafe { ffi::f28035_adc_configure_soc0(CHANNEL, ACQPS) };
        if configured == 0 {
            return Err(HalError::ConfigurationRejected(CHANNEL));
        }
        Ok(())
    }

    #[inline(always)]
    pub fn read<const INDEX: u16>(&self) -> u16 {
        assert!(INDEX <= 15, "INDEX <= 15");
        // Safety: the const-generic index is checked before crossing the FFI.
        unsafe { ffi::f28035_adc_result(INDEX) }
    }

    #[inline(always)]
    pub fn sample<const CHANNEL: u16>(&self) -> u16 {
        assert!(CHANNEL <= 15, "CHANNEL <= 15");
        // Safety: CHANNEL is validated and SOC0 is exclusively configured by
        // the uniquely owned ADC handle.
        unsafe { ffi::f28035_adc_sample(CHANNEL) }
    }

    #[inline(always)]
    pub fn timeout_count(&self) -> u16 {
        // Safety: an aligned u16 load is atomic on C28x.
        unsafe { ffi::f28035_adc_timeouts() }
    }

    /// Reads a result register by a *runtime* index (0..=15). Invalid indices
    /// return 0 rather than wrapping around to a different result register.
    #[inline(always)]
    pub fn read_channel(&self, channel: u16) -> u16 {
        if channel > 15 {
            return 0;
        }
        // Safety: the result index was validated before crossing the FFI.
        unsafe { ffi::f28035_adc_result(channel) }
    }
}

impl<const CHANNEL: u16> ConfiguredAdc<CHANNEL> {
    /// Samples the channel chosen when SOC0 was configured. A mutable borrow
    /// prevents two safe callers from starting overlapping conversions.
    #[inline(always)]
    pub fn sample(&mut self) -> u16 {
        // Safety: `ConfiguredAdc` is created only after valid SOC0 setup.
        unsafe { ffi::f28035_adc_sample(CHANNEL) }
    }

    #[inline(always)]
    pub fn timeout_count(&self) -> u16 {
        self.0.timeout_count()
    }

    /// Switches SOC0 to the ePWM1 SOCA hardware trigger.
    ///
    /// After this the conversion starts at every PWM zero event, so the ISR
    /// must call [`Self::sample_triggered`] instead of [`Self::sample`].
    #[inline(always)]
    pub fn use_pwm1_soca_trigger(&mut self) {
        // Safety: SOC0 is exclusively configured by this handle.
        unsafe { ffi::f28035_adc_soc0_use_epwm1_soca() };
    }

    /// Reads the conversion started by the hardware trigger.
    ///
    /// Returns the 12-bit result, or `0xFFFF` when no end-of-conversion flag
    /// arrived before the bounded wait expired.
    #[inline(always)]
    pub fn sample_triggered(&mut self) -> u16 {
        // Safety: this handle owns SOC0 and the trigger is configured.
        unsafe { ffi::f28035_adc_wait_result() }
    }
}

/// A uniquely owned SPI-B controller handle.
///
/// The current implementation keeps the audited register sequences in the
/// C-ABI bridge, but the application no longer calls those bridge symbols
/// directly.  Each method names the legal operation in Rust and validates the
/// small amount of static configuration that can be expressed today.
#[derive(Debug, PartialEq, Eq)]
pub struct SpiB(());

/// A completed SPI-B internal-loopback exercise. The C case uses 8-bit data.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct SpiLoopback<const CHAR_BITS: u16>(());

/// A configured SCI-A link (8-bit characters, 1 stop bit, no parity).
///
/// The transmitter is verified end to end: every [`send`](Self::send) waits for
/// `SCICTL2.TXRDY` before writing `SCITXBUF`. TXRDY is clear while the buffer
/// still holds a byte, so a successful return means the previous character had
/// already moved into the shifter and this one was accepted. Receiving needs a
/// peer or a loopback jumper; `SCIRXST.RXRDY` is not part of the send path.
///
/// ```compile_fail
/// use f28035_safe_hal::SciLink;
/// let _forged = SciLink(());
/// ```
#[derive(Debug, PartialEq, Eq)]
pub struct SciLink<const BAUD_DIV: u16>(());

impl<const BAUD_DIV: u16> SciLink<BAUD_DIV> {
    /// Sends one byte; returns `true` when the transmitter accepted it.
    ///
    /// The completion indication is a plain `bool`. B-1's compiler regression
    /// separately covers bool and tagged Result method returns; the historical
    /// wrapper failure alone did not establish a general enum ABI defect.
    ///
    /// Delegates to [`sci_send_byte`], which is the form verified on hardware.
    pub fn send(&mut self, byte: u8) -> bool {
        sci_send_byte(byte)
    }
}

/// Sends one byte through the configured SCI-A transmitter.
///
/// [`SciLink::send`] delegates here. This free form is also available as a
/// diagnostic control for the method path; the old difference between those
/// forms was insufficient evidence of a general zero-sized-handle ABI defect.
///
/// Returns `true` when the transmitter accepted the byte (`SCICTL2.TXRDY` was
/// set before the write).
#[inline(never)]
pub fn sci_send_byte(byte: u8) -> bool {
    // Safety: the caller configured SCI-A (see `SciA::configure`).
    (unsafe { ffi::f28035_sci_send(u16::from(byte)) }) != 0
}

/// A configured SPI-B hardware-loopback link (8-bit characters).
///
/// The module loops its own shift-register output back into the receiver
/// (`SPICCR.SPILBK`), so a business path can prove real serial transmission
/// with no pins and no external wiring.
///
/// ```compile_fail
/// use f28035_safe_hal::SpiLink;
/// let _forged = SpiLink(());
/// ```
#[derive(Debug, PartialEq, Eq)]
pub struct SpiLink<const CHAR_BITS: u16>(());

impl<const CHAR_BITS: u16> SpiLink<CHAR_BITS> {
    /// Exchanges one frame and returns the byte received back.
    ///
    /// Returns [`HalError::Timeout`] when the transfer never completes, so a
    /// dead link cannot be mistaken for a valid `0x00`.
    #[inline(always)]
    pub fn transfer(&mut self, byte: u8) -> Result<u8, HalError> {
        // Safety: this handle was produced by `SpiB::loopback_link`, so the
        // block is configured in hardware loopback mode.
        let received = unsafe { ffi::f28035_spi_loopback_xfer(u16::from(byte)) };
        if received & 0x8000 != 0 {
            return Err(HalError::Timeout);
        }
        Ok((received & 0x00ff) as u8)
    }
}

impl SpiB {
    #[inline(always)]
    pub fn reg_readback(&mut self) {
        pac::f28035_spi_reg_if_rw_basic();
    }

    /// Configures SPI-B for the hardware internal loopback and returns a link
    /// handle that can exchange 8-bit frames.
    ///
    /// The configuration is the audited register sequence (8-bit characters,
    /// master, `SPILBK`, FIFO words) that the C bridge and the host-verified
    /// [`pac::spi::run_internal_loopback`] share, so a caller never writes a
    /// register. Only 8-bit characters are supported; other widths are
    /// rejected at compile time.
    #[inline(always)]
    pub fn loopback_link<const CHAR_BITS: u16>(&mut self) -> Result<SpiLink<CHAR_BITS>, HalError> {
        assert!(CHAR_BITS == 8, "SPI loopback uses 8-bit characters");
        // Safety: this handle uniquely owns SPI-B.
        if unsafe { ffi::f28035_spi_loopback_configure() } == 0 {
            return Err(HalError::ConfigurationRejected(CHAR_BITS));
        }
        Ok(SpiLink(()))
    }

    /// Runs the SPI-B internal-loopback 8-bit exchange.
    ///
    /// An audited Rust port of this exact register sequence now lives at
    /// [`pac::spi::run_internal_loopback`] and is host-verified 1:1 against the
    /// C bridge (every failure-code branch asserted in the PAC host tests).
    /// Until the C28x backend lowers that sequence to target code, the target
    /// image still routes through the C bridge via
    /// [`pac::f28035_spi_internal_loopback_basic`] so the verified hardware
    /// behaviour is unchanged; the Rust sequence is the pending backend
    /// milestone.
    #[inline(always)]
    pub fn internal_loopback<const CHAR_BITS: u16>(&mut self) -> SpiLoopback<CHAR_BITS> {
        assert!(CHAR_BITS >= 1 && CHAR_BITS <= 16, "CHAR_BITS is 1..=16");
        assert!(CHAR_BITS == 8, "internal loopback C case uses 8-bit characters");
        pac::f28035_spi_internal_loopback_basic();
        SpiLoopback(())
    }

    #[inline(always)]
    pub fn triwire_loopback<const CHAR_BITS: u16>(&mut self) -> SpiLoopback<CHAR_BITS> {
        assert!(CHAR_BITS >= 1 && CHAR_BITS <= 16, "CHAR_BITS is 1..=16");
        assert!(CHAR_BITS == 8, "triwire C case uses 8-bit characters");
        pac::f28035_spi_triwire_loopback_basic();
        SpiLoopback(())
    }

    #[inline(always)]
    pub fn loopback_mode_matrix(&mut self) {
        pac::f28035_spi_loopback_mode_matrix_basic();
    }

    #[inline(always)]
    pub fn charlen_sweep(&mut self) {
        pac::f28035_spi_charlen_sweep_basic();
    }

    #[inline(always)]
    pub fn fifo_rx_boundary(&mut self) {
        pac::f28035_spi_fifo_rx_boundary_basic();
    }

    #[inline(always)]
    pub fn fifo_tx_boundary(&mut self) {
        pac::f28035_spi_fifo_tx_boundary_basic();
    }

    #[inline(always)]
    pub fn fifo_level_boundary(&mut self) {
        pac::f28035_spi_fifo_level_boundary_basic();
    }

    #[inline(always)]
    pub fn multiple_frame_loopback(&mut self) {
        pac::f28035_spi_multiple_frame_loopback_basic();
    }

    #[inline(always)]
    pub fn nonfifo_interrupt_flag(&mut self) {
        pac::f28035_spi_nonfifo_intflag_irq_basic();
    }
}

/// A uniquely owned SCI-A controller handle.
#[derive(Debug, PartialEq, Eq)]
pub struct SciA(());

/// Legacy result tag for SCI-A self-tests. The C cases do not program the
/// const parameters; use the explicit `*_self_test` methods for target builds.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct SciProfile<const BAUD_DIV: u16, const CHAR_BITS: u16>(());

impl SciA {
    /// Configures SCI-A as 8N1 at `LSPCLK / (8 * BAUD_DIV)` and returns a link
    /// handle.
    ///
    /// The bridge enables the SCI-A clock, routes GPIO28/GPIO29 to
    /// SCITXD/SCIRXD, programs the divisor and releases the software reset
    /// (`SWRESET = 0` is the operating state on F2803x; asserting it last would
    /// hold the module in reset). A zero divisor is rejected at compile time.
    #[inline(always)]
    pub fn configure<const BAUD_DIV: u16>(&mut self) -> Result<SciLink<BAUD_DIV>, HalError> {
        assert!(BAUD_DIV > 0, "BAUD_DIV > 0");
        // Safety: the divisor is nonzero and this handle uniquely owns SCI-A.
        if unsafe { ffi::f28035_sci_configure(BAUD_DIV) } == 0 {
            return Err(HalError::ConfigurationRejected(BAUD_DIV));
        }
        Ok(SciLink(()))
    }

    /// Runs the fixed SCI-A baud programming self-test in the C bridge.
    #[inline(always)]
    pub fn baud_program_self_test(&mut self) {
        pac::f28035_sci_baud_program_basic();
    }

    /// Runs the fixed SCI-A internal loopback self-test.
    #[inline(always)]
    pub fn internal_loopback_self_test(&mut self) {
        pac::f28035_sci_internal_loopback_basic();
    }

    /// Runs the fixed SCI-A loopback pattern self-test.
    #[inline(always)]
    pub fn loopback_data_pattern_self_test(&mut self) {
        pac::f28035_sci_loopback_data_pattern_basic();
    }

    #[inline(always)]
    pub fn configure_basic<const BAUD_DIV: u16, const CHAR_BITS: u16>(
        &mut self,
    ) -> SciProfile<BAUD_DIV, CHAR_BITS> {
        assert!(BAUD_DIV > 0, "BAUD_DIV > 0");
        assert!(CHAR_BITS >= 1 && CHAR_BITS <= 8, "CHAR_BITS is 1..=8");
        pac::f28035_sci_baud_program_basic();
        SciProfile(())
    }

    #[inline(always)]
    pub fn reg_readback(&mut self) {
        pac::f28035_sci_reg_if_rw_basic();
    }

    #[inline(always)]
    pub fn internal_loopback<const BAUD_DIV: u16, const CHAR_BITS: u16>(
        &mut self,
    ) -> SciProfile<BAUD_DIV, CHAR_BITS> {
        let profile = self.configure_basic::<BAUD_DIV, CHAR_BITS>();
        pac::f28035_sci_internal_loopback_basic();
        profile
    }

    #[inline(always)]
    pub fn loopback_data_pattern<const BAUD_DIV: u16, const CHAR_BITS: u16>(
        &mut self,
    ) -> SciProfile<BAUD_DIV, CHAR_BITS> {
        let profile = self.configure_basic::<BAUD_DIV, CHAR_BITS>();
        pac::f28035_sci_loopback_data_pattern_basic();
        profile
    }

    #[inline(always)]
    pub fn fifo_reset_then_loopback(&mut self) {
        pac::f28035_sci_fifo_reset_then_loopback_basic();
    }

    #[inline(always)]
    pub fn fifo_rx(&mut self) {
        pac::f28035_sci_fifo_rx_basic();
    }

    #[inline(always)]
    pub fn rx_ready_clears_on_read(&mut self) {
        pac::f28035_sci_rxrdy_clear_on_read_basic();
    }

    #[inline(always)]
    pub fn charlen_sweep(&mut self) {
        pac::f28035_sci_sciccr_charlen_sweep_basic();
    }

    #[inline(always)]
    pub fn stop_parity_charlen_sweep(&mut self) {
        pac::f28035_sci_stop2_parity_charlen_sweep_basic();
    }

    #[inline(always)]
    pub fn tx_ready_interrupt_nonfifo(&mut self) {
        pac::f28035_sci_txrdy_int_nonfifo_basic();
    }
}

/// A uniquely owned I2C-A master handle.
#[derive(Debug, PartialEq, Eq)]
pub struct I2cA(());

/// A 7-bit I2C slave address carried in the type system.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct I2cSlave<const ADDRESS: u16>(());

impl I2cA {
    #[inline(always)]
    pub fn slave<const ADDRESS: u16>(&mut self) -> I2cSlave<ADDRESS> {
        assert!(ADDRESS <= 0x7f, "ADDRESS is 7-bit");
        I2cSlave(())
    }

    #[inline(always)]
    fn fixed_case_slave<const ADDRESS: u16>(&mut self) -> I2cSlave<ADDRESS> {
        let slave = self.slave::<ADDRESS>();
        assert!(ADDRESS == 0x36, "I2C C cases use fixed address 0x36");
        slave
    }

    #[inline(always)]
    pub fn reg_readback_sweep(&mut self) {
        pac::f28035_i2c_reg_readback_sweep_basic();
    }

    #[inline(always)]
    pub fn master_write_1byte<const ADDRESS: u16>(&mut self) -> I2cSlave<ADDRESS> {
        let slave = self.fixed_case_slave::<ADDRESS>();
        pac::f28035_i2c_master_write_1byte_basic();
        slave
    }

    #[inline(always)]
    pub fn master_write_8byte_pattern<const ADDRESS: u16>(&mut self) -> I2cSlave<ADDRESS> {
        let slave = self.fixed_case_slave::<ADDRESS>();
        pac::f28035_i2c_master_write_8byte_pattern();
        slave
    }

    #[inline(always)]
    pub fn master_read_1byte<const ADDRESS: u16>(&mut self) -> I2cSlave<ADDRESS> {
        let slave = self.fixed_case_slave::<ADDRESS>();
        pac::f28035_i2c_master_read_1byte_basic();
        slave
    }

    #[inline(always)]
    pub fn master_read_8byte<const ADDRESS: u16>(&mut self) -> I2cSlave<ADDRESS> {
        let slave = self.fixed_case_slave::<ADDRESS>();
        pac::f28035_i2c_master_read_8byte_basic();
        slave
    }

    #[inline(always)]
    pub fn master_write_back_to_back<const ADDRESS: u16>(&mut self) -> I2cSlave<ADDRESS> {
        let slave = self.fixed_case_slave::<ADDRESS>();
        pac::f28035_i2c_master_write_back_to_back();
        slave
    }

    #[inline(always)]
    pub fn master_read_back_to_back<const ADDRESS: u16>(&mut self) -> I2cSlave<ADDRESS> {
        let slave = self.fixed_case_slave::<ADDRESS>();
        pac::f28035_i2c_master_read_back_to_back_basic();
        slave
    }

    #[inline(always)]
    pub fn master_write_then_read_4byte<const ADDRESS: u16>(&mut self) -> I2cSlave<ADDRESS> {
        let slave = self.fixed_case_slave::<ADDRESS>();
        pac::f28035_i2c_master_write_then_read_4byte_basic();
        slave
    }

    #[inline(always)]
    pub fn repeated_start_write_then_read_4byte<const ADDRESS: u16>(
        &mut self,
    ) -> I2cSlave<ADDRESS> {
        let slave = self.fixed_case_slave::<ADDRESS>();
        pac::f28035_i2c_master_repeated_start_write_then_read_4byte_basic();
        slave
    }

    #[inline(always)]
    pub fn addr_nack_stop<const ADDRESS: u16>(&mut self) -> I2cSlave<ADDRESS> {
        let slave = self.fixed_case_slave::<ADDRESS>();
        pac::f28035_i2c_master_addr_nack_stop_basic();
        slave
    }
}

/// A uniquely owned LIN-A controller handle.
#[derive(Debug, PartialEq, Eq)]
pub struct LinA(());

impl LinA {
    #[inline(always)]
    pub fn baud_program(&mut self) {
        pac::f28035_lin_baud_program_basic();
    }

    #[inline(always)]
    pub fn header_break_sync_master(&mut self) {
        pac::f28035_lin_header_break_sync_master_basic();
    }

    #[inline(always)]
    pub fn iodft_loopback(&mut self) {
        pac::f28035_lin_iodft_loopback_basic();
    }

    #[inline(always)]
    pub fn reg_readback(&mut self) {
        pac::f28035_lin_reg_if_rw_basic();
    }

    #[inline(always)]
    pub fn rx_checksum_length(&mut self) {
        pac::f28035_lin_rx_checksum_length_real_basic();
    }

    #[inline(always)]
    pub fn rx_count_boundary(&mut self) {
        pac::f28035_lin_rx_rxcnt_num_boundary_real_basic();
    }

    #[inline(always)]
    pub fn sci_multibuf_read_slot_sweep(&mut self) {
        pac::f28035_lin_sci_multibuf_rdslot_sweep_basic();
    }

    #[inline(always)]
    pub fn top_mode_loopback_power_cross(&mut self) {
        pac::f28035_lin_top_mode_loopback_power_cross_basic();
    }

    #[inline(always)]
    pub fn tx_checksum_extended(&mut self) {
        pac::f28035_lin_tx_checksum_ext_real_basic();
    }

    #[inline(always)]
    pub fn wakeup_break_flag_route(&mut self) {
        pac::f28035_lin_wakeup_break_flag_route_basic();
    }
}

/// A uniquely owned eCAP1 controller handle.
#[derive(Debug, PartialEq, Eq)]
pub struct ECap1(());

impl ECap1 {
    #[inline(always)]
    pub fn reg_readback(&mut self) {
        pac::f28035_ecap_reg_rw_smoke();
    }

    #[inline(always)]
    pub fn apwm_matrix(&mut self) {
        pac::f28035_ecap_apwm_matrix();
    }

    #[inline(always)]
    pub fn capture_single_edge(&mut self) {
        pac::f28035_ecap_capture_single_edge();
    }

    #[inline(always)]
    pub fn capture_dual_edge(&mut self) {
        pac::f28035_ecap_capture_dual_edge();
    }

    #[inline(always)]
    pub fn capture_quad_edge(&mut self) {
        pac::f28035_ecap_capture_quad_edge();
    }

    #[inline(always)]
    pub fn capture_continuous_wrap(&mut self) {
        pac::f28035_ecap_capture_continuous_wrap();
    }

    #[inline(always)]
    pub fn capture_counter_reset(&mut self) {
        pac::f28035_ecap_capture_counter_reset();
    }

    #[inline(always)]
    pub fn capture_prescale_div2(&mut self) {
        pac::f28035_ecap_capture_prescale_div2();
    }

    #[inline(always)]
    pub fn capture_wrap_matrix(&mut self) {
        pac::f28035_ecap_capture_wrap_matrix();
    }

    #[inline(always)]
    pub fn interrupt_integration(&mut self) {
        pac::f28035_ecap_interrupt_integration();
    }
}

/// A uniquely owned eQEP1 controller handle.
#[derive(Debug, PartialEq, Eq)]
pub struct EQep1(());

impl EQep1 {
    #[inline(always)]
    pub fn register_write_readback(&mut self) {
        pac::f28035_eqep_register_wr();
    }

    #[inline(always)]
    pub fn polarity_test(&mut self) {
        pac::f28035_eqep_polarity_test();
    }

    #[inline(always)]
    pub fn count_basic(&mut self) {
        pac::f28035_eqep_count_basic();
    }

    #[inline(always)]
    pub fn mode_test(&mut self) {
        pac::f28035_eqep_mode_test();
    }

    #[inline(always)]
    pub fn compare_output_pulse(&mut self) {
        pac::f28035_eqep_compare_output_pulse();
    }

    #[inline(always)]
    pub fn unit_timer(&mut self) {
        pac::f28035_eqep_unit_timer();
    }

    #[inline(always)]
    pub fn unit_timeout(&mut self) {
        pac::f28035_eqep_unit_timeout_test();
    }

    #[inline(always)]
    pub fn watchdog_timeout(&mut self) {
        pac::f28035_eqep_watchdog_timeout_test();
    }

    #[inline(always)]
    pub fn interrupt_gate(&mut self) {
        pac::f28035_eqep_interrupt_gate();
    }

    #[inline(always)]
    pub fn reset_fsm_matrix(&mut self) {
        pac::f28035_eqep_reset_fsm_matrix();
    }
}

/// embedded-hal trait implementations.
///
/// `OutputPin` / `InputPin` are infallible because all GPIO operations go
/// through a validated const-generic handle.  `StatefulOutputPin::is_set_high`
/// now reads back the GPIO output latch via the C bridge.
///
/// embedded-hal 1.0 trait implementations.
///
/// embedded-hal 1.0.0 exposes `digital` (OutputPin / StatefulOutputPin /
/// InputPin — no `v2` prefix) and `pwm::SetDutyCycle`, plus i2c/spi/delay.
/// Those traits all inherit from `ErrorType` (`type Error: Error`), so each
/// handle first implements `ErrorType` with `Infallible` (every GPIO/PWM op
/// goes through a validated const-generic handle and cannot fail), and then
/// the concrete trait.  1.0.0 has no `adc` / `timer` modules, so
/// `AdcResults` and `PeriodicTimer0` keep their native safe-HAL methods.
///
/// `StatefulOutputPin::is_set_high` reads back the GPIO output latch via the
/// C bridge; `SetDutyCycle` writes the real ePWM1 CMPA and reports the
/// configured period as `max_duty_cycle`.
///
/// ```no_run
/// use f28035_safe_hal::Peripherals;
///
/// fn drive_status_pin(mut peripherals: Peripherals) {
///     let mut pin = peripherals.gpio.output::<44>().unwrap();
///     embedded_hal::digital::OutputPin::set_high(&mut pin).unwrap();
/// }
/// ```
#[cfg(feature = "embedded-hal")]
mod hal_impl {
    use super::{InputPin, OutputPin, Pwm1Output};

    impl<const PIN: u16> embedded_hal::digital::ErrorType for OutputPin<PIN> {
        type Error = core::convert::Infallible;
    }

    impl<const PIN: u16> embedded_hal::digital::OutputPin for OutputPin<PIN> {
        fn set_high(&mut self) -> Result<(), Self::Error> {
            self.set_high();
            Ok(())
        }
        fn set_low(&mut self) -> Result<(), Self::Error> {
            self.set_low();
            Ok(())
        }
    }

    impl<const PIN: u16> embedded_hal::digital::StatefulOutputPin for OutputPin<PIN> {
        fn is_set_high(&mut self) -> Result<bool, Self::Error> {
            Ok(self.is_high())
        }
        fn is_set_low(&mut self) -> Result<bool, Self::Error> {
            Ok(self.is_low())
        }
    }

    impl<const PIN: u16> embedded_hal::digital::ErrorType for InputPin<PIN> {
        type Error = core::convert::Infallible;
    }

    impl<const PIN: u16> embedded_hal::digital::InputPin for InputPin<PIN> {
        fn is_high(&mut self) -> Result<bool, Self::Error> {
            // Disambiguate from the trait method of the same name: call the
            // inherent `bool`-returning read explicitly.
            Ok(InputPin::<PIN>::is_high(self))
        }
        fn is_low(&mut self) -> Result<bool, Self::Error> {
            Ok(InputPin::<PIN>::is_low(self))
        }
    }

    impl<const PERIOD: u16> embedded_hal::pwm::ErrorType for Pwm1Output<PERIOD> {
        type Error = core::convert::Infallible;
    }

    impl<const PERIOD: u16> embedded_hal::pwm::SetDutyCycle for Pwm1Output<PERIOD> {
        fn set_duty_cycle(&mut self, duty: u16) -> Result<(), Self::Error> {
            self.set_compare(duty);
            Ok(())
        }
        fn max_duty_cycle(&self) -> u16 {
            PERIOD
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{HalError, InterruptEdge, Peripherals, Qualification, ffi};

    fn fresh_peripherals() -> Peripherals {
        ffi::reset_peripherals();
        Peripherals::take().unwrap()
    }

    /// The business loop's ADC->duty mapping is pinned here so the hardware
    /// readback has a single reference formula (the DSS script mirrors it).
    #[cfg(feature = "bare-mmio-business")]
    #[test]
    fn business_duty_mapping_matches_expected_curve() {
        use super::{BUSINESS_ADC_FULL_SCALE, BUSINESS_PWM_PERIOD_TICKS, business_duty_for};
        assert_eq!(business_duty_for(0), 0);
        assert_eq!(business_duty_for(1), 0);
        assert_eq!(business_duty_for(2048), 500);
        assert_eq!(business_duty_for(BUSINESS_ADC_FULL_SCALE), BUSINESS_PWM_PERIOD_TICKS);
        // The ADC timeout marker clamps to full scale instead of wrapping.
        assert_eq!(business_duty_for(0xFFFF), BUSINESS_PWM_PERIOD_TICKS);
    }

    /// T2 proof: peripheral ownership is a singleton.  A second
    /// `Peripherals::take` returns `None` instead of aliasing the handles,
    /// so no two safe owners of the same peripheral root can exist.
    #[test]
    fn peripherals_can_only_be_taken_once() {
        let _first = fresh_peripherals();
        assert!(Peripherals::take().is_none());
    }

    #[test]
    fn valid_const_generic_resources_use_safe_handles() {
        let mut peripherals = fresh_peripherals();
        let mut pin = peripherals.gpio.output::<44>().unwrap();
        pin.set_high();
        assert!(pin.is_high());
        assert!(!pin.is_low());
        pin.set_low();
        assert!(pin.is_low());
        pin.toggle(); // low -> high
        assert!(pin.is_high());
        assert_eq!(peripherals.adc.read::<15>(), 0);
    }

    #[test]
    fn gpio_inputs_support_pullups_qualification_and_xint_tokens() {
        let mut peripherals = fresh_peripherals();
        let pin = peripherals
            .gpio
            .input_with::<1, true, { Qualification::Sample6 as u16 }>()
            .unwrap();
        assert!(pin.is_low());
        assert!(!pin.is_high());

        // Pin 1 is already claimed by the input handle above, so the XINT
        // routes use distinct pins (2 and 31) — claiming pin 1 as XINT1 is
        // intentionally rejected by the exclusivity mask.
        let _xint1 = peripherals
            .gpio
            .xint1::<2, { InterruptEdge::Falling as u16 }>()
            .unwrap();
        let _xint2 = peripherals
            .gpio
            .xint2::<31, { InterruptEdge::Both as u16 }>()
            .unwrap();
    }

    /// T1 proof: a pin can only be claimed once.  The second handle for the
    /// same physical pin is rejected with `PinAlreadyTaken` instead of
    /// aliasing it.
    #[test]
    fn same_pin_cannot_be_claimed_twice() {
        let mut peripherals = fresh_peripherals();
        let _out = peripherals.gpio.output::<5>().unwrap();
        let again = peripherals.gpio.output::<5>();
        assert_eq!(again, Err(HalError::PinAlreadyTaken(5)));

        // A different pin on the same root is still allowed.
        assert!(peripherals.gpio.output::<6>().is_ok());

        // An input handle for a pin already owned as an output conflicts too.
        assert_eq!(
            peripherals.gpio.input::<5>(),
            Err(HalError::PinAlreadyTaken(5))
        );
    }

    #[test]
    fn gpio_claims_span_all_three_16_bit_words() {
        let mut peripherals = fresh_peripherals();
        let gpio = &mut peripherals.gpio;
        assert!(gpio.output::<0>().is_ok());
        assert!(gpio.output::<15>().is_ok());
        assert!(gpio.output::<16>().is_ok());
        assert!(gpio.output::<31>().is_ok());
        assert!(gpio.output::<32>().is_ok());
        assert!(gpio.output::<44>().is_ok());

        assert_eq!(gpio.output::<0>(), Err(HalError::PinAlreadyTaken(0)));
        assert_eq!(gpio.input::<15>(), Err(HalError::PinAlreadyTaken(15)));
        assert_eq!(gpio.output::<16>(), Err(HalError::PinAlreadyTaken(16)));
        assert_eq!(gpio.input::<31>(), Err(HalError::PinAlreadyTaken(31)));
        assert_eq!(gpio.output::<32>(), Err(HalError::PinAlreadyTaken(32)));
        assert_eq!(gpio.input::<44>(), Err(HalError::PinAlreadyTaken(44)));
    }

    #[test]
    fn xint_pins_are_claimed_against_plain_handles() {
        let mut peripherals = fresh_peripherals();
        let _xint = peripherals
            .gpio
            .xint1::<1, { InterruptEdge::Falling as u16 }>()
            .unwrap();
        assert_eq!(
            peripherals.gpio.output::<1>(),
            Err(HalError::PinAlreadyTaken(1))
        );
    }

    #[test]
    #[should_panic(expected = "PIN <= 44")]
    fn nonexistent_gpio_is_rejected() {
        let mut peripherals = fresh_peripherals();
        let _ = peripherals.gpio.output::<45>();
    }

    #[test]
    #[should_panic(expected = "PIN <= 44")]
    fn nonexistent_gpio_input_is_rejected() {
        let mut peripherals = fresh_peripherals();
        let _ = peripherals.gpio.input::<45>();
    }

    #[test]
    #[should_panic(expected = "PIN <= 31")]
    fn xint_rejects_gpio_b_pins() {
        let mut peripherals = fresh_peripherals();
        let _ = peripherals
            .gpio
            .xint1::<32, { InterruptEdge::Rising as u16 }>();
    }

    #[test]
    #[should_panic(expected = "EDGE == 0 || EDGE == 1 || EDGE == 3")]
    fn xint_rejects_reserved_edge_encoding() {
        let mut peripherals = fresh_peripherals();
        let _ = peripherals.gpio.xint2::<1, 2>();
    }

    #[test]
    #[should_panic(expected = "INDEX <= 15")]
    fn nonexistent_adc_result_is_rejected() {
        let peripherals = fresh_peripherals();
        let _ = peripherals.adc.read::<16>();
    }

    #[test]
    fn peripheral_root_can_only_be_taken_once() {
        ffi::reset_peripherals();
        assert!(Peripherals::take().is_some());
        assert!(Peripherals::take().is_none());
    }

    #[test]
    fn timer_and_pwm_validate_configuration() {
        let peripherals = fresh_peripherals();
        let _timer = peripherals.timer0.start_periodic::<10>().unwrap();
        let mut pwm = peripherals.pwm1.configure::<4095>().unwrap();
        pwm.set_compare(2048);
        assert_eq!(pwm.get_compare(), 2048);
        pwm.enable();
        pwm.disable();
        assert_eq!(pwm.period_ticks(), 4095);
    }

    #[test]
    fn periodic_timer_state_transitions_preserve_ownership() {
        let peripherals = fresh_peripherals();
        let running = peripherals.timer0.start_periodic::<10>().unwrap();
        assert_eq!(running.interrupt_count(), 0);
        let stopped = running.stop().set_period::<20>().unwrap();
        let _running_again = stopped.restart();
    }

    #[test]
    #[should_panic(expected = "PERIOD_MS is 1..=1000")]
    fn timer_rejects_bad_period_const() {
        let peripherals = fresh_peripherals();
        let _ = peripherals.timer0.start_periodic::<0>();
    }

    #[test]
    fn adc_handle_is_reachable_only_from_peripherals() {
        // AdcResults no longer exposes `new()`; the only path is the root.
        let peripherals = fresh_peripherals();
        assert_eq!(peripherals.adc.read_channel(15), 0);
        assert_eq!(peripherals.adc.timeout_count(), 0);
    }

    #[test]
    fn configured_adc_keeps_its_channel_in_the_handle() {
        let peripherals = fresh_peripherals();
        let mut adc0 = peripherals.adc.into_soc0::<0, 7>().unwrap();
        assert_eq!(adc0.sample(), 0);
        assert_eq!(adc0.timeout_count(), 0);
    }

    #[test]
    fn serial_buses_are_reachable_only_from_peripherals() {
        let mut peripherals = fresh_peripherals();
        let _spi = peripherals.spi_b.internal_loopback::<8>();
        peripherals.spi_b.reg_readback();
        peripherals.spi_b.fifo_rx_boundary();

        let _sci = peripherals.sci_a.internal_loopback::<194, 8>();
        peripherals.sci_a.reg_readback();
        peripherals.sci_a.fifo_rx();

        let _slave = peripherals.i2c_a.master_write_1byte::<0x36>();
        peripherals.i2c_a.reg_readback_sweep();
    }

    #[test]
    #[should_panic(expected = "CHAR_BITS is 1..=16")]
    fn spi_rejects_invalid_char_length() {
        let mut peripherals = fresh_peripherals();
        let _ = peripherals.spi_b.internal_loopback::<17>();
    }

    #[test]
    #[should_panic(expected = "internal loopback C case uses 8-bit characters")]
    fn spi_fixed_case_rejects_other_valid_char_length() {
        let mut peripherals = fresh_peripherals();
        let _ = peripherals.spi_b.internal_loopback::<9>();
    }

    #[test]
    #[should_panic(expected = "CHAR_BITS is 1..=8")]
    fn sci_rejects_invalid_char_length() {
        let mut peripherals = fresh_peripherals();
        let _ = peripherals.sci_a.configure_basic::<194, 9>();
    }

    #[test]
    #[should_panic(expected = "ADDRESS is 7-bit")]
    fn i2c_rejects_non_7bit_slave_address() {
        let mut peripherals = fresh_peripherals();
        let _ = peripherals.i2c_a.slave::<0x80>();
    }

    #[test]
    #[should_panic(expected = "I2C C cases use fixed address 0x36")]
    fn i2c_fixed_case_rejects_other_valid_address() {
        let mut peripherals = fresh_peripherals();
        let _ = peripherals.i2c_a.master_write_1byte::<0x37>();
    }

    /// Direction switch: consuming the output handle releases the claim, so
    /// the same pin can be re-claimed as an input and then back as an output
    /// without ever holding two aliasing handles.
    #[test]
    fn direction_switch_reclaims_same_pin() {
        let mut peripherals = fresh_peripherals();
        let mut out = peripherals.gpio.output::<34>().unwrap();
        out.set_high();
        assert!(out.is_high());

        let input = out.into_input(&mut peripherals.gpio).unwrap();
        // The latch still reads what the output stage wrote (make_input does
        // not clear the DATA bit); what matters is the exclusivity transfer.
        assert!(input.is_high());

        // While the input handle is alive the pin cannot be taken as output.
        assert_eq!(
            peripherals.gpio.output::<34>(),
            Err(HalError::PinAlreadyTaken(34))
        );

        let mut out = input.into_output(&mut peripherals.gpio).unwrap();
        out.set_low();
        assert!(out.is_low());

        // After the direction switch the pin is once more exclusive.
        assert_eq!(
            peripherals.gpio.input::<34>(),
            Err(HalError::PinAlreadyTaken(34))
        );
    }

    /// MUX routing: set_mux programs the 2-bit MUX field and mux reads it
    /// back through the C-bridge stub (pin 0 lands in GPAMUX1 bits 0..1).
    /// The MUX path is orthogonal to the data-direction claim, so it works
    /// without consuming a claim slot and does not conflict with an output
    /// handle on a different pin.
    #[test]
    fn mux_routing_programs_and_reads_back_field() {
        let mut peripherals = fresh_peripherals();
        peripherals.gpio.set_mux::<0, 0>().unwrap();
        assert_eq!(peripherals.gpio.mux::<0>(), 0);
        peripherals.gpio.set_mux::<0, 1>().unwrap();
        assert_eq!(peripherals.gpio.mux::<0>(), 1);
        peripherals.gpio.set_mux::<0, 0>().unwrap();
        assert_eq!(peripherals.gpio.mux::<0>(), 0);
    }

    #[test]
    fn mux_cannot_change_a_pin_owned_by_gpio_handle() {
        let mut peripherals = fresh_peripherals();
        let _output = peripherals.gpio.output::<34>().unwrap();
        assert_eq!(
            peripherals.gpio.set_mux::<34, 1>(),
            Err(HalError::PinAlreadyTaken(34))
        );
        assert_eq!(peripherals.gpio.mux::<34>(), 0);
        peripherals.gpio.set_mux::<35, 1>().unwrap();
        assert_eq!(peripherals.gpio.mux::<35>(), 1);
    }

    /// MUX rejects a function encoding above 3 through the const assert.
    #[test]
    #[should_panic(expected = "FUNC <= 3")]
    fn mux_rejects_invalid_function_encoding() {
        let mut peripherals = fresh_peripherals();
        let _ = peripherals.gpio.set_mux::<0, 4>();
    }
}
