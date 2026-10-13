typedef int short i16;
typedef int long i32;

i16 f_i16_i32(i16 a, i32 b) { return (i16)(a + (i16)b); }
i32 f_i32_i16(i32 a, i16 b) { return a + (i32)b; }
i16 f_i16_i16_i32(i16 a, i16 b, i32 c) { return (i16)(a + b + (i16)c); }
i32 f_i32_i16_i16(i32 a, i16 b, i16 c) { return a + (i32)b + (i32)c; }
i16 f_i16_i32_i16(i16 a, i32 b, i16 c) { return (i16)(a + (i16)b + c); }
