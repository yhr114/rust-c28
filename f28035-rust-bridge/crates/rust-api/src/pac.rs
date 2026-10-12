//! PAC + FFI declarations for F28035.

pub mod ffi {
    #[allow(dead_code)]
    unsafe extern "C" {
        // ---- Basic ----
        pub fn f28035_system_init();
        pub fn f28035_disable_interrupts();
        pub fn f28035_enable_interrupts();
        pub fn f28035_interrupts_enabled() -> u16;
        pub fn f28035_delay_us(us: u16);

        // ---- GPIO ----
        pub fn f28035_gpio30_low();
        pub fn f28035_gpio39_low();
        pub fn f28035_gpio_read_input(pin: u16) -> u16;
        pub fn f28035_gpio_set_low(pin: u16);
        pub fn f28035_gpio_set_high(pin: u16);
        pub fn f28035_gpio_toggle_pin(pin: u16);
        pub fn f28035_gpio_set_output(pin: u16);
        pub fn f28035_gpio_set_input(pin: u16);
        pub fn f28035_gpio_pullup_enable(pin: u16);
        pub fn f28035_gpio_write();
        pub fn f28035_gpio_toggle();
        pub fn f28035_adc_force_mask();
        pub fn f28035_adc_clear_interrupt();
        pub fn f28035_adc_clear_overflow();
        pub fn f28035_timer0_ack();
        pub fn f28035_timer0_stop();
        pub fn f28035_timer0_start_periodic(period: u16);
        pub fn f28035_timer0_restart();
        pub fn f28035_timer0_stop_adc_trigger();
        pub fn f28035_epwm1_set_compare();
        pub fn f28035_epwm1_force_ost();
        pub fn f28035_epwm1_clear_ost();
        pub fn f28035_epwm1_reg_rw_smoke();
        pub fn f28035_gpio_pin_walk_smoke();
        pub fn f28035_gpio_xint_falling_smoke();
        pub fn f28035_gpio_xint_rising_smoke();
        pub fn f28035_spi_reg_if_rw_basic();
        pub fn f28035_spi_charlen_sweep_basic();
        pub fn f28035_spi_internal_loopback_basic();
        pub fn f28035_spi_triwire_loopback_basic();
        pub fn f28035_spi_loopback_mode_matrix_basic();
        pub fn f28035_spi_fifo_rx_boundary_basic();
        pub fn f28035_spi_fifo_tx_boundary_basic();
        pub fn f28035_spi_fifo_level_boundary_basic();
        pub fn f28035_spi_multiple_frame_loopback_basic();
        pub fn f28035_spi_nonfifo_intflag_irq_basic();
        pub fn f28035_i2c_master_addr_nack_stop_basic();
        pub fn f28035_i2c_master_read_1byte_basic();
        pub fn f28035_i2c_master_read_8byte_basic();
        pub fn f28035_i2c_master_read_back_to_back_basic();
        pub fn f28035_i2c_reg_readback_sweep_basic();
        pub fn f28035_i2c_master_repeated_start_write_then_read_4byte_basic();
        pub fn f28035_i2c_master_write_1byte_basic();
        pub fn f28035_i2c_master_write_8byte_pattern();
        pub fn f28035_i2c_master_write_back_to_back();
        pub fn f28035_i2c_master_write_then_read_4byte_basic();
        pub fn f28035_lin_baud_program_basic();
        pub fn f28035_lin_header_break_sync_master_basic();
        pub fn f28035_lin_iodft_loopback_basic();
        pub fn f28035_lin_reg_if_rw_basic();
        pub fn f28035_lin_rx_checksum_length_real_basic();
        pub fn f28035_lin_rx_rxcnt_num_boundary_real_basic();
        pub fn f28035_lin_sci_multibuf_rdslot_sweep_basic();
        pub fn f28035_lin_top_mode_loopback_power_cross_basic();
        pub fn f28035_lin_tx_checksum_ext_real_basic();
        pub fn f28035_lin_wakeup_break_flag_route_basic();
        pub fn f28035_sci_reg_if_rw_basic();
        pub fn f28035_sci_baud_program_basic();
        pub fn f28035_sci_internal_loopback_basic();
        pub fn f28035_sci_loopback_data_pattern_basic();
        pub fn f28035_sci_rxrdy_clear_on_read_basic();
        pub fn f28035_sci_sciccr_charlen_sweep_basic();
        pub fn f28035_sci_fifo_reset_then_loopback_basic();
        pub fn f28035_sci_fifo_rx_basic();
        pub fn f28035_sci_stop2_parity_charlen_sweep_basic();
        pub fn f28035_sci_txrdy_int_nonfifo_basic();
        pub fn f28035_ecap_reg_rw_smoke();
        pub fn f28035_ecap_capture_single_edge();
        pub fn f28035_ecap_capture_dual_edge();
        pub fn f28035_ecap_capture_quad_edge();
        pub fn f28035_ecap_capture_continuous_wrap();
        pub fn f28035_ecap_capture_counter_reset();
        pub fn f28035_ecap_capture_prescale_div2();
        pub fn f28035_ecap_capture_wrap_matrix();
        pub fn f28035_ecap_apwm_matrix();
        pub fn f28035_ecap_interrupt_integration();
        pub fn f28035_eqep_register_wr();
        pub fn f28035_eqep_polarity_test();
        pub fn f28035_eqep_count_basic();
        pub fn f28035_eqep_mode_test();
        pub fn f28035_eqep_compare_output_pulse();
        pub fn f28035_eqep_unit_timer();
        pub fn f28035_eqep_unit_timeout_test();
        pub fn f28035_eqep_watchdog_timeout_test();
        pub fn f28035_eqep_interrupt_gate();
        pub fn f28035_eqep_reset_fsm_matrix();
        // ---- Read functions ----
        pub fn f28035_adc_read_channel(channel: u16) -> u16;
        pub fn f28035_adc_configure_soc0(channel: u16, acqps: u16);
        pub fn f28035_sci_read_byte() -> u16;
        pub fn f28035_sci_print_string(s: *const u8);
        pub fn f28035_sci_print_u16(val: u16);

        // ---- Float math ----
        pub fn f28035_float_add(a: f32, b: f32) -> f32;
        pub fn f28035_float_sub(a: f32, b: f32) -> f32;
        pub fn f28035_float_mul(a: f32, b: f32) -> f32;
        pub fn f28035_float_div(a: f32, b: f32) -> f32;
        pub fn f28035_float_gt(a: f32, b: f32) -> u16;
        pub fn f28035_float_lt(a: f32, b: f32) -> u16;
        pub fn f28035_float_eq(a: f32, b: f32) -> u16;
        pub fn f28035_spi_read_byte() -> u16;
    }
}

