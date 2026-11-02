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
        .weak PreInit
        .weak DefaultHandler
        .def c28x_rt_default_handler
        .def c28x_rt_enable_interrupts
        .def c28x_rt_disable_interrupts
        .def c28x_rt_set_ier
        .def c28x_rt_enter_critical
        .def c28x_rt_exit_critical
        .ref main
        .ref __TI_auto_init
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
        DINT
        AND IER, #0
        AND IFR, #0
        MOV  SP, #__stack_end

        ; Set 28x object mode + disable watchdog.
        SETC OBJMODE
        EALLOW
        MOVZ DP, #01C0h
        MOV  @7029h, #0068h
        EDIS

; ---- Clock: PLL 10 MHz x 12 / 2 = 60 MHz SYSCLKOUT ---------------------
; Port of vendor DSP2803x_SysCtrl.c::InitPll(12, 2), the same configuration
; the proven vendor Timer0 tests run at.  Doing it here rather than in each
; demo is the point of the runtime: without it SYSCLKOUT stays at the reset
; default and every timing-sensitive demo (CPU timers, delays, PWM periods)
; silently runs at the wrong rate.
;   PLLSTS 0x7011: PLLLOCKS=bit0, MCLKSTS=bit3, MCLKOFF=bit6, DIVSEL=bits8:7
;   PLLCR  0x7021: DIV=bits3:0
        EALLOW
        MOV  AL, *(0:7011h)     ; PLLSTS
        AND  AL, #0FE7Fh        ; DIVSEL must be 0 before PLLCR may change
        MOV  *(0:7011h), AL
        OR   AL, #040h          ; MCLKOFF = 1 (mask the missing-clock detect)
        MOV  *(0:7011h), AL
        MOV  AL, #12
        MOV  *(0:7021h), AL     ; PLLCR.DIV = 12 -> 120 MHz VCO
        EDIS

        MOV  AR1, #0FFFFh       ; bounded wait for PLLLOCKS
.pll_wait:
        MOV  AL, *(0:7011h)
        TBIT AL, #0
        SB   .pll_lock, TC
        BANZ .pll_wait, AR1--
.pll_lock:
        EALLOW
        AND  AL, #0FFBFh        ; MCLKOFF = 0
        AND  AL, #0FE7Fh        ; DIVSEL = 0
        OR   AL, #0100h         ; DIVSEL = 2 -> 120 MHz / 2 = 60 MHz
        MOV  *(0:7011h), AL
        EDIS

        ; Call PreInit (default empty; user can override by linking
        ; their own `PreInit` symbol).
        LCR  PreInit

; F28035: 128 slots, 32 CPU/reserved + 12 groups of 8. Keep the first
; three Boot-ROM/emulation slots untouched, as TI InitPieVectTable does.
        EALLOW
        MOVL XAR0, #0D06h
        MOVL XAR1, #_pie_table+6
        MOVL XAR3, #DefaultHandler
        MOV  AR2, #124
.more_pie:
        MOV  AL, *XAR1++
        MOV  AH, *XAR1++
        CMP  AL, #0
        SB   .pie_value, NEQ
        CMP  AH, #0
        SB   .pie_value, NEQ
        MOVL ACC, XAR3
.pie_value:
        MOV  *XAR0++, AL
        MOV  *XAR0++, AH
        BANZ .more_pie, AR2--
        MOV  AL, #1
        MOV  *(0:0CE0h), AL
        EDIS

; BANZ tests the old counter before decrement: N words need counter N-1.
        MOV  AL, #_bss_size
        CMP  AL, #0
        SB   .done_bss, EQ
        SUBB AL, #1
        MOV  AR1, AL
        MOVL XAR0, #_sbss
.more_bss:
        MOV  *XAR0++, #0
        BANZ .more_bss, AR1--
.done_bss:
        MOV  AL, #_data_size
        CMP  AL, #0
        SB   .done_data, EQ
        SUBB AL, #1
        MOV  AR2, AL
        MOVL XAR0, #_sdata
        MOVL XAR1, #_sidata
