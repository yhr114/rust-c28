/* EABI section-name supplement for TI's legacy F28035.cmd file.
 * Memory regions are defined by vendor/ti/f2803x/common/cmd/F28035.cmd.
 */
SECTIONS
{
    .bss        : > RAML2  PAGE = 1
    .data       : > RAML2  PAGE = 1
    .sysmem     : > RAML2  PAGE = 1
    .const      : > FLASHA PAGE = 0
    .init_array : > FLASHA PAGE = 0
}

/*
 * TI's legacy F28035.cmd spells the ramfunc copy symbols with COFF-leading
 * underscores.  EABI C references do not add that underscore, so publish
 * EABI aliases without changing the vendor linker file.
 */
RamfuncsLoadStart = _RamfuncsLoadStart;
RamfuncsLoadSize  = _RamfuncsLoadSize;
RamfuncsRunStart  = _RamfuncsRunStart;
