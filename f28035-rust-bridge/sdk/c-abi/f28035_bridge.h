#ifndef F28035_BRIDGE_H
#define F28035_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

typedef unsigned short f28035_u16;

void f28035_system_init(void);
void f28035_enable_interrupts(void);
void f28035_disable_interrupts(void);
/* Task-level global INTM state (1 = enabled).  Shadowed by the
 * enable/disable implementations above; ISR-transient INTM is not visible. */
f28035_u16 f28035_interrupts_enabled(void);
f28035_u16 f28035_gpio_make_output(f28035_u16 pin);
f28035_u16 f28035_gpio_make_input(f28035_u16 pin, f28035_u16 pullup_enabled, f28035_u16 qualification);
f28035_u16 f28035_gpio_read(f28035_u16 pin);
void f28035_gpio_write(f28035_u16 pin, f28035_u16 high);
void f28035_gpio_toggle(f28035_u16 pin);
f28035_u16 f28035_gpio_set_mux(f28035_u16 pin, f28035_u16 function);
f28035_u16 f28035_gpio_mux(f28035_u16 pin);
f28035_u16 f28035_gpio_direction(f28035_u16 pin);
f28035_u16 f28035_gpio_qualification(f28035_u16 pin);
f28035_u16 f28035_gpio_wait_for_level(f28035_u16 pin, f28035_u16 expected);
f28035_u16 f28035_gpio_configure_xint(f28035_u16 line, f28035_u16 pin, f28035_u16 edge);
f28035_u16 f28035_adc_result(f28035_u16 result_index);
f28035_u16 f28035_adc_configure_soc0(f28035_u16 channel, f28035_u16 acqps);
f28035_u16 f28035_adc_sample(f28035_u16 channel);
f28035_u16 f28035_adc_timeouts(void);
f28035_u16 f28035_adc_int1_flag(void);
f28035_u16 f28035_adc_soc0_overflow(void);
f28035_u16 f28035_adc_clock_enabled(void);
f28035_u16 f28035_adc_clkdiv2_enabled(void);
f28035_u16 f28035_adc_ctl1_configured(void);
f28035_u16 f28035_adc_int1_configured(void);
f28035_u16 f28035_adc_soc0_channel(void);
f28035_u16 f28035_adc_soc0_acqps(void);
f28035_u16 f28035_adc_soc0_trigger(void);
f28035_u16 f28035_adc_configure_soc(f28035_u16 soc, f28035_u16 channel, f28035_u16 acqps, f28035_u16 trigger);
f28035_u16 f28035_adc_configure_interrupt(f28035_u16 irq, f28035_u16 eoc);
f28035_u16 f28035_adc_configure_interrupt_mode(f28035_u16 irq, f28035_u16 eoc, f28035_u16 continuous);
void f28035_adc_force_mask(f28035_u16 mask);
f28035_u16 f28035_adc_wait_interrupt(f28035_u16 irq);
f28035_u16 f28035_adc_wait_overflow(f28035_u16 irq);
void f28035_adc_clear_interrupt(f28035_u16 irq);
void f28035_adc_clear_overflow(f28035_u16 irq);
f28035_u16 f28035_adc_interrupt_flags(void);
f28035_u16 f28035_adc_overflow_flags(void);
f28035_u16 f28035_adc_busy_mask(void);
f28035_u16 f28035_adc_wait_soc_activity(f28035_u16 soc);
f28035_u16 f28035_take_peripherals(void);
f28035_u16 f28035_timer0_start_once_ms(f28035_u16 period_ms);
f28035_u16 f28035_timer0_start_periodic_ms(f28035_u16 period_ms);
void f28035_timer0_ack(void);
void f28035_timer0_stop(void);
void f28035_timer0_restart(void);
f28035_u16 f28035_timer0_set_period_ms(f28035_u16 period_ms);
f28035_u16 f28035_timer0_interrupts(void);
f28035_u16 f28035_timer0_start_adc_trigger(f28035_u16 period_ticks);
void f28035_timer0_stop_adc_trigger(void);
f28035_u16 f28035_epwm1_configure(f28035_u16 period_ticks);
f28035_u16 f28035_epwm1_configure_waveform(
    f28035_u16 period_ticks,
    f28035_u16 compare_ticks,
    f28035_u16 aqctla,
    f28035_u16 counter_mode);
void f28035_epwm1_set_compare(f28035_u16 compare_ticks);
f28035_u16 f28035_epwm1_period(void);
f28035_u16 f28035_epwm1_compare(void);
f28035_u16 f28035_epwm1_aqctla(void);
f28035_u16 f28035_epwm1_counter_mode(void);
f28035_u16 f28035_epwm1_configure_deadband(
    f28035_u16 period_ticks,
    f28035_u16 compare_ticks,
    f28035_u16 delay_ticks);