.more_data:
        MOV  AL, *XAR1++
        MOV  *XAR0++, AL
        BANZ .more_data, AR2--

.done_data:
        ; TI --rom_model keeps initialized C data (including function pointers)
        ; in .cinit records. The raw .data copy above handles Rust/load-image
        ; sections but cannot expand TI copy/zero-init records. Run the vendor
        ; initializer before main, using TI's own word-address memory helpers.
        LCR  __TI_auto_init
        LCR  main

.dead_loop:
        B    .dead_loop, UNC

; Default weak hook and non-returning unhandled-interrupt sink.
PreInit:
        LRETR
DefaultHandler:
c28x_rt_default_handler:
        B DefaultHandler, UNC
c28x_rt_enable_interrupts:
        EINT
        LRETR
c28x_rt_disable_interrupts:
        DINT
        LRETR
c28x_rt_set_ier:
        MOV IER, AL
        LRETR

; u16 c28x_rt_enter_critical(void): save the current INTM state (0 = enabled,
; 1 = disabled) in AL and disable global interrupts.  Pair with
; c28x_rt_exit_critical. INTM is ST1 bit 0. Read the single pushed word
; with pre-decrement, as in TI's DSP2803x_DisInt.asm (SP points past it).
c28x_rt_enter_critical:
        PUSH    ST1
        SETC    INTM
        MOV     AL, *--SP
        AND     AL, #1
        LRETR

; void c28x_rt_exit_critical(u16 saved): restore the INTM state saved above.
c28x_rt_exit_critical:
        CMPB    AL, #0
        BF      c28x_rt_xc_dis, NEQ
        CLRC    INTM
        LRETR
c28x_rt_xc_dis:
        SETC    INTM
        LRETR

        .sect ".pie_table"
