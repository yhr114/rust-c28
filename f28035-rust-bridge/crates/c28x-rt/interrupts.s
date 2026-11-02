; c28x-rt — interrupt entry trampolines for C28x / TI C2000.
;
; WHY THIS FILE EXISTS
;   C28x hardware pushes no context frame on interrupt entry, and rustc has
;   no C28x interrupt ABI, so an ISR has to
;     (a) save the registers a called function may clobber,
;     (b) run the handler,
;     (c) return with IRET,
;     (d) acknowledge the peripheral and the PIE group.
;   The current C28x rustc backend cannot emit (a) or (c) yet, so the
;   runtime supplies them here.  Without this file every demo either hand-wrote
;   its own trampoline or borrowed TI C's `__interrupt`, which is exactly the
;   per-demo boilerplate the runtime is meant to remove.
;
; PROVENANCE — the sequence is not invented
;   ISR_ENTER / ISR_EXIT below are transcribed instruction for instruction
;   from what cl2000 emits for `__interrupt void f(void)`
;   (the archived B-2 IRQ artifact probe_isr.dis.txt; opcodes ASP=761b, PUSH=0005,
;   SPM=ff69, MOVL *SP++=abbd/a8bd/a0bd/c2bd/c3bd, CLRC=2942/5616,
;   POP=0003, NASP=7617, IRET=7602).  The same sequence is what the vendor
;   ISR in sdk/c-abi/f28035_bridge.c::f28035_timer0_isr compiles to, and that
;   ISR is what the passing Timer0 hardware test runs.
;
; REGISTER COVERAGE
;   IRET restores PC; ST0/ST1 are restored by the interrupt return, which is
;   why the prologue only has to clear OVM/PAGE0/AMODE for the handler's
;   benefit.  The saved set is XT + XAR4..XAR7 + AR1H:AR0H, i.e. exactly the
;   registers the TI EABI lets a called function clobber.
;
; USAGE
;   Point the PIE vector at TINT0_ISR and provide `rust_timer0_isr` on the
;   Rust side.  Adding another PIE interrupt is a copy of the TINT0_ISR block
;   with a different `.ref`, different ack group, and a different vector slot.

; ---------------------------------------------------------------------------
; Macros
; ---------------------------------------------------------------------------

; Save the caller-clobbered context and put the CPU into a known mode.
ISR_ENTER       .macro
        ASP                     ; align the stack pointer to an even boundary
        PUSH    AR1H:AR0H       ; AR0H/AR1H ride along with the 32-bit push
        SPM     #0              ; product shift mode = 0 (EABI default)
        MOVL    *SP++, XT
        MOVL    *SP++, XAR4
        MOVL    *SP++, XAR5
        MOVL    *SP++, XAR6
        MOVL    *SP++, XAR7
        CLRC    OVM|PAGE0       ; handler must not inherit saturation/DP mode
        CLRC    AMODE
        .endm

; Restore the context and return from the interrupt.
ISR_EXIT        .macro
        MOVL    XAR7, *--SP
        MOVL    XAR6, *--SP
        MOVL    XAR5, *--SP
        MOVL    XAR4, *--SP
        MOVL    XT, *--SP
        POP     AR1H:AR0H
        NASP                    ; undo ASP
        IRET
        .endm

; Clear a CPU-timer interrupt flag (TCR.TIF is write-1-to-clear, so this has
; to be a read-modify-write - a plain store would also clear TIE/TSS).
;   base = CPU timer control register address (0C04h for Timer0)
TIMER_CLEAR_TIF .macro  base
        MOV     AL, *(0:base)
        OR      AL, #8000h
        MOV     *(0:base), AL
        .endm

; Acknowledge one PIE group so the next interrupt from it can be delivered.
; PIEACK is write-1-to-clear: writing the group bit clears the acknowledge.
;   bit = 0001h for group 1, 0002h for group 2, ...
PIE_ACK         .macro  bit
        MOV     AL, #bit
        MOV     *(0:0CE1h), AL
        .endm

; ---------------------------------------------------------------------------
; Timer0 / PIE INT1.7 entry
; ---------------------------------------------------------------------------
        .def    TINT0_ISR
        .global TINT0
        .ref    rust_timer0_isr

        .text
; `TINT0` and `TINT0_ISR` share one address so the PIE table's weak `TINT0`
; slot (asm.s _pie_table) installs this trampoline as the Timer0 vector.
TINT0:
TINT0_ISR:
        ISR_ENTER
        LCR     rust_timer0_isr ; the Rust body (extern "C", no context save)
        TIMER_CLEAR_TIF 0C04h   ; TCR0.TIF = 1
        PIE_ACK 0001h           ; release PIE group 1
        ISR_EXIT

        .end
