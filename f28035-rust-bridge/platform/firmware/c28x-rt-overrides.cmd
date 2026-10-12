/* c28x-rt-overrides.cmd — linker symbols needed by c28x-rt/asm.s.
 *
 * Append this after TI's F28035.cmd and F28035_EABI_sections.cmd.
 * Uses TI linker script syntax (LOAD_START / RUN_START / dot symbol).
 */

SECTIONS
{
    /* PIE vector table: the Rust static `_pie_table` goes into Flash. */
    .pie_table : > FLASHA PAGE = 0

    /* .bss: zero-initialized RAM. */
    .bss : > RAML2 PAGE = 1
    {
        _sbss = .;
        *(.bss)
        _ebss = .;
    }

    /* .data: initialized from Flash (LOAD) into RAM (RUN). */
    .data : LOAD = FLASHA PAGE = 0, RUN = RAML2 PAGE = 1,
            LOAD_START(_sidata),
            RUN_START(_sdata)
    {
        *(.data)
        _edata = .;
    }
}

/* Sizes for the Reset handler loops. */
_bss_size   = _ebss - _sbss;
_data_size  = _edata - _sdata;
__stack_end = 0x0400;