_pie_table:
        .field 0, 32
        .field 0, 32
        .field 0, 32
        .field 0, 32
        .field 0, 32
        .field 0, 32
        .field 0, 32
        .field 0, 32
        .field 0, 32
        .field 0, 32
        .field 0, 32
        .field 0, 32
        .field 0, 32
        .weak TINT1
        .field TINT1, 32
        .weak TINT2
        .field TINT2, 32
        .weak DATALOG
        .field DATALOG, 32
        .weak RTOSINT
        .field RTOSINT, 32
        .weak EMUINT
        .field EMUINT, 32
        .weak NMI
        .field NMI, 32
        .weak ILLEGAL
        .field ILLEGAL, 32
        .weak USER1
        .field USER1, 32
        .weak USER2
        .field USER2, 32
        .weak USER3
        .field USER3, 32
        .weak USER4
        .field USER4, 32
        .weak USER5
        .field USER5, 32
        .weak USER6
        .field USER6, 32
        .weak USER7
        .field USER7, 32
        .weak USER8
        .field USER8, 32
        .weak USER9
        .field USER9, 32
        .weak USER10
        .field USER10, 32
        .weak USER11
        .field USER11, 32
        .weak USER12
        .field USER12, 32
        .weak ADCINT1
        .field ADCINT1, 32
        .weak ADCINT2
        .field ADCINT2, 32
        .field 0, 32
        .weak XINT1
        .field XINT1, 32
        .weak XINT2
        .field XINT2, 32
        .weak ADCINT9
        .field ADCINT9, 32
        .weak TINT0
        .field TINT0, 32
        .weak WAKEINT
        .field WAKEINT, 32
        .weak EPWM1_TZINT
        .field EPWM1_TZINT, 32
        .weak EPWM2_TZINT
        .field EPWM2_TZINT, 32
        .weak EPWM3_TZINT
        .field EPWM3_TZINT, 32
        .weak EPWM4_TZINT
        .field EPWM4_TZINT, 32
        .weak EPWM5_TZINT
        .field EPWM5_TZINT, 32
        .weak EPWM6_TZINT
        .field EPWM6_TZINT, 32
        .weak EPWM7_TZINT
        .field EPWM7_TZINT, 32
        .field 0, 32
        .weak EPWM1_INT
        .field EPWM1_INT, 32
        .weak EPWM2_INT
        .field EPWM2_INT, 32
        .weak EPWM3_INT
        .field EPWM3_INT, 32
        .weak EPWM4_INT
        .field EPWM4_INT, 32
        .weak EPWM5_INT
        .field EPWM5_INT, 32
        .weak EPWM6_INT
        .field EPWM6_INT, 32
        .weak EPWM7_INT
        .field EPWM7_INT, 32
        .field 0, 32
        .weak ECAP1_INT
        .field ECAP1_INT, 32
        .field 0, 32
        .field 0, 32
        .field 0, 32
        .field 0, 32
        .field 0, 32
        .weak HRCAP1_INT
        .field HRCAP1_INT, 32
        .weak HRCAP2_INT
        .field HRCAP2_INT, 32
        .weak EQEP1_INT
        .field EQEP1_INT, 32
        .field 0, 32
        .field 0, 32
        .field 0, 32
        .field 0, 32
        .field 0, 32
        .field 0, 32
        .field 0, 32
        .weak SPIRXINTA
        .field SPIRXINTA, 32
        .weak SPITXINTA
        .field SPITXINTA, 32
        .weak SPIRXINTB
        .field SPIRXINTB, 32
        .weak SPITXINTB
        .field SPITXINTB, 32
        .field 0, 32
        .field 0, 32
        .field 0, 32
        .field 0, 32
        .field 0, 32
        .field 0, 32
        .field 0, 32
        .field 0, 32
        .field 0, 32
        .field 0, 32
        .field 0, 32
        .field 0, 32
        .weak I2CINT1A
        .field I2CINT1A, 32
        .weak I2CINT2A
        .field I2CINT2A, 32
        .field 0, 32
        .field 0, 32
        .field 0, 32
        .field 0, 32
        .field 0, 32
        .field 0, 32
        .weak SCIRXINTA
        .field SCIRXINTA, 32
        .weak SCITXINTA
        .field SCITXINTA, 32
        .weak LIN0INTA
        .field LIN0INTA, 32
        .weak LIN1INTA
        .field LIN1INTA, 32
        .weak ECAN0INTA
        .field ECAN0INTA, 32
        .weak ECAN1INTA
        .field ECAN1INTA, 32
        .field 0, 32
        .field 0, 32
        .field 0, 32
        .field 0, 32
        .weak ADCINT3
        .field ADCINT3, 32
        .weak ADCINT4
        .field ADCINT4, 32
        .weak ADCINT5
        .field ADCINT5, 32
        .weak ADCINT6
        .field ADCINT6, 32
        .weak ADCINT7
        .field ADCINT7, 32
        .weak ADCINT8
        .field ADCINT8, 32
        .weak CLA1_INT1
        .field CLA1_INT1, 32
        .weak CLA1_INT2
        .field CLA1_INT2, 32
        .weak CLA1_INT3
        .field CLA1_INT3, 32
        .weak CLA1_INT4
        .field CLA1_INT4, 32
        .weak CLA1_INT5
        .field CLA1_INT5, 32
        .weak CLA1_INT6
        .field CLA1_INT6, 32
        .weak CLA1_INT7
        .field CLA1_INT7, 32
        .weak CLA1_INT8
        .field CLA1_INT8, 32
        .weak XINT3
        .field XINT3, 32
        .field 0, 32
        .field 0, 32
        .field 0, 32
        .field 0, 32
        .field 0, 32
        .weak LVF
        .field LVF, 32
        .weak LUF
        .field LUF, 32

; EALLOW / EDIS leaf functions for the Rust PAC.
; EALLOW = opcode 0x7622, EDIS = opcode 0x761A (single-word instructions).
        .text
eallow_inst:
        EALLOW
        LRETR

edis_inst:
        EDIS
        LRETR

