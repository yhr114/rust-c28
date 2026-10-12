/* RAM-only build: all sections run in place, so the flash->RAM copy table
 * that bridges the F28035_EABI_sections.cmd names does not need to do anything.
 * Define the three symbols the C bridge references to zero (empty copy). */
RamfuncsLoadStart = 0;
RamfuncsLoadSize  = 0;
RamfuncsRunStart  = 0;
