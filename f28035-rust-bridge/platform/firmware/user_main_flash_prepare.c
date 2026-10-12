#include "DSP28x_Project.h"
#include <string.h>

extern Uint16 RamfuncsLoadStart;
extern Uint16 RamfuncsLoadSize;
extern Uint16 RamfuncsRunStart;

void f28035_flash_prepare(void)
{
    /* Linker symbols denote addresses, not C variables with stored values. */
    memcpy(&RamfuncsRunStart, &RamfuncsLoadStart,
           (unsigned long)&RamfuncsLoadSize);
    InitFlash();
}
