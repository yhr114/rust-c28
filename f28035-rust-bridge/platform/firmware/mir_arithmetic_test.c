#include <limits.h>

#if USHRT_MAX != 65535U
#error "MIR Rust ABI tests require a 16-bit unsigned short"
#endif

typedef unsigned short rust_u16;

extern rust_u16 rust_native_add(rust_u16 a, rust_u16 b);
extern rust_u16 rust_native_sub(rust_u16 a, rust_u16 b);
extern rust_u16 rust_native_mul(rust_u16 a, rust_u16 b);
extern rust_u16 mir_add_then_mul(rust_u16 a, rust_u16 b);
extern rust_u16 mir_xor_then_sub(rust_u16 a, rust_u16 b);
extern rust_u16 mir_linear_mix(rust_u16 a, rust_u16 b);
extern rust_u16 mir_reuse_first_result(rust_u16 a, rust_u16 b);
extern rust_u16 mir_non_lifo_locals(rust_u16 a, rust_u16 b);
extern rust_u16 rust_native_xor(rust_u16 a, rust_u16 b);
extern rust_u16 rust_native_not(rust_u16 value);
extern rust_u16 rust_native_max(rust_u16 a, rust_u16 b);
extern rust_u16 rust_native_min(rust_u16 a, rust_u16 b);
extern rust_u16 rust_native_add_three(rust_u16 value);
extern rust_u16 rust_native_add_large(rust_u16 value);
extern rust_u16 rust_unpack_low_byte(rust_u16 word);
extern rust_u16 rust_unpack_high_byte(rust_u16 word);
extern rust_u16 rust_write_low_byte(rust_u16 word, rust_u16 value);
extern rust_u16 rust_write_high_byte(rust_u16 word, rust_u16 value);

volatile rust_u16 mir_add_actual;
volatile rust_u16 mir_sub_actual;
volatile rust_u16 mir_mul_actual;
volatile rust_u16 mir_call_chain_actual;
volatile rust_u16 mir_call_chain_large_actual;
volatile rust_u16 mir_linear_mix_actual;
volatile rust_u16 mir_reuse_result_actual;
volatile rust_u16 mir_non_lifo_actual;
volatile rust_u16 mir_xor_actual;
volatile rust_u16 mir_not_actual;
volatile rust_u16 mir_max_actual;
volatile rust_u16 mir_min_actual;
volatile rust_u16 mir_add_three_actual;
volatile rust_u16 mir_add_large_actual;
volatile rust_u16 mir_low_byte_actual;
volatile rust_u16 mir_high_byte_actual;
volatile rust_u16 mir_write_low_actual;
volatile rust_u16 mir_write_high_actual;
volatile rust_u16 mir_arithmetic_pass;

int main(void)
{
    mir_arithmetic_pass = 0U;
    mir_add_actual = rust_native_add(65535U, 2U);
    mir_sub_actual = rust_native_sub(2U, 5U);
    mir_mul_actual = rust_native_mul(65535U, 2U);
    mir_call_chain_actual = mir_add_then_mul(65535U, 2U);
    mir_call_chain_large_actual = mir_xor_then_sub(0x55aaU, 0x0ff0U);
    mir_linear_mix_actual = mir_linear_mix(65535U, 2U);
    mir_reuse_result_actual = mir_reuse_first_result(65535U, 2U);
    mir_non_lifo_actual = mir_non_lifo_locals(10U, 5U);
    mir_xor_actual = rust_native_xor(0x55aaU, 0x0ff0U);
    mir_not_actual = rust_native_not(0x55aaU);
    mir_max_actual = rust_native_max(2U, 65535U);
    mir_min_actual = rust_native_min(65535U, 2U);
    mir_add_three_actual = rust_native_add_three(65535U);
    mir_add_large_actual = rust_native_add_large(65535U);
    mir_low_byte_actual = rust_unpack_low_byte(0x2211U);
    mir_high_byte_actual = rust_unpack_high_byte(0x2211U);
    mir_write_low_actual = rust_write_low_byte(0x2211U, 0x01aaU);
    mir_write_high_actual = rust_write_high_byte(0x2211U, 0x01bbU);
    mir_arithmetic_pass =
        (mir_add_actual == 1U &&
         mir_sub_actual == 65533U &&
         mir_mul_actual == 65534U &&
         mir_call_chain_actual == 3U &&
         mir_call_chain_large_actual == 0x4826U &&
         mir_linear_mix_actual == 0x122eU &&
         mir_reuse_result_actual == 0x1234U &&
         mir_non_lifo_actual == 0x48ddU &&
         mir_xor_actual == 0x5a5aU &&
         mir_not_actual == 0xaa55U &&
         mir_max_actual == 65535U &&
         mir_min_actual == 2U &&
         mir_add_three_actual == 2U &&
         mir_add_large_actual == 4659U &&
         mir_low_byte_actual == 0x0011U &&
         mir_high_byte_actual == 0x0022U &&
         mir_write_low_actual == 0x22aaU &&
         mir_write_high_actual == 0xbb11U) ? 1U : 0U;

    for (;;) {
    }
}
