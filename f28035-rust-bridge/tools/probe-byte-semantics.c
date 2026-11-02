/* Diagnostic: hardware meaning of a C28x byte access.
 *
 * Two byte-addressing schemes are in flight in the backend:
 *   (a) XARn holds a logical BYTE address (word*2 + lane) and the byte op is
 *       the plain/displacement form  MOV AL, *+XARn[0];
 *   (b) XARn holds a WORD address and AR0 carries the lane, using the indexed
 *       form  MOV AL, *+XARn[AR0].
 * TI's compiler emits (a).  This probe stores a known word through a word
 * object, then reads its two bytes through char pointers taken from that same
 * object, so the mapping is measured on the target rather than assumed.
 *
 * Under (a) with WORD = 0x1234:
 *   RES[0] = 0x0034   (byte address word*2 -> low byte)
 *   RES[1] = 0x0012   (byte address word*2+1 -> high byte)
 *   RES[2] = 0x0012   (p[1]: displacement unit is one byte)
 *   RES[4] = 0x00A5   (marker: the probe ran to completion)
 */
typedef unsigned short u16;
typedef unsigned long u32;

volatile u16 WORD;
volatile u16 RES[8];

extern void hw_done(void);

unsigned main(void) {
    volatile unsigned char *b0;
    volatile unsigned char *b1;

    WORD = 0x1234;
    b0 = (volatile unsigned char *)&WORD;
    b1 = b0 + 1;

    RES[0] = *b0;
    RES[1] = *b1;
    RES[2] = b0[1];
    RES[3] = (u16)((u32)b0 & 0xFFFF);

    RES[4] = 0x00A5;
    hw_done();
    for (;;) {
    }
}
