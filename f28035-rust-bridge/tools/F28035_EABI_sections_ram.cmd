/* EABI section-name supplement for RAM-only verification.
 * Rust emits per-symbol subsections (.bss.<mangled>, .data.<mangled>).
 * The TI linker does not auto-merge `.bss.foo` into `.bss`, so we
 * collect them explicitly.  __bss_start__/__bss_end__ are exported for
 * the startup stub to zero .bss.
 */
SECTIONS
{
    .bss : {
        __bss_start__ = .;
        *(.bss)  *(.bss.*)  *(.ebss)  *(.ebss.*)
        __bss_end__ = .;
    } > RAMM1  PAGE = 1

    .data : { *(.data) *(.data.*) *(.econst) *(.econst.*) } > RAMM1 PAGE = 1
    .sysmem : { *(.sysmem) *(.esysmem) } > RAMM1 PAGE = 1
    .const : > RAML0L1 PAGE = 0
    .init_array : > RAML0L1 PAGE = 0
    .rodata : {
        *(.rodata) *(.rodata.*)
        /* C28x TI linker formats read-only data in 16-bit words. */
        . = ALIGN(2);
    } > RAML0L1 PAGE = 0
    .pie_vect_table : > PIEVECT PAGE = 1
}
