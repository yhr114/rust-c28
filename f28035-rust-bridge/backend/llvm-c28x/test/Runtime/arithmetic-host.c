/* Native IEEE binary32 differential test for the TI-compiled runtime source.
 * NaN payloads may differ; every other bit, including signed zero, must match.
 * This checks the algorithms. It does not replace TI ABI / hardware tests. */
#define C28X_RUNTIME_HOST_TEST
#include "../../../../crates/c28x-compiler-builtins/ti-arithmetic.c"
#include <stdio.h>

static u32 state = 0x28b10001;
static u32 next_bits(void) {
    state ^= state << 13; state ^= state >> 17; state ^= state << 5;
    return state;
}
static int check(u32 a, u32 b) {
    binary32 x, y, want, got;
    unsigned op;
    x.u = a; y.u = b;
    for (op = 0; op < 4; ++op) {
        volatile float va = x.f, vb = y.f;
        switch (op) {
        case 0: want.f = va + vb; got.f = __addsf3(va, vb); break;
        case 1: want.f = va - vb; got.f = __subsf3(va, vb); break;
        case 2: want.f = va * vb; got.f = __mulsf3(va, vb); break;
        default: want.f = va / vb; got.f = __divsf3(va, vb); break;
        }
        if (want.u != got.u && !(is_nan(want.u) && is_nan(got.u))) {
            printf("FAIL op=%u a=%08lx b=%08lx got=%08lx want=%08lx\n",
                   op, (unsigned long)a, (unsigned long)b,
                   (unsigned long)got.u, (unsigned long)want.u);
            return 1;
        }
    }
    return 0;
}
int main(void) {
    static const u32 edge[] = {0, 0x80000000, 1, 2, 0x007fffff, 0x00800000,
        0x00800001, 0x3f800000, 0xbf800000, 0x33800000, 0x7f7fffff,
        0xff7fffff, 0x7f800000, 0xff800000, 0x7fc00000, 0x7f800001};
    unsigned i, j;
    for (i = 0; i < sizeof(edge)/sizeof(edge[0]); ++i)
        for (j = 0; j < sizeof(edge)/sizeof(edge[0]); ++j)
            if (check(edge[i], edge[j])) return 1;
    for (i = 0; i < 250000; ++i) {
        u32 a = next_bits(), b = next_bits();
        if (check(a, b)) return 1;
    }
    puts("PASS binary32: 1001024 native differential operations");
    return 0;
}
