; c28x-rt startup for F28035 (and similar C2000 Piccolo devices).
;
; Boot ROM jumps to BEGIN (0x3F7FF6) on flash boot.  The `codestart`
; section there jumps to `Reset`, which does: SP, OBJMODE, WD disable,
; PreInit, PIE table copy, .bss zero, .data copy, then main().

        .def Reset
        .def code_start
        .def _pie_table
        .def eallow_inst
        .def edis_inst
        .ref main
        .ref _sbss
        .ref _ebss
        .ref _bss_size
        .ref _sdata
        .ref _edata
        .ref _sidata
        .ref _data_size
        .ref __stack_end
        .sect "codestart"

code_start:
        LB  Reset

        .sect ".textreset"
Reset:
        MOV  SP, #__stack_end

        ; Set 28x object mode + disable watchdog.
        SETC OBJMODE
        EALLOW
        MOVZ DP, #01C0h
        MOV  @7029h, #0068h
        EDIS

        ; Call PreInit (default empty; user can override by linking
        ; their own `PreInit` symbol).
        LCR  PreInit_

; PIE table copy: Flash -> PIE RAM (0x0D00), 112 vectors x 2 words.
        MOVW DP, #0D00h >> 6
        MOVL XAR0, #0D00h
        MOVL XAR1, #_pie_table
        MOV  AR2, #112
.more_pie:
        MOV  T, *XAR1++
        MOV  *XAR0++, T
        MOV  T, *XAR1++
        MOV  *XAR0++, T
        BANZ .more_pie, AR2--

.done_pie:
        MOVW DP, #0CE0h >> 6
        MOV  @0E0h, #1          ; PIECTRL.bit0 = 1

        ; .bss zero-init
        MOVL XAR0, #_sbss
        MOV  AR1, #_bss_size
.more_bss:
        MOV  *XAR0++, #0
        BANZ .more_bss, AR1--

.done_bss:
        ; .data copy
        MOVL XAR0, #_sdata
        MOVL XAR1, #_sidata
        MOV  AR2, #_data_size
.more_data:
        MOV  AL, *XAR1++
        MOV  *XAR0++, AL
        BANZ .more_data, AR2--

.done_data:
        LCR  main

.dead_loop:
        B    .dead_loop, UNC

; Default PreInit (empty).
PreInit_:
        LRETR

; Default PIE table in Flash: 112 entries x 2 words = 224 words of 0.
; Each 22-bit handler address = 0 means "no handler" — any interrupt
; will vector to 0; for the control-loop test we only use Timer0 which
; is set up in software by the C runtime's PIE config (or by rust_main).
        .sect ".pie_table"
_pie_table:
        .field 0, 32
        .loop 111
        .field 0, 32
        .endloop

; EALLOW / EDIS leaf functions for the Rust PAC.
; EALLOW = opcode 0x7622, EDIS = opcode 0x761A (single-word instructions).
        .text
eallow_inst:
        EALLOW
        LRETR

edis_inst:
        EDIS
        LRETR

        .end
