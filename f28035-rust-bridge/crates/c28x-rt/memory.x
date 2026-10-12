/* memory.x — F28035 memory layout for c28x-rt.
 *
 * This is a GNU ld-style memory description (analogous to the MSP430
 * memory.x).  When the TI cl2000 linker is used directly, the equivalent
 * regions are in vendor/ti/f2803x/common/cmd/F28035.cmd.
 *
 * C28x has a unified address space (unlike the dual-PAGE TI linker).
 * Program and data share the same 22-bit word address; PAGE 0 / PAGE 1
 * in the TI linker script is a software convention.
 */

MEMORY
{
    /* Data RAM (PAGE 1) */
    RAMM0   : ORIGIN = 0x000050, LENGTH = 0x0003B0   /* stack lives here, top = 0x0400 */
    RAMM1   : ORIGIN = 0x000400, LENGTH = 0x000400
    RAML2   : ORIGIN = 0x008C00, LENGTH = 0x000400   /* .bss / .data */
    RAML3   : ORIGIN = 0x009000, LENGTH = 0x001000

    /* Program RAM (PAGE 0) — for ramfuncs / ISR hot paths */
    RAML0   : ORIGIN = 0x008000, LENGTH = 0x000800
    RAML1   : ORIGIN = 0x008800, LENGTH = 0x000400

    /* Flash (PAGE 0) */
    FLASHA  : ORIGIN = 0x3F6000, LENGTH = 0x001F80   /* main application */
    FLASHB  : ORIGIN = 0x3F4000, LENGTH = 0x002000
    FLASHC  : ORIGIN = 0x3F2000, LENGTH = 0x002000
    FLASHD  : ORIGIN = 0x3F0000, LENGTH = 0x002000
    FLASHE  : ORIGIN = 0x3EE000, LENGTH = 0x002000
    FLASHF  : ORIGIN = 0x3EC000, LENGTH = 0x002000
    FLASHG  : ORIGIN = 0x3EA000, LENGTH = 0x002000
    FLASHH  : ORIGIN = 0x3E8000, LENGTH = 0x002000

    /* Reset / Vector table (in Boot ROM) */
    RESET   : ORIGIN = 0x3FFFC0, LENGTH = 0x000002
    VECTORS : ORIGIN = 0x3FFFC2, LENGTH = 0x00003E
}

/* Stack grows down from top of RAMM0. */
__stack_end = ORIGIN(RAMM0) + LENGTH(RAMM0);
