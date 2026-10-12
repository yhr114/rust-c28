#include "board_lpm_case.h"
#include "case_config.h"
#include "test_runtime.h"

#if defined(DEVICE_28035)
#include "device_28035.h"
#else
#error Unsupported device for sys_lpm_reg_access_basic
#endif

typedef struct {
    Uint16 lpmcr0;
    Uint32 gpiolpmsel;
    Uint16 clkctl_lpm_keep;
    Uint16 scsr_wdenint;
    Uint16 profile_id;
} lpm_reg_profile_t;

static const lpm_reg_profile_t g_sys_lpm_reg_access_basic_profiles[] = {
    {0x0000U,     0x00000001UL, 0x0000U,                                          0U, 1U},
    {0x8005U,     0x00010000UL, S03_LPM_CLKCTL_WDHALTI_MASK,                      1U, 2U},
    {0x00FEU,     0x80000000UL, S03_LPM_CLKCTL_INTOSC1HALTI_MASK,                 0U, 3U},
    {0x80FFU,     0xA5A55A5AUL, (Uint16)(S03_LPM_CLKCTL_WDHALTI_MASK |
                                         S03_LPM_CLKCTL_INTOSC2HALTI_MASK |
                                         S03_LPM_CLKCTL_INTOSC1HALTI_MASK),       1U, 4U}
};

void main(void)
{
    Uint16 saved_lpmcr0;
    Uint16 saved_clkctl;
    Uint16 saved_scsr;
    Uint32 saved_gpiolpmsel;
    unsigned int idx;
    Uint16 rb16;
    Uint32 rb32;

    board_demo_init();
    DisableDog();

    if (lpm_case_read_lpmcr0() != SYS_LPM_REG_ACCESS_BASIC_RESET_LPMCR0) {
        test_runtime_fail(SYS_LPM_REG_ACCESS_BASIC_FAIL_RESET_LPMCR0);
    }

    if (lpm_case_read_gpio_wakeup_mask() != 0UL) {
        test_runtime_fail(SYS_LPM_REG_ACCESS_BASIC_FAIL_RESET_GPIOLPM);
    }

    saved_lpmcr0 = lpm_case_read_lpmcr0();
    saved_clkctl = lpm_case_read_clkctl();
    saved_scsr = lpm_case_read_scsr();
    saved_gpiolpmsel = lpm_case_read_gpio_wakeup_mask();

    for (idx = 0U;
         idx < (sizeof(g_sys_lpm_reg_access_basic_profiles) /
                sizeof(g_sys_lpm_reg_access_basic_profiles[0]));
         ++idx) {
        lpm_case_write_lpmcr0(g_sys_lpm_reg_access_basic_profiles[idx].lpmcr0);
        rb16 = (Uint16)(lpm_case_read_lpmcr0() &
                        (S03_LPM_LPMCR0_WDINTE_MASK |
                         S03_LPM_LPMCR0_QUAL_MASK |
                         S03_LPM_LPMCR0_MODE_MASK));
        if (rb16 != g_sys_lpm_reg_access_basic_profiles[idx].lpmcr0) {
            test_runtime_fail((unsigned int)(SYS_LPM_REG_ACCESS_BASIC_FAIL_LPMCR0_RB_BASE +
                                             g_sys_lpm_reg_access_basic_profiles[idx].profile_id));
        }

        lpm_case_write_gpio_wakeup_mask(g_sys_lpm_reg_access_basic_profiles[idx].gpiolpmsel);
        rb32 = lpm_case_read_gpio_wakeup_mask();
        if (rb32 != g_sys_lpm_reg_access_basic_profiles[idx].gpiolpmsel) {
            test_runtime_fail((unsigned int)(SYS_LPM_REG_ACCESS_BASIC_FAIL_GPIO_RB_BASE +
                                             g_sys_lpm_reg_access_basic_profiles[idx].profile_id));
        }

        lpm_case_write_clkctl_masked(S03_LPM_CLKCTL_LPM_KEEP_MASK,
                                     g_sys_lpm_reg_access_basic_profiles[idx].clkctl_lpm_keep);
        rb16 = (Uint16)(lpm_case_read_clkctl() & S03_LPM_CLKCTL_LPM_KEEP_MASK);
        if (rb16 != g_sys_lpm_reg_access_basic_profiles[idx].clkctl_lpm_keep) {
            test_runtime_fail((unsigned int)(SYS_LPM_REG_ACCESS_BASIC_FAIL_CLKCTL_RB_BASE +
                                             g_sys_lpm_reg_access_basic_profiles[idx].profile_id));
        }

        lpm_case_set_wdint_mode(g_sys_lpm_reg_access_basic_profiles[idx].scsr_wdenint);
        rb16 = (Uint16)((lpm_case_read_scsr() & S03_LPM_SCSR_WDENINT_MASK) ? 1U : 0U);
        if (rb16 != g_sys_lpm_reg_access_basic_profiles[idx].scsr_wdenint) {
            test_runtime_fail((unsigned int)(SYS_LPM_REG_ACCESS_BASIC_FAIL_SCSR_RB_BASE +
                                             g_sys_lpm_reg_access_basic_profiles[idx].profile_id));
        }
    }

    lpm_case_write_lpmcr0(saved_lpmcr0);
    lpm_case_write_gpio_wakeup_mask(saved_gpiolpmsel);
    lpm_case_write_clkctl(saved_clkctl);
    lpm_case_write_scsr(saved_scsr);

    test_runtime_pass();
}