f28035_u16 f28035_epwm1_dbctl(void);
f28035_u16 f28035_epwm1_dbred(void);
f28035_u16 f28035_epwm1_dbfed(void);
f28035_u16 f28035_epwm1_configure_events(f28035_u16 period_ticks, f28035_u16 compare_ticks);
f28035_u16 f28035_epwm1_event_int_enabled(void);
f28035_u16 f28035_epwm1_event_soca_enabled(void);
f28035_u16 f28035_epwm1_event_int_period(void);
f28035_u16 f28035_epwm1_event_soca_period(void);
f28035_u16 f28035_epwm1_configure_socb(f28035_u16 period_ticks, f28035_u16 compare_ticks);
f28035_u16 f28035_epwm1_event_socb_enabled(void);
f28035_u16 f28035_epwm1_event_socb_period(void);
f28035_u16 f28035_epwm1_set_clock_dividers(f28035_u16 hspclkdiv, f28035_u16 clkdiv);
f28035_u16 f28035_epwm1_hspclkdiv(void);
f28035_u16 f28035_epwm1_clkdiv(void);
f28035_u16 f28035_epwm1_configure_software_trip(f28035_u16 period_ticks, f28035_u16 compare_ticks);
void f28035_epwm1_force_ost(void);
void f28035_epwm1_clear_ost(void);
f28035_u16 f28035_epwm1_tzctl(void);
f28035_u16 f28035_epwm1_tzeint(void);
f28035_u16 f28035_epwm1_wait_ost(f28035_u16 expected);
f28035_u16 f28035_epwm1_configure_external_trip(f28035_u16 period_ticks, f28035_u16 compare_ticks);
f28035_u16 f28035_epwm1_tzsel(void);
void f28035_epwm1_reg_rw_smoke(void);
void f28035_gpio_pin_walk_smoke(void);
void f28035_gpio_xint_falling_smoke(void);
void f28035_gpio_xint_rising_smoke(void);
void f28035_spi_reg_if_rw_basic(void);
void f28035_spi_charlen_sweep_basic(void);
void f28035_spi_internal_loopback_basic(void);
void f28035_spi_triwire_loopback_basic(void);
void f28035_spi_loopback_mode_matrix_basic(void);
void f28035_spi_fifo_rx_boundary_basic(void);
void f28035_spi_fifo_tx_boundary_basic(void);
void f28035_spi_fifo_level_boundary_basic(void);
void f28035_spi_multiple_frame_loopback_basic(void);
void f28035_spi_nonfifo_intflag_irq_basic(void);
void f28035_i2c_reg_readback_sweep_basic(void);
void f28035_i2c_master_write_1byte_basic(void);
void f28035_i2c_master_write_8byte_pattern(void);
void f28035_i2c_master_read_1byte_basic(void);
void f28035_i2c_master_read_8byte_basic(void);
void f28035_i2c_master_write_back_to_back(void);
void f28035_i2c_master_read_back_to_back_basic(void);
void f28035_i2c_master_write_then_read_4byte_basic(void);
void f28035_i2c_master_addr_nack_stop_basic(void);
void f28035_i2c_master_repeated_start_write_then_read_4byte_basic(void);
void f28035_lin_baud_program_basic(void);
void f28035_lin_header_break_sync_master_basic(void);
void f28035_lin_iodft_loopback_basic(void);
void f28035_lin_reg_if_rw_basic(void);
void f28035_lin_rx_checksum_length_real_basic(void);
void f28035_lin_rx_rxcnt_num_boundary_real_basic(void);
void f28035_lin_sci_multibuf_rdslot_sweep_basic(void);
void f28035_lin_top_mode_loopback_power_cross_basic(void);
void f28035_lin_tx_checksum_ext_real_basic(void);
void f28035_lin_wakeup_break_flag_route_basic(void);
void f28035_sci_reg_if_rw_basic(void);
void f28035_sci_baud_program_basic(void);
void f28035_sci_internal_loopback_basic(void);
void f28035_sci_loopback_data_pattern_basic(void);
void f28035_sci_rxrdy_clear_on_read_basic(void);
void f28035_sci_sciccr_charlen_sweep_basic(void);
void f28035_sci_fifo_reset_then_loopback_basic(void);
void f28035_sci_fifo_rx_basic(void);
void f28035_sci_stop2_parity_charlen_sweep_basic(void);
void f28035_sci_txrdy_int_nonfifo_basic(void);
void f28035_ecap_reg_rw_smoke(void);
void f28035_ecap_apwm_matrix(void);
void f28035_ecap_capture_continuous_wrap(void);
void f28035_ecap_capture_counter_reset(void);
void f28035_ecap_capture_dual_edge(void);
void f28035_ecap_capture_prescale_div2(void);
void f28035_ecap_capture_quad_edge(void);
void f28035_ecap_capture_single_edge(void);
void f28035_ecap_capture_wrap_matrix(void);
void f28035_ecap_interrupt_integration(void);
void f28035_eqep_register_wr(void);
void f28035_eqep_polarity_test(void);
void f28035_eqep_count_basic(void);
void f28035_eqep_mode_test(void);
void f28035_eqep_compare_output_pulse(void);
void f28035_eqep_unit_timer(void);
void f28035_eqep_unit_timeout_test(void);
void f28035_eqep_watchdog_timeout_test(void);
void f28035_eqep_interrupt_gate(void);
void f28035_eqep_reset_fsm_matrix(void);
void f28035_delay_us(f28035_u16 delay_us);
void f28035_test_pass(void);
void f28035_test_fail(f28035_u16 code);

extern volatile f28035_u16 f28035_timer0_interrupt_count;
extern volatile f28035_u16 f28035_peripherals_taken;
extern volatile f28035_u16 f28035_adc_sample_count;
extern volatile f28035_u16 f28035_adc_timeout_count;
extern volatile f28035_u16 f28035_test_status;
extern volatile f28035_u16 f28035_test_fail_code;

#ifdef __cplusplus
}
#endif

#endif
