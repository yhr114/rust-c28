/* Compiler-rt entry points for B-1, compiled by TI cl2000 --abi=eabi
 * --float_support=softlib. LLVM uses GCC/compiler-rt names; TI RTS uses its
 * own helper names and internal helper calling convention. Real C wrappers
 * let the TI compiler perform that adaptation instead of aliasing symbols.
 * No pointers cross this interface: arguments/results are raw 32-bit values.
 */
#ifdef C28X_RUNTIME_HOST_TEST
#include <stdint.h>
typedef uint32_t u32;
typedef uint64_t u64;
#else
typedef unsigned long u32;
typedef unsigned long long u64;
typedef char require_ti_long32[(sizeof(u32) == 2) ? 1 : -1];
typedef char require_ti_longlong64[(sizeof(u64) == 4) ? 1 : -1];
typedef char require_ti_float32[(sizeof(float) == 2) ? 1 : -1];
#endif

unsigned long __udivsi3(unsigned long a, unsigned long b) { return a / b; }
unsigned long __umodsi3(unsigned long a, unsigned long b) { return a % b; }
long __divsi3(long a, long b) { return a / b; }
long __modsi3(long a, long b) { return a % b; }

/* TI softlib arithmetic does not implement Rust's IEEE binary32 boundary
 * behavior (including nearest-even rounding and gradual underflow). Keep
 * these operations entirely integer-based; using float arithmetic here
 * would recursively call a runtime helper or reintroduce TI's semantics.
 * The ABI wrapper still takes/returns float, as required by LLVM libcalls.
 */
typedef union { float f; u32 u; } binary32;

static u32 shift_jam(u32 a, unsigned n) {
    if (!n) return a;
    if (n >= 32) return a != 0;
    return (a >> n) | ((a << (32 - n)) != 0);
}

static u32 shift_jam64(u64 a, unsigned n) {
    return (u32)(a >> n) | ((a << (64 - n)) != 0);
}

/* sig has 24 significand bits plus guard/round/sticky bits. exp is the
 * biased exponent, with subnormals using the effective exponent one. */
static u32 round_pack(u32 sign, int exp, u32 sig) {
    u32 tail, rounded;
    if (!sig) return sign;
    if (sig >= 0x08000000ul) { sig = shift_jam(sig, 1); ++exp; }
    while (sig < 0x04000000ul && exp > 1) { sig <<= 1; --exp; }
    if (exp < 1) { sig = shift_jam(sig, (unsigned)(1 - exp)); exp = 1; }
    tail = sig & 7;
    rounded = (sig >> 3) + (tail > 4 || (tail == 4 && ((sig >> 3) & 1)));
    if (rounded >= 0x01000000ul) { rounded >>= 1; ++exp; }
    if (exp >= 255) return sign | 0x7f800000ul;
    return sign | (rounded >= 0x00800000ul ? (u32)exp << 23 : 0) |
           (rounded & 0x007ffffful);
}

static int is_nan(u32 a) { return (a & 0x7ffffffful) > 0x7f800000ul; }
static u32 quiet_nan(u32 a) { return a | 0x00400000ul; }

static u32 add_bits(u32 a, u32 b) {
    u32 sa = a & 0x80000000ul, sb = b & 0x80000000ul;
    u32 ma = a & 0x007ffffful, mb = b & 0x007ffffful, t;
    int ea = (int)((a >> 23) & 255), eb = (int)((b >> 23) & 255), e;
    if (is_nan(a)) return quiet_nan(a);
    if (is_nan(b)) return quiet_nan(b);
    if (ea == 255) return eb == 255 && sa != sb ? 0x7fc00000ul : a;
    if (eb == 255) return b;
    if (ea) ma |= 0x00800000ul; else ea = 1;
    if (eb) mb |= 0x00800000ul; else eb = 1;
    if (ea < eb || (ea == eb && ma < mb)) {
        e = ea; ea = eb; eb = e; t = ma; ma = mb; mb = t;
        t = sa; sa = sb; sb = t;
    }
    ma <<= 3; mb = shift_jam(mb << 3, (unsigned)(ea - eb));
    if (sa == sb) return round_pack(sa, ea, ma + mb);
    if (ma == mb) return 0; /* cancellation is +0 in nearest-even mode */
    return round_pack(sa, ea, ma - mb);
}