// Host-only stubs. These exist only so `cargo test` on x86_64-pc-windows-msvc
// can link the rlib into a test binary. The real implementations live in the
// C bridge built by tools/build-c-bridge.ps1 and are linked only on the C28x
// side. The MIR backend driver does not set `cfg(test)`, so these stubs are
// invisible to the C28x codegen path and the real `extern "C"` declarations
// above remain authoritative for target compilation.
#[cfg(test)]
mod host_stubs {
    #[unsafe(no_mangle)]
    pub extern "C" fn f28035_system_init() {}
    #[unsafe(no_mangle)]
    pub extern "C" fn f28035_disable_interrupts() {}
    #[unsafe(no_mangle)]
    pub extern "C" fn f28035_enable_interrupts() {}
    #[unsafe(no_mangle)]
    pub extern "C" fn f28035_interrupts_enabled() -> u16 { 0 }
    #[unsafe(no_mangle)]
    pub extern "C" fn f28035_delay_us(_us: u16) {}

    #[unsafe(no_mangle)]
    pub extern "C" fn f28035_gpio_read_input(_pin: u16) -> u16 { 0 }
    #[unsafe(no_mangle)]
    pub extern "C" fn f28035_gpio_set_low(_pin: u16) {}
    #[unsafe(no_mangle)]
    pub extern "C" fn f28035_gpio_set_high(_pin: u16) {}
    #[unsafe(no_mangle)]
    pub extern "C" fn f28035_gpio_toggle_pin(_pin: u16) {}
    #[unsafe(no_mangle)]
    pub extern "C" fn f28035_gpio_set_output(_pin: u16) {}
    #[unsafe(no_mangle)]
    pub extern "C" fn f28035_gpio_set_input(_pin: u16) {}

    #[unsafe(no_mangle)]
    pub extern "C" fn f28035_adc_read_channel(_ch: u16) -> u16 { 0 }
    #[unsafe(no_mangle)]
    pub extern "C" fn f28035_adc_configure_soc0(_ch: u16, _acqps: u16) {}

    #[unsafe(no_mangle)]
    pub extern "C" fn f28035_timer0_start_periodic(_period: u16) {}
    #[unsafe(no_mangle)]
    pub extern "C" fn f28035_timer0_stop() {}
    #[unsafe(no_mangle)]
    pub extern "C" fn f28035_timer0_ack() {}
}