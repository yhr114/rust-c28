; hello.reference.s — Expected output of `llc -mtriple=c28x hello.ll`
;
; C source:
;   int main() {
;     int x = 1 + 2;
;     return x;
;   }
;
; This is the assembly the C28x backend should produce.
;

    .sect .text
    .global _main

_main:
    push        acc             ; save callee-saved ACC
    mov         al, #1          ; x = 1
    add         al, #2          ; x = 1 + 2 = 3
    pop         acc             ; restore ACC
    lretr                       ; return (x is already in AL)

; Machine code (16-bit words, stored little-endian: low byte first).
; Every word below was verified against the vendor tools
; (asm2000 -v28 + dis2000 + ofd2000, and cl2000):
;   push acc    : word 1EBD  -> bytes BD 1E
;   mov al, #1  : word 9A01  -> bytes 01 9A   (MOVB AX,#8bit = 1001 101A)
;   add al, #2  : word 9C02  -> bytes 02 9C   (ADDB AX,#8bitSigned = 1001 110A)
;   pop acc     : word 06BE  -> bytes BE 06
;   lretr       : word 0006  -> bytes 06 00
;
; NOTE (historical): earlier revisions of this file listed "6E 80 / 68 01 /
; 64 02 / 6F 80 / 7B 00". Those are NOT C28x opcodes: SPRU430F defines
; PUSH ACC = 0001 1110 1011 1101, POP ACC = 0000 0110 1011 1110, LRETR =
; 0000 0000 0000 0110, and the 8-bit immediate forms are MOVB/ADDB (1001 101A /
; 1001 110A). The old bytes were also printed opcode-byte-first, which is the
; opposite of TI's little-endian word order.