; Bounded hardware waits used by the Safe HAL.
;
; ADC: a fixed settle (60 NOPs, ~1 us) runs first, then ADCCTL1.ADCBSY is
; polled until it clears. Reading ADCRESULT0 while the converter was still
; busy left the next software-triggered conversion stuck (an exact
; ok/timeout alternation on hardware), and clearing ADCINTFLG perturbed it the
; same way, so neither a flag clear nor an early read is used.
; SPI: 40 unrolled reads of SPISTS.INT.
;
; Both are unrolled: a counted loop is not reliable in this toolchain.
;
        .def c28x_rt_wait_adc_eoc
c28x_rt_wait_adc_eoc:
        MOVL    XAR7, #0x7100          ; ADCCTL1 (bit 13 = ADCBSY)
        NOP
        NOP
        NOP
        NOP
        NOP
        NOP
        NOP
        NOP
        NOP
        NOP
        NOP
        NOP
        NOP
        NOP
        NOP
        NOP
        NOP
        NOP
        NOP
        NOP
        NOP
        NOP
        NOP
        NOP
        NOP
        NOP
        NOP
        NOP
        NOP
        NOP
        NOP
        NOP
        NOP
        NOP
        NOP
        NOP
        NOP
        NOP
        NOP
        NOP
        NOP
        NOP
        NOP
        NOP
        NOP
        NOP
        NOP
        NOP
        NOP
        NOP
        NOP
        NOP
        NOP
        NOP
        NOP
        NOP
        NOP
        NOP
        NOP
        NOP
        MOV     AL, *XAR7
        TBIT    AL, #13
        BF      c28x_rt_wait_adc_eoc_done, NTC
        MOV     AL, *XAR7
        TBIT    AL, #13
        BF      c28x_rt_wait_adc_eoc_done, NTC
        MOV     AL, *XAR7
        TBIT    AL, #13
        BF      c28x_rt_wait_adc_eoc_done, NTC
        MOV     AL, *XAR7
        TBIT    AL, #13
        BF      c28x_rt_wait_adc_eoc_done, NTC
        MOV     AL, *XAR7
        TBIT    AL, #13
        BF      c28x_rt_wait_adc_eoc_done, NTC
        MOV     AL, *XAR7
        TBIT    AL, #13
        BF      c28x_rt_wait_adc_eoc_done, NTC
        MOV     AL, *XAR7
        TBIT    AL, #13
        BF      c28x_rt_wait_adc_eoc_done, NTC
        MOV     AL, *XAR7
        TBIT    AL, #13
        BF      c28x_rt_wait_adc_eoc_done, NTC
        MOV     AL, *XAR7
        TBIT    AL, #13
        BF      c28x_rt_wait_adc_eoc_done, NTC
        MOV     AL, *XAR7
        TBIT    AL, #13
        BF      c28x_rt_wait_adc_eoc_done, NTC
        MOV     AL, *XAR7
        TBIT    AL, #13
        BF      c28x_rt_wait_adc_eoc_done, NTC
        MOV     AL, *XAR7
        TBIT    AL, #13
        BF      c28x_rt_wait_adc_eoc_done, NTC
        MOV     AL, *XAR7
        TBIT    AL, #13
        BF      c28x_rt_wait_adc_eoc_done, NTC
        MOV     AL, *XAR7
        TBIT    AL, #13
        BF      c28x_rt_wait_adc_eoc_done, NTC
        MOV     AL, *XAR7
        TBIT    AL, #13
        BF      c28x_rt_wait_adc_eoc_done, NTC
        MOV     AL, *XAR7
        TBIT    AL, #13
        BF      c28x_rt_wait_adc_eoc_done, NTC
        MOV     AL, *XAR7
        TBIT    AL, #13
        BF      c28x_rt_wait_adc_eoc_done, NTC
        MOV     AL, *XAR7
        TBIT    AL, #13
        BF      c28x_rt_wait_adc_eoc_done, NTC
        MOV     AL, *XAR7
        TBIT    AL, #13
        BF      c28x_rt_wait_adc_eoc_done, NTC
        MOV     AL, *XAR7
        TBIT    AL, #13
        BF      c28x_rt_wait_adc_eoc_done, NTC
        MOV     AL, *XAR7
        TBIT    AL, #13
        BF      c28x_rt_wait_adc_eoc_done, NTC
        MOV     AL, *XAR7
        TBIT    AL, #13
        BF      c28x_rt_wait_adc_eoc_done, NTC
        MOV     AL, *XAR7
        TBIT    AL, #13
        BF      c28x_rt_wait_adc_eoc_done, NTC
        MOV     AL, *XAR7
        TBIT    AL, #13
        BF      c28x_rt_wait_adc_eoc_done, NTC
        MOV     AL, *XAR7
        TBIT    AL, #13
        BF      c28x_rt_wait_adc_eoc_done, NTC
        MOV     AL, *XAR7
        TBIT    AL, #13
        BF      c28x_rt_wait_adc_eoc_done, NTC
        MOV     AL, *XAR7
        TBIT    AL, #13
        BF      c28x_rt_wait_adc_eoc_done, NTC
        MOV     AL, *XAR7
        TBIT    AL, #13
        BF      c28x_rt_wait_adc_eoc_done, NTC
        MOV     AL, *XAR7
        TBIT    AL, #13
        BF      c28x_rt_wait_adc_eoc_done, NTC
        MOV     AL, *XAR7
        TBIT    AL, #13
        BF      c28x_rt_wait_adc_eoc_done, NTC
        MOV     AL, *XAR7
        TBIT    AL, #13
        BF      c28x_rt_wait_adc_eoc_done, NTC
        MOV     AL, *XAR7
        TBIT    AL, #13
        BF      c28x_rt_wait_adc_eoc_done, NTC
        MOV     AL, *XAR7
        TBIT    AL, #13
        BF      c28x_rt_wait_adc_eoc_done, NTC
        MOV     AL, *XAR7
        TBIT    AL, #13
        BF      c28x_rt_wait_adc_eoc_done, NTC
        MOV     AL, *XAR7
        TBIT    AL, #13
        BF      c28x_rt_wait_adc_eoc_done, NTC
        MOV     AL, *XAR7
        TBIT    AL, #13
        BF      c28x_rt_wait_adc_eoc_done, NTC
        MOV     AL, *XAR7
        TBIT    AL, #13
        BF      c28x_rt_wait_adc_eoc_done, NTC
        MOV     AL, *XAR7
        TBIT    AL, #13
        BF      c28x_rt_wait_adc_eoc_done, NTC
        MOV     AL, *XAR7
        TBIT    AL, #13
        BF      c28x_rt_wait_adc_eoc_done, NTC
        MOV     AL, *XAR7
        TBIT    AL, #13
        BF      c28x_rt_wait_adc_eoc_done, NTC
        MOV     AL, *XAR7
        TBIT    AL, #13
        BF      c28x_rt_wait_adc_eoc_done, NTC
        MOV     AL, *XAR7
        TBIT    AL, #13
        BF      c28x_rt_wait_adc_eoc_done, NTC
        MOV     AL, *XAR7
        TBIT    AL, #13
        BF      c28x_rt_wait_adc_eoc_done, NTC
        MOV     AL, *XAR7
        TBIT    AL, #13
        BF      c28x_rt_wait_adc_eoc_done, NTC
        MOV     AL, *XAR7
        TBIT    AL, #13
        BF      c28x_rt_wait_adc_eoc_done, NTC
        MOV     AL, *XAR7
        TBIT    AL, #13
        BF      c28x_rt_wait_adc_eoc_done, NTC
        MOV     AL, *XAR7
        TBIT    AL, #13
        BF      c28x_rt_wait_adc_eoc_done, NTC
        MOV     AL, *XAR7
        TBIT    AL, #13
        BF      c28x_rt_wait_adc_eoc_done, NTC
