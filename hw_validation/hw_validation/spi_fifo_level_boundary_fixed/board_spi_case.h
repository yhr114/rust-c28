#ifndef BOARD_SPI_CASE_H
#define BOARD_SPI_CASE_H
#include "DSP28x_Project.h"
/* TI F28035 word addresses, not the unavailable original SDK mapping. */
#define SPI_REG_SPITXBUF 0x7048UL
#define SPI_REG_SPIFFTX  0x704AUL
#define spi_reg_write16(address, value) (*(volatile unsigned short *)(address) = (value))
#define spi_reg_read16(address) (*(volatile unsigned short *)(address))
#endif

