typedef int long i32;
typedef int short i16;

/* sret: real struct return -> hidden return-buffer pointer in XAR6. */
typedef struct { i32 lo; i32 hi; } Wide;
Wide make_wide(i32 a, i32 b) { Wide w; w.lo = a; w.hi = b; return w; }
i32  use_wide(i32 a, i32 b) { Wide w = make_wide(a, b); return w.lo + w.hi; }

/* Stack overflow: only ACC for the first i32, the rest go on the stack. */
i32  many(i32 a, i32 b, i32 c, i32 d, i32 e) { return a + b + c + d + e; }
i32  call_many(void) { return many(1, 2, 3, 4, 5); }

/* i64 return -> TI convention P:ACC (low 32 in P, high 32 in ACC). */
typedef int long long i64;
i64  wide_mul(i32 a, i32 b) { return (i64)a * (i64)b; }
i32  use_widemul(i32 a, i32 b) { return (i32)wide_mul(a, b); }
