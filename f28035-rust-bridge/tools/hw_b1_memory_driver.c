/* TI C provides the independent byte-lane reference and checks every buffer
 * byte, including untouched sentinels. Rust pointers carry logical BYTE
 * addresses, so C word addresses are doubled explicitly at the boundary. */
#include <string.h>
extern unsigned long rust_memory_copy(unsigned *, const unsigned *, unsigned long);
extern unsigned long rust_memory_copy_intrinsic(unsigned *, const unsigned *, unsigned long);
extern unsigned long rust_memory_move(unsigned *, const unsigned *, unsigned long);
extern unsigned long rust_memory_move_intrinsic(unsigned *, const unsigned *, unsigned long);
extern unsigned long rust_memory_fill(unsigned *, unsigned long, unsigned);
extern unsigned long rust_memory_fill_intrinsic(unsigned *, unsigned long, unsigned);
extern long rust_memory_compare(const unsigned *, const unsigned *, unsigned long);
extern long rust_memory_bcmp(const unsigned *, const unsigned *, unsigned long);
extern void hw_done(void);

#pragma DATA_SECTION(HW_MEMORY_RESULT, ".hw_result")
volatile unsigned HW_MEMORY_RESULT[8];
static unsigned source[64], destination[64], expected[64];
volatile unsigned long HW_MEMORY_LENGTH;
static const unsigned lengths[6] = {0, 1, 3, 7, 33, 67};
#if MEMORY_GROUP == 5
/* Volatile function pointers keep this a test of the actual RTS providers,
 * rather than a constant-size operation inlined by the TI compiler. */
static void *(*volatile ti_copy)(void *, const void *, size_t) = memcpy;
static void *(*volatile ti_move)(void *, const void *, size_t) = memmove;
static void *(*volatile ti_fill)(void *, int, size_t) = memset;
static int (*volatile ti_compare)(const void *, const void *, size_t) = memcmp;
#endif

static unsigned get_byte(const unsigned *p, unsigned i) {
    return (p[i >> 1] >> ((i & 1u) * 8u)) & 255u;
}
static void set_byte(unsigned *p, unsigned i, unsigned v) {
    unsigned shift = (i & 1u) * 8u;
    p[i >> 1] = (p[i >> 1] & ~(255u << shift)) | ((v & 255u) << shift);
}
static unsigned *logical(unsigned *p, unsigned offset) {
    return (unsigned *)((unsigned long)p * 2ul + offset);
}
static void fail(unsigned position, unsigned want, unsigned got) {
    HW_MEMORY_RESULT[1]++;
    if (!HW_MEMORY_RESULT[2]) {
        HW_MEMORY_RESULT[2] = HW_MEMORY_RESULT[0] + 1;
        HW_MEMORY_RESULT[3] = position;
        HW_MEMORY_RESULT[4] = want;
        HW_MEMORY_RESULT[5] = got;
    }
}
static void initialize(void) {
    unsigned i;
    for (i = 0; i < 64; ++i) {
        source[i] = ((i * 11u + 1u) & 255u) | (((i * 13u + 2u) & 255u) << 8);
        destination[i] = expected[i] = 0xDDCCu;
    }
}
static void check_destination(void) {
    unsigned i;
    for (i = 0; i < 128; ++i) {
        unsigned want = get_byte(expected, i), got = get_byte(destination, i);
        if (want != got) fail(i, want, got);
    }
}
static void check_return(unsigned long got, unsigned *d) {
    if (got != (unsigned long)d) fail(0xFFFEu, (unsigned)(unsigned long)d, (unsigned)got);
}

