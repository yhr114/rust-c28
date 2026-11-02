/* RAM-only c28x-rt symbols for JTAG tests. */
SECTIONS
{
    .bss :
    {
        _sbss = .;
        *(.bss) *(.bss.*) *(.ebss) *(.ebss.*)
        _ebss = .;
    } > RAMM1 PAGE = 1

    .hw_result : { *(.hw_result) } > RAMM1 PAGE = 1
    /* Group B writes every test word before it is observed.  Keeping this
     * buffer NOINIT avoids a pointless .cinit record in the nearly-full
     * 4096-word RAM image. */
    .hw_result_noinit : { *(.hw_result_noinit) } > RAMM1 PAGE = 1, type=NOINIT

    .data :
    {
        _sdata = .;
        *(.data) *(.data.*) *(.econst) *(.econst.*)
        _edata = .;
    } > RAMM1 PAGE = 1

    .rodata : { *(.rodata) *(.rodata.*) } > RAML0L1 PAGE = 0
    .pie_table : { *(.pie_table) } > PIEVECT PAGE = 1
}

_sidata = _sdata;
_bss_size = _ebss - _sbss;
_data_size = _edata - _sdata;
/* C28x SP grows upward.  Keep this test stack in RAMM0, below RAMM1 data
 * beginning at 0x0400; 0x0200..0x02FF is reserved for the 0x100-word stack. */
__stack_end = 0x0200;
