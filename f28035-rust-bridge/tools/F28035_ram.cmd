/* F28035 RAM-only linker command file.
   Loads all code and data into on-chip SARAM; no flash sectors are
   touched by loadProgram.  For JTAG/RAM case verification without
   flash programming (flash-and-verify normally writes FLASHA).
   Derived from vendor F28035.cmd; flash-only memory blocks removed.
   Pair with F28035_EABI_sections_ram.cmd (replaces the flash-bound
   F28035_EABI_sections.cmd from f28035-rust-bridge).

   2026-10-20: RAML0L1 length corrected 0x3000 -> 0x2000.  The vendor
   value claims 12K words, but the F28035 program-space SARAM is only
   0x8000-0x9FFF (L0 2K + L1 1K + L2 1K + L3 4K = 8192 16-bit words,
   or 16 KiB; the earlier comment incorrectly said 4096 words),
   per ccs_base/emulation/gel/f28035.gel.  Oversized images linked
   "successfully" at 0x3000 but the CCS loader refused to write the
   sections past 0x9FFF ("memory region that is not writable") and the
   CPU executed whatever was in ROM.  Keeping the real length makes the
   linker fail fast instead of producing an image that cannot run. */

MEMORY
{
PAGE 0:    /* Program Memory */
   RAML0L1     : origin = 0x008000, length = 0x002000  /* L0+L1+L2+L3: 8192 16-bit words = 16 KiB */

   IQTABLES    : origin = 0x3FE000, length = 0x000B50  /* IQ Math Tables in Boot ROM */
   IQTABLES2   : origin = 0x3FEB50, length = 0x00008C  /* IQ Math Tables in Boot ROM */
   IQTABLES3   : origin = 0x3FEBDC, length = 0x0000AA  /* IQ Math Tables in Boot ROM */
   ROM         : origin = 0x3FF27C, length = 0x000D44  /* Boot ROM */
   RESET       : origin = 0x3FFFC0, length = 0x000002  /* part of boot ROM */
   VECTORS     : origin = 0x3FFFC2, length = 0x00003E  /* part of boot ROM */

PAGE 1:    /* Data Memory */
   BOOT_RSVD   : origin = 0x000000, length = 0x000050  /* Part of M0, boot ROM stack */
   RAMM0       : origin = 0x000050, length = 0x0003B0  /* on-chip RAM block M0 (stack) */
   RAMM1       : origin = 0x000400, length = 0x000400  /* on-chip RAM block M1 */
   PIEVECT     : origin = 0x000D00, length = 0x000100  /* PIE vector table RAM */
}

SECTIONS
{
   /* Allocate program areas: */
   .cinit              : > RAML0L1     PAGE = 0
   .pinit              : > RAML0L1     PAGE = 0
   /* LLVM emits one .text.<symbol> section per function.  Collect every one
      explicitly so the TI linker cannot place orphan code into the Boot-ROM
      IQTABLES/ROM ranges when RAML0L1 is full. */
   .text               : { *(.text) *(.text.*) *(.textreset) } > RAML0L1 PAGE = 0
   codestart           : > RAML0L1     PAGE = 0
   ramfuncs            : > RAML0L1     PAGE = 0
   .econst             : > RAML0L1     PAGE = 0
   .switch             : > RAML0L1     PAGE = 0
   IQmath              : > RAML0L1     PAGE = 0
   IQmathTables        : > IQTABLES,   PAGE = 0, TYPE = NOLOAD

   /* Allocate uninitialized data sections: */
   .stack              : > RAMM0       PAGE = 1
   .ebss               : > RAMM1       PAGE = 1
   .esysmem            : > RAMM1       PAGE = 1

   /* Standard non-loaded sections (boot ROM owns these): */
   .reset              : > RESET,      PAGE = 0, TYPE = DSECT
   vectors             : > VECTORS,    PAGE = 0, TYPE = DSECT
}
