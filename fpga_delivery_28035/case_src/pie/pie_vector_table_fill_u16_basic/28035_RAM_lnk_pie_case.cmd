/* PIE vector table case linker.
 * PIE_VECT region (0x0D00-0x0DFF) and PieVectTableFile section placement
 * are declared by SDK header linker (DSP2803x_Headers_nonBIOS.cmd).
 * This linker only handles standard code/data sections.
 */
MEMORY
{
PAGE 0 :
   BEGIN          : origin = 0x000000, length = 0x000002
   RAMM0          : origin = 0x000050, length = 0x0003B0
   RAML3          : origin = 0x009000, length = 0x001000
   RESET          : origin = 0x3FFFC0, length = 0x000002

PAGE 1 :
   BOOT_RSVD      : origin = 0x000002, length = 0x00004E
   RAMM1          : origin = 0x000480, length = 0x000380
   RAML0_DATA     : origin = 0x008000, length = 0x000800
}

SECTIONS
{
   codestart          : > BEGIN,        PAGE = 0
   ramfuncs           : > RAMM0,        PAGE = 0
   .text              : > RAML3,        PAGE = 0
   .cinit             : > RAMM0,        PAGE = 0
   .pinit             : > RAMM0,        PAGE = 0
   .switch            : > RAMM0,        PAGE = 0
   .reset             : > RESET,        PAGE = 0, TYPE = DSECT

   .stack             : > RAMM1,        PAGE = 1
   .ebss              : > RAML0_DATA,   PAGE = 1
   .econst            : > RAML0_DATA,   PAGE = 1
   .esysmem           : > RAML0_DATA,   PAGE = 1
}
