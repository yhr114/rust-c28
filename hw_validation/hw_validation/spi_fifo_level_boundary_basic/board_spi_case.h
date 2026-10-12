#ifndef BOARD_SPI_CASE_H
#define BOARD_SPI_CASE_H
#include "DSP28x_Project.h"
/* TI F28035 word addresses, not the unavailable original SDK mapping. */
#define SPI_REG_SPICCR  0x7040UL
#define SPI_REG_SPICTL  0x7041UL
#define SPI_REG_SPIBRR  0x7044UL
#define SPI_REG_SPITXBUF 0x7048UL
#define SPI_REG_SPIFFTX 0x704AUL
#define SPI_REG_SPIFFRX 0x704BUL
#define SPICCR_SPILBK_MASK    0x0040U  /* bit 6: loopback */
#define SPICCR_SWRSTN_MASK    0x0080U  /* bit 7: SW reset */
#define SPIFFTX_SPIRSTN_MASK  0x8000U  /* bit 15: SPI reset */
#define SPIFFTX_SPIFFENA_MASK 0x4000U  /* bit 14: FIFO enable */
#define SPIFFTX_FFRSTN_MASK   0x2000U  /* bit 13: FIFO reset */
#define SPIFFTX_FFST_MASK     0x0700U  /* bits 10:8: TX FIFO level */
#define SPIFFRX_FFRSTN_MASK   0x2000U  /* bit 13: RX FIFO reset */
#define spi_reg_write16(address, value) (*(volatile unsigned short *)(address) = (value))
#define spi_reg_read16(address) (*(volatile unsigned short *)(address))
#endif
