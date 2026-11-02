/* F28035 B-1 RAM/JTAG profile. Addresses and sizes are TI 16-bit words. */
--retain="*(codestart)"
--retain="*(.pie_table)"
MEMORY {
PAGE 0:
  RAMCODE : origin=0x008000, length=0x002000
PAGE 1:
  RAMSTACK : origin=0x000100, length=0x000300
  RAMDATA  : origin=0x000400, length=0x000400
  PIEVECT  : origin=0x000D00, length=0x000100
}
SECTIONS {
  codestart : > RAMCODE PAGE=0
  .text : { *(.text) *(.text.*) *(.textreset) } > RAMCODE PAGE=0
  .rodata : { *(.rodata) *(.rodata.*) } > RAMCODE PAGE=0
  .pie_table : > RAMCODE PAGE=0
  .cinit : > RAMCODE PAGE=0
  .pinit : > RAMCODE PAGE=0
  .init_array : > RAMCODE PAGE=0
  .switch : > RAMCODE PAGE=0
  .const : > RAMCODE PAGE=0
  .bss : {
    _sbss = .; *(.bss) *(.bss.*) *(.ebss) *(.ebss.*) *(.hw_result)
    _ebss = .;
  } > RAMDATA PAGE=1
  .data : { _sdata = .; *(.data) *(.data.*) *(.econst) _edata = .; } > RAMDATA PAGE=1
  .rt_noinit : { *(.rt_noinit) } > RAMDATA PAGE=1, type=NOINIT
  .stack : > RAMSTACK PAGE=1
  .sysmem : > RAMDATA PAGE=1
}
_sidata=_sdata;
_bss_size=_ebss-_sbss;
_data_size=_edata-_sdata;
/* Legacy symbol spelling: this is the BASE of the upward-growing stack. */
__stack_end=0x0100;
