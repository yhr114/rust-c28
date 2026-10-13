/* F28035 RAM-only linker command file.
   Loads all code and data into on-chip SARAM; no flash sectors are
   touched by loadProgram.  For JTAG/RAM case verification without
   flash programming (flash-and-verify normally writes FLASHA).
   Derived from vendor F28035.cmd; flash-only memory blocks removed.
   Pair with F28035_EABI_sections_ram.cmd (replaces the flash-bound
   F28035_EABI_sections.cmd from f28035-rust-bridge). */

MEMORY
{
PAGE 0:    /* Program Memory */
   RAML0L1     : origin = 0x008000, length = 0x003000  /* on-chip RAM L0+L1+L2+L3 (12K) */

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
   .text               : > RAML0L1     PAGE = 0
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