static void normalize(u32 *m, int *e) {
    if (*e) *m |= 0x00800000ul;
    else {
        *e = 1;
        while (*m < 0x00800000ul) { *m <<= 1; --*e; }
    }
}

static u32 mul_bits(u32 a, u32 b) {
    u32 sign = (a ^ b) & 0x80000000ul;
    u32 aa = a & 0x7ffffffful, ab = b & 0x7ffffffful;
    u32 ma = a & 0x007ffffful, mb = b & 0x007ffffful;
    int ea = (int)((a >> 23) & 255), eb = (int)((b >> 23) & 255);
    if (is_nan(a)) return quiet_nan(a);
    if (is_nan(b)) return quiet_nan(b);
    if (aa == 0x7f800000ul || ab == 0x7f800000ul)
        return !aa || !ab ? 0x7fc00000ul : sign | 0x7f800000ul;
    if (!aa || !ab) return sign;
    normalize(&ma, &ea); normalize(&mb, &eb);
    return round_pack(sign, ea + eb - 127, shift_jam64((u64)ma * mb, 20));
}

static u32 div_bits(u32 a, u32 b) {
    u32 sign = (a ^ b) & 0x80000000ul, sig;
    u32 aa = a & 0x7ffffffful, ab = b & 0x7ffffffful;
    u32 ma = a & 0x007ffffful, mb = b & 0x007ffffful;
    int ea = (int)((a >> 23) & 255), eb = (int)((b >> 23) & 255), exp;
    u64 numerator;
    if (is_nan(a)) return quiet_nan(a);
    if (is_nan(b)) return quiet_nan(b);
    if (aa == 0x7f800000ul)
        return ab == 0x7f800000ul ? 0x7fc00000ul : sign | 0x7f800000ul;
    if (ab == 0x7f800000ul) return sign;
    if (!ab) return !aa ? 0x7fc00000ul : sign | 0x7f800000ul;
    if (!aa) return sign;
    normalize(&ma, &ea); normalize(&mb, &eb);
    exp = ea - eb + 127;
    numerator = (u64)ma << (ma < mb ? 27 : 26);
    if (ma < mb) --exp;
    sig = (u32)(numerator / mb);
    if (numerator % mb) sig |= 1;
    return round_pack(sign, exp, sig);
}

float __addsf3(float a, float b) {
    binary32 x, y, r; x.f = a; y.f = b; r.u = add_bits(x.u, y.u); return r.f;
}
float __subsf3(float a, float b) {
    binary32 x, y, r; x.f = a; y.f = b;
    /* Do not flip the sign of a NaN operand. */
    r.u = add_bits(x.u, is_nan(y.u) ? y.u : y.u ^ 0x80000000ul); return r.f;
}
float __mulsf3(float a, float b) {
    binary32 x, y, r; x.f = a; y.f = b; r.u = mul_bits(x.u, y.u); return r.f;
}
float __divsf3(float a, float b) {
    binary32 x, y, r; x.f = a; y.f = b; r.u = div_bits(x.u, y.u); return r.f;
}

/* ---- f32 comparisons and integer<->float conversions ----
 * GCC/compiler-rt libcall names that LLVM's soft-float lowering emits for
 * dynamic f32 comparison and i32<->f32 conversion. Comparisons return the
 * compiler-rt three-valued result: -1 if a<b, 0 if a==b, +1 if a>b; the
 * ordered ones return +1 (a<b / a<=b family) or -1 (a>b / a>=b family) when
 * either operand is NaN, so the LLVM branch on the result stays false for
 * unordered operands. Equality returns 0/1; __unordsf2 returns 1 on NaN.
 */