c28x_rt_wait_adc_eoc_timeout:
        MOVB    AL, #0
        LRETR
c28x_rt_wait_adc_eoc_done:
        MOVB    AL, #1
        LRETR
        .def c28x_rt_wait_spi_int
c28x_rt_wait_spi_int:
        MOVL    XAR7, #0x7742          ; SPI-B SPISTS (bit 6 = INT)
        MOV     AL, *XAR7
        TBIT    AL, #6
        BF      c28x_rt_wait_spi_int_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #6
        BF      c28x_rt_wait_spi_int_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #6
        BF      c28x_rt_wait_spi_int_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #6
        BF      c28x_rt_wait_spi_int_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #6
        BF      c28x_rt_wait_spi_int_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #6
        BF      c28x_rt_wait_spi_int_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #6
        BF      c28x_rt_wait_spi_int_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #6
        BF      c28x_rt_wait_spi_int_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #6
        BF      c28x_rt_wait_spi_int_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #6
        BF      c28x_rt_wait_spi_int_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #6
        BF      c28x_rt_wait_spi_int_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #6
        BF      c28x_rt_wait_spi_int_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #6
        BF      c28x_rt_wait_spi_int_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #6
        BF      c28x_rt_wait_spi_int_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #6
        BF      c28x_rt_wait_spi_int_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #6
        BF      c28x_rt_wait_spi_int_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #6
        BF      c28x_rt_wait_spi_int_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #6
        BF      c28x_rt_wait_spi_int_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #6
        BF      c28x_rt_wait_spi_int_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #6
        BF      c28x_rt_wait_spi_int_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #6
        BF      c28x_rt_wait_spi_int_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #6
        BF      c28x_rt_wait_spi_int_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #6
        BF      c28x_rt_wait_spi_int_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #6
        BF      c28x_rt_wait_spi_int_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #6
        BF      c28x_rt_wait_spi_int_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #6
        BF      c28x_rt_wait_spi_int_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #6
        BF      c28x_rt_wait_spi_int_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #6
        BF      c28x_rt_wait_spi_int_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #6
        BF      c28x_rt_wait_spi_int_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #6
        BF      c28x_rt_wait_spi_int_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #6
        BF      c28x_rt_wait_spi_int_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #6
        BF      c28x_rt_wait_spi_int_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #6
        BF      c28x_rt_wait_spi_int_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #6
        BF      c28x_rt_wait_spi_int_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #6
        BF      c28x_rt_wait_spi_int_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #6
        BF      c28x_rt_wait_spi_int_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #6
        BF      c28x_rt_wait_spi_int_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #6
        BF      c28x_rt_wait_spi_int_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #6
        BF      c28x_rt_wait_spi_int_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #6
        BF      c28x_rt_wait_spi_int_hit, TC
