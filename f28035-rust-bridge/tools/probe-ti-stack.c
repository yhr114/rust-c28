/* Diagnostic: TI C stack-argument layout probe.
 * Compiled with cl2000 and run on the target; tools/dss-probe-stkargs.js
 * dumps SP and the stack words at each callee entry so the position of the
 * first stack-argument word can be measured for different argument counts.
 * The constant values (0x5555, 0x1111..0x4444) make the words identifiable. */
typedef unsigned short u16;
typedef unsigned long u32;

volatile u32 HW_RESULT[4];

/* 5 x u16: only e goes on the stack (1 word). */
u32 callee_a(u16 a, u16 b, u16 c, u16 d, u16 e) {
    return (u32)a + b + c + d + e;
}

/* 8 x u16: e,f,g,h go on the stack (4 words). */
u32 callee_b(u16 a, u16 b, u16 c, u16 d, u16 e, u16 f, u16 g, u16 h) {
    return (u32)a + b + c + d + e + f + g + h;
}

unsigned main(void) {
    HW_RESULT[0] = callee_a(11, 12, 13, 14, 0x5555);
    HW_RESULT[1] = callee_b(21, 22, 23, 24, 0x1111, 0x2222, 0x3333, 0x4444);
    HW_RESULT[2] = 0xA5;
    for (;;) {
    }
}