/* Three-valued compare of non-NaN f32 bit patterns: -1 / 0 / +1.
 * -0.0 and +0.0 compare equal; the sign bit orders negative below positive. */
static int float_cmp(u32 a, u32 b) {
    int as = (int)((a >> 31) & 1);
    int bs = (int)((b >> 31) & 1);
    u32 am = a & 0x7fffffffu;
    u32 bm = b & 0x7fffffffu;
    if (am == 0 && bm == 0) return 0;          /* +/-0 equal */
    if (as != bs) return as ? -1 : 1;          /* negative < positive */
    if (am < bm) return as ? 1 : -1;           /* same sign: smaller mag < larger */
    if (am > bm) return as ? -1 : 1;
    return 0;
}

long __lesf2(float a, float b) {
    binary32 x, y; x.f = a; y.f = b;
    if (is_nan(x.u) || is_nan(y.u)) return 1;  /* unordered: a<=b is false */
    return (long)float_cmp(x.u, y.u);
}
long __ltsf2(float a, float b) {
    binary32 x, y; x.f = a; y.f = b;
    if (is_nan(x.u) || is_nan(y.u)) return 1;  /* unordered: a<b is false */
    return (long)float_cmp(x.u, y.u);
}
long __gesf2(float a, float b) {
    binary32 x, y; x.f = a; y.f = b;
    if (is_nan(x.u) || is_nan(y.u)) return -1; /* unordered: a>=b is false */
    return (long)float_cmp(x.u, y.u);
}
long __gtsf2(float a, float b) {
    binary32 x, y; x.f = a; y.f = b;
    if (is_nan(x.u) || is_nan(y.u)) return -1; /* unordered: a>b is false */
    return (long)float_cmp(x.u, y.u);
}
long __eqsf2(float a, float b) {
    binary32 x, y; x.f = a; y.f = b;
    if (is_nan(x.u) || is_nan(y.u)) return 1;  /* NaN != NaN */
    return float_cmp(x.u, y.u) == 0 ? 0 : 1;
}
long __nesf2(float a, float b) {
    binary32 x, y; x.f = a; y.f = b;
    if (is_nan(x.u) || is_nan(y.u)) return 1;  /* NaN != anything */
    return float_cmp(x.u, y.u) != 0 ? 1 : 0;
}
long __unordsf2(float a, float b) {
    binary32 x, y; x.f = a; y.f = b;
    return (is_nan(x.u) || is_nan(y.u)) ? 1 : 0;
}

/* Truncate f32 toward zero to signed 32-bit, saturating out of range. */
long __fixsfsi(float a) {
    binary32 x; x.f = a; u32 u = x.u;
    int sign = (int)((u >> 31) & 1);
    int exp = (int)((u >> 23) & 0xff);
    u32 frac = u & 0x007fffffu;
    if (exp == 0xff) return sign ? (long)0x80000000 : (long)0x7fffffff; /* Inf/NaN */
    if (exp == 0) return 0;                     /* zero/subnormal */
    u32 sig = frac | 0x00800000u;               /* 24-bit significand */
    int shift = exp - 127 - 23;
    long res;
    if (shift >= 0) {
        if (shift >= 8) return sign ? (long)0x80000000 : (long)0x7fffffff;
        res = (long)(sig << shift);
    } else {
        res = (long)(sig >> (-shift));
    }
    return sign ? -res : res;
}

/* Truncate f32 toward zero to unsigned 32-bit; negatives and NaN -> 0,
 * saturate huge values to 0xffffffff. */
unsigned long __fixunssfsi(float a) {
    binary32 x; x.f = a; u32 u = x.u;
    int sign = (int)((u >> 31) & 1);
    int exp = (int)((u >> 23) & 0xff);
    u32 frac = u & 0x007fffffu;
    if (exp == 0xff) {
        if (is_nan(u)) return 0u;              /* NaN -> 0 */
        return sign ? 0u : 0xffffffffu;        /* -Inf -> 0, +Inf saturate */
    }
    if (exp == 0) return 0;
    if (sign) return 0;                         /* negative -> 0 */
    u32 sig = frac | 0x00800000u;
    int shift = exp - 127 - 23;
    if (shift >= 0) {
        if (shift >= 9) return 0xffffffffu;
        return sig << shift;
    }
    return sig >> (-shift);
}