c28x_rt_wait_spi_int_miss:
        MOVB    AL, #0
        LRETR
c28x_rt_wait_spi_int_hit:
        MOVB    AL, #1
        LRETR
; u16 c28x_rt_wait_sci_txrdy(void): 40 unrolled reads of SCICTL2.TXRDY (bit 7).
; A byte may only be written to SCITXBUF while TXRDY is set, and the same
; bit proves the previous byte left the buffer.
;
        .def c28x_rt_wait_sci_txrdy
c28x_rt_wait_sci_txrdy:
        MOVL    XAR7, #0x7054
        MOV     AL, *XAR7
        TBIT    AL, #7
        BF      c28x_rt_wait_sci_txrdy_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #7
        BF      c28x_rt_wait_sci_txrdy_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #7
        BF      c28x_rt_wait_sci_txrdy_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #7
        BF      c28x_rt_wait_sci_txrdy_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #7
        BF      c28x_rt_wait_sci_txrdy_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #7
        BF      c28x_rt_wait_sci_txrdy_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #7
        BF      c28x_rt_wait_sci_txrdy_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #7
        BF      c28x_rt_wait_sci_txrdy_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #7
        BF      c28x_rt_wait_sci_txrdy_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #7
        BF      c28x_rt_wait_sci_txrdy_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #7
        BF      c28x_rt_wait_sci_txrdy_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #7
        BF      c28x_rt_wait_sci_txrdy_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #7
        BF      c28x_rt_wait_sci_txrdy_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #7
        BF      c28x_rt_wait_sci_txrdy_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #7
        BF      c28x_rt_wait_sci_txrdy_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #7
        BF      c28x_rt_wait_sci_txrdy_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #7
        BF      c28x_rt_wait_sci_txrdy_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #7
        BF      c28x_rt_wait_sci_txrdy_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #7
        BF      c28x_rt_wait_sci_txrdy_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #7
        BF      c28x_rt_wait_sci_txrdy_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #7
        BF      c28x_rt_wait_sci_txrdy_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #7
        BF      c28x_rt_wait_sci_txrdy_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #7
        BF      c28x_rt_wait_sci_txrdy_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #7
        BF      c28x_rt_wait_sci_txrdy_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #7
        BF      c28x_rt_wait_sci_txrdy_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #7
        BF      c28x_rt_wait_sci_txrdy_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #7
        BF      c28x_rt_wait_sci_txrdy_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #7
        BF      c28x_rt_wait_sci_txrdy_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #7
        BF      c28x_rt_wait_sci_txrdy_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #7
        BF      c28x_rt_wait_sci_txrdy_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #7
        BF      c28x_rt_wait_sci_txrdy_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #7
        BF      c28x_rt_wait_sci_txrdy_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #7
        BF      c28x_rt_wait_sci_txrdy_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #7
        BF      c28x_rt_wait_sci_txrdy_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #7
        BF      c28x_rt_wait_sci_txrdy_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #7
        BF      c28x_rt_wait_sci_txrdy_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #7
        BF      c28x_rt_wait_sci_txrdy_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #7
        BF      c28x_rt_wait_sci_txrdy_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #7
        BF      c28x_rt_wait_sci_txrdy_hit, TC
        MOV     AL, *XAR7
        TBIT    AL, #7
        BF      c28x_rt_wait_sci_txrdy_hit, TC
