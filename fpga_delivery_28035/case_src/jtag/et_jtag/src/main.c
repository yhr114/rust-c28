#include "DSP28x_Project.h"

volatile unsigned long a = 0UL;

void main(void)
{
    InitSysCtrl();

    while (1)
    {
        a++;
    }
}