/* Convert signed 32-bit int to f32 (round to nearest, ties to even). */
float __floatsisf(long a) {
    if (a == 0) return 0.0f;
    int sign = (a < 0);
    u32 mag = sign ? (u32)(0u - (unsigned long)a) : (u32)a;
    u32 m = mag;
    int clz = 0;
    while (!(m & 0x80000000u)) { m <<= 1; ++clz; }
    int exp = 31 - clz + 127;
    u32 guard = (m >> 7) & 1u;
    u32 round = (m >> 6) & 1u;
    u32 sticky = (m & 0x3fu) != 0;
    u32 sig24 = m >> 8;
    u32 add = (guard && (round || sticky || (sig24 & 1u))) ? 1u : 0u;
    sig24 += add;
    if (sig24 >= 0x01000000u) { sig24 >>= 1; ++exp; }
    binary32 r;
    r.u = (sign ? 0x80000000u : 0u) | ((u32)exp << 23) | (sig24 & 0x007fffffu);
    return r.f;
}

/* Convert unsigned 32-bit int to f32 (round to nearest, ties to even). */
float __floatunsisf(unsigned long a) {
    if (a == 0) return 0.0f;
    u32 m = (u32)a;
    int clz = 0;
    while (!(m & 0x80000000u)) { m <<= 1; ++clz; }
    int exp = 31 - clz + 127;
    u32 guard = (m >> 7) & 1u;
    u32 round = (m >> 6) & 1u;
    u32 sticky = (m & 0x3fu) != 0;
    u32 sig24 = m >> 8;
    u32 add = (guard && (round || sticky || (sig24 & 1u))) ? 1u : 0u;
    sig24 += add;
    if (sig24 >= 0x01000000u) { sig24 >>= 1; ++exp; }
    binary32 r;
    r.u = ((u32)exp << 23) | (sig24 & 0x007fffffu);
    return r.f;
}

/* ---- 64-bit integer helpers (di3) ----
 * LLVM's multi-precision lowering for i64/u64 arithmetic emits the GCC/
 * compiler-rt names below (NOT TI's own __c28xabi_* names). The C28x EABI
 * passes/returns a long long in ACC:P and these signatures match what the
 * LLVM C28x backend generates for a (long long, long long) -> long long call,
 * so the linker resolves the reference without any adaptation on our side.
 *
 * Each routine is a real C wrapper that performs the native operation. On
 * C28x this is exactly the pattern already used for the 32-bit helpers above
 * (__udivsi3 = a/b, etc.): the TI compiler lowers the 64-bit operator to the
 * matching __c28xabi_* helper, which rts2800_ml_eabi.lib provides. No 64-bit
 * libcall is emitted by our own body, so there is no recursion back to __muldi3
 * / __ashldi3 / etc. (Verified by probe: 32-bit multiply and 64-bit shifts
 * inline; only the 64x64 multiply/divide lower to __c28xabi_mpyll / _divull,
 * which the RTS defines.)
 */
unsigned long long __muldi3(unsigned long long a, unsigned long long b) {
    return a * b;
}
long long __divdi3(long long a, long long b) {
    return a / b;
}
long long __moddi3(long long a, long long b) {
    return a % b;
}
unsigned long long __udivdi3(unsigned long long a, unsigned long long b) {
    return a / b;
}
unsigned long long __umoddi3(unsigned long long a, unsigned long long b) {
    return a % b;
}
unsigned long long __ashldi3(unsigned long long a, int b) {
    return a << (b & 63);
}
unsigned long long __lshrdi3(unsigned long long a, int b) {
    return a >> (b & 63);
}
long long __ashrdi3(long long a, int b) {
    return a >> (b & 63);
}