unsigned main(void) {
    unsigned i, s, d, k, variant;
    for (i = 0; i < 8; ++i) HW_MEMORY_RESULT[i] = 0;
    HW_MEMORY_RESULT[6] = MEMORY_GROUP;
#if MEMORY_GROUP == 1
    for (variant = 0; variant < 2; ++variant)
    for (s = 0; s < 2; ++s) for (d = 0; d < 2; ++d) for (k = 0; k < 6; ++k) {
        unsigned n = lengths[k]; unsigned long ret; unsigned *dst;
        initialize();
        for (i = 0; i < n; ++i) set_byte(expected, d + i, get_byte(source, s + i));
        dst = logical(destination, d); HW_MEMORY_LENGTH = n;
        ret = variant ? rust_memory_copy_intrinsic(dst, logical(source, s), HW_MEMORY_LENGTH)
                      : rust_memory_copy(dst, logical(source, s), HW_MEMORY_LENGTH);
        check_return(ret, dst); check_destination();
        for (i = 0; i < 64; ++i) {
            unsigned want = ((i * 11u + 1u) & 255u) | (((i * 13u + 2u) & 255u) << 8);
            if (source[i] != want) fail(128 + i, want, source[i]);
        }
        HW_MEMORY_RESULT[0]++;
    }
#elif MEMORY_GROUP == 2
    for (variant = 0; variant < 2; ++variant)
    for (s = 0; s < 4; ++s) for (d = 0; d < 4; ++d) for (k = 0; k < 6; ++k) {
        unsigned n = lengths[k]; unsigned long ret; unsigned *dst;
        initialize();
        for (i = 0; i < 64; ++i) destination[i] = expected[i] = source[i];
        for (i = 0; i < n; ++i) set_byte(expected, d + i, get_byte(source, s + i));
        dst = logical(destination, d); HW_MEMORY_LENGTH = n;
        ret = variant ? rust_memory_move_intrinsic(dst, logical(destination, s), HW_MEMORY_LENGTH)
                      : rust_memory_move(dst, logical(destination, s), HW_MEMORY_LENGTH);
        check_return(ret, dst); check_destination(); HW_MEMORY_RESULT[0]++;
    }
#elif MEMORY_GROUP == 3
    for (variant = 0; variant < 2; ++variant)
    for (s = 0; s < 3; ++s) for (d = 0; d < 2; ++d) for (k = 0; k < 6; ++k) {
        unsigned n = lengths[k], value = s == 0 ? 0 : (s == 1 ? 0xA5 : 0xFF);
        unsigned long ret; unsigned *dst;
        initialize();
        for (i = 0; i < n; ++i) set_byte(expected, d + i, value);
        dst = logical(destination, d); HW_MEMORY_LENGTH = n;
        ret = variant ? rust_memory_fill_intrinsic(dst, HW_MEMORY_LENGTH, value)
                      : rust_memory_fill(dst, HW_MEMORY_LENGTH, value);
        check_return(ret, dst); check_destination(); HW_MEMORY_RESULT[0]++;
    }
#elif MEMORY_GROUP == 4
    for (variant = 0; variant < 2; ++variant)
    for (s = 0; s < 2; ++s) for (d = 0; d < 2; ++d) for (k = 0; k < 6; ++k) {
        unsigned scenario, n = lengths[k];
        for (scenario = 0; scenario < 3; ++scenario) {
            long result; int sign = 0;
            initialize();
            for (i = 0; i < n; ++i) set_byte(destination, d + i, get_byte(source, s + i));
            if (n && scenario) {
                unsigned offset = scenario == 1 ? 0 : n - 1;
                set_byte(source, s + offset, scenario == 1 ? 1 : 255);
                set_byte(destination, d + offset, scenario == 1 ? 255 : 1);
                sign = scenario == 1 ? -1 : 1;
            }
            HW_MEMORY_LENGTH = n;
            result = variant ? rust_memory_bcmp(logical(source, s), logical(destination, d), HW_MEMORY_LENGTH)
                             : rust_memory_compare(logical(source, s), logical(destination, d), HW_MEMORY_LENGTH);
            if (variant ? ((result != 0) != (sign != 0)) : ((result < 0 ? -1 : (result > 0 ? 1 : 0)) != sign))
                fail(0xFFFDu, (unsigned)sign, (unsigned)result);
            HW_MEMORY_RESULT[0]++;
        }
    }
#elif MEMORY_GROUP == 5
    /* TI C's ordinary names must retain WORD-address semantics alongside the
     * distinct Rust helpers. Its size_t counts C chars (16-bit words here). */
    initialize();
    if (ti_copy(destination, source, 3) != destination) fail(0xFFFEu, 1, 0);
    for (i = 0; i < 3; ++i) if (destination[i] != source[i]) fail(i, source[i], destination[i]);
    HW_MEMORY_RESULT[0]++;
    if (ti_move(destination + 1, destination, 3) != destination + 1) fail(0xFFFEu, 1, 0);
    for (i = 0; i < 3; ++i) if (destination[i + 1] != source[i]) fail(i, source[i], destination[i + 1]);
    HW_MEMORY_RESULT[0]++;
    if (ti_move(destination, destination + 1, 3) != destination) fail(0xFFFEu, 1, 0);
    for (i = 0; i < 3; ++i) if (destination[i] != source[i]) fail(i, source[i], destination[i]);
    HW_MEMORY_RESULT[0]++;
    if (ti_fill(destination, 0xA5, 3) != destination) fail(0xFFFEu, 1, 0);
    for (i = 0; i < 3; ++i) if (destination[i] != 0xA5) fail(i, 0xA5, destination[i]);
    HW_MEMORY_RESULT[0]++;
    destination[0] = source[0]; destination[1] = source[1]; destination[2] = source[2];
    if (ti_compare(source, destination, 3) != 0) fail(0xFFFDu, 0, 1);
    HW_MEMORY_RESULT[0]++;
    source[0] = 1; destination[0] = 255;
    if (ti_compare(source, destination, 3) >= 0) fail(0xFFFDu, 0xFFFFu, 1);
    HW_MEMORY_RESULT[0]++;
#else
#error Invalid MEMORY_GROUP
#endif
    HW_MEMORY_RESULT[7] = 0xB1E0u + MEMORY_GROUP;
    hw_done();
    return 0;
}
