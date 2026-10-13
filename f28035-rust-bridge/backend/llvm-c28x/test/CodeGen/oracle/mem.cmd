-stack 0x40
MEMORY
{
  M0M1  : origin = 0x000002, length = 0x0007FE
  RAM1  : origin = 0x008000, length = 0x008000
  EXT   : origin = 0x100000, length = 0x2E0000
}
SECTIONS {
  .text       : >> EXT
  .cinit      : >  EXT
  .const      : >> EXT
  .stack      : >  M0M1 | RAM1
  .ebss       : >> M0M1 | RAM1 | EXT
  .data       : >> M0M1 | RAM1 | EXT
  .bss        : >> M0M1 | RAM1 | EXT
}
