#include <limits.h>

#if USHRT_MAX != 65535U
#error "Native Rust ABI tests require a 16-bit unsigned short"
#endif

typedef unsigned short rust_u16;

extern rust_u16 rust_native_add(rust_u16 a, rust_u16 b);
extern rust_u16 rust_native_sub(rust_u16 a, rust_u16 b);
extern rust_u16 rust_native_mul(rust_u16 a, rust_u16 b);
extern rust_u16 rust_native_xor(rust_u16 a, rust_u16 b);
extern rust_u16 rust_native_not(rust_u16 value);
extern rust_u16 rust_native_max(rust_u16 a, rust_u16 b);
extern rust_u16 rust_native_add_three(rust_u16 value);
extern rust_u16 rust_native_add_large(rust_u16 value);
extern rust_u16 rust_native_min(rust_u16 a, rust_u16 b);
extern rust_u16 rust_unpack_low_byte(rust_u16 word);
extern rust_u16 rust_unpack_high_byte(rust_u16 word);
extern rust_u16 rust_write_low_byte(rust_u16 word, rust_u16 value);
extern rust_u16 rust_write_high_byte(rust_u16 word, rust_u16 value);
extern rust_u16 c28x_read_logical_byte(const rust_u16 *words, rust_u16 offset);
extern void c28x_write_logical_byte(rust_u16 *words, rust_u16 offset, rust_u16 value);

volatile rust_u16 native_add_actual;
volatile rust_u16 native_sub_actual;
volatile rust_u16 native_mul_actual;
volatile rust_u16 native_xor_actual;
volatile rust_u16 native_not_actual;
volatile rust_u16 native_max_actual;
volatile rust_u16 native_max_reverse_actual;
volatile rust_u16 native_add_three_actual;
volatile rust_u16 native_add_large_actual;
volatile rust_u16 native_min_actual;
volatile rust_u16 native_min_reverse_actual;
volatile rust_u16 packed_low_actual;
volatile rust_u16 packed_high_actual;
volatile rust_u16 packed_write_low_actual;
volatile rust_u16 packed_write_high_actual;
volatile rust_u16 packed_words[2];
volatile rust_u16 pointer_read_0_actual;
volatile rust_u16 pointer_read_1_actual;
volatile rust_u16 pointer_read_2_actual;
volatile rust_u16 pointer_read_3_actual;
volatile rust_u16 pointer_exhaustive_pass;
volatile rust_u16 native_arithmetic_pass;

int main(void)
{
    rust_u16 value;

    /* DSS enters main directly, so do not depend on _c_int00/.cinit here. */
    native_arithmetic_pass = 0U;
    pointer_exhaustive_pass = 0U;
    packed_words[0] = 0x2211U;
    packed_words[1] = 0x4433U;
    native_add_actual = rust_native_add(65535U, 2U);
    native_sub_actual = rust_native_sub(2U, 5U);
    native_mul_actual = rust_native_mul(65535U, 2U);
    native_xor_actual = rust_native_xor(0x55aaU, 0x0ff0U);
    native_not_actual = rust_native_not(0x55aaU);
    native_max_actual = rust_native_max(2U, 65535U);
    native_max_reverse_actual = rust_native_max(65535U, 2U);
    native_add_three_actual = rust_native_add_three(65535U);
    native_add_large_actual = rust_native_add_large(65535U);
    native_min_actual = rust_native_min(0U, 65535U);
    native_min_reverse_actual = rust_native_min(65535U, 2U);
    packed_low_actual = rust_unpack_low_byte(0x2211U);
    packed_high_actual = rust_unpack_high_byte(0x2211U);
    packed_write_low_actual = rust_write_low_byte(0x2211U, 0x01aaU);
    packed_write_high_actual = rust_write_high_byte(0x2211U, 0x01bbU);
    pointer_read_0_actual = c28x_read_logical_byte((const rust_u16 *)packed_words, 0U);
    pointer_read_1_actual = c28x_read_logical_byte((const rust_u16 *)packed_words, 1U);
    pointer_read_2_actual = c28x_read_logical_byte((const rust_u16 *)packed_words, 2U);
    pointer_read_3_actual = c28x_read_logical_byte((const rust_u16 *)packed_words, 3U);
    c28x_write_logical_byte((rust_u16 *)packed_words, 0U, 0x00aaU);
    c28x_write_logical_byte((rust_u16 *)packed_words, 3U, 0x00bbU);
    pointer_exhaustive_pass = 1U;
    for (value = 0U; value < 256U; ++value) {
        packed_words[0] = 0xa55aU;
        c28x_write_logical_byte((rust_u16 *)packed_words, 0U, value);
        if (packed_words[0] != (rust_u16)(0xa500U | value) ||
            c28x_read_logical_byte((const rust_u16 *)packed_words, 0U) != value ||
            c28x_read_logical_byte((const rust_u16 *)packed_words, 1U) != 0x00a5U) {
            pointer_exhaustive_pass = 0U;
            break;
        }

        packed_words[0] = 0xa55aU;
        c28x_write_logical_byte((rust_u16 *)packed_words, 1U, value);
        if (packed_words[0] != (rust_u16)(0x005aU | (value << 8)) ||
            c28x_read_logical_byte((const rust_u16 *)packed_words, 0U) != 0x005aU ||
            c28x_read_logical_byte((const rust_u16 *)packed_words, 1U) != value) {
            pointer_exhaustive_pass = 0U;
            break;
        }
    }
    packed_words[0] = 0x22aaU;
    packed_words[1] = 0xbb33U;
    native_arithmetic_pass =
        (native_add_actual == 1U &&
         native_sub_actual == 65533U &&
         native_mul_actual == 65534U &&
         native_xor_actual == 0x5a5aU &&
         native_not_actual == 0xaa55U &&
         native_max_actual == 65535U &&
         native_max_reverse_actual == 65535U &&
         native_add_three_actual == 2U &&
         native_add_large_actual == 4659U &&
         native_min_actual == 0U &&
         native_min_reverse_actual == 2U &&
         packed_low_actual == 0x0011U &&
         packed_high_actual == 0x0022U &&
         packed_write_low_actual == 0x22aaU &&
         packed_write_high_actual == 0xbb11U &&
         pointer_read_0_actual == 0x0011U &&
         pointer_read_1_actual == 0x0022U &&
         pointer_read_2_actual == 0x0033U &&
         pointer_read_3_actual == 0x0044U &&
         pointer_exhaustive_pass == 1U &&
         packed_words[0] == 0x22aaU &&
         packed_words[1] == 0xbb33U) ? 1U : 0U;

    for (;;) {
    }
}
