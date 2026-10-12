/* pie_vector_table_fill_u16_basic */
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

volatile Uint16 g_pie_fill_fail_addr     = 0U;
volatile Uint16 g_pie_fill_fail_expected = 0U;
volatile Uint16 g_pie_fill_fail_actual   = 0U;

void main(void)
{
    volatile Uint16 * const p_pie = (volatile Uint16 *)PIE_VECT_BASE_WORD_ADDR;
    const unsigned long pie_word_count =
        (PIE_VECT_LAST_WORD_ADDR - PIE_VECT_BASE_WORD_ADDR + 1UL);
    unsigned long i;
    Uint16 expected, actual, fail_addr;

    board_demo_init();

    EALLOW;
    for (i = 0UL; i < pie_word_count; ++i) {
        p_pie[i] = (Uint16)(PIE_VECT_BASE_WORD_ADDR + i);
    }
    EDIS;

    for (i = 0UL; i < pie_word_count; ++i) {
        expected = (Uint16)(PIE_VECT_BASE_WORD_ADDR + i);
        actual   = p_pie[i];
        if (actual != expected) {
            fail_addr = (Uint16)(PIE_VECT_BASE_WORD_ADDR + i);
            g_pie_fill_fail_addr     = fail_addr;
            g_pie_fill_fail_expected = expected;
            g_pie_fill_fail_actual   = actual;
            test_runtime_fail((unsigned int)fail_addr);
        }
    }
    test_runtime_pass();
}
