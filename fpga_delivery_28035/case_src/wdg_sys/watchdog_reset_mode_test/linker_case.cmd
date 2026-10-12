/* linker_case.cmd for watchdog_reset_mode_test
 * Adds .noinit section in M1 (0x400-0x43F) that is NOT zero-initialised
 * by _c_int00, allowing watchdog reset boot marker to survive watchdog resets.
 */
MEMORY
{
PAGE 0 :
   BEGIN          : origin = 0x000000, length = 0x000002
   RAMM0          : origin = 0x000050, length = 0x0003B0
   RAML0          : origin = 0x008000, length = 0x000800
   RAML1          : origin = 0x008800, length = 0x000500
   RESET          : origin = 0x3FFFC0, length = 0x000002
   IQTABLES       : origin = 0x3FE000, length = 0x000B50
   IQTABLES2      : origin = 0x3FEB50, length = 0x00008C
   IQTABLES3      : origin = 0x3FEBDC, length = 0x0000AA
   BOOTROM        : origin = 0x3FF27C, length = 0x000D44

PAGE 1 :
   BOOT_RSVD      : origin = 0x000002, length = 0x00004E
   NOINIT_MEM     : origin = 0x000400, length = 0x000040
   RAMM1          : origin = 0x000480, length = 0x000380
   RAML2          : origin = 0x008D00, length = 0x000300
   RAML3          : origin = 0x009000, length = 0x001000
}

SECTIONS
{
   codestart          : > BEGIN,      PAGE = 0
   ramfuncs           : > RAMM0,      PAGE = 0
   .text              : >> RAML0 | RAML1, PAGE = 0
   .cinit             : > RAMM0,      PAGE = 0
   .pinit             : > RAMM0,      PAGE = 0
   .switch            : > RAMM0,      PAGE = 0
   .reset             : > RESET,      PAGE = 0, TYPE = DSECT

   .noinit            : > NOINIT_MEM, PAGE = 1, TYPE = NOINIT
   .stack             : > RAMM1,      PAGE = 1
   .ebss              : > RAML2,      PAGE = 1
   .econst            : > RAML2,      PAGE = 1
   .esysmem           : > RAML2,      PAGE = 1

   IQmath             : > RAML1,      PAGE = 0
   IQmathTables       : > IQTABLES,   PAGE = 0, TYPE = NOLOAD
}
