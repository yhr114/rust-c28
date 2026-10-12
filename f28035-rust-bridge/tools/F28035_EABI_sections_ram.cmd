/* EABI section-name supplement for RAM-only verification.
 * Replaces f28035-rust-bridge/firmware/F28035_EABI_sections.cmd
 * (which binds .const/.init_array to FLASHA) so that nothing is
 * loaded into flash.  Memory regions come from tools/F28035_ram.cmd.
 */
SECTIONS
{
    .bss        : > RAMM1  PAGE = 1
    .data       : > RAMM1  PAGE = 1
    .sysmem     : > RAMM1  PAGE = 1
    .const      : > RAML0L1 PAGE = 0
    .init_array : > RAML0L1 PAGE = 0
}