c28x_rt_wait_sci_txrdy_miss:
        MOVB    AL, #0
        LRETR
c28x_rt_wait_sci_txrdy_hit:
        MOVB    AL, #1
        LRETR
        .def c28x_rt_read_scictl2
c28x_rt_read_scictl2:
        MOVL    XAR7, #0x7054
        MOV     AL, *XAR7
        LRETR

; u16 c28x_rt_read_timer0_tim(void): read CPU Timer0 TIML (0x0C00), the
; down-counter that free-runs between periods.  Reading it at ISR entry and
; exit gives the ISR's execution time in SYSCLK cycles.
        .def c28x_rt_read_timer0_tim
c28x_rt_read_timer0_tim:
        MOVL    XAR7, #0x0C00
        MOV     AL, *XAR7
        LRETR

; void c28x_rt_fill_stack_sentinel(void)
;   Paint the *unused* stack (from the current SP+1 up to the RAMSTACK top at
;   0x0400) with 0xBEEF so a post-run JTAG scan can measure the stack
;   high-water mark.  Reading SP first is what makes this safe: the live
;   frames and this function's own return address (at and below SP) are left
;   untouched, so the LRETR below still returns correctly.  Registers only.
        .def c28x_rt_fill_stack_sentinel
c28x_rt_fill_stack_sentinel:
        MOV     AL, SP                 ; AL = current SP (top of live frames)
        MOVZ    AR7, AL                ; XAR7 = SP (high word cleared)
        ADDB    XAR7, #1               ; start one word above the return address
        MOV     AL, #0BEEFh
c28x_rt_fill_stack_loop:
        MOV     *XAR7++, AL
        CMP     AR7, #0400h            ; stop at the RAMSTACK top
        BF      c28x_rt_fill_stack_loop, NEQ
        LRETR

        .end
