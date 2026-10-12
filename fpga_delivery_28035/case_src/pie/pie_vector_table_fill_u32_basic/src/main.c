/* pie_vector_table_fill_u32_basic */
#include "board_gpio.h"
#include "board_sram_case.h"
#include "case_config.h"
#include "test_runtime.h"

#if defined(DEVICE_28035)
#include "device_28035.h"
#elif defined(DEVICE_28335)
#include "device_28335.h"
#else
#error Unsupported device
#endif

volatile Uint16 g_pie_fill_u32_fail_low_addr  = 0U;
volatile Uint32 g_pie_fill_u32_fail_expected  = 0U;
volatile Uint32 g_pie_fill_u32_fail_actual    = 0U;

void main(void)
{
    volatile Uint32 * const p_pie = (volatile Uint32 *)PIE_VECT_BASE_WORD_ADDR;
    const unsigned long pie_dword_count =
        ((PIE_VECT_LAST_WORD_ADDR - PIE_VECT_BASE_WORD_ADDR + 1UL) >> 1);
    unsigned long i;
    Uint16 low_word_addr, high_word_addr;
    Uint32 expected, actual;

    board_demo_init();

    EALLOW;
    for (i = 0UL; i < pie_dword_count; ++i) {
        low_word_addr  = (Uint16)(PIE_VECT_BASE_WORD_ADDR + (i << 1));
        high_word_addr = (Uint16)(PIE_VECT_BASE_WORD_ADDR + (i << 1) + 1UL);
        p_pie[i] = ((Uint32)high_word_addr << 16) | (Uint32)low_word_addr;
    }
    EDIS;

    for (i = 0UL; i < pie_dword_count; ++i) {
        low_word_addr  = (Uint16)(PIE_VECT_BASE_WORD_ADDR + (i << 1));
        high_word_addr = (Uint16)(PIE_VECT_BASE_WORD_ADDR + (i << 1) + 1UL);
        expected = ((Uint32)high_word_addr << 16) | (Uint32)low_word_addr;
        actual   = p_pie[i];
        if (actual != expected) {
            g_pie_fill_u32_fail_low_addr  = low_word_addr;
            g_pie_fill_u32_fail_expected  = expected;
            g_pie_fill_u32_fail_actual    = actual;
            test_runtime_fail((unsigned int)low_word_addr);
        }
    }
    test_runtime_pass();
}
