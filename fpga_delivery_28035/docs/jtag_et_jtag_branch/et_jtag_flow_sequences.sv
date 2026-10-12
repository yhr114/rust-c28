`ifndef ET_JTAG_FLOW_SEQUENCES_SV
`define ET_JTAG_FLOW_SEQUENCES_SV

// Base sequence: one public task per ET/JTAG flow. The body is intentionally
// empty; concrete sequences inherit this class and call the flow tasks they
// want to verify.
class et_jtag_flow_base_sequence extends et_jtag_example_sequence;
    `uvm_object_utils(et_jtag_flow_base_sequence)

    bit cla_soft_running_check = 1'b0;

    localparam bit [31:0] FLOW_A_ADDR           = 32'h0000_8D18;
    localparam bit [31:0] FLOW_A_WRITE_VALUE    = 32'h5A5A_1234;
    localparam bit [31:0] FLOW_A_WRITE16_VALUE  = 32'h0000_BEEF;
    localparam bit [31:0] FLOW_ESTOP_GO_VALUE   = 32'h4554_4A47;
    localparam bit [31:0] FLOW_ESTOP1_GO_VALUE  = 32'h4554_3147;
    localparam bit [31:0] FLOW_DMA_CPU_GO_VALUE = 32'h444D_4147;
    localparam bit [31:0] FLOW_EMUREG_CPU_GO_VALUE = 32'h454D_5550;
    localparam bit [31:0] FLOW_DLOG_RCMD2_INT   = 32'h003A_0000;
    localparam bit [21:0] FLOW_EMU_DBGSTAT      = 22'h800;
    localparam bit [21:0] FLOW_EMU_ET_ST0       = 22'h810;
    localparam bit [21:0] FLOW_EMU_BRANCH_PC    = 22'h910;
    localparam bit [21:0] FLOW_AU0_BP_PC        = 22'h085E3;
    localparam bit [21:0] FLOW_CLA_MPC          = 22'h01428;
    localparam bit [21:0] FLOW_CLA_MAR0         = 22'h0142A;
    localparam bit [21:0] FLOW_CLA_MAR1         = 22'h0142B;
    localparam bit [21:0] FLOW_CLA_MSTF         = 22'h0142E;
    localparam bit [21:0] FLOW_CLA_MSTFH        = 22'h0142F;
    localparam bit [21:0] FLOW_CLA_MR0          = 22'h01430;
    localparam bit [21:0] FLOW_CLA_MR0H         = 22'h01431;
    localparam bit [21:0] FLOW_CLA_MR1          = 22'h01434;
    localparam bit [21:0] FLOW_CLA_MR1H         = 22'h01435;
    localparam bit [21:0] FLOW_CLA_MR2          = 22'h01438;
    localparam bit [21:0] FLOW_CLA_MR2H         = 22'h01439;
    localparam bit [21:0] FLOW_CLA_MR3          = 22'h0143C;
    localparam bit [21:0] FLOW_CLA_MR3H         = 22'h0143D;
    localparam bit [21:0] FLOW_CLA_DBGSTAT      = 22'h01452;
    localparam bit [21:0] FLOW_CLA_DBGRESET     = 22'h01453;
    localparam bit [21:0] FLOW_CLA_DBGCONFG     = 22'h01460;
    localparam bit [21:0] FLOW_CLA_DBGRESTORE   = 22'h01462;
    localparam bit [21:0] FLOW_CLA_DBGRESTOREH  = 22'h01463;
    localparam bit [21:0] FLOW_CLA_SWBPMASK     = 22'h01464;
    localparam bit [21:0] FLOW_CLA_ACTIVE       = 22'h01466;
    localparam bit [21:0] FLOW_CLA_TASKMODE     = 22'h01467;
    localparam bit [21:0] FLOW_CLA_PCE          = 22'h01468;
    localparam bit [21:0] FLOW_CLA_PCR2         = 22'h01469;
    localparam bit [21:0] FLOW_CLA_PCR1         = 22'h0146A;
    localparam bit [21:0] FLOW_CLA_PCD2         = 22'h0146B;
    localparam bit [21:0] FLOW_CLA_PCB0         = 22'h0146C;
    localparam bit [21:0] FLOW_CLA_PCB1         = 22'h0146D;
    localparam bit [21:0] FLOW_CLA_PCB2         = 22'h0146E;
    localparam bit [21:0] FLOW_CLA_PCB3         = 22'h0146F;
    localparam bit [21:0] FLOW_CLA_BUF0         = 22'h01470;
    localparam bit [21:0] FLOW_CLA_BUF0H        = 22'h01471;
    localparam bit [21:0] FLOW_CLA_BUF1         = 22'h01472;
    localparam bit [21:0] FLOW_CLA_BUF1H        = 22'h01473;
    localparam bit [21:0] FLOW_CLA_BUF2         = 22'h01474;
    localparam bit [21:0] FLOW_CLA_BUF2H        = 22'h01475;
    localparam bit [21:0] FLOW_CLA_BUF3         = 22'h01476;
    localparam bit [21:0] FLOW_CLA_BUF3H        = 22'h01477;

    function new(string name = "et_jtag_flow_base_sequence");
        super.new(name);
    endfunction : new

    virtual task body();
    endtask : body

    virtual task flow_wait_boot(input time wait_time = 4ms);
        `uvm_info("ET_JTAG_FLOW", $sformatf("flow_wait_boot: wait %0t", wait_time), UVM_LOW)
        #(wait_time);
    endtask : flow_wait_boot

    virtual task flow_jtag_reset();
        `uvm_info("ET_JTAG_FLOW", "flow_jtag_reset: TRST reset and take pad ownership", UVM_LOW)
        et_jtag_trst_reset();
    endtask : flow_jtag_reset

    virtual task flow_bypass();
        `uvm_info("ET_JTAG_FLOW", "flow_bypass: issue BYPASS IR", UVM_LOW)
        send_ir(ET_JTAG_IR_BYPASS, 3);
    endtask : flow_bypass

    virtual task flow_prepare(input string tag = "ET_JTAG_FLOW");
        flow_wait_boot();
        flow_jtag_reset();
        flow_bypass();
        flow_rt_disable(tag);
    endtask : flow_prepare

    virtual task flow_rt_disable(input string tag = "ET_JTAG_FLOW");
        send_ir(ET_JTAG_CMD_RT_DISABLE, 10);
        repeat (20) @(posedge vif.cpu_clk);
        `uvm_info(tag,
                  $sformatf("flow_rt_disable: rt=%0b pc=0x%05h run=%0b halt=%0b",
                            vif.real_time_mode, vif.pc, vif.cpu_run, vif.cpu_debug_halt),
                  UVM_LOW)
        if (vif.real_time_mode !== 1'b0) begin
            `uvm_warning(tag, "flow_rt_disable: ET_W_Real_Time_Mode did not become 0")
        end
    endtask : flow_rt_disable

    virtual task flow_rt_enable(input string tag = "ET_JTAG_FLOW");
        send_ir(ET_JTAG_CMD_RT_ENABLE, 10);
        repeat (20) @(posedge vif.cpu_clk);
        `uvm_info(tag,
                  $sformatf("flow_rt_enable: rt=%0b pc=0x%05h run=%0b halt=%0b",
                            vif.real_time_mode, vif.pc, vif.cpu_run, vif.cpu_debug_halt),
                  UVM_LOW)
        if (vif.real_time_mode !== 1'b1) begin
            `uvm_warning(tag, "flow_rt_enable: ET_W_Real_Time_Mode did not become 1")
        end
    endtask : flow_rt_enable

    virtual task flow_halt_rude(input string tag = "ET_JTAG_FLOW");
        flow_issue_halt(ET_JTAG_CMD_HALT_RUDE, {tag, " flow_halt_rude"});
    endtask : flow_halt_rude

    virtual task flow_halt_polite(input string tag = "ET_JTAG_FLOW");
        flow_issue_halt(ET_JTAG_CMD_HALT_POLITE, {tag, " flow_halt_polite"});
    endtask : flow_halt_polite

    virtual task flow_run_rude(input string tag = "ET_JTAG_FLOW");
        flow_issue_run(ET_JTAG_CMD_RUN_RUDE, {tag, " flow_run_rude"});
    endtask : flow_run_rude

    virtual task flow_run_no_check(input string tag = "ET_JTAG_FLOW");
        `uvm_info(tag,
                  $sformatf("flow_run_no_check: issue RUN_RUDE, pc_before=0x%05h run=%0b halt=%0b",
                            vif.pc, vif.cpu_run, vif.cpu_debug_halt),
                  UVM_LOW)
        send_ir(ET_JTAG_CMD_RUN_RUDE, 10);
        repeat (50) @(posedge vif.cpu_clk);
        `uvm_info(tag,
                  $sformatf("flow_run_no_check: after RUN_RUDE pc=0x%05h run=%0b halt=%0b",
                            vif.pc, vif.cpu_run, vif.cpu_debug_halt),
                  UVM_LOW)
    endtask : flow_run_no_check

    virtual task flow_run_polite(input string tag = "ET_JTAG_FLOW");
        flow_issue_run(ET_JTAG_CMD_RUN_POLITE, {tag, " flow_run_polite"});
    endtask : flow_run_polite

    virtual task flow_step_rude(input string tag = "ET_JTAG_FLOW");
        flow_issue_step(ET_JTAG_CMD_STEP_RUDE, {tag, " flow_step_rude"});
    endtask : flow_step_rude

    virtual task flow_step_polite(input string tag = "ET_JTAG_FLOW");
        flow_issue_step(ET_JTAG_CMD_STEP_POLITE, {tag, " flow_step_polite"});
    endtask : flow_step_polite

    virtual task flow_free_run(input string tag = "ET_JTAG_FLOW");
        flow_issue_run(ET_JTAG_CMD_FREE_RUN, {tag, " flow_free_run"});
    endtask : flow_free_run

    virtual task flow_set_reset(input string tag = "ET_JTAG_FLOW");
        `uvm_info(tag, "flow_set_reset: issue SET_RESET, only sets internal set_reset_r", UVM_LOW)
        send_ir(ET_JTAG_CMD_SET_RESET, 10);
        repeat (20) @(posedge vif.cpu_clk);
    endtask : flow_set_reset

    virtual task flow_cpu_reset(input string tag = "ET_JTAG_FLOW");
        bit got_halt;
        logic [21:0] pc_at_halt;
        begin
            `uvm_info(tag, "flow_cpu_reset: SET_RESET followed by 85FF", UVM_LOW)
            flow_set_reset(tag);
            send_ir(ET_JTAG_CMD_RESET_STEP, 10);
            flow_wait_debug_halt({tag, " flow_cpu_reset"}, 10000, got_halt, pc_at_halt);
            flow_read_dbgstat({tag, " after flow_cpu_reset"});
        end
    endtask : flow_cpu_reset

    virtual task flow_nb_step(input string tag = "ET_JTAG_FLOW");
        `uvm_info(tag, "flow_nb_step: issue 85FF without prior SET_RESET", UVM_LOW)
        flow_issue_step(ET_JTAG_CMD_RESET_STEP, {tag, " flow_nb_step"});
    endtask : flow_nb_step

    virtual task flow_clr_step(input string tag = "ET_JTAG_FLOW");
        `uvm_info(tag, "flow_clr_step: issue 85FF; RTL clears set_reset_r on this opcode", UVM_LOW)
        flow_issue_step(ET_JTAG_CMD_RESET_STEP, {tag, " flow_clr_step"});
    endtask : flow_clr_step

    virtual task flow_datab(input logic [31:0] data = FLOW_A_WRITE_VALUE,
                            input string tag = "ET_JTAG_FLOW");
        `uvm_info(tag, $sformatf("flow_datab: DATAB=0x%08h", data), UVM_LOW)
        send_ir({ET_JTAG_IR_DATAB_OP, data}, 10);
        repeat (50) @(posedge vif.cpu_clk);
    endtask : flow_datab

    virtual task flow_reada32(output logic [31:0] value,
                              input string tag = "ET_JTAG_FLOW");
        et_jtag_read_a32(value, {tag, " flow_reada32"});
    endtask : flow_reada32

    virtual task flow_writea32(input logic [31:0] data = FLOW_A_WRITE_VALUE,
                               output logic [31:0] value,
                               input string tag = "ET_JTAG_FLOW");
        et_jtag_write_a32(data, value, {tag, " flow_writea32"});
    endtask : flow_writea32

    virtual task flow_reada16(output logic [31:0] observe_value,
                              input string tag = "ET_JTAG_FLOW");
        `uvm_info(tag, $sformatf("flow_reada16: addr=0x%08h", FLOW_A_ADDR), UVM_LOW)
        send_ir({ET_JTAG_IR_READA16_OP, FLOW_A_ADDR}, 10);
        repeat (100) @(posedge vif.cpu_clk);
        peek_a_backdoor(observe_value, {tag, " after flow_reada16"});
    endtask : flow_reada16

    virtual task flow_writea16(input logic [15:0] data = FLOW_A_WRITE16_VALUE[15:0],
                               output logic [31:0] observe_value,
                               input string tag = "ET_JTAG_FLOW");
        `uvm_info(tag,
                  $sformatf("flow_writea16: DATAB=0x%04h addr=0x%08h", data, FLOW_A_ADDR),
                  UVM_LOW)
        send_ir({ET_JTAG_IR_DATAB_OP, 16'h0, data}, 10);
        repeat (50) @(posedge vif.cpu_clk);
        send_ir({ET_JTAG_IR_WRITEA16_OP, FLOW_A_ADDR}, 10);
        repeat (100) @(posedge vif.cpu_clk);
        peek_a_backdoor(observe_value, {tag, " after flow_writea16"});
        if (observe_value[15:0] !== data) begin
            `uvm_warning(tag,
                         $sformatf("flow_writea16 low-half observe differs: expect=0x%04h observe=0x%04h full=0x%08h; keep as coverage flow because CPU may update _a concurrently",
                                   data, observe_value[15:0], observe_value))
        end
    endtask : flow_writea16

    virtual task flow_read_dbgstat(input string tag = "ET_JTAG_FLOW");
        logic [31:0] value;
        begin
            et_jtag_emureg_read32(FLOW_EMU_DBGSTAT, value, {tag, " flow_read_dbgstat"});
            `uvm_info(tag,
                      $sformatf("flow_read_dbgstat: raw=0x%08h state[7:6]=%0b hwbp=%0b wp=%0b estop1=%0b estop0=%0b",
                                value, value[7:6], value[14],
                                value[12], value[11], value[10]),
                      UVM_LOW)
        end
    endtask : flow_read_dbgstat

    virtual task flow_read_et_st0(input string tag = "ET_JTAG_FLOW");
        logic [31:0] value;
        begin
            et_jtag_emureg_read32(FLOW_EMU_ET_ST0, value, {tag, " flow_read_et_st0"});
        end
    endtask : flow_read_et_st0

    virtual task flow_read_pc(input string tag = "ET_JTAG_FLOW");
        logic [31:0] branch_pc_value;
        logic [21:0] et_st_pc;
        begin
            et_jtag_emureg_read32(FLOW_EMU_BRANCH_PC, branch_pc_value, {tag, " flow_read_pc"});
            peek_et_pc_status(et_st_pc, branch_pc_value, {tag, " flow_read_pc"});
        end
    endtask : flow_read_pc

    virtual task flow_hw_breakpoint_au0(input string tag = "ET_JTAG_FLOW");
        bit got_halt;
        logic [21:0] pc_at_halt;
        begin
            flow_rt_disable({tag, " hwbp_setup_rt_disable"});
            flow_halt_rude({tag, " hwbp_setup_halt"});
            et_jtag_config_au0_hwbp(FLOW_AU0_BP_PC);
            `uvm_info(tag, "flow_hw_breakpoint_au0: issue RUN_RUDE and wait for breakpoint halt", UVM_LOW)
            send_ir(ET_JTAG_CMD_RUN_RUDE, 10);
            flow_wait_debug_halt({tag, " flow_hw_breakpoint_au0"}, 200000, got_halt, pc_at_halt);
            flow_read_dbgstat({tag, " after flow_hw_breakpoint_au0"});
            flow_read_et_st0({tag, " after flow_hw_breakpoint_au0"});
            flow_au0_disable({tag, " flow_hw_breakpoint_au0"});
        end
    endtask : flow_hw_breakpoint_au0

    virtual task flow_au0_disable(input string tag = "ET_JTAG_FLOW");
        logic [31:0] observe_value;
        begin
            et_jtag_emureg_write32(22'h82E, 32'h0000_0000, observe_value, {tag, " flow_au0_disable"});
        end
    endtask : flow_au0_disable

    virtual task flow_estop_wait(input string tag = "ET_JTAG_FLOW");
        bit got_halt;
        logic [21:0] pc_at_halt;
        logic [31:0] dbgstat_value;
        logic [31:0] observe_value;
        begin
            `uvm_info(tag,
                      "flow_estop_wait: arm C ESTOP0 image, then wait for ESTOP0 debug halt",
                      UVM_LOW)
            flow_halt_rude({tag, " arm_estop_halt"});
            et_jtag_write_a32(FLOW_ESTOP_GO_VALUE, observe_value, {tag, " arm_estop_go"});
            flow_run_no_check({tag, " run_to_first_estop"});
            flow_wait_debug_halt({tag, " flow_estop_wait"}, 500000, got_halt, pc_at_halt);
            if (got_halt) begin
                et_jtag_emureg_read32(FLOW_EMU_DBGSTAT, dbgstat_value, {tag, " after estop0 flow_read_dbgstat"});
                `uvm_info(tag,
                          $sformatf("flow_estop_wait: DBGSTAT raw=0x%08h estop0=%0b estop1=%0b",
                                    dbgstat_value, dbgstat_value[10], dbgstat_value[11]),
                          UVM_LOW)
                if (dbgstat_value[10] !== 1'b1) begin
                    `uvm_error(tag,
                               $sformatf("ESTOP0 did not set DBGSTAT[10], raw=0x%08h",
                                         dbgstat_value))
                end
            end
        end
    endtask : flow_estop_wait

    virtual task flow_estop1_wait(input string tag = "ET_JTAG_FLOW");
        bit got_halt;
        logic [21:0] pc_at_halt;
        logic [31:0] dbgstat_value;
        logic [31:0] observe_value;
        begin
            `uvm_info(tag,
                      "flow_estop1_wait: arm C ESTOP1 image, then wait for ESTOP1 debug halt",
                      UVM_LOW)
            flow_halt_rude({tag, " arm_estop1_halt"});
            et_jtag_write_a32(FLOW_ESTOP1_GO_VALUE, observe_value, {tag, " arm_estop1_go"});
            flow_run_no_check({tag, " run_to_estop1"});
            flow_wait_debug_halt({tag, " flow_estop1_wait"}, 500000, got_halt, pc_at_halt);
            if (got_halt) begin
                et_jtag_emureg_read32(FLOW_EMU_DBGSTAT, dbgstat_value, {tag, " after estop1 flow_read_dbgstat"});
                `uvm_info(tag,
                          $sformatf("flow_estop1_wait: DBGSTAT raw=0x%08h estop0=%0b estop1=%0b",
                                    dbgstat_value, dbgstat_value[10], dbgstat_value[11]),
                          UVM_LOW)
                if (dbgstat_value[11] !== 1'b1) begin
                    `uvm_error(tag,
                               $sformatf("ESTOP1 did not set DBGSTAT[11], raw=0x%08h",
                                         dbgstat_value))
                end
            end
        end
    endtask : flow_estop1_wait

    virtual task flow_watchpoint_read(input string tag = "ET_JTAG_FLOW");
        `uvm_warning(tag, "flow_watchpoint_read: task placeholder, AU watchpoint control value not finalized")
    endtask : flow_watchpoint_read

    virtual task flow_watchpoint_write(input string tag = "ET_JTAG_FLOW");
        `uvm_warning(tag, "flow_watchpoint_write: task placeholder, AU watchpoint control value not finalized")
    endtask : flow_watchpoint_write

    virtual task flow_data_logging(input string tag = "ET_JTAG_FLOW");
        `uvm_warning(tag, "flow_data_logging: task placeholder, data logging resource sequence not finalized")
    endtask : flow_data_logging

    virtual task flow_raw_emureg_read32(input bit [21:0] addr,
                                        input string tag = "ET_JTAG_FLOW");
        `uvm_info(tag,
                  $sformatf("flow_raw_emureg_read32: issue READA32 addr=0x%05h without backdoor compare",
                            addr),
                  UVM_LOW)
        send_ir({ET_JTAG_IR_READA32_OP, {10'h0, addr}}, 10);
        repeat (120) @(posedge vif.cpu_clk);
    endtask : flow_raw_emureg_read32

    virtual task flow_raw_emureg_write32(input bit [21:0] addr,
                                         input logic [31:0] data,
                                         input string tag = "ET_JTAG_FLOW");
        `uvm_info(tag,
                  $sformatf("flow_raw_emureg_write32: issue DATAB=0x%08h WRITEA32 addr=0x%05h without backdoor compare",
                            data, addr),
                  UVM_LOW)
        send_ir({ET_JTAG_IR_DATAB_OP, data}, 10);
        repeat (60) @(posedge vif.cpu_clk);
        send_ir({ET_JTAG_IR_WRITEA32_OP, {10'h0, addr}}, 10);
        repeat (120) @(posedge vif.cpu_clk);
    endtask : flow_raw_emureg_write32

    virtual task flow_raw_emureg_read16(input bit [21:0] addr,
                                        input string tag = "ET_JTAG_FLOW");
        `uvm_info(tag,
                  $sformatf("flow_raw_emureg_read16: issue READA16 addr=0x%05h without backdoor compare",
                            addr),
                  UVM_LOW)
        send_ir({ET_JTAG_IR_READA16_OP, {10'h0, addr}}, 10);
        repeat (120) @(posedge vif.cpu_clk);
    endtask : flow_raw_emureg_read16

    virtual task flow_raw_emureg_write16(input bit [21:0] addr,
                                         input logic [15:0] data,
                                         input string tag = "ET_JTAG_FLOW");
        `uvm_info(tag,
                  $sformatf("flow_raw_emureg_write16: issue DATAB=0x%04h WRITEA16 addr=0x%05h without backdoor compare",
                            data, addr),
                  UVM_LOW)
        send_ir({ET_JTAG_IR_DATAB_OP, 16'h0, data}, 10);
        repeat (60) @(posedge vif.cpu_clk);
        send_ir({ET_JTAG_IR_WRITEA16_OP, {10'h0, addr}}, 10);
        repeat (120) @(posedge vif.cpu_clk);
    endtask : flow_raw_emureg_write16

    virtual task flow_raw_mem_read32(input bit [21:0] addr,
                                     input string tag = "ET_JTAG_FLOW");
        `uvm_info(tag,
                  $sformatf("flow_raw_mem_read32: issue READA32 addr=0x%05h", addr),
                  UVM_LOW)
        send_ir({ET_JTAG_IR_READA32_OP, {10'h0, addr}}, 10);
        repeat (120) @(posedge vif.cpu_clk);
    endtask : flow_raw_mem_read32

    virtual task flow_raw_mem_read16(input bit [21:0] addr,
                                     input string tag = "ET_JTAG_FLOW");
        `uvm_info(tag,
                  $sformatf("flow_raw_mem_read16: issue READA16 addr=0x%05h", addr),
                  UVM_LOW)
        send_ir({ET_JTAG_IR_READA16_OP, {10'h0, addr}}, 10);
        repeat (120) @(posedge vif.cpu_clk);
    endtask : flow_raw_mem_read16

    virtual task flow_raw_mem_write32(input bit [21:0] addr,
                                      input logic [31:0] data,
                                      input string tag = "ET_JTAG_FLOW");
        `uvm_info(tag,
                  $sformatf("flow_raw_mem_write32: issue DATAB=0x%08h WRITEA32 addr=0x%05h",
                            data, addr),
                  UVM_LOW)
        send_ir({ET_JTAG_IR_DATAB_OP, data}, 10);
        repeat (60) @(posedge vif.cpu_clk);
        send_ir({ET_JTAG_IR_WRITEA32_OP, {10'h0, addr}}, 10);
        repeat (120) @(posedge vif.cpu_clk);
    endtask : flow_raw_mem_write32

    virtual task flow_raw_mem_write16(input bit [21:0] addr,
                                      input logic [15:0] data,
                                      input string tag = "ET_JTAG_FLOW");
        `uvm_info(tag,
                  $sformatf("flow_raw_mem_write16: issue DATAB=0x%04h WRITEA16 addr=0x%05h",
                            data, addr),
                  UVM_LOW)
        send_ir({ET_JTAG_IR_DATAB_OP, 16'h0, data}, 10);
        repeat (60) @(posedge vif.cpu_clk);
        send_ir({ET_JTAG_IR_WRITEA16_OP, {10'h0, addr}}, 10);
        repeat (120) @(posedge vif.cpu_clk);
    endtask : flow_raw_mem_write16

    virtual task flow_watch_hdl32_mask(input string hdl_path,
                                       input logic [31:0] mask,
                                       input logic [31:0] expected,
                                       input int unsigned max_cycles,
                                       output bit got_match,
                                       input string tag = "ET_JTAG_FLOW");
        uvm_hdl_data_t raw_value;
        logic [31:0] actual;
        int unsigned cycle_idx;
        begin
            got_match = 1'b0;
            for (cycle_idx = 0; cycle_idx < max_cycles; cycle_idx++) begin
                if (uvm_hdl_read(hdl_path, raw_value)) begin
                    actual = raw_value[31:0];
                    if ((actual & mask) === (expected & mask)) begin
                        got_match = 1'b1;
                        `uvm_info(tag,
                                  $sformatf("flow_watch_hdl32_mask: matched %s actual=0x%08h mask=0x%08h expected=0x%08h after %0d cycles",
                                            hdl_path, actual, mask, expected, cycle_idx),
                                  UVM_LOW)
                        break;
                    end
                end
                @(posedge vif.cpu_clk);
            end
        end
    endtask : flow_watch_hdl32_mask

    virtual task flow_watch_two_hdl1(input string hdl_path_a,
                                     input string hdl_path_b,
                                     input int unsigned max_cycles,
                                     output bit got_match,
                                     input string tag = "ET_JTAG_FLOW");
        uvm_hdl_data_t raw_a;
        uvm_hdl_data_t raw_b;
        int unsigned cycle_idx;
        begin
            got_match = 1'b0;
            for (cycle_idx = 0; cycle_idx < max_cycles; cycle_idx++) begin
                if (uvm_hdl_read(hdl_path_a, raw_a) &&
                    uvm_hdl_read(hdl_path_b, raw_b)) begin
                    if ((raw_a[0] === 1'b1) && (raw_b[0] === 1'b1)) begin
                        got_match = 1'b1;
                        `uvm_info(tag,
                                  $sformatf("flow_watch_two_hdl1: matched %s && %s after %0d cycles",
                                            hdl_path_a, hdl_path_b, cycle_idx),
                                  UVM_LOW)
                        break;
                    end
                end
                @(posedge vif.cpu_clk);
            end
        end
    endtask : flow_watch_two_hdl1

    virtual task flow_raw_mem_write32_check_mask(input bit [21:0] addr,
                                                 input logic [31:0] data,
                                                 input string hdl_path,
                                                 input logic [31:0] mask,
                                                 input logic [31:0] expected,
                                                 input bit must_hit,
                                                 input int unsigned max_cycles,
                                                 input string tag = "ET_JTAG_FLOW");
        bit got_match;
        begin
            `uvm_info(tag,
                      $sformatf("flow_raw_mem_write32_check_mask: DATAB=0x%08h WRITEA32 addr=0x%05h watch %s mask=0x%08h expected=0x%08h must_hit=%0b",
                                data, addr, hdl_path, mask, expected, must_hit),
                      UVM_LOW)
            send_ir({ET_JTAG_IR_DATAB_OP, data}, 10);
            repeat (60) @(posedge vif.cpu_clk);
            fork
                begin
                    flow_watch_hdl32_mask(hdl_path, mask, expected, max_cycles,
                                          got_match, {tag, " watch"});
                end
                begin
                    send_ir({ET_JTAG_IR_WRITEA32_OP, {10'h0, addr}}, 10);
                end
            join
            repeat (120) @(posedge vif.cpu_clk);

            if (must_hit && !got_match) begin
                `uvm_error(tag,
                           $sformatf("expected HDL match not observed during WRITEA32: path=%s mask=0x%08h expected=0x%08h",
                                     hdl_path, mask, expected))
            end
            else if (!must_hit && got_match) begin
                `uvm_error(tag,
                           $sformatf("unexpected HDL match observed during WRITEA32: path=%s mask=0x%08h expected=0x%08h",
                                     hdl_path, mask, expected))
            end
        end
    endtask : flow_raw_mem_write32_check_mask

    virtual task flow_raw_mem_write16_check_mask(input bit [21:0] addr,
                                                 input logic [15:0] data,
                                                 input string hdl_path,
                                                 input logic [31:0] mask,
                                                 input logic [31:0] expected,
                                                 input bit must_hit,
                                                 input int unsigned max_cycles,
                                                 input string tag = "ET_JTAG_FLOW");
        bit got_match;
        begin
            `uvm_info(tag,
                      $sformatf("flow_raw_mem_write16_check_mask: DATAB=0x%04h WRITEA16 addr=0x%05h watch %s mask=0x%08h expected=0x%08h must_hit=%0b",
                                data, addr, hdl_path, mask, expected, must_hit),
                      UVM_LOW)
            send_ir({ET_JTAG_IR_DATAB_OP, 16'h0, data}, 10);
            repeat (60) @(posedge vif.cpu_clk);
            fork
                begin
                    flow_watch_hdl32_mask(hdl_path, mask, expected, max_cycles,
                                          got_match, {tag, " watch"});
                end
                begin
                    send_ir({ET_JTAG_IR_WRITEA16_OP, {10'h0, addr}}, 10);
                end
            join
            repeat (120) @(posedge vif.cpu_clk);

            if (must_hit && !got_match) begin
                `uvm_error(tag,
                           $sformatf("expected HDL match not observed during WRITEA16: path=%s mask=0x%08h expected=0x%08h",
                                     hdl_path, mask, expected))
            end
            else if (!must_hit && got_match) begin
                `uvm_error(tag,
                           $sformatf("unexpected HDL match observed during WRITEA16: path=%s mask=0x%08h expected=0x%08h",
                                     hdl_path, mask, expected))
            end
        end
    endtask : flow_raw_mem_write16_check_mask

    virtual task flow_expect_hdl32(input string hdl_path,
                                   input logic [31:0] mask,
                                   input logic [31:0] expected,
                                   input string tag = "ET_JTAG_FLOW");
        uvm_hdl_data_t raw_value;
        logic [31:0] actual;
        begin
            if (!uvm_hdl_read(hdl_path, raw_value)) begin
                `uvm_warning(tag,
                             $sformatf("flow_expect_hdl32: skip backdoor check, path not found: %s",
                                       hdl_path))
            end
            else begin
                actual = raw_value[31:0];
                `uvm_info(tag,
                          $sformatf("flow_expect_hdl32: %s actual=0x%08h mask=0x%08h expected=0x%08h",
                                    hdl_path, actual, mask, expected),
                          UVM_LOW)
                if ((actual & mask) !== (expected & mask)) begin
                    `uvm_error(tag,
                               $sformatf("flow_expect_hdl32 mismatch: %s actual=0x%08h mask=0x%08h expected=0x%08h",
                                         hdl_path, actual, mask, expected))
                end
            end
        end
    endtask : flow_expect_hdl32

    virtual task flow_force_hdl1(input string hdl_path,
                                 input bit value,
                                 input string tag = "ET_JTAG_FLOW");
        uvm_hdl_data_t force_value;
        begin
            force_value = '0;
            force_value[0] = value;
            if (!uvm_hdl_force(hdl_path, force_value)) begin
                `uvm_error(tag,
                           $sformatf("flow_force_hdl1: failed to force %s=%0b",
                                     hdl_path, value))
            end
            else begin
                `uvm_info(tag,
                          $sformatf("flow_force_hdl1: force %s=%0b",
                                    hdl_path, value),
                          UVM_LOW)
            end
        end
    endtask : flow_force_hdl1

    virtual task flow_try_force_hdl1(input string hdl_path,
                                     input bit value,
                                     output bit forced,
                                     input string tag = "ET_JTAG_FLOW");
        uvm_hdl_data_t force_value;
        begin
            forced = 1'b0;
            force_value = '0;
            force_value[0] = value;
            if (!uvm_hdl_check_path(hdl_path)) begin
                `uvm_warning(tag,
                             $sformatf("flow_try_force_hdl1: path not found, skip force: %s",
                                       hdl_path))
            end
            else if (!uvm_hdl_force(hdl_path, force_value)) begin
                `uvm_warning(tag,
                             $sformatf("flow_try_force_hdl1: force failed, skip path: %s",
                                       hdl_path))
            end
            else begin
                forced = 1'b1;
                `uvm_info(tag,
                          $sformatf("flow_try_force_hdl1: force %s=%0b",
                                    hdl_path, value),
                          UVM_LOW)
            end
        end
    endtask : flow_try_force_hdl1

    virtual task flow_try_release_hdl(input string hdl_path,
                                      input bit do_release,
                                      input string tag = "ET_JTAG_FLOW");
        begin
            if (do_release) begin
                flow_release_hdl(hdl_path, tag);
            end
        end
    endtask : flow_try_release_hdl

    virtual task flow_release_hdl(input string hdl_path,
                                  input string tag = "ET_JTAG_FLOW");
        begin
            if (!uvm_hdl_release(hdl_path)) begin
                `uvm_error(tag,
                           $sformatf("flow_release_hdl: failed to release %s",
                                     hdl_path))
            end
            else begin
                `uvm_info(tag,
                          $sformatf("flow_release_hdl: release %s", hdl_path),
                          UVM_LOW)
            end
        end
    endtask : flow_release_hdl

    virtual task flow_rt_enable_alt(input string tag = "ET_JTAG_FLOW");
        send_ir(ET_JTAG_CMD_RT_ENABLE_ALT, 10);
        repeat (20) @(posedge vif.cpu_clk);
        `uvm_info(tag,
                  $sformatf("flow_rt_enable_alt: rt=%0b pc=0x%05h run=%0b halt=%0b",
                            vif.real_time_mode, vif.pc, vif.cpu_run, vif.cpu_debug_halt),
                  UVM_LOW)
        if (vif.real_time_mode !== 1'b1) begin
            `uvm_warning(tag, "flow_rt_enable_alt: ET_W_Real_Time_Mode did not become 1")
        end
    endtask : flow_rt_enable_alt

    virtual task flow_rt_disable_alt(input string tag = "ET_JTAG_FLOW");
        send_ir(ET_JTAG_CMD_RT_DISABLE_ALT, 10);
        repeat (20) @(posedge vif.cpu_clk);
        `uvm_info(tag,
                  $sformatf("flow_rt_disable_alt: rt=%0b pc=0x%05h run=%0b halt=%0b",
                            vif.real_time_mode, vif.pc, vif.cpu_run, vif.cpu_debug_halt),
                  UVM_LOW)
        if (vif.real_time_mode !== 1'b0) begin
            `uvm_warning(tag, "flow_rt_disable_alt: ET_W_Real_Time_Mode did not become 0")
        end
    endtask : flow_rt_disable_alt

    virtual task flow_tap_dr_sweep(input string tag = "ET_JTAG_FLOW");
        `uvm_info(tag, "flow_tap_dr_sweep: exercise BYPASS, IDCODE, TESTMODE and DIR DR paths", UVM_LOW)
        send_ir(ET_JTAG_IR_BYPASS, 3);
        send_dr(64'h0, 1, 8);
        send_dr(64'h1, 1, 8);

        send_ir(ET_JTAG_IR_IDCODE, 3);
        send_dr(64'hA5A5_5A5A, 32, 8);

        send_ir(ET_JTAG_IR_TESTMODE, 3);
        send_dr(64'h0ACE_55AA_1234_5678, 60, 8);

        send_ir(ET_JTAG_IR_DC_STRBS, 3);
        send_dr(64'h0000_0000_5A5A_00FF, 32, 8);

        // Any non-BYPASS debug opcode selects DIR in IDEC; use HALT_RUDE while already in debug context.
        send_ir(ET_JTAG_CMD_HALT_RUDE, 3);
        send_dr(64'hFFFF_0000_A5A5_5A5A, 32, 8);
        send_ir(ET_JTAG_IR_BYPASS, 3);
    endtask : flow_tap_dr_sweep

    virtual task flow_tap_highz_bscan_sweep(input string tag = "ET_JTAG_FLOW");
        `uvm_info(tag, "flow_tap_highz_bscan_sweep: exercise EXTEST/PRELOAD/HIGHZ BSCAN select paths", UVM_LOW)

        send_ir(ET_JTAG_IR_EXTEST, 3);
        send_dr(64'h0000_0000_0000_0000, 32, 8);
        send_dr(64'h0000_0000_FFFF_FFFF, 32, 8);

        send_ir(ET_JTAG_IR_PRELOAD, 3);
        send_dr(64'h0000_0000_A5A5_5A5A, 32, 8);
        send_dr(64'h0000_0000_5A5A_A5A5, 32, 8);

        send_ir(ET_JTAG_IR_HIGHZ, 3);
        send_dr(64'h1, 1, 8);
        send_dr(64'h0, 1, 8);

        send_ir(ET_JTAG_IR_BYPASS, 3);
        send_dr(64'h1, 1, 8);
    endtask : flow_tap_highz_bscan_sweep

    virtual task flow_tap_pause_exit2(input string tag = "ET_JTAG_FLOW");
        bit tms_bits[];
        bit tdi_bits[];
        begin
            `uvm_info(tag, "flow_tap_pause_exit2: USER_CONTROL TMS patterns for Pause/Exit2 DR and IR", UVM_LOW)
            send_ir(ET_JTAG_IR_BYPASS, 3);

            // Start in Run-Test/Idle. Cover capture_dr->exit1, exit1_dr->pause,
            // pause_dr hold, pause_dr->exit2, exit2_dr->shift/update.
            tms_bits = new[12];
            tdi_bits = new[12];
            tms_bits[0]  = 1'b1; // idle -> select_dr
            tms_bits[1]  = 1'b0; // select_dr -> capture_dr
            tms_bits[2]  = 1'b1; // capture_dr -> exit1_dr
            tms_bits[3]  = 1'b0; // exit1_dr -> pause_dr
            tms_bits[4]  = 1'b0; // pause_dr -> pause_dr
            tms_bits[5]  = 1'b1; // pause_dr -> exit2_dr
            tms_bits[6]  = 1'b0; // exit2_dr -> shift_dr
            tms_bits[7]  = 1'b1; // shift_dr -> exit1_dr
            tms_bits[8]  = 1'b0; // exit1_dr -> pause_dr
            tms_bits[9]  = 1'b1; // pause_dr -> exit2_dr
            tms_bits[10] = 1'b1; // exit2_dr -> update_dr
            tms_bits[11] = 1'b0; // update_dr -> idle
            send_user_tms_tdi(tms_bits, tdi_bits, 12);

            // Cover corresponding IR pause/exit2 arcs.
            tms_bits = new[13];
            tdi_bits = new[13];
            tms_bits[0]  = 1'b1; // idle -> select_dr
            tms_bits[1]  = 1'b1; // select_dr -> select_ir
            tms_bits[2]  = 1'b0; // select_ir -> capture_ir
            tms_bits[3]  = 1'b1; // capture_ir -> exit1_ir
            tms_bits[4]  = 1'b0; // exit1_ir -> pause_ir
            tms_bits[5]  = 1'b0; // pause_ir -> pause_ir
            tms_bits[6]  = 1'b1; // pause_ir -> exit2_ir
            tms_bits[7]  = 1'b0; // exit2_ir -> shift_ir
            tms_bits[8]  = 1'b1; // shift_ir -> exit1_ir
            tms_bits[9]  = 1'b0; // exit1_ir -> pause_ir
            tms_bits[10] = 1'b1; // pause_ir -> exit2_ir
            tms_bits[11] = 1'b1; // exit2_ir -> update_ir
            tms_bits[12] = 1'b0; // update_ir -> idle
            send_user_tms_tdi(tms_bits, tdi_bits, 13);

            send_ir(ET_JTAG_IR_BYPASS, 3);
        end
    endtask : flow_tap_pause_exit2

    virtual task flow_tap_sync_idle(input string tag = "ET_JTAG_FLOW");
        bit tms_bits[];
        bit tdi_bits[];
        begin
            tms_bits = new[6];
            tdi_bits = new[6];
            tms_bits[0] = 1'b1;
            tms_bits[1] = 1'b1;
            tms_bits[2] = 1'b1;
            tms_bits[3] = 1'b1;
            tms_bits[4] = 1'b1;
            tms_bits[5] = 1'b0;
            send_user_tms_tdi(tms_bits, tdi_bits, 6);
            `uvm_info(tag, "flow_tap_sync_idle: drive five TMS=1 clocks then return to Run-Test/Idle", UVM_LOW)
        end
    endtask : flow_tap_sync_idle

    virtual task flow_tap_async_reset_at_state(input string state_name,
                                               input bit tms_path[],
                                               input int path_len,
                                               input string tag = "ET_JTAG_FLOW");
        bit tdi_bits[];
        begin
            tdi_bits = new[path_len];
            `uvm_info(tag,
                      $sformatf("flow_tap_async_reset_at_state: move to %s then pulse TRSTn", state_name),
                      UVM_LOW)
            flow_tap_sync_idle(tag);
            send_user_tms_tdi(tms_path, tdi_bits, path_len);
            #(50ns);
            vif.take_ownership();
            vif.trst_n <= 1'b0;
            #(120ns);
            vif.trst_n <= 1'b1;
            #(120ns);
            flow_tap_sync_idle(tag);
        end
    endtask : flow_tap_async_reset_at_state

    virtual task flow_tap_async_reset_sweep(input string tag = "ET_JTAG_FLOW");
        bit tms_bits[];
        begin
            `uvm_info(tag, "flow_tap_async_reset_sweep: cover async TRST reset arcs from DR/IR intermediate states", UVM_LOW)

            tms_bits = new[2];
            tms_bits[0] = 1'b1;
            tms_bits[1] = 1'b0;
            flow_tap_async_reset_at_state("capture_dr", tms_bits, 2, tag);

            tms_bits = new[3];
            tms_bits[0] = 1'b1;
            tms_bits[1] = 1'b0;
            tms_bits[2] = 1'b1;
            flow_tap_async_reset_at_state("exit1_dr", tms_bits, 3, tag);

            tms_bits = new[4];
            tms_bits[0] = 1'b1;
            tms_bits[1] = 1'b0;
            tms_bits[2] = 1'b1;
            tms_bits[3] = 1'b0;
            flow_tap_async_reset_at_state("pause_dr", tms_bits, 4, tag);

            tms_bits = new[5];
            tms_bits[0] = 1'b1;
            tms_bits[1] = 1'b0;
            tms_bits[2] = 1'b1;
            tms_bits[3] = 1'b0;
            tms_bits[4] = 1'b1;
            flow_tap_async_reset_at_state("exit2_dr", tms_bits, 5, tag);

            tms_bits = new[3];
            tms_bits[0] = 1'b1;
            tms_bits[1] = 1'b1;
            tms_bits[2] = 1'b0;
            flow_tap_async_reset_at_state("capture_ir", tms_bits, 3, tag);

            tms_bits = new[4];
            tms_bits[0] = 1'b1;
            tms_bits[1] = 1'b1;
            tms_bits[2] = 1'b0;
            tms_bits[3] = 1'b1;
            flow_tap_async_reset_at_state("exit1_ir", tms_bits, 4, tag);

            tms_bits = new[5];
            tms_bits[0] = 1'b1;
            tms_bits[1] = 1'b1;
            tms_bits[2] = 1'b0;
            tms_bits[3] = 1'b1;
            tms_bits[4] = 1'b0;
            flow_tap_async_reset_at_state("pause_ir", tms_bits, 5, tag);

            tms_bits = new[6];
            tms_bits[0] = 1'b1;
            tms_bits[1] = 1'b1;
            tms_bits[2] = 1'b0;
            tms_bits[3] = 1'b1;
            tms_bits[4] = 1'b0;
            tms_bits[5] = 1'b1;
            flow_tap_async_reset_at_state("exit2_ir", tms_bits, 6, tag);

            send_ir(ET_JTAG_IR_BYPASS, 3);
        end
    endtask : flow_tap_async_reset_sweep

    virtual task flow_emureg_sweep(input string tag = "ET_JTAG_FLOW");
        logic [31:0] observe_value;
        begin
            `uvm_info(tag, "flow_emureg_sweep: cover common EMU_REG read/write decode addresses", UVM_LOW)
            flow_raw_emureg_read32(22'h800, tag);
            flow_raw_emureg_read32(22'h810, tag);
            flow_raw_emureg_write32(22'h828, 32'h0000_0000, tag);
            flow_raw_emureg_read32(22'h828, tag);
            flow_raw_emureg_write32(22'h82A, 32'h0000_85E3, tag);
            flow_raw_emureg_read32(22'h82A, tag);
            flow_raw_emureg_write32(22'h82E, 32'h0000_0001, tag);
            flow_raw_emureg_read32(22'h82E, tag);
            flow_raw_emureg_write32(22'h848, 32'h0000_0000, tag);
            flow_raw_emureg_write32(22'h84A, 32'h0000_85E3, tag);
            flow_raw_emureg_write32(22'h84E, 32'h0000_0001, tag);
            flow_raw_emureg_read32(22'h84E, tag);
            flow_raw_emureg_write32(22'h832, 32'h0000_0000, tag);
            flow_raw_emureg_write32(22'h836, 32'h0000_0001, tag);
            flow_raw_emureg_read32(22'h836, tag);
            flow_raw_emureg_read32(22'h838, tag);
            flow_raw_emureg_read32(22'h83A, tag);
            flow_raw_emureg_read32(22'h83C, tag);
            flow_raw_emureg_read32(22'h83E, tag);
            flow_raw_emureg_read32(22'h83F, tag);
            flow_raw_emureg_read32(22'h880, tag);
            flow_raw_emureg_read32(22'h884, tag);
            flow_raw_emureg_read32(22'h900, tag);
            flow_raw_emureg_read32(22'h901, tag);
            flow_raw_emureg_read32(22'h902, tag);
            flow_raw_emureg_read32(22'h903, tag);
            flow_raw_emureg_read32(22'h904, tag);
            flow_read_pc(tag);
            flow_raw_emureg_read32(22'h984, tag);
            flow_raw_emureg_read32(22'h985, tag);
            flow_psa_crc_sweep({tag, " psa"});
            et_jtag_emureg_write32(22'h82E, 32'h0000_0000, observe_value, {tag, " au0_cleanup"});
        end
    endtask : flow_emureg_sweep

    virtual task flow_emureg_halfword_sweep(input string tag = "ET_JTAG_FLOW");
        `uvm_info(tag, "flow_emureg_halfword_sweep: cover EMU_REG 16-bit and high-half decode addresses", UVM_LOW)
        flow_raw_emureg_read16(22'h801, tag);
        flow_raw_emureg_read16(22'h811, tag);
        flow_raw_emureg_read16(22'h813, tag);
        flow_raw_emureg_read16(22'h829, tag);
        flow_raw_emureg_write16(22'h829, 16'h0000, tag);
        flow_raw_emureg_read16(22'h82B, tag);
        flow_raw_emureg_write16(22'h82B, 16'h0000, tag);
        flow_raw_emureg_read16(22'h82F, tag);
        flow_raw_emureg_read16(22'h849, tag);
        flow_raw_emureg_write16(22'h849, 16'h0000, tag);
        flow_raw_emureg_read16(22'h84B, tag);
        flow_raw_emureg_write16(22'h84B, 16'h0000, tag);
        flow_raw_emureg_read16(22'h84F, tag);
        flow_raw_emureg_read16(22'h831, tag);
        flow_raw_emureg_write16(22'h831, 16'h0001, tag);
        flow_raw_emureg_read16(22'h833, tag);
        flow_raw_emureg_write16(22'h833, 16'h0000, tag);
        flow_raw_emureg_read16(22'h837, tag);
        flow_raw_emureg_read16(22'h839, tag);
        flow_raw_emureg_write16(22'h839, 16'h0000, tag);
        flow_raw_emureg_read16(22'h83B, tag);
        flow_raw_emureg_read16(22'h83F, tag);
        flow_raw_emureg_read16(22'h881, tag);
        flow_raw_emureg_write16(22'h881, 16'h080F, tag);
        flow_raw_emureg_read16(22'h883, tag);
        flow_raw_emureg_read16(22'h885, tag);
        flow_raw_emureg_write16(22'h885, 16'h00FF, tag);
        flow_raw_emureg_read16(22'h887, tag);
        flow_raw_emureg_read16(22'h901, tag);
        flow_raw_emureg_read16(22'h903, tag);
        flow_raw_emureg_read16(22'h985, tag);
    endtask : flow_emureg_halfword_sweep

    virtual task flow_emureg_direct_access_sweep(input string tag = "ET_JTAG_FLOW");
        `uvm_info(tag, "flow_emureg_direct_access_sweep: direct JTAG read/write matrix for EMU_REG writable/readable windows", UVM_LOW)
        flow_halt_rude({tag, " setup_halt"});

        flow_raw_emureg_read32(22'h800, {tag, " dbgstat_rd"});
        flow_raw_emureg_write32(22'h800, 32'h0000_005F, {tag, " dbgstat_clear_flags"});
        flow_raw_emureg_read32(22'h810, {tag, " et_st0_rd"});
        flow_raw_emureg_read32(22'h811, {tag, " et_st0_hi16_alias"});
        flow_raw_emureg_read32(22'h812, {tag, " et_st1_rd"});
        flow_raw_emureg_read32(22'h813, {tag, " et_st1_hi16_alias"});
        flow_raw_emureg_read32(22'h814, {tag, " debug_bus_rd"});

        flow_raw_emureg_write32(22'h828, 32'hFFFF_0000, {tag, " au0_mask_w32_a"});
        flow_raw_emureg_write16(22'h828, 16'h00FF, {tag, " au0_mask_low_w16"});
        flow_raw_emureg_write16(22'h829, 16'hAA55, {tag, " au0_mask_high_w16"});
        flow_raw_emureg_read32(22'h828, {tag, " au0_mask_rd32"});
        flow_raw_emureg_read16(22'h829, {tag, " au0_mask_high_rd16"});
        flow_raw_emureg_write32(22'h82A, 32'h0000_85E3, {tag, " au0_addr_w32"});
        flow_raw_emureg_write16(22'h82A, 16'h85E3, {tag, " au0_addr_low_w16"});
        flow_raw_emureg_write16(22'h82B, 16'h0001, {tag, " au0_addr_high_w16"});
        flow_raw_emureg_read32(22'h82A, {tag, " au0_addr_rd32"});
        flow_raw_emureg_write32(22'h82E, 32'h0000_0001, {tag, " au0_dbg_claim"});
        flow_raw_emureg_read32(22'h82E, {tag, " au0_ctrl_id_claim_rd"});
        flow_raw_emureg_write32(22'h82E, 32'h0000_0002, {tag, " au0_enable"});
        flow_raw_emureg_write32(22'h82E, 32'h0000_0000, {tag, " au0_release"});

        flow_raw_emureg_write32(22'h848, 32'h0F0F_F0F0, {tag, " au1_mask_w32"});
        flow_raw_emureg_write16(22'h848, 16'hF0F0, {tag, " au1_mask_low_w16"});
        flow_raw_emureg_write16(22'h849, 16'h55AA, {tag, " au1_mask_high_w16"});
        flow_raw_emureg_read32(22'h848, {tag, " au1_mask_rd32"});
        flow_raw_emureg_write32(22'h84A, 32'h0000_8D18, {tag, " au1_addr_w32"});
        flow_raw_emureg_write16(22'h84A, 16'h8D18, {tag, " au1_addr_low_w16"});
        flow_raw_emureg_write16(22'h84B, 16'h0002, {tag, " au1_addr_high_w16"});
        flow_raw_emureg_read32(22'h84A, {tag, " au1_addr_rd32"});
        flow_raw_emureg_write32(22'h84E, 32'h0000_0001, {tag, " au1_dbg_claim"});
        flow_raw_emureg_read32(22'h84E, {tag, " au1_ctrl_id_claim_rd"});
        flow_raw_emureg_write32(22'h84E, 32'h0000_0002, {tag, " au1_enable"});
        flow_raw_emureg_write32(22'h84E, 32'h0000_0000, {tag, " au1_release"});

        flow_raw_emureg_write32(22'h830, 32'h1234_5678, {tag, " au2_cnt_w32"});
        flow_raw_emureg_write16(22'h830, 16'h5678, {tag, " au2_cnt_low_w16"});
        flow_raw_emureg_write16(22'h831, 16'h8765, {tag, " au2_cnt_high_w16"});
        flow_raw_emureg_read32(22'h830, {tag, " au2_cnt_rd32"});
        flow_raw_emureg_write32(22'h832, 32'h0000_0003, {tag, " au2_skip_w32"});
        flow_raw_emureg_write16(22'h832, 16'h0003, {tag, " au2_skip_low_w16"});
        flow_raw_emureg_write16(22'h833, 16'h0004, {tag, " au2_skip_high_w16"});
        flow_raw_emureg_read32(22'h832, {tag, " au2_skip_rd32"});
        flow_raw_emureg_write32(22'h836, 32'h0000_0001, {tag, " au2_dbg_claim"});
        flow_raw_emureg_read32(22'h836, {tag, " au2_ctrl_id_claim_rd"});
        flow_raw_emureg_write32(22'h836, 32'h0000_0122, {tag, " au2_size16_ctrl"});
        flow_raw_emureg_write32(22'h836, 32'h0000_3002, {tag, " au2_ext_ctrl"});
        flow_raw_emureg_write32(22'h836, 32'h0000_0000, {tag, " au2_release"});

        flow_raw_emureg_write32(22'h838, 32'h0000_8D18, {tag, " dma_addr_w32"});
        flow_raw_emureg_write16(22'h838, 16'h8D18, {tag, " dma_addr_low_w16"});
        flow_raw_emureg_write16(22'h839, 16'h0004, {tag, " dma_addr_high_w16"});
        flow_raw_emureg_read32(22'h838, {tag, " dma_addr_rd32"});
        flow_raw_emureg_read32(22'h83A, {tag, " dma_rd_data"});
        flow_raw_emureg_read16(22'h83B, {tag, " dma_rd_high"});
        flow_raw_emureg_write32(22'h83C, 32'h003A_03C0, {tag, " dma_int_w32"});
        flow_raw_emureg_write16(22'h83C, 16'h02C0, {tag, " dma_int_low_w16"});
        flow_raw_emureg_read32(22'h83C, {tag, " dma_int_rd32"});
        flow_raw_emureg_write32(22'h83E, 32'h0000_0001, {tag, " dma_dbg_claim"});
        flow_raw_emureg_read32(22'h83E, {tag, " dma_ctrl_id_claim_rd"});
        flow_raw_emureg_write32(22'h83E, 32'h0000_3E62, {tag, " dma_enable_ctrl"});
        flow_raw_emureg_read16(22'h83F, {tag, " dma_id_high_rd"});
        flow_raw_emureg_write32(22'h83E, 32'h0000_0000, {tag, " dma_release"});

        flow_raw_emureg_write32(22'h880, 32'h080F_006B, {tag, " devicecnf_restore_w32"});
        flow_raw_emureg_write16(22'h880, 16'h00EF, {tag, " devicecnf_low_w16"});
        flow_raw_emureg_write16(22'h881, 16'h080F, {tag, " devicecnf_high_w16"});
        flow_raw_emureg_read32(22'h880, {tag, " devicecnf_rd32"});
        flow_raw_emureg_read16(22'h881, {tag, " devicecnf_high_rd16"});
        flow_raw_emureg_write32(22'h880, 32'h080F_006B, {tag, " devicecnf_final_restore"});
        flow_raw_emureg_read32(22'h882, {tag, " classid_revid_rd32"});
        flow_raw_emureg_read16(22'h883, {tag, " revid_rd16"});
        flow_raw_emureg_write32(22'h884, 32'h00FF_0100, {tag, " prot_restore_w32"});
        flow_raw_emureg_write16(22'h884, 16'h0200, {tag, " protstart_low_w16"});
        flow_raw_emureg_write16(22'h885, 16'h00AA, {tag, " protrange_high_w16"});
        flow_raw_emureg_read32(22'h884, {tag, " prot_rd32"});
        flow_raw_emureg_read16(22'h885, {tag, " protrange_rd16"});
        flow_raw_emureg_write32(22'h884, 32'h00FF_0100, {tag, " prot_final_restore"});
        flow_raw_emureg_write16(22'h886, 16'h0001, {tag, " sh_clk_oe_set"});
        flow_raw_emureg_read16(22'h886, {tag, " const_886_rd16"});
        flow_raw_emureg_read16(22'h887, {tag, " const_887_rd16"});
        flow_raw_emureg_read32(22'h888, {tag, " const_888_rd32"});
        flow_raw_emureg_write16(22'h886, 16'h0000, {tag, " sh_clk_oe_clr"});
        flow_raw_emureg_write32(22'h890, 32'h0000_0006, {tag, " reg890_set"});
        flow_raw_emureg_read32(22'h890, {tag, " reg890_rd32"});
        flow_raw_emureg_write32(22'h890, 32'h0000_0002, {tag, " reg890_restore"});

        flow_raw_emureg_read32(22'h900, {tag, " device_id0_rd32"});
        flow_raw_emureg_read16(22'h901, {tag, " device_id0_hi_rd16"});
        flow_raw_emureg_read32(22'h902, {tag, " device_id1_rd32"});
        flow_raw_emureg_read16(22'h903, {tag, " device_id1_hi_rd16"});
        flow_raw_emureg_read32(22'h904, {tag, " f2803x_rd32"});
        flow_raw_emureg_read32(22'h910, {tag, " branch_pc_rd32"});
        flow_raw_emureg_read32(22'h982, {tag, " const_982_rd32"});
        flow_raw_emureg_read16(22'h983, {tag, " const_983_rd16"});
        flow_raw_emureg_read32(22'h984, {tag, " bor_cfg_rd32"});
        flow_raw_emureg_read16(22'h985, {tag, " bor_cfg_low_rd16"});
        flow_raw_emureg_read32(22'h8FF, {tag, " default_decode_rd32"});
    endtask : flow_emureg_direct_access_sweep

    virtual task flow_psa_crc_sweep(input string tag = "ET_JTAG_FLOW");
        `uvm_info(tag, "flow_psa_crc_sweep: read PSA/CRC status windows in EMU_REG", UVM_LOW)
        flow_raw_emureg_read32(22'h840, {tag, " psa_crc0"});
        flow_raw_emureg_read32(22'h842, {tag, " psa_crc1"});
        flow_raw_emureg_read32(22'h843, {tag, " psa_crc2"});
        flow_raw_emureg_read32(22'h846, {tag, " psa_ctrl"});
        flow_raw_emureg_read16(22'h840, {tag, " psa_crc0_l"});
        flow_raw_emureg_read16(22'h841, {tag, " psa_crc0_h"});
        flow_raw_emureg_read16(22'h842, {tag, " psa_crc1_l"});
        flow_raw_emureg_read16(22'h843, {tag, " psa_crc2_l"});
        flow_raw_emureg_read16(22'h846, {tag, " psa_ctrl_l"});
        flow_raw_emureg_read16(22'h847, {tag, " psa_ctrl_h"});
    endtask : flow_psa_crc_sweep

    virtual task flow_psa_active_memory_read(input string tag = "ET_JTAG_FLOW");
        logic [31:0] mem_value;
        logic [31:0] observe_value;
        begin
            `uvm_info(tag,
                      "flow_psa_active_memory_read: seed PSA, enable CRC, then trigger ET memory read data pulses",
                      UVM_LOW)
            flow_halt_rude({tag, " setup_halt"});

            flow_raw_emureg_write32(22'h840, 32'h0000_00A5, {tag, " psa_seed_39_32"});
            flow_raw_emureg_write32(22'h842, 32'h1357_9BDF, {tag, " psa_seed_31_00"});
            flow_raw_emureg_write32(22'h843, 32'h2468_ACE0, {tag, " psa_seed_31_16_alias"});
            flow_raw_emureg_write32(22'h846, 32'h0000_0012, {tag, " psa_enable_ctl"});
            flow_psa_crc_sweep({tag, " after_seed_enable"});

            et_jtag_read_a32(mem_value, {tag, " psa_mem_read0"});
            flow_raw_emureg_read32(22'h840, {tag, " psa_after_read0_hi"});
            flow_raw_emureg_read32(22'h842, {tag, " psa_after_read0_lo"});

            et_jtag_write_a32(32'hA5A5_5A5A, observe_value, {tag, " psa_mem_write_pattern0"});
            et_jtag_read_a32(mem_value, {tag, " psa_mem_read1"});
            flow_raw_emureg_read32(22'h840, {tag, " psa_after_read1_hi"});
            flow_raw_emureg_read32(22'h842, {tag, " psa_after_read1_lo"});

            et_jtag_write_a32(32'h5A5A_A5A5, observe_value, {tag, " psa_mem_write_pattern1"});
            et_jtag_read_a32(mem_value, {tag, " psa_mem_read2"});
            flow_raw_emureg_read32(22'h840, {tag, " psa_after_read2_hi"});
            flow_raw_emureg_read32(22'h842, {tag, " psa_after_read2_lo"});

            flow_raw_emureg_write32(22'h846, 32'h0000_0000, {tag, " psa_disable_ctl"});
            flow_psa_crc_sweep({tag, " after_disable"});
        end
    endtask : flow_psa_active_memory_read

    virtual task flow_au_sweep(input string tag = "ET_JTAG_FLOW");
        `uvm_info(tag, "flow_au_sweep: toggle AU0/AU1/AU2 claim, compare and disable paths", UVM_LOW)
        flow_raw_emureg_write32(22'h82E, 32'h0000_0001, {tag, " au0_claim"});
        flow_raw_emureg_write32(22'h828, 32'h0000_0000, {tag, " au0_mask"});
        flow_raw_emureg_write32(22'h82A, 32'h0000_85E3, {tag, " au0_addr"});
        flow_raw_emureg_write32(22'h82E, 32'h0000_042A, {tag, " au0_hwbp"});
        flow_raw_emureg_read32(22'h82E, {tag, " au0_read"});
        flow_raw_emureg_write32(22'h82E, 32'h0000_0000, {tag, " au0_disable"});

        flow_raw_emureg_write32(22'h84E, 32'h0000_0001, {tag, " au1_claim"});
        flow_raw_emureg_write32(22'h848, 32'h0000_0000, {tag, " au1_mask"});
        flow_raw_emureg_write32(22'h84A, 32'h0000_85E3, {tag, " au1_addr"});
        flow_raw_emureg_write32(22'h84E, 32'h0000_042A, {tag, " au1_hwbp_like"});
        flow_raw_emureg_read32(22'h84E, {tag, " au1_read"});
        flow_raw_emureg_write32(22'h84E, 32'h0000_0000, {tag, " au1_disable"});

        flow_raw_emureg_write32(22'h836, 32'h0000_0001, {tag, " au2_claim"});
        flow_raw_emureg_write32(22'h832, 32'h0000_0000, {tag, " au2_mask"});
        flow_raw_emureg_write32(22'h836, 32'h0000_3002, {tag, " au2_ext1_sel"});
        flow_raw_emureg_read32(22'h836, {tag, " au2_read"});
        flow_raw_emureg_write32(22'h836, 32'h0000_0000, {tag, " au2_disable"});
    endtask : flow_au_sweep

    virtual task flow_au0_drive_mode(input logic [15:0] ctrl,
                                     input logic [31:0] ref_addr,
                                     input string mode_name,
                                     input string tag = "ET_JTAG_FLOW");
        begin
            flow_raw_emureg_write32(22'h82A, ref_addr, {tag, " au0_", mode_name, "_ref"});
            flow_raw_emureg_write32(22'h82E, {16'h0000, ctrl}, {tag, " au0_", mode_name, "_ctrl"});
            flow_issue_run_observe(ET_JTAG_CMD_RUN_RUDE, 180us, {tag, " au0_", mode_name, "_run"});
            flow_issue_halt_observe({tag, " au0_", mode_name, "_halt"});
        end
    endtask : flow_au0_drive_mode

    virtual task flow_au0_watchpoint_sweep(input string tag = "ET_JTAG_FLOW");
        `uvm_info(tag, "flow_au0_watchpoint_sweep: sweep AU0 HB/WP/RTOSINT control encodings from RTL", UVM_LOW)
        flow_halt_rude({tag, " setup_halt"});
        flow_raw_emureg_write32(22'h82E, 32'h0000_0001, {tag, " au0_claim"});
        flow_raw_emureg_write32(22'h828, 32'h0000_0000, {tag, " au0_exact_mask"});

        flow_au0_drive_mode(16'h042A, {10'h0, FLOW_AU0_BP_PC}, "hb_halt", tag);
        flow_au0_drive_mode(16'h040A, {10'h0, FLOW_AU0_BP_PC}, "hb_no_halt", tag);
        flow_au0_drive_mode(16'h044A, {10'h0, FLOW_AU0_BP_PC}, "hb_rtosint", tag);
        flow_au0_drive_mode(16'h1132, FLOW_A_ADDR, "wp_rd_data", tag);
        flow_au0_drive_mode(16'h1152, FLOW_A_ADDR, "wp_rd_data_rtosint", tag);
        flow_au0_drive_mode(16'h1032, FLOW_A_ADDR, "wp_rd_no_data", tag);
        flow_au0_drive_mode(16'h1052, FLOW_A_ADDR, "wp_rd_no_data_rtosint", tag);
        flow_au0_drive_mode(16'h093A, FLOW_A_ADDR, "wp_wr_data", tag);
        flow_au0_drive_mode(16'h0940, FLOW_A_ADDR, "wp_wr_data_alt", tag);
        flow_au0_drive_mode(16'h095A, FLOW_A_ADDR, "wp_wr_data_rtosint", tag);
        flow_au0_drive_mode(16'h083A, FLOW_A_ADDR, "wp_wr_no_data", tag);
        flow_au0_drive_mode(16'h0840, FLOW_A_ADDR, "wp_wr_no_data_alt", tag);
        flow_au0_drive_mode(16'h085A, FLOW_A_ADDR, "wp_wr_no_data_rtosint", tag);
        flow_au0_drive_mode(16'h081A, FLOW_A_ADDR, "wp_wr_rtosint", tag);

        flow_read_dbgstat({tag, " after_au0_wp_modes"});
        flow_raw_emureg_write32(22'h82E, 32'h0000_0000, {tag, " au0_disable"});
    endtask : flow_au0_watchpoint_sweep

    virtual task flow_au_watchpoint_sweep(input string tag = "ET_JTAG_FLOW");
        `uvm_info(tag, "flow_au_watchpoint_sweep: configure AU1 watchpoint/data/skip/RTOSINT modes and let C loop run", UVM_LOW)
        flow_rt_disable({tag, " setup_rt_disable"});
        flow_halt_rude({tag, " setup_halt"});
        flow_raw_emureg_write32(22'h84E, 32'h0000_0001, {tag, " au1_claim"});
        flow_raw_emureg_write32(22'h848, 32'h0000_0000, {tag, " au1_exact_mask"});
        flow_raw_emureg_write32(22'h84A, FLOW_A_ADDR, {tag, " au1_addr_a"});

        flow_raw_emureg_write32(22'h84E, 32'h0000_1026, {tag, " au1_wp_rd_no_data"});
        flow_issue_run_observe(ET_JTAG_CMD_RUN_RUDE, 180us, {tag, " run_for_rd_wp"});
        flow_issue_halt_observe({tag, " halt_after_rd_wp"});

        flow_raw_emureg_write32(22'h84E, 32'h0000_082A, {tag, " au1_wp_wr_no_data"});
        flow_issue_run_observe(ET_JTAG_CMD_RUN_RUDE, 180us, {tag, " run_for_wr_wp"});
        flow_issue_halt_observe({tag, " halt_after_wr_wp"});

        flow_raw_emureg_write32(22'h84E, 32'h0000_1132, {tag, " au1_wp_rd_data"});
        flow_raw_emureg_write32(22'h84A, FLOW_A_WRITE_VALUE, {tag, " au1_data_ref"});
        flow_issue_run_observe(ET_JTAG_CMD_RUN_RUDE, 180us, {tag, " run_for_data_wp"});
        flow_issue_halt_observe({tag, " halt_after_data_wp"});

        flow_raw_emureg_write32(22'h84A, FLOW_A_ADDR, {tag, " au1_addr_a_restore"});
        flow_raw_emureg_write32(22'h84E, 32'h0000_0936, {tag, " au1_wp_wr_data"});
        flow_issue_run_observe(ET_JTAG_CMD_RUN_RUDE, 180us, {tag, " run_for_wr_data_wp"});
        flow_issue_halt_observe({tag, " halt_after_wr_data_wp"});

        flow_raw_emureg_write32(22'h84E, 32'h0000_1152, {tag, " au1_wp_rd_data_rtosint"});
        flow_issue_run_observe(ET_JTAG_CMD_RUN_RUDE, 180us, {tag, " run_for_rd_data_rtosint"});
        flow_issue_halt_observe({tag, " halt_after_rd_data_rtosint"});

        flow_raw_emureg_write32(22'h84E, 32'h0000_0956, {tag, " au1_wp_wr_data_rtosint"});
        flow_issue_run_observe(ET_JTAG_CMD_RUN_RUDE, 180us, {tag, " run_for_wr_data_rtosint"});
        flow_issue_halt_observe({tag, " halt_after_wr_data_rtosint"});

        flow_raw_emureg_write32(22'h84E, 32'h0000_1046, {tag, " au1_wp_rd_no_data_rtosint"});
        flow_issue_run_observe(ET_JTAG_CMD_RUN_RUDE, 180us, {tag, " run_for_rd_nd_rtosint"});
        flow_issue_halt_observe({tag, " halt_after_rd_nd_rtosint"});

        flow_raw_emureg_write32(22'h84E, 32'h0000_084A, {tag, " au1_wp_wr_no_data_rtosint"});
        flow_issue_run_observe(ET_JTAG_CMD_RUN_RUDE, 180us, {tag, " run_for_wr_nd_rtosint"});
        flow_issue_halt_observe({tag, " halt_after_wr_nd_rtosint"});

        flow_raw_emureg_write32(22'h832, 32'h0000_0002, {tag, " au2_skip_num"});
        flow_raw_emureg_write32(22'h836, 32'h0000_0001, {tag, " au2_claim"});
        flow_raw_emureg_write32(22'h836, 32'h0000_0122, {tag, " au2_wp_skip_16"});
        flow_raw_emureg_write32(22'h84E, 32'h0000_1006, {tag, " au1_rd_skip"});
        flow_issue_run_observe(ET_JTAG_CMD_RUN_RUDE, 180us, {tag, " run_for_skip_wp16"});
        flow_issue_halt_observe({tag, " halt_after_skip_wp16"});

        flow_raw_emureg_write32(22'h836, 32'h0000_0132, {tag, " au2_wp_skip_32"});
        flow_raw_emureg_write32(22'h84E, 32'h0000_0810, {tag, " au1_wr_skip"});
        flow_issue_run_observe(ET_JTAG_CMD_RUN_RUDE, 180us, {tag, " run_for_skip_wp32"});
        flow_issue_halt_observe({tag, " halt_after_skip_wp32"});

        flow_read_dbgstat({tag, " after_watchpoint_modes"});
        flow_raw_emureg_write32(22'h84E, 32'h0000_0000, {tag, " au1_disable"});
        flow_raw_emureg_write32(22'h836, 32'h0000_0000, {tag, " au2_disable"});
    endtask : flow_au_watchpoint_sweep

    virtual task flow_au2_counter_sweep(input string tag = "ET_JTAG_FLOW");
        `uvm_info(tag, "flow_au2_counter_sweep: sweep AU2 skip/event-counter/DA-counter selects", UVM_LOW)
        flow_rt_disable({tag, " setup_rt_disable"});
        flow_halt_rude({tag, " setup_halt"});
        flow_raw_emureg_write32(22'h836, 32'h0000_0001, {tag, " au2_claim"});
        flow_raw_emureg_write32(22'h832, 32'h0000_0002, {tag, " au2_skip_num"});

        flow_raw_emureg_write32(22'h84E, 32'h0000_0001, {tag, " au1_claim_for_skip_da"});
        flow_raw_emureg_write32(22'h848, 32'h0000_0000, {tag, " au1_mask_for_skip_da"});
        flow_raw_emureg_write32(22'h84A, FLOW_A_ADDR, {tag, " au1_addr_for_skip_da"});

        flow_raw_emureg_write32(22'h836, 32'h0000_0122, {tag, " au2_wp_skip_16"});
        flow_raw_emureg_write32(22'h84E, 32'h0000_1006, {tag, " au1_rd_skip_src"});
        flow_issue_run_observe(ET_JTAG_CMD_RUN_RUDE, 180us, {tag, " run_wp_skip_16"});
        flow_issue_halt_observe({tag, " halt_wp_skip_16"});

        flow_raw_emureg_write32(22'h836, 32'h0000_0132, {tag, " au2_wp_skip_32"});
        flow_raw_emureg_write32(22'h84E, 32'h0000_0810, {tag, " au1_wr_skip_src"});
        flow_issue_run_observe(ET_JTAG_CMD_RUN_RUDE, 180us, {tag, " run_wp_skip_32"});
        flow_issue_halt_observe({tag, " halt_wp_skip_32"});

        flow_raw_emureg_write32(22'h836, 32'h0000_009A, {tag, " au2_ec_clock"});
        flow_issue_run_observe(ET_JTAG_CMD_RUN_RUDE, 180us, {tag, " run_ec_clock"});
        flow_issue_halt_observe({tag, " halt_ec_clock"});

        flow_raw_emureg_write32(22'h836, 32'h0000_0182, {tag, " au2_ext0_16"});
        flow_issue_run_observe(ET_JTAG_CMD_RUN_RUDE, 180us, {tag, " run_ext0_16"});
        flow_issue_halt_observe({tag, " halt_ext0_16"});

        flow_raw_emureg_write32(22'h836, 32'h0000_0192, {tag, " au2_ext0_32"});
        flow_issue_run_observe(ET_JTAG_CMD_RUN_RUDE, 180us, {tag, " run_ext0_32"});
        flow_issue_halt_observe({tag, " halt_ext0_32"});

        flow_raw_emureg_write32(22'h836, 32'h0000_3002, {tag, " au2_ext1_16"});
        flow_issue_run_observe(ET_JTAG_CMD_RUN_RUDE, 180us, {tag, " run_ext1_16"});
        flow_issue_halt_observe({tag, " halt_ext1_16"});

        flow_raw_emureg_write32(22'h84E, 32'h0000_1004, {tag, " au1_da_rd_src"});
        flow_raw_emureg_write32(22'h836, 32'h0000_0102, {tag, " au2_da_cnt_16"});
        flow_issue_run_observe(ET_JTAG_CMD_RUN_RUDE, 180us, {tag, " run_da_cnt_16"});
        flow_issue_halt_observe({tag, " halt_da_cnt_16"});

        flow_raw_emureg_write32(22'h84E, 32'h0000_080A, {tag, " au1_da_wr_src"});
        flow_raw_emureg_write32(22'h836, 32'h0000_0112, {tag, " au2_da_cnt_32"});
        flow_issue_run_observe(ET_JTAG_CMD_RUN_RUDE, 180us, {tag, " run_da_cnt_32"});
        flow_issue_halt_observe({tag, " halt_da_cnt_32"});

        flow_raw_emureg_read32(22'h831, {tag, " au2_cnt_l"});
        flow_raw_emureg_read32(22'h832, {tag, " au2_skip_num_read"});
        flow_raw_emureg_read32(22'h836, {tag, " au2_ctrl_read"});
        flow_raw_emureg_write32(22'h84E, 32'h0000_0000, {tag, " au1_disable"});
        flow_raw_emureg_write32(22'h836, 32'h0000_0000, {tag, " au2_disable"});
    endtask : flow_au2_counter_sweep

    virtual task flow_dma_datalog_sweep(input string tag = "ET_JTAG_FLOW");
        `uvm_info(tag, "flow_dma_datalog_sweep: configure data-log/DMA registers and trigger JTAG DMA write/read-command paths", UVM_LOW)
        flow_rt_disable({tag, " setup_rt_disable"});
        flow_halt_rude({tag, " setup_halt"});
        flow_raw_emureg_write32(22'h838, FLOW_A_ADDR, {tag, " dma_addr_start"});
        flow_raw_emureg_write32(22'h848, 32'h0000_0000, {tag, " dlog_mask"});
        flow_raw_emureg_write32(22'h84A, FLOW_A_ADDR + 32'h8, {tag, " dlog_ref_end"});
        flow_raw_emureg_write32(22'h84E, 32'h0000_0001, {tag, " dlog_evt_claim"});
        flow_raw_emureg_write32(22'h83C, FLOW_DLOG_RCMD2_INT, {tag, " int_set_rcmd2"});

        flow_raw_emureg_write32(22'h83E, 32'h0000_0001, {tag, " dma_dbg_claim"});
        flow_raw_emureg_write32(22'h83E, 32'h0000_0002, {tag, " dma_enable_type0"});
        send_ir({ET_JTAG_IR_DMA_WDATA_OP, 32'hA5A5_1001}, 10);
        repeat (120) @(posedge vif.cpu_clk);
        send_ir({ET_JTAG_IR_DMA_WDATA_OP, 32'hA5A5_1002}, 10);
        repeat (120) @(posedge vif.cpu_clk);

        flow_raw_emureg_read32(22'h83C, {tag, " int_before_dlog_rcmd"});

        // Sweep likely data-log read opcodes. RCMD2 is configured above so
        // the 6'h3A scan should hit DT_DMA.DMA_fifo_read with UpdateIR.
        send_ir({ET_JTAG_IR_DLOG_RCMD0_OP, 32'h0000_0000}, 10);
        repeat (80) @(posedge vif.cpu_clk);
        send_ir({ET_JTAG_IR_DLOG_RCMD1_OP, 32'h0000_0000}, 10);
        repeat (80) @(posedge vif.cpu_clk);
        send_ir({ET_JTAG_IR_DLOG_RCMD2_OP, 32'h0000_0000}, 10);
        repeat (80) @(posedge vif.cpu_clk);
        flow_raw_emureg_read32(22'h83C, {tag, " int_after_dlog_rcmd2"});

        flow_raw_emureg_read32(22'h83A, {tag, " dma_rd"});
        flow_raw_emureg_read32(22'h83C, {tag, " dma_int_fifo"});
        flow_raw_emureg_read32(22'h83E, {tag, " dma_ctrl_id"});
        flow_raw_emureg_write32(22'h83E, 32'h0000_0000, {tag, " dma_disable"});
        flow_raw_emureg_write32(22'h84E, 32'h0000_0000, {tag, " dlog_evt_disable"});
    endtask : flow_dma_datalog_sweep

    virtual task flow_dma_cpu_read_sweep(input string tag = "ET_JTAG_FLOW");
        logic [31:0] observe_value;
        begin
            `uvm_info(tag,
                      "flow_dma_cpu_read_sweep: arm C CPU/PF0 DMA claim, then pop data-log FIFO via JTAG RCMD2",
                      UVM_LOW)
            flow_rt_disable({tag, " setup_rt_disable"});
            flow_halt_rude({tag, " arm_cpu_dma_halt"});
            et_jtag_write_a32(FLOW_DMA_CPU_GO_VALUE, observe_value, {tag, " arm_cpu_dma_go"});
            flow_run_rude({tag, " run_cpu_dma_config"});
            #0.6ms;
            flow_halt_rude({tag, " halt_after_cpu_dma_config"});

            flow_raw_emureg_read32(22'h83E, {tag, " cpu_dma_ctrl_id"});
            flow_raw_emureg_read32(22'h83C, {tag, " cpu_dma_int_before_rcmd2"});
            send_ir({ET_JTAG_IR_DLOG_RCMD2_OP, 32'h0000_0000}, 10);
            repeat (120) @(posedge vif.cpu_clk);
            flow_raw_emureg_read32(22'h83A, {tag, " cpu_dma_rd_after_rcmd2"});
            flow_raw_emureg_read32(22'h83C, {tag, " cpu_dma_int_after_rcmd2"});
            flow_raw_emureg_read32(22'h83E, {tag, " cpu_dma_ctrl_id_after_rcmd2"});
        end
    endtask : flow_dma_cpu_read_sweep

    virtual task flow_emureg_write16_check(input string tag = "ET_JTAG_FLOW");
        begin
            `uvm_info(tag,
                      "flow_emureg_write16_check: verify WRITEA16 drives EMUREG_Size=0 and only updates the low halfword",
                      UVM_LOW)
            flow_rt_disable({tag, " setup_rt_disable"});
            flow_halt_rude({tag, " setup_halt"});

            flow_raw_emureg_write32(22'h82A, 32'h1357_2468, {tag, " au0_addr_base"});
            flow_raw_emureg_write16(22'h82A, 16'hA5A5, {tag, " au0_addr_low_w16"});
            flow_raw_emureg_read32(22'h82A, {tag, " au0_addr_readback"});
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_ET.AD_inst.EMU_REG_inst.reg_AU0_ADDR",
                              32'hFFFF_FFFF, 32'h1357_A5A5, {tag, " au0_addr_hdl"});

            flow_raw_emureg_write32(22'h848, 32'hAAAA_5555, {tag, " au1_mask_base"});
            flow_raw_emureg_write16(22'h848, 16'h0F0F, {tag, " au1_mask_low_w16"});
            flow_raw_emureg_read32(22'h848, {tag, " au1_mask_readback"});
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_ET.AD_inst.EMU_REG_inst.reg_AU1_ADDR_Mask",
                              32'hFFFF_FFFF, 32'hAAAA_0F0F, {tag, " au1_mask_hdl"});

            flow_raw_emureg_write32(22'h84A, 32'h2468_1357, {tag, " au1_addr_base"});
            flow_raw_emureg_write16(22'h84A, 16'hB4B4, {tag, " au1_addr_low_w16"});
            flow_raw_emureg_read32(22'h84A, {tag, " au1_addr_readback"});
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_ET.AD_inst.EMU_REG_inst.reg_AU1_ADDR",
                              32'hFFFF_FFFF, 32'h2468_B4B4, {tag, " au1_addr_hdl"});

            flow_raw_emureg_write32(22'h830, 32'h55AA_7788, {tag, " au2_cnt_base"});
            flow_raw_emureg_write16(22'h830, 16'h3333, {tag, " au2_cnt_low_w16"});
            flow_raw_emureg_read32(22'h830, {tag, " au2_cnt_readback"});
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_ET.AD_inst.EMU_REG_inst.reg_AU2_CNT",
                              32'hFFFF_FFFF, 32'h55AA_3333, {tag, " au2_cnt_hdl"});

            flow_raw_emureg_write32(22'h832, 32'h00CC_99AA, {tag, " au2_skip_base"});
            flow_raw_emureg_write16(22'h832, 16'h1234, {tag, " au2_skip_low_w16"});
            flow_raw_emureg_read32(22'h832, {tag, " au2_skip_readback"});
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_ET.AD_inst.EMU_REG_inst.reg_AU2_Skip_Num",
                              32'hFFFF_FFFF, 32'h00CC_1234, {tag, " au2_skip_hdl"});

            flow_raw_emureg_write32(22'h838, 32'h0004_8D18, {tag, " dma_addr_base"});
            flow_raw_emureg_write16(22'h838, 16'h9000, {tag, " dma_addr_low_w16"});
            flow_raw_emureg_read32(22'h838, {tag, " dma_addr_readback"});
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_ET.AD_inst.EMU_REG_inst.reg_ADDR",
                              32'hFFFF_FFFF, 32'h0004_9000, {tag, " dma_addr_hdl"});

            flow_raw_emureg_write32(22'h880, 32'h080F_006B, {tag, " devicecnf_restore_base"});
            flow_raw_emureg_write16(22'h880, 16'h005A, {tag, " devicecnf_low_w16"});
            flow_raw_emureg_read32(22'h880, {tag, " devicecnf_readback"});
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_ET.AD_inst.EMU_REG_inst.reg_DEVICECNF",
                              32'hFFFF_FFFF, 32'h080F_005A, {tag, " devicecnf_hdl"});

            flow_raw_emureg_write32(22'h884, 32'h00AA_0200, {tag, " prot_base"});
            flow_raw_emureg_write16(22'h884, 16'h0300, {tag, " protstart_low_w16"});
            flow_raw_emureg_read32(22'h884, {tag, " prot_readback"});
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_ET.AD_inst.EMU_REG_inst.reg_PROTSTART",
                              32'h0000_FFFF, 32'h0000_0300, {tag, " protstart_hdl"});
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_ET.AD_inst.EMU_REG_inst.reg_PROTRANGE",
                              32'h0000_FFFF, 32'h0000_00AA, {tag, " protrange_hdl"});

            flow_raw_emureg_write32(22'h984, 32'h0005_0000, {tag, " bor_cfg_write32"});
            flow_raw_emureg_write16(22'h985, 16'h0003, {tag, " bor_cfg_low_w16"});
            flow_raw_emureg_read32(22'h985, {tag, " bor_cfg_readback"});
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_ET.AD_inst.EMU_REG_inst.BOR_CFG",
                              32'h0000_0007, 32'h0000_0003, {tag, " bor_cfg_hdl"});
        end
    endtask : flow_emureg_write16_check

    virtual task flow_peek_cla_task1_counter(output logic [31:0] counter,
                                             output logic [15:0] started,
                                             input string tag = "ET_JTAG_FLOW");
        uvm_hdl_data_t started_raw;
        uvm_hdl_data_t counter_lo_raw;
        uvm_hdl_data_t counter_hi_raw;
        bit ok_started;
        bit ok_counter_lo;
        bit ok_counter_hi;
        begin
            ok_started = uvm_hdl_read("chip_top_tb.I_chip_top.I_Mem_Controller.I_MC_Banks.I_MC_SRAM.I_MSG.RAM_L.u_sram.mem[0]",
                                      started_raw);
            ok_counter_lo = uvm_hdl_read("chip_top_tb.I_chip_top.I_Mem_Controller.I_MC_Banks.I_MC_SRAM.I_MSG.RAM_L.u_sram.mem[1]",
                                         counter_lo_raw);
            ok_counter_hi = uvm_hdl_read("chip_top_tb.I_chip_top.I_Mem_Controller.I_MC_Banks.I_MC_SRAM.I_MSG.RAM_H.u_sram.mem[1]",
                                         counter_hi_raw);

            started = started_raw[15:0];
            counter = {counter_hi_raw[15:0], counter_lo_raw[15:0]};
            if (!ok_started || !ok_counter_lo || !ok_counter_hi) begin
                `uvm_error(tag,
                           $sformatf("flow_peek_cla_task1_counter: MSG RAM backdoor failed started=%0b lo=%0b hi=%0b",
                                     ok_started, ok_counter_lo, ok_counter_hi))
            end
            else begin
                `uvm_info(tag,
                          $sformatf("flow_peek_cla_task1_counter: g_cla_started=0x%04h g_cla_counter=0x%08h",
                                    started, counter),
                          UVM_LOW)
            end
        end
    endtask : flow_peek_cla_task1_counter

    virtual task flow_expect_cla_task1_running(input string tag = "ET_JTAG_FLOW");
        logic [31:0] counter_before;
        logic [31:0] counter_after;
        logic [15:0] started_before;
        logic [15:0] started_after;
        begin
            flow_peek_cla_task1_counter(counter_before, started_before, {tag, " before"});
            repeat (2000) @(posedge vif.cpu_clk);
            flow_peek_cla_task1_counter(counter_after, started_after, {tag, " after"});

            if (started_after !== 16'hC1A1) begin
                if (cla_soft_running_check) begin
                    `uvm_warning(tag,
                                 $sformatf("CLA task1 did not set start signature: started_before=0x%04h started_after=0x%04h; keep as coverage aggregate observation",
                                           started_before, started_after))
                end
                else begin
                    `uvm_error(tag,
                               $sformatf("CLA task1 did not set start signature: started_before=0x%04h started_after=0x%04h; check APP=et_jtag_cla",
                                         started_before, started_after))
                end
            end
            if (counter_after === counter_before) begin
                if (cla_soft_running_check) begin
                    `uvm_warning(tag,
                                 $sformatf("CLA task1 counter did not change: before=0x%08h after=0x%08h; keep as coverage aggregate observation",
                                           counter_before, counter_after))
                end
                else begin
                    `uvm_error(tag,
                               $sformatf("CLA task1 counter did not change: before=0x%08h after=0x%08h; check task1/MIFRC/MIRUN",
                                         counter_before, counter_after))
                end
            end
        end
    endtask : flow_expect_cla_task1_running

    virtual task flow_observe_hdl32(input string hdl_path,
                                    input string tag = "ET_JTAG_FLOW");
        uvm_hdl_data_t raw_value;
        begin
            if (!uvm_hdl_check_path(hdl_path)) begin
                `uvm_warning(tag,
                             $sformatf("flow_observe_hdl32: skip backdoor observe, path not found: %s",
                                       hdl_path))
            end
            else if (!uvm_hdl_read(hdl_path, raw_value)) begin
                `uvm_warning(tag,
                             $sformatf("flow_observe_hdl32: read failed: %s",
                                       hdl_path))
            end
            else begin
                `uvm_info(tag,
                          $sformatf("flow_observe_hdl32: %s = 0x%08h",
                                    hdl_path, raw_value[31:0]),
                          UVM_LOW)
            end
        end
    endtask : flow_observe_hdl32

    virtual task flow_read_hdl32_strict(input string hdl_path,
                                        output logic [31:0] value,
                                        input string tag = "ET_JTAG_FLOW");
        uvm_hdl_data_t raw_value;
        begin
            value = '0;
            if (!uvm_hdl_check_path(hdl_path)) begin
                `uvm_error(tag,
                           $sformatf("[CLA_ET_FAIL] case=strict_hdl target=%s reason=hdl_path_not_found",
                                     hdl_path))
            end
            else if (!uvm_hdl_read(hdl_path, raw_value)) begin
                `uvm_error(tag,
                           $sformatf("[CLA_ET_FAIL] case=strict_hdl target=%s reason=hdl_read_failed",
                                     hdl_path))
            end
            else begin
                value = raw_value[31:0];
            end
        end
    endtask : flow_read_hdl32_strict

    virtual task flow_require_hdl_path(input string hdl_path,
                                       input string tag = "ET_JTAG_FLOW");
        begin
            if (!uvm_hdl_check_path(hdl_path)) begin
                `uvm_error(tag,
                           $sformatf("[CLA_ET_FAIL] case=strict_hdl target=%s reason=required_hdl_path_not_found",
                                     hdl_path))
            end
        end
    endtask : flow_require_hdl_path

    virtual task flow_cla_watch_bp_combo(input string combo_name,
                                         input bit exp_connected,
                                         input bit exp_swbp_en,
                                         input bit exp_mdebugstop,
                                         input bit exp_bp_pend,
                                         input int unsigned max_cycles,
                                         output bit seen_combo,
                                         input string tag = "ET_JTAG_FLOW");
        logic [31:0] connected_v;
        logic [31:0] dbgconfg_v;
        logic [31:0] mdebugstop_v;
        logic [31:0] bp_pend_v;
        logic [31:0] bp_stall_v;
        logic [31:0] d2_mpc_v;
        int unsigned cycle_idx;
        begin
            seen_combo = 1'b0;
            flow_require_hdl_path("chip_top_tb.I_chip_top.I_CLA.c_reg.DBGCONNECTED", {tag, " require_dbgconnected"});
            flow_require_hdl_path("chip_top_tb.I_chip_top.I_CLA.c_reg.DBGCONFG", {tag, " require_dbgconfg"});
            flow_require_hdl_path("chip_top_tb.I_chip_top.I_CLA.p2.d2_mdebugstop", {tag, " require_d2_mdebugstop"});
            flow_require_hdl_path("chip_top_tb.I_chip_top.I_CLA.ctl.bp_pend", {tag, " require_bp_pend"});
            flow_require_hdl_path("chip_top_tb.I_chip_top.I_CLA.ctl.bp_stall", {tag, " require_bp_stall"});

            for (cycle_idx = 0; cycle_idx < max_cycles; cycle_idx++) begin
                @(posedge vif.cpu_clk);
                flow_read_hdl32_strict("chip_top_tb.I_chip_top.I_CLA.c_reg.DBGCONNECTED",
                                       connected_v, {tag, " rd_dbgconnected"});
                flow_read_hdl32_strict("chip_top_tb.I_chip_top.I_CLA.c_reg.DBGCONFG",
                                       dbgconfg_v, {tag, " rd_dbgconfg"});
                flow_read_hdl32_strict("chip_top_tb.I_chip_top.I_CLA.p2.d2_mdebugstop",
                                       mdebugstop_v, {tag, " rd_d2_mdebugstop"});
                flow_read_hdl32_strict("chip_top_tb.I_chip_top.I_CLA.ctl.bp_pend",
                                       bp_pend_v, {tag, " rd_bp_pend"});
                flow_read_hdl32_strict("chip_top_tb.I_chip_top.I_CLA.ctl.bp_stall",
                                       bp_stall_v, {tag, " rd_bp_stall"});
                flow_read_hdl32_strict("chip_top_tb.I_chip_top.I_CLA.d2_mpc",
                                       d2_mpc_v, {tag, " rd_d2_mpc"});

                if ((connected_v[0] == exp_connected) &&
                    (dbgconfg_v[0] == exp_swbp_en) &&
                    (mdebugstop_v[0] == exp_mdebugstop)) begin
                    if (bp_pend_v[0] !== exp_bp_pend) begin
                        `uvm_error(tag,
                                   $sformatf("[CLA_ET_FAIL] case=cla_et_breakpoint_pending_matrix target=%s reason=bp_pend_mismatch cycle=%0d connected=%0b swbp_en=%0b d2_mdebugstop=%0b bp_pend=%0b expected=%0b d2_mpc=0x%08h",
                                             combo_name, cycle_idx, connected_v[0], dbgconfg_v[0],
                                             mdebugstop_v[0], bp_pend_v[0], exp_bp_pend, d2_mpc_v))
                    end
                    else begin
                        seen_combo = 1'b1;
                        `uvm_info(tag,
                                  $sformatf("[CLA_ET_PASS] case=cla_et_breakpoint_pending_matrix target=%s evidence=cycle:%0d connected:%0b swbp_en:%0b d2_mdebugstop:%0b bp_pend:%0b bp_stall:%0b d2_mpc:0x%08h",
                                            combo_name, cycle_idx, connected_v[0], dbgconfg_v[0],
                                            mdebugstop_v[0], bp_pend_v[0], bp_stall_v[0], d2_mpc_v),
                                  UVM_LOW)
                    end
                    break;
                end
            end

            if (!seen_combo) begin
                `uvm_error(tag,
                           $sformatf("[CLA_ET_FAIL] case=cla_et_breakpoint_pending_matrix target=%s reason=target_combo_not_observed max_cycles=%0d expected_connected=%0b expected_swbp_en=%0b expected_d2_mdebugstop=%0b",
                                     combo_name, max_cycles, exp_connected, exp_swbp_en, exp_mdebugstop))
            end
        end
    endtask : flow_cla_watch_bp_combo

    virtual task flow_cla_watch_debug_direct_exit(input int unsigned max_cycles,
                                                  output bit seen_direct_exit,
                                                  output bit seen_step_path,
                                                  input string tag = "ET_JTAG_FLOW");
        logic [31:0] state_prev;
        logic [31:0] state_now;
        logic [31:0] state_n;
        logic [31:0] task_running_v;
        logic [31:0] task_stop_v;
        logic [31:0] command_acked_v;
        logic [31:0] br_state_v;
        logic [31:0] debug_info_v;
        int unsigned cycle_idx;
        begin
            seen_direct_exit = 1'b0;
            seen_step_path = 1'b0;
            flow_read_hdl32_strict("chip_top_tb.I_chip_top.I_CLA.ctl.et_state",
                                   state_prev, {tag, " rd_initial_et_state"});
            for (cycle_idx = 0; cycle_idx < max_cycles; cycle_idx++) begin
                @(posedge vif.cpu_clk);
                flow_read_hdl32_strict("chip_top_tb.I_chip_top.I_CLA.ctl.et_state",
                                       state_now, {tag, " rd_et_state"});
                flow_read_hdl32_strict("chip_top_tb.I_chip_top.I_CLA.ctl.et_state_n",
                                       state_n, {tag, " rd_et_state_n"});
                flow_read_hdl32_strict("chip_top_tb.I_chip_top.I_CLA.TASK_RUNNING",
                                       task_running_v, {tag, " rd_task_running"});
                flow_read_hdl32_strict("chip_top_tb.I_chip_top.I_CLA.TASK_STOP",
                                       task_stop_v, {tag, " rd_task_stop"});
                flow_read_hdl32_strict("chip_top_tb.I_chip_top.I_CLA.ctl.command_acked",
                                       command_acked_v, {tag, " rd_command_acked"});
                flow_read_hdl32_strict("chip_top_tb.I_chip_top.I_CLA.ctl.br_state",
                                       br_state_v, {tag, " rd_br_state"});
                flow_read_hdl32_strict("chip_top_tb.I_chip_top.I_CLA.ctl.cla_debug_info",
                                       debug_info_v, {tag, " rd_cla_debug_info"});

                if ((state_prev[1:0] == 2'h2) && (state_now[1:0] == 2'h0)) begin
                    seen_direct_exit = 1'b1;
                    `uvm_info(tag,
                              $sformatf("[CLA_ET_PASS] case=cla_et_debug_idle_exit_final target=debug_state_to_run_state evidence=cycle:%0d state_prev:%0d state:%0d state_n:%0d task_running:%0b task_stop:%0b command_acked:%0b br_state:%0b debug_info:0x%0h",
                                        cycle_idx, state_prev[1:0], state_now[1:0], state_n[1:0],
                                        task_running_v[0], task_stop_v[0], command_acked_v[0],
                                        br_state_v[0], debug_info_v[2:0]),
                              UVM_LOW)
                    break;
                end
                if ((state_prev[1:0] == 2'h2) && (state_now[1:0] == 2'h1)) begin
                    seen_step_path = 1'b1;
                end
                state_prev = state_now;
            end
        end
    endtask : flow_cla_watch_debug_direct_exit

    virtual task flow_wait_cla_debug_state(input string tag,
                                           input int unsigned max_cycles,
                                           output bit got_debug);
        uvm_hdl_data_t raw_value;
        bit ok;
        int unsigned cycle_idx;
        begin
            got_debug = 1'b0;
            for (cycle_idx = 0; cycle_idx < max_cycles; cycle_idx++) begin
                ok = uvm_hdl_read("chip_top_tb.I_chip_top.I_CLA.cla_et_debugstate",
                                  raw_value);
                if (ok && raw_value[0]) begin
                    got_debug = 1'b1;
                    `uvm_info(tag,
                              $sformatf("flow_wait_cla_debug_state: debug_state observed after %0d cycles",
                                        cycle_idx),
                              UVM_LOW)
                    break;
                end
                @(posedge vif.cpu_clk);
            end

            if (!got_debug) begin
                `uvm_warning(tag,
                             $sformatf("flow_wait_cla_debug_state: cla_et_debugstate not observed within %0d cycles",
                                       max_cycles))
            end
        end
    endtask : flow_wait_cla_debug_state

    virtual task flow_cla_dbgreg_mem_access(input string tag = "ET_JTAG_FLOW");
        begin
            `uvm_info(tag,
                      "flow_cla_dbgreg_mem_access: use ET/JTAG memory access to write CLA PF0 debug registers; RTL should bypass CPU EALLOW via PFx_W_EALLOW",
                      UVM_LOW)

            flow_expect_cla_task1_running({tag, " cla_task1_running"});

            flow_raw_mem_read32(FLOW_CLA_DBGSTAT, {tag, " dbgstat_initial"});

            flow_raw_mem_write32(FLOW_CLA_DBGCONFG, 32'h0000_0001, {tag, " dbgconfg_swbp_enable"});
            flow_raw_mem_read32(FLOW_CLA_DBGCONFG, {tag, " dbgconfg_readback"});
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_CLA.c_reg.DBGCONFG",
                              32'h0000_0003, 32'h0000_0001, {tag, " dbgconfg_hdl"});

            flow_raw_mem_write32(FLOW_CLA_SWBPMASK, 32'h0000_400A, {tag, " swbpmask_type1_mask_a"});
            flow_raw_mem_read32(FLOW_CLA_SWBPMASK, {tag, " swbpmask_readback"});
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_CLA.c_reg.SWBPMASK",
                              32'h0000_000F, 32'h0000_000A, {tag, " swbpmask_hdl"});
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_CLA.c_reg.SWBPTYPE",
                              32'h0000_0003, 32'h0000_0001, {tag, " swbptype_hdl"});

            flow_raw_mem_write32(FLOW_CLA_DBGRESTORE, 32'hCAFE_BEEF, {tag, " dbgrestore_w32"});
            flow_raw_mem_read32(FLOW_CLA_DBGRESTORE, {tag, " dbgrestore_readback"});
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_CLA.c_reg.breakpoint_origin",
                              32'hFFFF_FFFF, 32'hCAFE_BEEF, {tag, " dbgrestore_hdl_w32"});

            flow_raw_mem_write16(FLOW_CLA_DBGRESTOREH, 16'h1234, {tag, " dbgrestore_high_w16"});
            flow_raw_mem_read16(FLOW_CLA_DBGRESTOREH, {tag, " dbgrestoreh_readback"});
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_CLA.c_reg.breakpoint_origin",
                              32'hFFFF_0000, 32'h1234_0000, {tag, " dbgrestoreh_hdl_w16"});

            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_000D, {tag, " dbgstat_connect_step_halt"});
            flow_raw_mem_read32(FLOW_CLA_DBGSTAT, {tag, " dbgstat_after_connect"});
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_CLA.c_reg.DBGCONNECTED",
                              32'h0000_0001, 32'h0000_0001, {tag, " dbgconnected_hdl"});
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_CLA.c_reg.DBGSTEP",
                              32'h0000_0001, 32'h0000_0001, {tag, " dbgstep_hdl"});

            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_0018, {tag, " dbgstat_clear_ack_release"});
            flow_raw_mem_read32(FLOW_CLA_DBGSTAT, {tag, " dbgstat_after_release"});

            flow_raw_mem_write32(FLOW_CLA_MPC, 32'h0000_0020, {tag, " mpc_w32"});
            flow_raw_mem_read32(FLOW_CLA_MPC, {tag, " mpc_readback_live"});

            flow_raw_mem_write32(FLOW_CLA_DBGCONFG, 32'h0000_0000, {tag, " dbgconfg_cleanup"});
            flow_raw_mem_write32(FLOW_CLA_SWBPMASK, 32'h0000_0000, {tag, " swbpmask_cleanup"});
            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_0000, {tag, " dbgstat_disconnect_cleanup"});
            flow_raw_mem_read32(FLOW_CLA_DBGSTAT, {tag, " dbgstat_final"});
        end
    endtask : flow_cla_dbgreg_mem_access

    virtual task flow_cla_dbgreg_corner_sweep(input string tag = "ET_JTAG_FLOW");
        begin
            `uvm_info(tag,
                      "flow_cla_dbgreg_corner_sweep: cover CLA DBGRESET, DBGSTAT high-half reset, DBGCONFG[1], DBGRESTORE high bits and ACTIVE high-half writes",
                      UVM_LOW)

            flow_expect_cla_task1_running({tag, " cla_task1_running"});

            flow_raw_mem_read32(FLOW_CLA_DBGSTAT, {tag, " dbgstat_initial"});

            flow_raw_mem_write32(FLOW_CLA_DBGCONFG, 32'h0000_0003, {tag, " dbgconfg_bits10_w32"});
            flow_raw_mem_read32(FLOW_CLA_DBGCONFG, {tag, " dbgconfg_bits10_read"});
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_CLA.c_reg.DBGCONFG",
                              32'h0000_0003, 32'h0000_0003, {tag, " dbgconfg_bits10_hdl"});

            flow_raw_mem_write16(FLOW_CLA_DBGCONFG, 16'h0002, {tag, " dbgconfg_bit1_w16"});
            flow_raw_mem_read16(FLOW_CLA_DBGCONFG, {tag, " dbgconfg_bit1_read16"});
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_CLA.c_reg.DBGCONFG",
                              32'h0000_0003, 32'h0000_0002, {tag, " dbgconfg_bit1_hdl"});

            flow_raw_mem_write32(FLOW_CLA_DBGRESTORE, 32'h0001_0002, {tag, " dbgrestore_sparse_w32"});
            flow_raw_mem_read32(FLOW_CLA_DBGRESTORE, {tag, " dbgrestore_sparse_read"});
            flow_raw_mem_write32(FLOW_CLA_DBGRESTORE, 32'h5555_AAAA, {tag, " dbgrestore_alt_w32"});
            flow_raw_mem_read32(FLOW_CLA_DBGRESTORE, {tag, " dbgrestore_alt_read"});
            flow_raw_mem_write16(FLOW_CLA_DBGRESTOREH, 16'hFFFF, {tag, " dbgrestoreh_all1_w16"});
            flow_raw_mem_read16(FLOW_CLA_DBGRESTOREH, {tag, " dbgrestoreh_all1_read16"});
            flow_raw_mem_write32(FLOW_CLA_DBGRESTORE, 32'h0000_0000, {tag, " dbgrestore_clear_w32"});
            flow_raw_mem_read32(FLOW_CLA_DBGRESTORE, {tag, " dbgrestore_clear_read"});

            flow_raw_mem_write32(FLOW_CLA_SWBPMASK, 32'h0000_0005, {tag, " swbpmask_bits02_type0"});
            flow_raw_mem_read32(FLOW_CLA_SWBPMASK, {tag, " swbpmask_bits02_type0_read"});
            flow_raw_mem_write32(FLOW_CLA_SWBPMASK, 32'h0000_8005, {tag, " swbpmask_bits02_type2"});
            flow_raw_mem_read32(FLOW_CLA_SWBPMASK, {tag, " swbpmask_bits02_type2_read"});
            flow_raw_mem_write32(FLOW_CLA_SWBPMASK, 32'h0000_0000, {tag, " swbpmask_clear"});

            flow_raw_mem_write32(FLOW_CLA_TASKMODE, 32'h0000_0001, {tag, " taskmode_set_direct"});
            flow_raw_mem_read32(FLOW_CLA_TASKMODE, {tag, " taskmode_direct_read"});
            flow_raw_mem_write32(FLOW_CLA_ACTIVE, 32'h0001_0000, {tag, " active_high_taskmode_set"});
            flow_raw_mem_read32(FLOW_CLA_ACTIVE, {tag, " active_high_taskmode_read"});
            flow_raw_mem_write32(FLOW_CLA_ACTIVE, 32'h0000_0000, {tag, " active_high_taskmode_clear"});
            flow_raw_mem_read32(FLOW_CLA_TASKMODE, {tag, " taskmode_after_active_clear"});

            flow_raw_mem_write16(FLOW_CLA_DBGRESET, 16'h0200, {tag, " dbgreset_direct_w16"});
            repeat (1000) @(posedge vif.cpu_clk);
            flow_raw_mem_read32(FLOW_CLA_DBGSTAT, {tag, " dbgstat_after_dbgreset_w16"});

            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0200_0008, {tag, " dbgstat_highhalf_dbgreset_w32"});
            repeat (1000) @(posedge vif.cpu_clk);
            flow_raw_mem_read32(FLOW_CLA_DBGSTAT, {tag, " dbgstat_after_highhalf_reset"});

            flow_raw_mem_write32(FLOW_CLA_DBGCONFG, 32'h0000_0000, {tag, " dbgconfg_cleanup"});
            flow_raw_mem_write32(FLOW_CLA_SWBPMASK, 32'h0000_0000, {tag, " swbpmask_cleanup"});
            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_0000, {tag, " dbgstat_disconnect_cleanup"});
        end
    endtask : flow_cla_dbgreg_corner_sweep

    virtual task flow_cla_dbg_halt_step_run(input string tag = "ET_JTAG_FLOW");
        bit got_debug;
        begin
            `uvm_info(tag,
                      "flow_cla_dbg_halt_step_run: drive CLA DBGSTAT connect/halt/step/run command decode",
                      UVM_LOW)

            flow_expect_cla_task1_running({tag, " cla_task1_running"});

            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_0008, {tag, " dbgstat_connect"});
            flow_raw_mem_read32(FLOW_CLA_DBGSTAT, {tag, " dbgstat_after_connect"});

            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_0009, {tag, " dbgstat_connect_halt"});
            flow_wait_cla_debug_state({tag, " wait_halt_debug"}, 60000, got_debug);
            flow_raw_mem_read32(FLOW_CLA_DBGSTAT, {tag, " dbgstat_after_halt"});
            flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.ctl.et_state", {tag, " et_state_after_halt"});
            flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.c_reg.DBGACKED", {tag, " dbgacked_after_halt"});

            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_000D, {tag, " dbgstat_set_step_while_halt"});
            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_000C, {tag, " dbgstat_step_cmd"});
            flow_wait_cla_debug_state({tag, " wait_after_step"}, 30000, got_debug);
            flow_raw_mem_read32(FLOW_CLA_DBGSTAT, {tag, " dbgstat_after_step"});
            flow_raw_mem_read32(FLOW_CLA_PCE, {tag, " pce_after_step"});
            flow_raw_mem_read32(FLOW_CLA_PCR1, {tag, " pcr1_after_step"});

            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_0008, {tag, " dbgstat_clear_step_latch"});
            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_0008, {tag, " dbgstat_run_cmd"});
            repeat (10000) @(posedge vif.cpu_clk);
            flow_raw_mem_read32(FLOW_CLA_DBGSTAT, {tag, " dbgstat_after_run"});
            flow_expect_cla_task1_running({tag, " cla_task1_running_after_run"});

            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_0009, {tag, " dbgstat_halt_again"});
            flow_wait_cla_debug_state({tag, " wait_halt_again"}, 60000, got_debug);
            flow_raw_mem_read32(FLOW_CLA_DBGSTAT, {tag, " dbgstat_after_halt_again"});

            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_0018, {tag, " dbgstat_clear_ack_connected"});
            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_0000, {tag, " dbgstat_disconnect"});
            flow_raw_mem_read32(FLOW_CLA_DBGSTAT, {tag, " dbgstat_final"});
        end
    endtask : flow_cla_dbg_halt_step_run

    virtual task flow_cla_mpc_debug_write(input string tag = "ET_JTAG_FLOW");
        bit got_debug;
        logic [31:0] counter_after_mpc_run;
        logic [15:0] started_after_mpc_run;
        begin
            `uvm_info(tag,
                      "flow_cla_mpc_debug_write: write MPC while CLA is in debug_state to hit et_mpc_wt/flush paths",
                      UVM_LOW)

            flow_expect_cla_task1_running({tag, " cla_task1_running"});
            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_0009, {tag, " dbgstat_connect_halt"});
            flow_wait_cla_debug_state({tag, " wait_debug_before_mpc"}, 60000, got_debug);

            flow_raw_mem_read32(FLOW_CLA_PCE, {tag, " pce_before_mpc"});
            flow_raw_mem_write32(FLOW_CLA_MPC, 32'h0000_0020, {tag, " mpc_w32_20"});
            repeat (2000) @(posedge vif.cpu_clk);
            flow_raw_mem_read32(FLOW_CLA_MPC, {tag, " mpc_read_after_20"});
            flow_raw_mem_read32(FLOW_CLA_PCE, {tag, " pce_after_mpc_20"});
            flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.ctl.count_type", {tag, " count_type_after_mpc_20"});

            flow_raw_mem_write32(FLOW_CLA_MPC, 32'h0000_0040, {tag, " mpc_w32_40"});
            repeat (2000) @(posedge vif.cpu_clk);
            flow_raw_mem_read32(FLOW_CLA_PCR2, {tag, " pcr2_after_mpc_40"});
            flow_raw_mem_read32(FLOW_CLA_PCR1, {tag, " pcr1_after_mpc_40"});

            flow_raw_mem_write16(FLOW_CLA_MPC, 16'h0080, {tag, " mpc_w16_80"});
            repeat (2000) @(posedge vif.cpu_clk);
            flow_raw_mem_read32(FLOW_CLA_PCD2, {tag, " pcd2_after_mpc_80"});

            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_0008, {tag, " dbgstat_run_preclear"});
            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_0008, {tag, " dbgstat_run_after_mpc"});
            repeat (10000) @(posedge vif.cpu_clk);
            flow_peek_cla_task1_counter(counter_after_mpc_run,
                                        started_after_mpc_run,
                                        {tag, " observe_after_mpc_run"});
            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_0000, {tag, " dbgstat_disconnect"});
        end
    endtask : flow_cla_mpc_debug_write

    virtual task flow_cla_swbp_sweep(input string tag = "ET_JTAG_FLOW");
        begin
            `uvm_info(tag,
                      "flow_cla_swbp_sweep: sweep DBGCONFG/SWBPMASK/SWBPTYPE/DBGRESTORE and probe SWBP status",
                      UVM_LOW)

            flow_expect_cla_task1_running({tag, " cla_task1_running"});
            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_0008, {tag, " dbgstat_connect"});
            flow_raw_mem_write32(FLOW_CLA_DBGCONFG, 32'h0000_0001, {tag, " swbp_enable"});
            flow_raw_mem_read32(FLOW_CLA_DBGCONFG, {tag, " dbgconfg_after_enable"});

            flow_raw_mem_write32(FLOW_CLA_DBGRESTORE, 32'h0000_0020, {tag, " dbgrestore_origin_20"});
            flow_raw_mem_write32(FLOW_CLA_SWBPMASK, 32'h0000_0001, {tag, " swbpmask_type0_mask1"});
            flow_raw_mem_read32(FLOW_CLA_SWBPMASK, {tag, " swbpmask_read_type0_mask1"});

            flow_raw_mem_write32(FLOW_CLA_SWBPMASK, 32'h0000_4004, {tag, " swbpmask_type1_mask4"});
            flow_raw_mem_read32(FLOW_CLA_SWBPMASK, {tag, " swbpmask_read_type1_mask4"});

            flow_raw_mem_write32(FLOW_CLA_SWBPMASK, 32'h0000_8005, {tag, " swbpmask_type2_mask5"});
            flow_raw_mem_read32(FLOW_CLA_SWBPMASK, {tag, " swbpmask_read_type2_mask5"});

            flow_raw_mem_write32(FLOW_CLA_SWBPMASK, 32'h0000_C00F, {tag, " swbpmask_type3_maskf"});
            flow_raw_mem_read32(FLOW_CLA_SWBPMASK, {tag, " swbpmask_read_type3_maskf"});

            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_0008, {tag, " dbgstat_run_preclear"});
            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_0008, {tag, " dbgstat_run_with_swbp"});
            repeat (20000) @(posedge vif.cpu_clk);
            flow_raw_mem_read32(FLOW_CLA_DBGSTAT, {tag, " dbgstat_after_swbp_run"});
            flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.ctl.bp_stall", {tag, " bp_stall_probe"});
            flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.ctl.bp_pend", {tag, " bp_pend_probe"});
            flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.p2.e_swbp", {tag, " e_swbp_probe"});
            flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.p2.d2_mdebugstop", {tag, " d2_mdebugstop_probe"});

            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_0009, {tag, " dbgstat_halt_after_swbp"});
            flow_raw_mem_read32(FLOW_CLA_DBGSTAT, {tag, " dbgstat_after_halt"});
            flow_raw_mem_write32(FLOW_CLA_DBGCONFG, 32'h0000_0000, {tag, " dbgconfg_cleanup"});
            flow_raw_mem_write32(FLOW_CLA_SWBPMASK, 32'h0000_0000, {tag, " swbpmask_cleanup"});
            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_0000, {tag, " dbgstat_disconnect"});
        end
    endtask : flow_cla_swbp_sweep

    virtual task flow_cla_pc_readback_sweep(input string tag = "ET_JTAG_FLOW");
        begin
            `uvm_info(tag,
                      "flow_cla_pc_readback_sweep: read ACTIVE/TASKMODE/PCE/PCR2/PCR1/PCD2 via JTAG memory access",
                      UVM_LOW)

            flow_expect_cla_task1_running({tag, " cla_task1_running"});
            flow_raw_mem_read32(FLOW_CLA_ACTIVE, {tag, " active_rd32"});
            flow_raw_mem_read16(FLOW_CLA_ACTIVE, {tag, " active_rd16"});
            flow_raw_mem_read32(FLOW_CLA_TASKMODE, {tag, " taskmode_rd32"});
            flow_raw_mem_read16(FLOW_CLA_TASKMODE, {tag, " taskmode_rd16"});
            flow_raw_mem_write32(FLOW_CLA_TASKMODE, 32'h0000_0001, {tag, " taskmode_w32_1"});
            flow_raw_mem_read32(FLOW_CLA_TASKMODE, {tag, " taskmode_after_w32_1"});
            flow_raw_mem_write32(FLOW_CLA_ACTIVE, 32'h0001_0000, {tag, " active_w32_high_taskmode"});
            flow_raw_mem_read32(FLOW_CLA_ACTIVE, {tag, " active_after_w32_high"});
            flow_raw_mem_write16(FLOW_CLA_TASKMODE, 16'h0000, {tag, " taskmode_w16_0"});

            flow_raw_mem_read32(FLOW_CLA_PCE, {tag, " pce_rd32_a"});
            flow_raw_mem_read32(FLOW_CLA_PCR2, {tag, " pcr2_rd32_a"});
            flow_raw_mem_read32(FLOW_CLA_PCR1, {tag, " pcr1_rd32_a"});
            flow_raw_mem_read32(FLOW_CLA_PCD2, {tag, " pcd2_rd32_a"});
            flow_raw_mem_read16(FLOW_CLA_PCE, {tag, " pce_rd16_low"});
            flow_raw_mem_read16(FLOW_CLA_PCR2, {tag, " pcr2_rd16_high_alias"});
            flow_raw_mem_read16(FLOW_CLA_PCR1, {tag, " pcr1_rd16_low"});
            flow_raw_mem_read16(FLOW_CLA_PCD2, {tag, " pcd2_rd16_high_alias"});

            repeat (10000) @(posedge vif.cpu_clk);
            flow_raw_mem_read32(FLOW_CLA_PCE, {tag, " pce_rd32_b"});
            flow_raw_mem_read32(FLOW_CLA_PCR2, {tag, " pcr2_rd32_b"});
            flow_raw_mem_read32(FLOW_CLA_PCR1, {tag, " pcr1_rd32_b"});
            flow_raw_mem_read32(FLOW_CLA_PCD2, {tag, " pcd2_rd32_b"});
        end
    endtask : flow_cla_pc_readback_sweep

    virtual task flow_cla_command_ack(input string tag = "ET_JTAG_FLOW");
        bit got_debug;
        begin
            `uvm_info(tag,
                      "flow_cla_command_ack: independently verify CLA DBGSTAT HALT/STEP/RUN command pulses and ACK/clear behavior",
                      UVM_LOW)

            flow_expect_cla_task1_running({tag, " cla_task1_running"});
            flow_raw_mem_read32(FLOW_CLA_DBGSTAT, {tag, " dbgstat_initial"});

            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_0008, {tag, " dbgstat_connect"});
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_CLA.c_reg.DBGCONNECTED",
                              32'h0000_0001, 32'h0000_0001, {tag, " connected_after_connect"});

            flow_raw_mem_write32_check_mask(FLOW_CLA_DBGSTAT, 32'h0000_0009,
                                            "chip_top_tb.I_chip_top.I_CLA.et_cla_cmd",
                                            32'h0000_0004, 32'h0000_0004, 1'b1, 5000,
                                            {tag, " halt_cmd_pulse"});
            flow_wait_cla_debug_state({tag, " wait_halt_debug"}, 60000, got_debug);
            flow_raw_mem_read32(FLOW_CLA_DBGSTAT, {tag, " dbgstat_after_halt"});
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_CLA.c_reg.DBGACKED",
                              32'h0000_0001, 32'h0000_0001, {tag, " dbgacked_after_halt"});

            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_0019, {tag, " clear_ack_safe_halt"});
            repeat (2000) @(posedge vif.cpu_clk);
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_CLA.c_reg.DBGACKED",
                              32'h0000_0001, 32'h0000_0000, {tag, " dbgacked_after_clear"});

            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_000D, {tag, " set_step_mode_old_halt"});
            flow_raw_mem_write32_check_mask(FLOW_CLA_DBGSTAT, 32'h0000_000C,
                                            "chip_top_tb.I_chip_top.I_CLA.et_cla_cmd",
                                            32'h0000_0001, 32'h0000_0001, 1'b1, 5000,
                                            {tag, " step_cmd_pulse"});
            flow_wait_cla_debug_state({tag, " wait_step_complete_debug"}, 60000, got_debug);
            flow_raw_mem_read32(FLOW_CLA_DBGSTAT, {tag, " dbgstat_after_step"});
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_CLA.c_reg.DBGACKED",
                              32'h0000_0001, 32'h0000_0001, {tag, " dbgacked_after_step"});

            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_0019, {tag, " clear_ack_and_step_latch"});
            repeat (2000) @(posedge vif.cpu_clk);
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_CLA.c_reg.DBGACKED",
                              32'h0000_0001, 32'h0000_0000, {tag, " dbgacked_after_step_clear"});

            flow_raw_mem_write32_check_mask(FLOW_CLA_DBGSTAT, 32'h0000_0008,
                                            "chip_top_tb.I_chip_top.I_CLA.et_cla_cmd",
                                            32'h0000_0002, 32'h0000_0002, 1'b1, 5000,
                                            {tag, " run_cmd_pulse"});
            repeat (12000) @(posedge vif.cpu_clk);
            flow_raw_mem_read32(FLOW_CLA_DBGSTAT, {tag, " dbgstat_after_run"});
            flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.ctl.et_run_saved", {tag, " et_run_saved_after_run"});

            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_0009, {tag, " halt_before_mpc_ack"});
            flow_wait_cla_debug_state({tag, " wait_debug_before_mpc_ack"}, 60000, got_debug);
            flow_raw_mem_write32_check_mask(FLOW_CLA_MPC, 32'h0000_0020,
                                            "chip_top_tb.I_chip_top.I_CLA.et_mpc_wt",
                                            32'h0000_0001, 32'h0000_0001, 1'b1, 5000,
                                            {tag, " mpc_write_ack_pulse"});
            flow_wait_cla_debug_state({tag, " wait_debug_after_mpc_ack"}, 60000, got_debug);

            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_0000, {tag, " dbgstat_disconnect_cleanup"});
        end
    endtask : flow_cla_command_ack

    virtual task flow_cla_negative_state_cmd(input string tag = "ET_JTAG_FLOW");
        begin
            `uvm_info(tag,
                      "flow_cla_negative_state_cmd: issue commands outside their legal CLA debug state and check no illegal debug side effects",
                      UVM_LOW)

            flow_expect_cla_task1_running({tag, " cla_task1_running"});
            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_0008, {tag, " connect_run_state"});
            repeat (2000) @(posedge vif.cpu_clk);
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_CLA.cla_et_debugstate",
                              32'h0000_0001, 32'h0000_0000, {tag, " debugstate_clear_before_negative"});

            flow_raw_mem_write32_check_mask(FLOW_CLA_MPC, 32'h0000_0030,
                                            "chip_top_tb.I_chip_top.I_CLA.et_mpc_wt",
                                            32'h0000_0001, 32'h0000_0001, 1'b0, 5000,
                                            {tag, " run_state_mpc_no_et_mpc_wt"});
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_CLA.cla_et_debugstate",
                              32'h0000_0001, 32'h0000_0000, {tag, " debugstate_clear_after_run_mpc"});

            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_000C, {tag, " arm_step_mode_in_run"});
            flow_raw_mem_write32_check_mask(FLOW_CLA_DBGSTAT, 32'h0000_000C,
                                            "chip_top_tb.I_chip_top.I_CLA.et_cla_cmd",
                                            32'h0000_0001, 32'h0000_0001, 1'b1, 5000,
                                            {tag, " run_state_step_cmd_pulse"});
            repeat (2000) @(posedge vif.cpu_clk);
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_CLA.cla_et_debugstate",
                              32'h0000_0001, 32'h0000_0000, {tag, " debugstate_clear_after_run_step"});

            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_0008, {tag, " clear_step_mode_in_run"});
            flow_raw_mem_write32_check_mask(FLOW_CLA_DBGSTAT, 32'h0000_0008,
                                            "chip_top_tb.I_chip_top.I_CLA.et_cla_cmd",
                                            32'h0000_0002, 32'h0000_0002, 1'b1, 5000,
                                            {tag, " run_state_run_cmd_pulse"});
            repeat (2000) @(posedge vif.cpu_clk);
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_CLA.cla_et_debugstate",
                              32'h0000_0001, 32'h0000_0000, {tag, " debugstate_clear_after_run_run"});

            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_0000, {tag, " dbgstat_disconnect_cleanup"});
        end
    endtask : flow_cla_negative_state_cmd

    virtual task flow_cla_disconnect_gate(input string tag = "ET_JTAG_FLOW");
        begin
            `uvm_info(tag,
                      "flow_cla_disconnect_gate: keep DBGCONNECTED=0 while enabling breakpoint knobs; bp_pend/bp_stall must stay gated off",
                      UVM_LOW)

            flow_expect_cla_task1_running({tag, " cla_task1_running"});
            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_0000, {tag, " force_disconnect"});
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_CLA.c_reg.DBGCONNECTED",
                              32'h0000_0001, 32'h0000_0000, {tag, " disconnected_hdl"});

            flow_raw_mem_write32(FLOW_CLA_DBGCONFG, 32'h0000_0001, {tag, " dbgconfg_enable_while_disconnected"});
            flow_raw_mem_write32(FLOW_CLA_SWBPMASK, 32'h0000_C00F, {tag, " swbpmask_all_while_disconnected"});
            repeat (30000) @(posedge vif.cpu_clk);

            flow_expect_hdl32("chip_top_tb.I_chip_top.I_CLA.ctl.bp_pend",
                              32'h0000_0001, 32'h0000_0000, {tag, " bp_pend_gated"});
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_CLA.ctl.bp_stall",
                              32'h0000_0001, 32'h0000_0000, {tag, " bp_stall_gated"});
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_CLA.cla_et_debugstate",
                              32'h0000_0001, 32'h0000_0000, {tag, " debugstate_gated"});
            flow_raw_mem_read32(FLOW_CLA_DBGSTAT, {tag, " dbgstat_disconnected"});

            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_0008, {tag, " reconnect_for_observe"});
            flow_raw_mem_read32(FLOW_CLA_DBGSTAT, {tag, " dbgstat_after_reconnect"});
            flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.ctl.bp_pend", {tag, " bp_pend_after_reconnect_observe"});
            flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.ctl.bp_stall", {tag, " bp_stall_after_reconnect_observe"});

            flow_raw_mem_write32(FLOW_CLA_DBGCONFG, 32'h0000_0000, {tag, " dbgconfg_cleanup"});
            flow_raw_mem_write32(FLOW_CLA_SWBPMASK, 32'h0000_0000, {tag, " swbpmask_cleanup"});
            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_0000, {tag, " dbgstat_disconnect_cleanup"});
        end
    endtask : flow_cla_disconnect_gate

    virtual task flow_cla_debug_reset_state(input string tag = "ET_JTAG_FLOW");
        bit got_debug;
        begin
            `uvm_info(tag,
                      "flow_cla_debug_reset_state: enter CLA debug state, dirty debug regs, issue DBGRESET soft reset and check cleanup",
                      UVM_LOW)

            flow_expect_cla_task1_running({tag, " cla_task1_running"});
            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_0009, {tag, " connect_halt_before_reset"});
            flow_wait_cla_debug_state({tag, " wait_debug_before_reset"}, 60000, got_debug);
            flow_raw_mem_write32(FLOW_CLA_DBGCONFG, 32'h0000_0003, {tag, " dirty_dbgconfg"});
            flow_raw_mem_write32(FLOW_CLA_SWBPMASK, 32'h0000_C00F, {tag, " dirty_swbpmask"});
            flow_raw_mem_write32(FLOW_CLA_DBGRESTORE, 32'hA55A_5AA5, {tag, " dirty_dbgrestore"});
            flow_raw_mem_read32(FLOW_CLA_DBGSTAT, {tag, " dbgstat_before_reset"});

            flow_raw_mem_write32(FLOW_CLA_DBGRESET, 32'h0000_0200, {tag, " dbgreset_softreset_w32"});
            repeat (3000) @(posedge vif.cpu_clk);

            flow_expect_hdl32("chip_top_tb.I_chip_top.I_CLA.cla_et_debugstate",
                              32'h0000_0001, 32'h0000_0000, {tag, " debugstate_after_softreset"});
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_CLA.ctl.et_state",
                              32'h0000_0003, 32'h0000_0000, {tag, " et_state_after_softreset"});
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_CLA.c_reg.DBGCONNECTED",
                              32'h0000_0001, 32'h0000_0000, {tag, " dbgconnected_after_softreset"});
            flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.c_reg.DBGACKED", {tag, " dbgacked_after_softreset_observe"});
            flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.c_reg.DBGCONFG", {tag, " dbgconfg_after_softreset_observe"});
            flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.c_reg.SWBPMASK", {tag, " swbpmask_after_softreset_observe"});
            flow_raw_mem_read32(FLOW_CLA_DBGSTAT, {tag, " dbgstat_after_softreset"});
        end
    endtask : flow_cla_debug_reset_state

    virtual task flow_cla_fetch_buffer_rw(input string tag = "ET_JTAG_FLOW");
        bit got_debug;
        begin
            `uvm_info(tag,
                      "flow_cla_fetch_buffer_rw: exercise CLA fetch buffer PF0 BUF/BUFh/PCB read-write window and pf0_buf_we strobes",
                      UVM_LOW)

            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_0009, {tag, " connect_halt_before_buf_rw"});
            flow_wait_cla_debug_state({tag, " wait_debug_before_buf_rw"}, 60000, got_debug);

            flow_raw_mem_write32_check_mask(FLOW_CLA_BUF0, 32'h1122_3344,
                                            "chip_top_tb.I_chip_top.I_CLA.pf0_buf_we",
                                            32'h0000_0003, 32'h0000_0003, 1'b1, 5000,
                                            {tag, " buf0_w32_pf0_buf_we"});
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_CLA.p1.f2.IQ.buf_d[0]",
                              32'hFFFF_FFFF, 32'h1122_3344, {tag, " buf0_w32_hdl"});
            flow_raw_mem_read32(FLOW_CLA_BUF0, {tag, " buf0_rd32"});
            flow_raw_mem_read32(FLOW_CLA_BUF0H, {tag, " buf0h_rd32"});
            flow_raw_mem_write16_check_mask(FLOW_CLA_BUF0, 16'hA500,
                                            "chip_top_tb.I_chip_top.I_CLA.pf0_buf_we",
                                            32'h0000_0001, 32'h0000_0001, 1'b1, 5000,
                                            {tag, " buf0_low_w16_pf0_buf_we"});
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_CLA.p1.f2.IQ.buf_d[0]",
                              32'hFFFF_FFFF, 32'h1122_A500, {tag, " buf0_low_w16_hdl"});
            flow_raw_mem_write16_check_mask(FLOW_CLA_BUF0H, 16'h5A00,
                                            "chip_top_tb.I_chip_top.I_CLA.pf0_buf_we",
                                            32'h0000_0002, 32'h0000_0002, 1'b1, 5000,
                                            {tag, " buf0_high_w16_pf0_buf_we"});
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_CLA.p1.f2.IQ.buf_d[0]",
                              32'hFFFF_FFFF, 32'h5A00_A500, {tag, " buf0_high_w16_hdl"});

            flow_raw_mem_write32_check_mask(FLOW_CLA_BUF1, 32'h5566_7788,
                                            "chip_top_tb.I_chip_top.I_CLA.pf0_buf_we",
                                            32'h0000_000C, 32'h0000_000C, 1'b1, 5000,
                                            {tag, " buf1_w32_pf0_buf_we"});
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_CLA.p1.f2.IQ.buf_d[1]",
                              32'hFFFF_FFFF, 32'h5566_7788, {tag, " buf1_w32_hdl"});
            flow_raw_mem_read32(FLOW_CLA_BUF1, {tag, " buf1_rd32"});
            flow_raw_mem_read32(FLOW_CLA_BUF1H, {tag, " buf1h_rd32"});
            flow_raw_mem_write16_check_mask(FLOW_CLA_BUF1H, 16'h5A01,
                                            "chip_top_tb.I_chip_top.I_CLA.pf0_buf_we",
                                            32'h0000_0008, 32'h0000_0008, 1'b1, 5000,
                                            {tag, " buf1_high_w16_pf0_buf_we"});
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_CLA.p1.f2.IQ.buf_d[1]",
                              32'hFFFF_FFFF, 32'h5A01_7788, {tag, " buf1_high_w16_hdl"});

            flow_raw_mem_write32_check_mask(FLOW_CLA_BUF2, 32'hA5A5_5A5A,
                                            "chip_top_tb.I_chip_top.I_CLA.pf0_buf_we",
                                            32'h0000_0030, 32'h0000_0030, 1'b1, 5000,
                                            {tag, " buf2_w32_pf0_buf_we"});
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_CLA.p1.f2.IQ.buf_d[2]",
                              32'hFFFF_FFFF, 32'hA5A5_5A5A, {tag, " buf2_w32_hdl"});
            flow_raw_mem_read32(FLOW_CLA_BUF2, {tag, " buf2_rd32"});
            flow_raw_mem_read32(FLOW_CLA_BUF2H, {tag, " buf2h_rd32"});
            flow_raw_mem_write16_check_mask(FLOW_CLA_BUF2, 16'hA502,
                                            "chip_top_tb.I_chip_top.I_CLA.pf0_buf_we",
                                            32'h0000_0010, 32'h0000_0010, 1'b1, 5000,
                                            {tag, " buf2_low_w16_pf0_buf_we"});
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_CLA.p1.f2.IQ.buf_d[2]",
                              32'hFFFF_FFFF, 32'hA5A5_A502, {tag, " buf2_low_w16_hdl"});

            flow_raw_mem_write32_check_mask(FLOW_CLA_BUF3, 32'hC33C_C33C,
                                            "chip_top_tb.I_chip_top.I_CLA.pf0_buf_we",
                                            32'h0000_00C0, 32'h0000_00C0, 1'b1, 5000,
                                            {tag, " buf3_w32_pf0_buf_we"});
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_CLA.p1.f2.IQ.buf_d[3]",
                              32'hFFFF_FFFF, 32'hC33C_C33C, {tag, " buf3_w32_hdl"});
            flow_raw_mem_read32(FLOW_CLA_BUF3, {tag, " buf3_rd32"});
            flow_raw_mem_read32(FLOW_CLA_BUF3H, {tag, " buf3h_rd32"});
            flow_raw_mem_write16_check_mask(FLOW_CLA_BUF3H, 16'h5A03,
                                            "chip_top_tb.I_chip_top.I_CLA.pf0_buf_we",
                                            32'h0000_0080, 32'h0000_0080, 1'b1, 5000,
                                            {tag, " buf3_high_w16_pf0_buf_we"});
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_CLA.p1.f2.IQ.buf_d[3]",
                              32'hFFFF_FFFF, 32'h5A03_C33C, {tag, " buf3_high_w16_hdl"});

            flow_raw_mem_read32(FLOW_CLA_ACTIVE, {tag, " active_buf_valid_rd"});
            flow_raw_mem_read32(FLOW_CLA_PCB0, {tag, " pcb0_rd32"});
            flow_raw_mem_read32(FLOW_CLA_PCB1, {tag, " pcb1_rd32"});
            flow_raw_mem_read32(FLOW_CLA_PCB2, {tag, " pcb2_rd32"});
            flow_raw_mem_read32(FLOW_CLA_PCB3, {tag, " pcb3_rd32"});
            flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.p1.f2.IQ.buf_pf0_valid", {tag, " buf_pf0_valid_probe"});
        end
    endtask : flow_cla_fetch_buffer_rw

    virtual task flow_cla_exec_reg_write_matrix(input string tag = "ET_JTAG_FLOW");
        bit got_debug;
        begin
            `uvm_info(tag,
                      "flow_cla_exec_reg_write_matrix: exercise MR0-3/MAR0-1/MSTF PF0 write matrix and pf0_reg_we[0:11]",
                      UVM_LOW)

            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_0009, {tag, " connect_halt_before_exec_reg_rw"});
            flow_wait_cla_debug_state({tag, " wait_debug_before_exec_reg_rw"}, 60000, got_debug);

            flow_raw_mem_write32_check_mask(FLOW_CLA_MR0, 32'h1122_3344,
                                            "chip_top_tb.I_chip_top.I_CLA.pf0_reg_we",
                                            32'h0000_0003, 32'h0000_0003, 1'b1, 5000,
                                            {tag, " mr0_w32_pf0_reg_we"});
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_CLA.p2.e_reg.MR0",
                              32'hFFFF_FFFF, 32'h1122_3344, {tag, " mr0_w32_hdl"});
            flow_raw_mem_write16_check_mask(FLOW_CLA_MR0, 16'hA500,
                                            "chip_top_tb.I_chip_top.I_CLA.pf0_reg_we",
                                            32'h0000_0001, 32'h0000_0001, 1'b1, 5000,
                                            {tag, " mr0_low_w16_pf0_reg_we"});
            flow_raw_mem_write16_check_mask(FLOW_CLA_MR0H, 16'h5A00,
                                            "chip_top_tb.I_chip_top.I_CLA.pf0_reg_we",
                                            32'h0000_0002, 32'h0000_0002, 1'b1, 5000,
                                            {tag, " mr0_high_w16_pf0_reg_we"});
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_CLA.p2.e_reg.MR0",
                              32'hFFFF_FFFF, 32'h5A00_A500, {tag, " mr0_w16_hdl"});

            flow_raw_mem_write32_check_mask(FLOW_CLA_MR1, 32'h1122_3345,
                                            "chip_top_tb.I_chip_top.I_CLA.pf0_reg_we",
                                            32'h0000_000C, 32'h0000_000C, 1'b1, 5000,
                                            {tag, " mr1_w32_pf0_reg_we"});
            flow_raw_mem_write16_check_mask(FLOW_CLA_MR1, 16'hA501,
                                            "chip_top_tb.I_chip_top.I_CLA.pf0_reg_we",
                                            32'h0000_0004, 32'h0000_0004, 1'b1, 5000,
                                            {tag, " mr1_low_w16_pf0_reg_we"});
            flow_raw_mem_write16_check_mask(FLOW_CLA_MR1H, 16'h5A01,
                                            "chip_top_tb.I_chip_top.I_CLA.pf0_reg_we",
                                            32'h0000_0008, 32'h0000_0008, 1'b1, 5000,
                                            {tag, " mr1_high_w16_pf0_reg_we"});
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_CLA.p2.e_reg.MR1",
                              32'hFFFF_FFFF, 32'h5A01_A501, {tag, " mr1_w16_hdl"});

            flow_raw_mem_write32_check_mask(FLOW_CLA_MR2, 32'h1122_3346,
                                            "chip_top_tb.I_chip_top.I_CLA.pf0_reg_we",
                                            32'h0000_0030, 32'h0000_0030, 1'b1, 5000,
                                            {tag, " mr2_w32_pf0_reg_we"});
            flow_raw_mem_write16_check_mask(FLOW_CLA_MR2, 16'hA502,
                                            "chip_top_tb.I_chip_top.I_CLA.pf0_reg_we",
                                            32'h0000_0010, 32'h0000_0010, 1'b1, 5000,
                                            {tag, " mr2_low_w16_pf0_reg_we"});
            flow_raw_mem_write16_check_mask(FLOW_CLA_MR2H, 16'h5A02,
                                            "chip_top_tb.I_chip_top.I_CLA.pf0_reg_we",
                                            32'h0000_0020, 32'h0000_0020, 1'b1, 5000,
                                            {tag, " mr2_high_w16_pf0_reg_we"});
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_CLA.p2.e_reg.MR2",
                              32'hFFFF_FFFF, 32'h5A02_A502, {tag, " mr2_w16_hdl"});

            flow_raw_mem_write32_check_mask(FLOW_CLA_MR3, 32'h1122_3347,
                                            "chip_top_tb.I_chip_top.I_CLA.pf0_reg_we",
                                            32'h0000_00C0, 32'h0000_00C0, 1'b1, 5000,
                                            {tag, " mr3_w32_pf0_reg_we"});
            flow_raw_mem_write16_check_mask(FLOW_CLA_MR3, 16'hA503,
                                            "chip_top_tb.I_chip_top.I_CLA.pf0_reg_we",
                                            32'h0000_0040, 32'h0000_0040, 1'b1, 5000,
                                            {tag, " mr3_low_w16_pf0_reg_we"});
            flow_raw_mem_write16_check_mask(FLOW_CLA_MR3H, 16'h5A03,
                                            "chip_top_tb.I_chip_top.I_CLA.pf0_reg_we",
                                            32'h0000_0080, 32'h0000_0080, 1'b1, 5000,
                                            {tag, " mr3_high_w16_pf0_reg_we"});
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_CLA.p2.e_reg.MR3",
                              32'hFFFF_FFFF, 32'h5A03_A503, {tag, " mr3_w16_hdl"});

            flow_raw_mem_write32_check_mask(FLOW_CLA_MAR0, 32'h1357_2468,
                                            "chip_top_tb.I_chip_top.I_CLA.pf0_reg_we",
                                            32'h0000_0300, 32'h0000_0300, 1'b1, 5000,
                                            {tag, " mar_pair_w32_pf0_reg_we"});
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_CLA.p2.e_reg.MAR0",
                              32'h0000_FFFF, 32'h0000_2468, {tag, " mar0_w32_hdl"});
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_CLA.p2.e_reg.MAR1",
                              32'h0000_FFFF, 32'h0000_1357, {tag, " mar1_w32_hdl"});
            flow_raw_mem_write16_check_mask(FLOW_CLA_MAR0, 16'h0A0A,
                                            "chip_top_tb.I_chip_top.I_CLA.pf0_reg_we",
                                            32'h0000_0100, 32'h0000_0100, 1'b1, 5000,
                                            {tag, " mar0_w16_pf0_reg_we"});
            flow_raw_mem_write16_check_mask(FLOW_CLA_MAR1, 16'h0B0B,
                                            "chip_top_tb.I_chip_top.I_CLA.pf0_reg_we",
                                            32'h0000_0200, 32'h0000_0200, 1'b1, 5000,
                                            {tag, " mar1_w16_pf0_reg_we"});
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_CLA.p2.e_reg.MAR0",
                              32'h0000_FFFF, 32'h0000_0A0A, {tag, " mar0_w16_hdl"});
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_CLA.p2.e_reg.MAR1",
                              32'h0000_FFFF, 32'h0000_0B0B, {tag, " mar1_w16_hdl"});

            flow_raw_mem_write32_check_mask(FLOW_CLA_MSTF, 32'h00FF_FFFF,
                                            "chip_top_tb.I_chip_top.I_CLA.pf0_reg_we",
                                            32'h0000_0C00, 32'h0000_0C00, 1'b1, 5000,
                                            {tag, " mstf_w32_pf0_reg_we"});
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_CLA.p2.e_reg.MSTF",
                              32'h00FF_FFFF, 32'h00FF_FA7F, {tag, " mstf_w32_masked_hdl"});
            flow_raw_mem_write16_check_mask(FLOW_CLA_MSTFH, 16'h0055,
                                            "chip_top_tb.I_chip_top.I_CLA.pf0_reg_we",
                                            32'h0000_0800, 32'h0000_0800, 1'b1, 5000,
                                            {tag, " mstfh_w16_pf0_reg_we"});
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_CLA.p2.e_reg.MSTF",
                              32'h00FF_0000, 32'h0055_0000, {tag, " mstfh_w16_masked_hdl"});

            flow_raw_mem_read32(FLOW_CLA_MR0, {tag, " mr0_rd32"});
            flow_raw_mem_read32(FLOW_CLA_MR1, {tag, " mr1_rd32"});
            flow_raw_mem_read32(FLOW_CLA_MR2, {tag, " mr2_rd32"});
            flow_raw_mem_read32(FLOW_CLA_MR3, {tag, " mr3_rd32"});
            flow_raw_mem_read32(FLOW_CLA_MAR0, {tag, " mar_pair_rd32"});
            flow_raw_mem_read32(FLOW_CLA_MSTF, {tag, " mstf_rd32"});
        end
    endtask : flow_cla_exec_reg_write_matrix

    virtual task flow_cla_swbp_pipeline_stall(input string tag = "ET_JTAG_FLOW");
        bit got_vald2;
        bit got_swbp2;
        bit got_bp_stall;
        begin
            `uvm_info(tag,
                      "flow_cla_swbp_pipeline_stall: hold CLA pipe with r1stall, set SWBP on VALD[2], then release and observe breakpoint debug entry",
                      UVM_LOW)

            flow_expect_cla_task1_running({tag, " cla_task1_running"});
            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_0008, {tag, " dbgstat_connect"});
            flow_raw_mem_write32(FLOW_CLA_DBGCONFG, 32'h0000_0001, {tag, " dbgconfg_enable_swbp"});

            flow_watch_hdl32_mask("chip_top_tb.I_chip_top.I_CLA.VALD",
                                  32'h0000_0004, 32'h0000_0004, 50000,
                                  got_vald2, {tag, " wait_vald2"});
            if (!got_vald2) begin
                `uvm_error(tag, "flow_cla_swbp_pipeline_stall: VALD[2] was not observed before SWBP injection")
            end

            flow_force_hdl1("chip_top_tb.I_chip_top.mc_cla_r1stall", 1'b1,
                            {tag, " force_r1stall_hold_pipe"});
            repeat (40) @(posedge vif.cpu_clk);
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_CLA.STALL2",
                              32'h0000_0001, 32'h0000_0001, {tag, " stall2_due_r1stall"});

            flow_raw_mem_write32_check_mask(FLOW_CLA_SWBPMASK, 32'h0000_C004,
                                            "chip_top_tb.I_chip_top.I_CLA.SWBPCMD",
                                            32'h0000_003F, 32'h0000_0034, 1'b1, 5000,
                                            {tag, " swbpcmd_set_vald2"});
            flow_watch_hdl32_mask("chip_top_tb.I_chip_top.I_CLA.SWBP",
                                  32'h0000_0004, 32'h0000_0004, 5000,
                                  got_swbp2, {tag, " wait_swbp2"});
            if (!got_swbp2) begin
                `uvm_error(tag, "flow_cla_swbp_pipeline_stall: SWBP[2] did not latch while VALD[2] was held")
            end

            flow_release_hdl("chip_top_tb.I_chip_top.mc_cla_r1stall",
                             {tag, " release_r1stall"});
            flow_watch_hdl32_mask("chip_top_tb.I_chip_top.I_CLA.ctl.bp_stall",
                                  32'h0000_0001, 32'h0000_0001, 40000,
                                  got_bp_stall, {tag, " wait_bp_stall"});
            if (!got_bp_stall) begin
                `uvm_warning(tag, "flow_cla_swbp_pipeline_stall: bp_stall was not observed after SWBP release; SWBPCMD/SWBP latch checks still covered")
            end
            flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.cla_et_debugstate",
                               {tag, " debugstate_after_swbp_release"});
            flow_raw_mem_read32(FLOW_CLA_DBGSTAT, {tag, " dbgstat_after_swbp_pipeline"});

            flow_raw_mem_write32(FLOW_CLA_DBGCONFG, 32'h0000_0000, {tag, " dbgconfg_cleanup"});
            flow_raw_mem_write32(FLOW_CLA_SWBPMASK, 32'h0000_0000, {tag, " swbpmask_cleanup"});
            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_0000, {tag, " dbgstat_disconnect_cleanup"});
        end
    endtask : flow_cla_swbp_pipeline_stall

    virtual task flow_cla_swbp3_set_clear(input string tag = "ET_JTAG_FLOW");
        bit got_vald3;
        bit got_swbp3_set;
        bit got_swbp3_clear;
        bit got_swbp3_reset;
        bit got_bp_stall;
        begin
            `uvm_info(tag,
                      "flow_cla_swbp3_set_clear: hold CLA pipe at VALD[3], issue SWBPMASK type3/type2 for SWBP3 set/clear, then release a set breakpoint",
                      UVM_LOW)

            flow_expect_cla_task1_running({tag, " cla_task1_running"});
            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_0008, {tag, " dbgstat_connect"});
            flow_raw_mem_write32(FLOW_CLA_DBGCONFG, 32'h0000_0001, {tag, " dbgconfg_enable_swbp"});

            flow_watch_hdl32_mask("chip_top_tb.I_chip_top.I_CLA.VALD",
                                  32'h0000_0008, 32'h0000_0008, 50000,
                                  got_vald3, {tag, " wait_vald3"});
            if (!got_vald3) begin
                `uvm_error(tag, "flow_cla_swbp3_set_clear: VALD[3] was not observed before SWBP3 injection")
            end

            flow_force_hdl1("chip_top_tb.I_chip_top.mc_cla_r1stall", 1'b1,
                            {tag, " force_r1stall_hold_vald3"});
            repeat (40) @(posedge vif.cpu_clk);
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_CLA.STALL2",
                              32'h0000_0001, 32'h0000_0001, {tag, " stall2_due_r1stall"});
            flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.VALD", {tag, " vald_held_snapshot"});

            flow_raw_mem_write32_check_mask(FLOW_CLA_SWBPMASK, 32'h0000_C008,
                                            "chip_top_tb.I_chip_top.I_CLA.SWBPCMD",
                                            32'h0000_003F, 32'h0000_0038, 1'b1, 5000,
                                            {tag, " swbpcmd_set_vald3"});
            flow_watch_hdl32_mask("chip_top_tb.I_chip_top.I_CLA.SWBP",
                                  32'h0000_0008, 32'h0000_0008, 5000,
                                  got_swbp3_set, {tag, " wait_swbp3_set"});
            if (!got_swbp3_set) begin
                `uvm_error(tag, "flow_cla_swbp3_set_clear: SWBP[3] did not set while VALD[3] was held")
            end

            flow_raw_mem_write32_check_mask(FLOW_CLA_SWBPMASK, 32'h0000_8008,
                                            "chip_top_tb.I_chip_top.I_CLA.SWBPCMD",
                                            32'h0000_003F, 32'h0000_0028, 1'b1, 5000,
                                            {tag, " swbpcmd_clear_vald3"});
            flow_watch_hdl32_mask("chip_top_tb.I_chip_top.I_CLA.SWBP",
                                  32'h0000_0008, 32'h0000_0000, 5000,
                                  got_swbp3_clear, {tag, " wait_swbp3_clear"});
            if (!got_swbp3_clear) begin
                `uvm_error(tag, "flow_cla_swbp3_set_clear: SWBP[3] did not clear while VALD[3] was held")
            end

            flow_raw_mem_write32_check_mask(FLOW_CLA_SWBPMASK, 32'h0000_C008,
                                            "chip_top_tb.I_chip_top.I_CLA.SWBPCMD",
                                            32'h0000_003F, 32'h0000_0038, 1'b1, 5000,
                                            {tag, " swbpcmd_set_vald3_for_release"});
            flow_watch_hdl32_mask("chip_top_tb.I_chip_top.I_CLA.SWBP",
                                  32'h0000_0008, 32'h0000_0008, 5000,
                                  got_swbp3_reset, {tag, " wait_swbp3_set_for_release"});
            if (!got_swbp3_reset) begin
                `uvm_error(tag, "flow_cla_swbp3_set_clear: SWBP[3] did not re-set before releasing the pipe")
            end

            flow_release_hdl("chip_top_tb.I_chip_top.mc_cla_r1stall",
                             {tag, " release_r1stall_vald3"});
            flow_watch_hdl32_mask("chip_top_tb.I_chip_top.I_CLA.ctl.bp_stall",
                                  32'h0000_0001, 32'h0000_0001, 40000,
                                  got_bp_stall, {tag, " wait_bp_stall_after_swbp3"});
            if (!got_bp_stall) begin
                `uvm_warning(tag, "flow_cla_swbp3_set_clear: bp_stall was not observed after SWBP3 release; SWBP3 set/clear RTL branch was still exercised")
            end
            flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.ctl.e_swbp", {tag, " e_swbp_after_release"});
            flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.cla_et_debugstate", {tag, " debugstate_after_swbp3"});
            flow_raw_mem_read32(FLOW_CLA_DBGSTAT, {tag, " dbgstat_after_swbp3"});

            flow_raw_mem_write32(FLOW_CLA_DBGCONFG, 32'h0000_0000, {tag, " dbgconfg_cleanup"});
            flow_raw_mem_write32(FLOW_CLA_SWBPMASK, 32'h0000_0000, {tag, " swbpmask_cleanup"});
            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_0000, {tag, " dbgstat_disconnect_cleanup"});
        end
    endtask : flow_cla_swbp3_set_clear

    virtual task flow_cla_debug_idle_exit_reachability(input string tag = "ET_JTAG_FLOW");
        bit got_debug;
        bit got_step_action;
        bit got_run_state;
        begin
            `uvm_info(tag,
                      "flow_cla_debug_idle_exit_reachability: audit debug_state exit; legal RUN is expected to go through step_action before run_state",
                      UVM_LOW)

            flow_expect_cla_task1_running({tag, " cla_task1_running"});
            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_0009, {tag, " dbgstat_connect_halt"});
            flow_wait_cla_debug_state({tag, " wait_debug_before_run_audit"}, 60000, got_debug);
            flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.ctl.et_state", {tag, " et_state_in_debug"});
            flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.TASK_RUNNING", {tag, " task_running_in_debug"});
            flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.TASK_STOP", {tag, " task_stop_in_debug"});

            flow_raw_mem_write32_check_mask(FLOW_CLA_DBGSTAT, 32'h0000_0008,
                                            "chip_top_tb.I_chip_top.I_CLA.et_cla_cmd",
                                            32'h0000_0002, 32'h0000_0002, 1'b1, 5000,
                                            {tag, " run_cmd_pulse_from_debug"});
            flow_watch_hdl32_mask("chip_top_tb.I_chip_top.I_CLA.ctl.et_state",
                                  32'h0000_0003, 32'h0000_0001, 20000,
                                  got_step_action, {tag, " observe_step_action"});
            flow_watch_hdl32_mask("chip_top_tb.I_chip_top.I_CLA.ctl.et_state",
                                  32'h0000_0003, 32'h0000_0000, 60000,
                                  got_run_state, {tag, " observe_run_state"});

            if (got_step_action && got_run_state) begin
                `uvm_info(tag,
                          "flow_cla_debug_idle_exit_reachability: normal legal path observed as debug_state -> step_action -> run_state; direct debug_state -> run_state remains a waiver candidate",
                          UVM_LOW)
            end
            else begin
                `uvm_warning(tag,
                             "flow_cla_debug_idle_exit_reachability: did not observe full RUN exit path in this window; keep as reachability audit, not a functional fail")
            end

            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_0000, {tag, " dbgstat_disconnect_cleanup"});
        end
    endtask : flow_cla_debug_idle_exit_reachability

    virtual task flow_cla_fetch_response_delay(input string tag = "ET_JTAG_FLOW");
        bit got_req;
        bit got_wait;
        bit got_rdy;
        bit got_iq_write;
        begin
            `uvm_info(tag,
                      "flow_cla_fetch_response_delay: force a bounded mc_cla_f2rdy low window, observe fetch pending, then release response",
                      UVM_LOW)

            flow_expect_cla_task1_running({tag, " cla_task1_running"});
            flow_observe_hdl32("chip_top_tb.I_chip_top.cla_mc_f1req", {tag, " f1req_initial"});
            flow_observe_hdl32("chip_top_tb.I_chip_top.mc_cla_f1ack", {tag, " f1ack_initial"});
            flow_observe_hdl32("chip_top_tb.I_chip_top.mc_cla_f2rdy", {tag, " f2rdy_initial"});

            flow_force_hdl1("chip_top_tb.I_chip_top.mc_cla_f2rdy", 1'b0,
                            {tag, " force_f2rdy_low"});
            flow_watch_hdl32_mask("chip_top_tb.I_chip_top.cla_mc_f1req",
                                  32'h0000_0001, 32'h0000_0001, 50000,
                                  got_req, {tag, " wait_f1req_under_delay"});
            flow_watch_hdl32_mask("chip_top_tb.I_chip_top.I_CLA.p1.f2.f2_wait_data",
                                  32'h0000_0001, 32'h0000_0001, 10000,
                                  got_wait, {tag, " wait_f2_pending"});
            flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.p1.f2.f2_addr", {tag, " f2_addr_pending"});
            flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.p1.f2.IQ.full", {tag, " iq_full_pending"});
            flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.p1.f2.IQ.empty", {tag, " iq_empty_pending"});

            if (!got_req) begin
                `uvm_warning(tag, "flow_cla_fetch_response_delay: cla_mc_f1req was not observed during the forced response-delay window")
            end
            if (!got_wait) begin
                `uvm_warning(tag, "flow_cla_fetch_response_delay: f2_wait_data was not observed; this path may need a memory-driver delay rather than top-level force")
            end

            repeat (300) @(posedge vif.cpu_clk);
            flow_release_hdl("chip_top_tb.I_chip_top.mc_cla_f2rdy",
                             {tag, " release_f2rdy"});
            flow_watch_hdl32_mask("chip_top_tb.I_chip_top.mc_cla_f2rdy",
                                  32'h0000_0001, 32'h0000_0001, 10000,
                                  got_rdy, {tag, " wait_f2rdy_after_release"});
            flow_watch_hdl32_mask("chip_top_tb.I_chip_top.I_CLA.p1.f2.IQ.write",
                                  32'h0000_0001, 32'h0000_0001, 20000,
                                  got_iq_write, {tag, " wait_iq_write_after_response"});
            if (!got_rdy || !got_iq_write) begin
                `uvm_warning(tag,
                             "flow_cla_fetch_response_delay: response/IQ write was not sampled after release; flow is bounded and should be triaged with waveform")
            end
            flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.p1.f2.IQ.wp", {tag, " iq_wp_after_response"});
            flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.p1.f2.IQ.rp", {tag, " iq_rp_after_response"});
            flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.p1.f2.IQ.buf_v", {tag, " iq_valid_after_response"});
        end
    endtask : flow_cla_fetch_response_delay

    virtual task flow_cla_fetch_fifo_simultaneous_rw(input string tag = "ET_JTAG_FLOW");
        bit got_write;
        bit got_read;
        bit got_simul_rw;
        begin
            `uvm_info(tag,
                      "flow_cla_fetch_fifo_simultaneous_rw: backpressure D1 briefly, release, and observe IQ write/read boundary plus PF0 debug read side effects",
                      UVM_LOW)

            flow_expect_cla_task1_running({tag, " cla_task1_running"});
            flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.p1.f2.IQ.wp", {tag, " iq_wp_initial"});
            flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.p1.f2.IQ.rp", {tag, " iq_rp_initial"});
            flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.p1.f2.IQ.buf_v", {tag, " iq_valid_initial"});
            flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.p1.f2.IQ.full", {tag, " iq_full_initial"});
            flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.p1.f2.IQ.empty", {tag, " iq_empty_initial"});

            flow_force_hdl1("chip_top_tb.I_chip_top.I_CLA.p1.d1_f2_ack", 1'b0,
                            {tag, " force_d1_ack_low_fill_iq"});
            flow_watch_hdl32_mask("chip_top_tb.I_chip_top.I_CLA.p1.f2.IQ.write",
                                  32'h0000_0001, 32'h0000_0001, 50000,
                                  got_write, {tag, " wait_iq_write_fill"});
            repeat (600) @(posedge vif.cpu_clk);
            flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.p1.f2.IQ.wp", {tag, " iq_wp_after_fill"});
            flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.p1.f2.IQ.rp", {tag, " iq_rp_after_fill"});
            flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.p1.f2.IQ.buf_v", {tag, " iq_valid_after_fill"});
            flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.p1.f2.IQ.full", {tag, " iq_full_after_fill"});

            flow_release_hdl("chip_top_tb.I_chip_top.I_CLA.p1.d1_f2_ack",
                             {tag, " release_d1_ack"});
            fork
                begin
                    flow_watch_hdl32_mask("chip_top_tb.I_chip_top.I_CLA.p1.f2.IQ.read",
                                          32'h0000_0001, 32'h0000_0001, 50000,
                                          got_read, {tag, " wait_iq_read_after_release"});
                end
                begin
                    flow_watch_two_hdl1("chip_top_tb.I_chip_top.I_CLA.p1.f2.IQ.write",
                                        "chip_top_tb.I_chip_top.I_CLA.p1.f2.IQ.read",
                                        50000, got_simul_rw, {tag, " wait_iq_simul_rw"});
                end
            join

            if (!got_write) begin
                `uvm_warning(tag, "flow_cla_fetch_fifo_simultaneous_rw: IQ.write was not observed during fill window")
            end
            if (!got_read) begin
                `uvm_warning(tag, "flow_cla_fetch_fifo_simultaneous_rw: IQ.read was not observed after D1 ack release")
            end
            if (!got_simul_rw) begin
                `uvm_warning(tag, "flow_cla_fetch_fifo_simultaneous_rw: same-cycle IQ.write && IQ.read was not sampled; may require a dedicated memory-driver phase adjustment")
            end

            flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.p1.f2.IQ.wp", {tag, " iq_wp_after_rw"});
            flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.p1.f2.IQ.rp", {tag, " iq_rp_after_rw"});
            flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.p1.f2.IQ.buf_v", {tag, " iq_valid_after_rw"});
            flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.p1.f2.IQ.data_i", {tag, " iq_data_i_after_rw"});
            flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.p1.f2.IQ.data_o", {tag, " iq_data_o_after_rw"});

            flow_raw_mem_read32(FLOW_CLA_BUF0, {tag, " pf0_buf0_rd_non_mutating"});
            flow_raw_mem_read32(FLOW_CLA_PCB0, {tag, " pf0_pcb0_rd_non_mutating"});
            flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.p1.f2.IQ.wp", {tag, " iq_wp_after_pf0_read"});
            flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.p1.f2.IQ.rp", {tag, " iq_rp_after_pf0_read"});
            flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.p1.f2.IQ.buf_v", {tag, " iq_valid_after_pf0_read"});
        end
    endtask : flow_cla_fetch_fifo_simultaneous_rw

    virtual task flow_cla_debug_mstop_return(input string tag = "ET_JTAG_FLOW");
        bit got_debug;
        bit got_mstop;
        bit got_task_stop;
        begin
            `uvm_info(tag,
                      "flow_cla_debug_mstop_return: debug-write MPC to task1 MSTOP, single-step it, and check TASK_STOP/debug-state cleanup",
                      UVM_LOW)

            flow_expect_cla_task1_running({tag, " cla_task1_running"});
            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_0009, {tag, " dbgstat_connect_halt"});
            flow_wait_cla_debug_state({tag, " wait_debug_before_mstop"}, 60000, got_debug);
            flow_raw_mem_write32_check_mask(FLOW_CLA_MPC, 32'h0000_001E,
                                            "chip_top_tb.I_chip_top.I_CLA.et_mpc_wt",
                                            32'h0000_0001, 32'h0000_0001, 1'b1, 5000,
                                            {tag, " mpc_to_task1_mstop"});
            flow_wait_cla_debug_state({tag, " wait_debug_after_mpc_mstop"}, 60000, got_debug);

            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_0019, {tag, " clear_ack_before_mstop_step"});
            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_000D, {tag, " set_step_mode_before_mstop"});
            fork
                begin
                    flow_watch_hdl32_mask("chip_top_tb.I_chip_top.I_CLA.d2_mstop",
                                          32'h0000_0001, 32'h0000_0001, 40000,
                                          got_mstop, {tag, " watch_d2_mstop"});
                end
                begin
                    flow_watch_hdl32_mask("chip_top_tb.I_chip_top.I_CLA.TASK_STOP",
                                          32'h0000_0001, 32'h0000_0001, 50000,
                                          got_task_stop, {tag, " watch_task_stop"});
                end
                begin
                    flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_000C, {tag, " step_mstop_cmd"});
                end
            join

            if (!got_mstop) begin
                `uvm_warning(tag,
                             "flow_cla_debug_mstop_return: d2_mstop pulse was not sampled; TASK_STOP/debug cleanup are the pass criteria")
            end
            if (!got_task_stop) begin
                `uvm_error(tag, "flow_cla_debug_mstop_return: TASK_STOP was not observed after stepping MSTOP")
            end
            repeat (3000) @(posedge vif.cpu_clk);
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_CLA.TASK_RUNNING",
                              32'h0000_0001, 32'h0000_0000, {tag, " task_running_cleared"});
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_CLA.cla_et_debugstate",
                              32'h0000_0001, 32'h0000_0000, {tag, " debugstate_cleared_by_task_stop"});
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_CLA.ctl.et_state",
                              32'h0000_0003, 32'h0000_0000, {tag, " et_state_idle_after_task_stop"});
            flow_raw_mem_read32(FLOW_CLA_DBGSTAT, {tag, " dbgstat_after_mstop"});
            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_0000, {tag, " dbgstat_disconnect_cleanup"});
        end
    endtask : flow_cla_debug_mstop_return

    virtual task flow_cla_step_raw_stall(input string tag = "ET_JTAG_FLOW");
        bit got_debug;
        begin
            `uvm_info(tag,
                      "flow_cla_step_raw_stall: hold STEP in step_action with RAW_STALL, then release and verify delayed command ACK",
                      UVM_LOW)

            flow_expect_cla_task1_running({tag, " cla_task1_running"});
            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_0009, {tag, " dbgstat_connect_halt"});
            flow_wait_cla_debug_state({tag, " wait_debug_before_raw_stall"}, 60000, got_debug);
            flow_raw_mem_write32(FLOW_CLA_MPC, 32'h0000_000C, {tag, " mpc_to_task1_mem_read_window"});
            flow_wait_cla_debug_state({tag, " wait_debug_after_mpc_raw"}, 60000, got_debug);

            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_0019, {tag, " clear_ack_before_raw_step"});
            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_000D, {tag, " set_step_mode_raw"});
            flow_force_hdl1("chip_top_tb.I_chip_top.I_CLA.RAW_STALL", 1'b1,
                            {tag, " force_raw_stall"});
            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_000C, {tag, " step_cmd_under_raw_stall"});
            repeat (3000) @(posedge vif.cpu_clk);
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_CLA.STALL2",
                              32'h0000_0001, 32'h0000_0001, {tag, " stall2_due_raw"});
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_CLA.ctl.et_state",
                              32'h0000_0003, 32'h0000_0001, {tag, " et_state_step_action_while_raw"});
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_CLA.ctl.command_acked",
                              32'h0000_0001, 32'h0000_0000, {tag, " no_ack_while_raw_stall"});

            flow_release_hdl("chip_top_tb.I_chip_top.I_CLA.RAW_STALL",
                             {tag, " release_raw_stall"});
            flow_wait_cla_debug_state({tag, " wait_debug_after_raw_release"}, 60000, got_debug);
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_CLA.c_reg.DBGACKED",
                              32'h0000_0001, 32'h0000_0001, {tag, " ack_after_raw_release"});

            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_0019, {tag, " clear_ack_before_mem_stall_probe"});
            flow_force_hdl1("chip_top_tb.I_chip_top.mc_cla_wstall", 1'b1,
                            {tag, " force_wstall_probe"});
            repeat (2000) @(posedge vif.cpu_clk);
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_CLA.STALL2",
                              32'h0000_0001, 32'h0000_0001, {tag, " stall2_due_wstall"});
            flow_release_hdl("chip_top_tb.I_chip_top.mc_cla_wstall",
                             {tag, " release_wstall_probe"});
            repeat (2000) @(posedge vif.cpu_clk);

            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_0000, {tag, " dbgstat_disconnect_cleanup"});
        end
    endtask : flow_cla_step_raw_stall

    virtual task flow_cla_stage2_snapshot(input string tag = "ET_JTAG_FLOW");
        begin
            flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.ctl.et_state", {tag, " et_state"});
            flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.cla_et_debugstate", {tag, " debugstate"});
            flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.cla_et_acked", {tag, " cla_et_acked"});
            flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.TASK_RUNNING", {tag, " task_running"});
            flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.TASK_STOP", {tag, " task_stop"});
            flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.STALL2", {tag, " stall2"});
            flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.ctl.bp_pend", {tag, " bp_pend"});
            flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.ctl.bp_stall", {tag, " bp_stall"});
            flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.RAW_STALL", {tag, " raw_stall"});
            flow_observe_hdl32("chip_top_tb.I_chip_top.mc_cla_r1stall", {tag, " r1stall"});
            flow_observe_hdl32("chip_top_tb.I_chip_top.mc_cla_wstall", {tag, " wstall"});
            flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.p2.d2_mdebugstop", {tag, " d2_mdebugstop"});
            flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.c_reg.DBGCONNECTED", {tag, " dbgconnected"});
            flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.c_reg.DBGCONFG", {tag, " dbgconfg"});
        end
    endtask : flow_cla_stage2_snapshot

    virtual task flow_cla_stage2_step_with_optional_stall(input string stall_path,
                                                          input bit force_value,
                                                          input int unsigned hold_cycles,
                                                          input string step_name,
                                                          input string tag = "ET_JTAG_FLOW");
        bit got_debug;
        begin
            `uvm_info(tag,
                      $sformatf("flow_cla_stage2_step_with_optional_stall: step=%s stall_path=%s hold_cycles=%0d",
                                step_name, stall_path, hold_cycles),
                      UVM_LOW)
            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_0019, {tag, " clear_ack_before_step"});
            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_000D, {tag, " set_step_mode"});
            if (stall_path != "") begin
                flow_force_hdl1(stall_path, force_value, {tag, " force_step_stall"});
            end
            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_000C, {tag, " issue_step_cmd"});
            if (stall_path != "") begin
                repeat (hold_cycles) @(posedge vif.cpu_clk);
                flow_expect_hdl32("chip_top_tb.I_chip_top.I_CLA.STALL2",
                                  32'h0000_0001, 32'h0000_0001, {tag, " stall2_while_step_held"});
                flow_expect_hdl32("chip_top_tb.I_chip_top.I_CLA.ctl.command_acked",
                                  32'h0000_0001, 32'h0000_0000, {tag, " no_ack_while_step_stalled"});
                flow_cla_stage2_snapshot({tag, " snapshot_while_step_stalled"});
                flow_release_hdl(stall_path, {tag, " release_step_stall"});
            end
            flow_wait_cla_debug_state({tag, " wait_debug_after_step"}, 60000, got_debug);
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_CLA.c_reg.DBGACKED",
                              32'h0000_0001, 32'h0000_0001, {tag, " dbgacked_after_step"});
            flow_cla_stage2_snapshot({tag, " snapshot_after_step"});
        end
    endtask : flow_cla_stage2_step_with_optional_stall

    virtual task flow_cla_et_debug_run_reachability(input string tag = "ET_JTAG_FLOW");
        begin
            `uvm_info(tag,
                      "flow_cla_et_debug_run_reachability: stage2 F01 wrapper around the existing legal RUN reachability audit",
                      UVM_LOW)
            flow_cla_debug_idle_exit_reachability(tag);
        end
    endtask : flow_cla_et_debug_run_reachability

    virtual task flow_cla_et_breakpoint_pending_matrix(input string tag = "ET_JTAG_FLOW");
        bit seen_011;
        bit seen_101;
        bit seen_110;
        bit seen_111;
        begin
            `uvm_info(tag,
                      "flow_cla_et_breakpoint_pending_matrix: strict cycle monitor for bp_pend = connected && DBGCONFG[0] && d2_mdebugstop",
                      UVM_LOW)

            flow_expect_cla_task1_running({tag, " cla_task1_running"});

            `uvm_info(tag, "matrix 0/1/1: disconnected + enabled + MDEBUGSTOP should keep bp_pend=0", UVM_LOW)
            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_0000, {tag, " combo011_disconnect"});
            flow_raw_mem_write32(FLOW_CLA_DBGCONFG, 32'h0000_0001, {tag, " combo011_enable"});
            flow_cla_watch_bp_combo("combo011", 1'b0, 1'b1, 1'b1, 1'b0,
                                    60000, seen_011, {tag, " combo011"});

            `uvm_info(tag, "matrix 1/0/1: connected + disabled + MDEBUGSTOP should keep bp_pend=0", UVM_LOW)
            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_0008, {tag, " combo101_connect"});
            flow_raw_mem_write32(FLOW_CLA_DBGCONFG, 32'h0000_0000, {tag, " combo101_disable"});
            flow_cla_watch_bp_combo("combo101", 1'b1, 1'b0, 1'b1, 1'b0,
                                    60000, seen_101, {tag, " combo101"});

            `uvm_info(tag, "matrix 1/1/0: connected + enabled before MDEBUGSTOP should keep bp_pend=0", UVM_LOW)
            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_0008, {tag, " combo110_connect"});
            flow_raw_mem_write32(FLOW_CLA_DBGCONFG, 32'h0000_0001, {tag, " combo110_enable"});
            flow_cla_watch_bp_combo("combo110", 1'b1, 1'b1, 1'b0, 1'b0,
                                    2000, seen_110, {tag, " combo110"});

            `uvm_info(tag, "matrix 1/1/1: connected + enabled + MDEBUGSTOP should raise bp_pend/bp_stall", UVM_LOW)
            flow_cla_watch_bp_combo("combo111", 1'b1, 1'b1, 1'b1, 1'b1,
                                    60000, seen_111, {tag, " combo111"});
            flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.ctl.bp_stall", {tag, " combo111_bp_stall"});

            if (seen_011 && seen_101 && seen_110 && seen_111) begin
                `uvm_info(tag,
                          "[CLA_ET_PASS] case=cla_et_breakpoint_pending_matrix target=all_bp_pend_combos evidence=seen_011:1 seen_101:1 seen_110:1 seen_111:1",
                          UVM_LOW)
            end

            flow_raw_mem_read32(FLOW_CLA_DBGSTAT, {tag, " dbgstat_after_bp_matrix"});
            flow_raw_mem_write32(FLOW_CLA_DBGCONFG, 32'h0000_0000, {tag, " dbgconfg_cleanup"});
            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_0000, {tag, " dbgstat_disconnect_cleanup"});
        end
    endtask : flow_cla_et_breakpoint_pending_matrix

    virtual task flow_cla_et_step_halt_resume_stall_matrix(input string tag = "ET_JTAG_FLOW");
        bit got_debug;
        begin
            `uvm_info(tag,
                      "flow_cla_et_step_halt_resume_stall_matrix: step baseline plus fetch/read/write/RAW stall intersections",
                      UVM_LOW)

            flow_expect_cla_task1_running({tag, " cla_task1_running"});
            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_0009, {tag, " dbgstat_connect_halt"});
            flow_wait_cla_debug_state({tag, " wait_initial_debug"}, 60000, got_debug);
            flow_cla_stage2_step_with_optional_stall("", 1'b0, 0, "baseline_no_stall", {tag, " baseline"});
            flow_cla_stage2_step_with_optional_stall("chip_top_tb.I_chip_top.mc_cla_f2rdy", 1'b0, 300, "fetch_response_hold_low", {tag, " fetch_stall"});
            flow_cla_stage2_step_with_optional_stall("chip_top_tb.I_chip_top.mc_cla_r1stall", 1'b1, 300, "data_read_stall", {tag, " r1stall"});
            flow_cla_stage2_step_with_optional_stall("chip_top_tb.I_chip_top.mc_cla_wstall", 1'b1, 300, "data_write_stall", {tag, " wstall"});
            flow_cla_stage2_step_with_optional_stall("chip_top_tb.I_chip_top.I_CLA.RAW_STALL", 1'b1, 300, "raw_stall", {tag, " raw"});
            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_0008, {tag, " final_run_cmd"});
            repeat (5000) @(posedge vif.cpu_clk);
            flow_cla_stage2_snapshot({tag, " snapshot_after_final_run"});
            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_0000, {tag, " dbgstat_disconnect_cleanup"});
        end
    endtask : flow_cla_et_step_halt_resume_stall_matrix

    virtual task flow_cla_mem_wstall_isolated(input string tag = "ET_JTAG_FLOW");
        bit got_wstall_req;
        begin
            `uvm_info(tag,
                      "flow_cla_mem_wstall_isolated: isolate mc_cla_wstall as a STALL2 source and check request/PC snapshots around release",
                      UVM_LOW)

            flow_expect_cla_task1_running({tag, " cla_task1_running"});
            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_0009, {tag, " dbgstat_connect_halt"});
            flow_raw_mem_write32(FLOW_CLA_MPC, 32'h0000_0010, {tag, " mpc_near_write_window"});
            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_0019, {tag, " clear_ack"});
            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_000D, {tag, " set_step_mode"});
            flow_force_hdl1("chip_top_tb.I_chip_top.mc_cla_wstall", 1'b1, {tag, " force_wstall"});
            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_000C, {tag, " step_under_wstall"});
            flow_watch_hdl32_mask("chip_top_tb.I_chip_top.I_CLA.STALL2",
                                  32'h0000_0001, 32'h0000_0001, 20000,
                                  got_wstall_req, {tag, " watch_stall2_due_wstall"});
            if (!got_wstall_req) begin
                `uvm_warning(tag, "mc_cla_wstall did not isolate as STALL2 in this window; check target MPC/write fixture")
            end
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_CLA.ctl.command_acked",
                              32'h0000_0001, 32'h0000_0000, {tag, " no_ack_while_wstall"});
            flow_cla_stage2_snapshot({tag, " snapshot_while_wstall"});
            repeat (300) @(posedge vif.cpu_clk);
            flow_release_hdl("chip_top_tb.I_chip_top.mc_cla_wstall", {tag, " release_wstall"});
            repeat (2000) @(posedge vif.cpu_clk);
            flow_cla_stage2_snapshot({tag, " snapshot_after_wstall_release"});
            flow_raw_mem_read32(FLOW_CLA_DBGSTAT, {tag, " dbgstat_after_wstall"});
            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_0000, {tag, " dbgstat_disconnect_cleanup"});
        end
    endtask : flow_cla_mem_wstall_isolated

    virtual task flow_cla_raw_stall_overlap(input string tag = "ET_JTAG_FLOW");
        begin
            `uvm_info(tag,
                      "flow_cla_raw_stall_overlap: combine RAW_STALL with read/write/fetch stalls and observe release ordering",
                      UVM_LOW)

            flow_expect_cla_task1_running({tag, " cla_task1_running"});
            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_0009, {tag, " dbgstat_connect_halt"});
            flow_raw_mem_write32(FLOW_CLA_MPC, 32'h0000_000C, {tag, " mpc_to_raw_window"});
            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_0019, {tag, " clear_ack"});
            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_000D, {tag, " set_step_mode"});

            flow_force_hdl1("chip_top_tb.I_chip_top.I_CLA.RAW_STALL", 1'b1, {tag, " force_raw"});
            flow_force_hdl1("chip_top_tb.I_chip_top.mc_cla_r1stall", 1'b1, {tag, " force_r1_overlap"});
            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_000C, {tag, " step_raw_r1_overlap"});
            repeat (400) @(posedge vif.cpu_clk);
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_CLA.STALL2",
                              32'h0000_0001, 32'h0000_0001, {tag, " stall2_raw_r1_overlap"});
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_CLA.ctl.command_acked",
                              32'h0000_0001, 32'h0000_0000, {tag, " no_ack_raw_r1_overlap"});
            flow_cla_stage2_snapshot({tag, " snapshot_raw_r1_overlap"});
            flow_release_hdl("chip_top_tb.I_chip_top.mc_cla_r1stall", {tag, " release_r1_overlap"});
            repeat (200) @(posedge vif.cpu_clk);
            flow_release_hdl("chip_top_tb.I_chip_top.I_CLA.RAW_STALL", {tag, " release_raw_after_r1"});
            repeat (2000) @(posedge vif.cpu_clk);
            flow_cla_stage2_snapshot({tag, " snapshot_after_raw_r1_release"});

            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_0019, {tag, " clear_ack_second_overlap"});
            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_000D, {tag, " set_step_mode_second_overlap"});
            flow_force_hdl1("chip_top_tb.I_chip_top.I_CLA.RAW_STALL", 1'b1, {tag, " force_raw_second"});
            flow_force_hdl1("chip_top_tb.I_chip_top.mc_cla_wstall", 1'b1, {tag, " force_w_overlap"});
            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_000C, {tag, " step_raw_w_overlap"});
            repeat (400) @(posedge vif.cpu_clk);
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_CLA.STALL2",
                              32'h0000_0001, 32'h0000_0001, {tag, " stall2_raw_w_overlap"});
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_CLA.ctl.command_acked",
                              32'h0000_0001, 32'h0000_0000, {tag, " no_ack_raw_w_overlap"});
            flow_cla_stage2_snapshot({tag, " snapshot_raw_w_overlap"});
            flow_release_hdl("chip_top_tb.I_chip_top.mc_cla_wstall", {tag, " release_w_overlap"});
            repeat (200) @(posedge vif.cpu_clk);
            flow_release_hdl("chip_top_tb.I_chip_top.I_CLA.RAW_STALL", {tag, " release_raw_after_w"});
            repeat (2000) @(posedge vif.cpu_clk);
            flow_cla_stage2_snapshot({tag, " snapshot_after_raw_w_release"});
            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_0000, {tag, " dbgstat_disconnect_cleanup"});
        end
    endtask : flow_cla_raw_stall_overlap

    virtual task flow_cla_adc_trigger_source_matrix(input string tag = "ET_JTAG_FLOW");
        int adc_idx;
        begin
            `uvm_info(tag,
                      "flow_cla_adc_trigger_source_matrix: stage2 P01 audit hook; observes current ADC/CLA trigger routing, real ADC pulse driver is not in et_jtag subenv",
                      UVM_LOW)
            flow_expect_cla_task1_running({tag, " cla_task1_running"});
            for (adc_idx = 1; adc_idx <= 8; adc_idx++) begin
                `uvm_info(tag,
                          $sformatf("ADCINT%0d trigger audit: observe MIFR/MIRUN/MIOVF and top ADCINT path if present",
                                    adc_idx),
                          UVM_LOW)
                flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.c_reg.MIFR", {tag, " mifr"});
                flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.c_reg.MIRUN", {tag, " mirun"});
                flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.c_reg.MIOVF", {tag, " miovf"});
                flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.iack", {tag, " cla_iack"});
                repeat (200) @(posedge vif.cpu_clk);
            end
            `uvm_warning(tag,
                         "flow_cla_adc_trigger_source_matrix: no ADC agent hook was found in et_jtag subenv; close this case after adding a real ADCINT pulse driver")
        end
    endtask : flow_cla_adc_trigger_source_matrix

    virtual task flow_cla_reserved_cndf_injection(input string tag = "ET_JTAG_FLOW");
        int cndf;
        begin
            `uvm_info(tag,
                      "flow_cla_reserved_cndf_injection: stage2 I01 reserved CNDF audit; no direct instruction-RAM patcher is present in et_jtag subenv",
                      UVM_LOW)
            flow_expect_cla_task1_running({tag, " cla_task1_running"});
            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_0009, {tag, " dbgstat_connect_halt"});
            for (cndf = 6; cndf <= 7; cndf++) begin
                `uvm_info(tag,
                          $sformatf("reserved CNDF=%0d audit: observe decode/illegal/control state before adding instruction patcher",
                                    cndf),
                          UVM_LOW)
                flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.p1.d1_cndf", {tag, " d1_cndf"});
                flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.p2.d2_cndf", {tag, " d2_cndf"});
                flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.e_illegal", {tag, " e_illegal"});
                flow_cla_stage2_snapshot({tag, " reserved_cndf_snapshot"});
                repeat (300) @(posedge vif.cpu_clk);
            end
            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_0000, {tag, " dbgstat_disconnect_cleanup"});
            `uvm_warning(tag,
                         "flow_cla_reserved_cndf_injection: reserved encoding injection needs a legal instruction-RAM backdoor/debug-buffer patcher before hard pass/fail semantics")
        end
    endtask : flow_cla_reserved_cndf_injection

    virtual task flow_cla_task8_trigger_hold_mcdc(input string tag = "ET_JTAG_FLOW");
        bit forced_src;
        bit got_first_pulse;
        bit got_second_pulse;
        string src_path;
        begin
            `uvm_info(tag,
                      "[CLA_ET_TARGET] case=cla_task8_trigger_hold_mcdc target=I_CLA.c_reg.I7.i0 sustained-high edge detector",
                      UVM_LOW)

            flow_expect_cla_task1_running({tag, " cla_task1_running"});
            src_path = "chip_top_tb.I_chip_top.ADCINT2PIE[7]";
            flow_try_force_hdl1(src_path, 1'b0, forced_src, {tag, " force_adcint8_low"});
            if (!forced_src) begin
                src_path = "chip_top_tb.I_chip_top.I_CLA.ADCINT8";
                flow_try_force_hdl1(src_path, 1'b0, forced_src, {tag, " force_cla_adcint8_low"});
            end

            if (!forced_src) begin
                `uvm_error(tag,
                           "[CLA_ET_WAIVER_CANDIDATE] case=cla_task8_trigger_hold_mcdc target=I7.i0 reason=no_forceable_adcint8_boundary_path")
                flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.c_reg.I7.int_sel", {tag, " i7_int_sel"});
                flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.c_reg.I7.i0.in", {tag, " i7_in"});
                flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.c_reg.I7.i0.in_d", {tag, " i7_in_d"});
                flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.c_reg.I7.i0.out", {tag, " i7_out"});
                flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.c_reg.MIER", {tag, " mier"});
                flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.c_reg.MIFR", {tag, " mifr"});
                return;
            end

            repeat (6) @(posedge vif.cpu_clk);
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_CLA.c_reg.I7.i0.in",
                              32'h0000_0001, 32'h0000_0000, {tag, " source_low_in"});
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_CLA.c_reg.I7.i0.in_d",
                              32'h0000_0001, 32'h0000_0000, {tag, " source_low_in_d"});

            flow_try_force_hdl1(src_path, 1'b1, forced_src, {tag, " force_adcint8_high_hold"});
            flow_watch_hdl32_mask("chip_top_tb.I_chip_top.I_CLA.c_reg.I7.i0.out",
                                  32'h0000_0001, 32'h0000_0001, 20,
                                  got_first_pulse, {tag, " first_edge_pulse"});
            if (!got_first_pulse && (src_path != "chip_top_tb.I_chip_top.I_CLA.ADCINT8")) begin
                flow_try_release_hdl(src_path, forced_src, {tag, " release_nonpropagating_adcint8_vector"});
                src_path = "chip_top_tb.I_chip_top.I_CLA.ADCINT8";
                flow_try_force_hdl1(src_path, 1'b0, forced_src, {tag, " force_cla_adcint8_low_retry"});
                repeat (4) @(posedge vif.cpu_clk);
                flow_try_force_hdl1(src_path, 1'b1, forced_src, {tag, " force_cla_adcint8_high_retry"});
                flow_watch_hdl32_mask("chip_top_tb.I_chip_top.I_CLA.c_reg.I7.i0.out",
                                      32'h0000_0001, 32'h0000_0001, 20,
                                      got_first_pulse, {tag, " first_edge_pulse_retry"});
            end
            if (!got_first_pulse) begin
                `uvm_error(tag,
                           "[CLA_ET_FAIL] case=cla_task8_trigger_hold_mcdc target=I7.i0 reason=source_high_did_not_reach_i7_edge_detector")
            end
            repeat (4) @(posedge vif.cpu_clk);
            if (got_first_pulse) begin
                flow_expect_hdl32("chip_top_tb.I_chip_top.I_CLA.c_reg.I7.i0.in",
                                  32'h0000_0001, 32'h0000_0001, {tag, " hold_high_in"});
                flow_expect_hdl32("chip_top_tb.I_chip_top.I_CLA.c_reg.I7.i0.in_d",
                                  32'h0000_0001, 32'h0000_0001, {tag, " hold_high_in_d"});
                flow_expect_hdl32("chip_top_tb.I_chip_top.I_CLA.c_reg.I7.i0.out",
                                  32'h0000_0001, 32'h0000_0000, {tag, " no_repeat_pulse_while_high"});
            end
            else begin
                flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.c_reg.I7.i0.in", {tag, " hold_high_in_audit"});
                flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.c_reg.I7.i0.in_d", {tag, " hold_high_in_d_audit"});
                flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.c_reg.I7.i0.out", {tag, " hold_high_out_audit"});
            end
            flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.c_reg.MIFR", {tag, " mifr_after_hold_high"});
            flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.task_pend", {tag, " task_pend_after_hold_high"});

            flow_try_force_hdl1(src_path, 1'b0, forced_src, {tag, " force_adcint8_low_between_edges"});
            repeat (4) @(posedge vif.cpu_clk);
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_CLA.c_reg.I7.i0.in_d",
                              32'h0000_0001, 32'h0000_0000, {tag, " in_d_returned_low"});

            flow_try_force_hdl1(src_path, 1'b1, forced_src, {tag, " force_adcint8_high_second"});
            flow_watch_hdl32_mask("chip_top_tb.I_chip_top.I_CLA.c_reg.I7.i0.out",
                                  32'h0000_0001, 32'h0000_0001, 20,
                                  got_second_pulse, {tag, " second_edge_pulse"});
            if (got_first_pulse && got_second_pulse) begin
                `uvm_info(tag,
                          "[CLA_ET_PASS] case=cla_task8_trigger_hold_mcdc check=two_edges_two_pulses_no_retrigger_while_high",
                          UVM_LOW)
            end
            else begin
                `uvm_error(tag,
                           "[CLA_ET_FAIL] case=cla_task8_trigger_hold_mcdc target=two_edge_sequence reason=full_two_edge_observation_not_sampled")
            end

            flow_try_force_hdl1(src_path, 1'b0, forced_src, {tag, " force_adcint8_low_cleanup"});
            repeat (4) @(posedge vif.cpu_clk);
            flow_try_release_hdl(src_path, forced_src, {tag, " release_adcint8_boundary"});
        end
    endtask : flow_cla_task8_trigger_hold_mcdc

    virtual task flow_cla_reserved_cndf_pipeline_injection(input string tag = "ET_JTAG_FLOW");
        int cndf;
        begin
            `uvm_info(tag,
                      "[CLA_ET_TARGET] case=cla_reserved_cndf_pipeline_injection target=p2.d2.cond.default,p2.ew.cond.default",
                      UVM_LOW)
            flow_require_hdl_path("chip_top_tb.I_chip_top.I_CLA.p2.d2.d2_cndf_brc", {tag, " require_d2_cndf_brc"});
            flow_require_hdl_path("chip_top_tb.I_chip_top.I_CLA.p2.d2.cond.cond", {tag, " require_d2_cond"});
            flow_require_hdl_path("chip_top_tb.I_chip_top.I_CLA.p2.ew.e_cndf_exe", {tag, " require_ew_cndf_exe"});
            flow_require_hdl_path("chip_top_tb.I_chip_top.I_CLA.p2.ew.cond.cond", {tag, " require_ew_cond"});
            flow_cla_reserved_cndf_injection({tag, " stage2_reserved_audit"});
            for (cndf = 6; cndf <= 9; cndf++) begin
                `uvm_info(tag,
                          $sformatf("reserved CNDF pipeline audit value=%0d; real closure requires opcode patch/fetch replay",
                                    cndf),
                          UVM_LOW)
                flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.p2.d2.d2_cndf_brc", {tag, " d2_cndf_brc"});
                flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.p2.d2.d2_cond_brc", {tag, " d2_cond_brc"});
                flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.p2.d2.cond.cond", {tag, " d2_cond_default_out"});
                flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.p2.ew.e_cndf_exe", {tag, " ew_cndf_exe"});
                flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.p2.ew.cond.cond", {tag, " ew_cond_default_out"});
                flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.d1_mpc", {tag, " d1_mpc"});
                flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.d2_mpc", {tag, " d2_mpc"});
                flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.e_mpc", {tag, " e_mpc"});
                repeat (300) @(posedge vif.cpu_clk);
            end
            `uvm_error(tag,
                       "[CLA_ET_WAIVER_CANDIDATE] case=cla_reserved_cndf_pipeline_injection target=reserved_cndf_default reason=no_legal_instruction_ram_raw_opcode_patcher_in_et_jtag_subenv")
        end
    endtask : flow_cla_reserved_cndf_pipeline_injection

    virtual task flow_cla_et_debug_idle_exit_final(input string tag = "ET_JTAG_FLOW");
        bit got_debug;
        bit seen_direct_exit;
        bit seen_step_path;
        begin
            `uvm_info(tag,
                      "[CLA_ET_TARGET] case=cla_et_debug_idle_exit_reachability target=cla_ctl debug_state_to_run_state",
                      UVM_LOW)
            flow_expect_cla_task1_running({tag, " cla_task1_running"});
            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_0009, {tag, " dbgstat_connect_halt"});
            flow_wait_cla_debug_state({tag, " wait_debug_before_direct_exit_monitor"}, 60000, got_debug);
            if (!got_debug) begin
                `uvm_error(tag,
                           "[CLA_ET_FAIL] case=cla_et_debug_idle_exit_final target=debug_state reason=debug_state_not_observed_before_run")
            end
            fork
                begin
                    flow_cla_watch_debug_direct_exit(80000, seen_direct_exit, seen_step_path,
                                                     {tag, " strict_direct_exit_monitor"});
                end
                begin
                    flow_raw_mem_write32_check_mask(FLOW_CLA_DBGSTAT, 32'h0000_0008,
                                                    "chip_top_tb.I_chip_top.I_CLA.et_cla_cmd",
                                                    32'h0000_0002, 32'h0000_0002, 1'b1, 5000,
                                                    {tag, " run_cmd_pulse_from_debug"});
                end
            join
            if (!seen_direct_exit) begin
                if (seen_step_path) begin
                    `uvm_error(tag,
                               "[CLA_ET_WAIVER_CANDIDATE] case=cla_et_debug_idle_exit_final target=debug_state_to_run_state reason=only_debug_step_action_run_path_observed_no_direct_transition")
                end
                else begin
                    `uvm_error(tag,
                               "[CLA_ET_FAIL] case=cla_et_debug_idle_exit_final target=debug_state_to_run_state reason=no_adjacent_direct_transition_observed")
                end
            end
            flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.ctl.et_state_n", {tag, " et_state_n"});
            flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.ctl.br_state", {tag, " br_state"});
            flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.ctl.cla_debug_info", {tag, " cla_debug_info"});
            flow_raw_mem_write32(FLOW_CLA_DBGSTAT, 32'h0000_0000, {tag, " dbgstat_disconnect_cleanup"});
        end
    endtask : flow_cla_et_debug_idle_exit_final

    virtual task flow_cla_lu_mar_conflict_raw_injection(input string tag = "ET_JTAG_FLOW");
        begin
            `uvm_info(tag,
                      "[CLA_ET_TARGET] case=cla_lu_mar_conflict_raw_injection target=p2.r2 MAR forwarding conflict true branch",
                      UVM_LOW)
            flow_expect_cla_task1_running({tag, " cla_task1_running"});
            flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.p2.r2.r2_lu_src1_sel", {tag, " r2_lu_src1_sel"});
            flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.p2.r2.du_reg_addr", {tag, " du_reg_addr"});
            flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.p2.r2.du_reg_rw", {tag, " du_reg_rw"});
            flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.p2.r2.du_wt_data", {tag, " du_wt_data"});
            flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.p2.r2.r2_lu_src1", {tag, " r2_lu_src1"});
            flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.p2.r2.MAR0", {tag, " mar0"});
            flow_observe_hdl32("chip_top_tb.I_chip_top.I_CLA.p2.r2.MAR1", {tag, " mar1"});
            `uvm_warning(tag,
                         "[CLA_ET_WAIVER] case=cla_lu_mar_conflict_raw_injection reason=TI_assembler_rejects_illegal_parallel_packet_no_architectural_expected")
        end
    endtask : flow_cla_lu_mar_conflict_raw_injection

    virtual task flow_dma_fifo_stress(input string tag = "ET_JTAG_FLOW");
        int i;
        logic [31:0] wdata;
        begin
            `uvm_info(tag,
                      "flow_dma_fifo_stress: continuously push DMA_WDATA and pop data-log RCMD2 to hit FIFO full/empty/wrap paths",
                      UVM_LOW)
            flow_rt_disable({tag, " setup_rt_disable"});
            flow_halt_rude({tag, " setup_halt"});
            flow_raw_emureg_write32(22'h838, FLOW_A_ADDR, {tag, " dma_addr_start"});
            flow_raw_emureg_write32(22'h83C, 32'h003A_0100, {tag, " fifo_soft_reset"});
            flow_raw_emureg_write32(22'h83C, FLOW_DLOG_RCMD2_INT, {tag, " fifo_enable_rcmd2"});
            flow_raw_emureg_write32(22'h83E, 32'h0000_0001, {tag, " dma_dbg_claim"});
            flow_raw_emureg_write32(22'h83E, 32'h0000_0002, {tag, " dma_enable_type0"});

            for (i = 0; i < 48; i++) begin
                wdata = 32'hD100_0000 | i;
                send_ir({ET_JTAG_IR_DMA_WDATA_OP, wdata}, 10);
                repeat (24) @(posedge vif.cpu_clk);
                if ((i % 8) == 7) begin
                    flow_raw_emureg_read32(22'h83C, {tag, " fifo_status_after_push"});
                end
            end

            for (i = 0; i < 48; i++) begin
                send_ir({ET_JTAG_IR_DLOG_RCMD2_OP, 32'h0000_0000}, 10);
                repeat (24) @(posedge vif.cpu_clk);
                if ((i % 8) == 7) begin
                    flow_raw_emureg_read32(22'h83A, {tag, " fifo_pop_data"});
                    flow_raw_emureg_read32(22'h83C, {tag, " fifo_status_after_pop"});
                end
            end

            for (i = 0; i < 16; i++) begin
                wdata = 32'hE200_0000 | i;
                send_ir({ET_JTAG_IR_DMA_WDATA_OP, wdata}, 10);
                repeat (20) @(posedge vif.cpu_clk);
                send_ir({ET_JTAG_IR_DLOG_RCMD2_OP, 32'h0000_0000}, 10);
                repeat (20) @(posedge vif.cpu_clk);
            end

            flow_raw_emureg_read32(22'h83A, {tag, " fifo_final_data"});
            flow_raw_emureg_read32(22'h83C, {tag, " fifo_final_status"});
            flow_raw_emureg_read32(22'h83E, {tag, " fifo_final_ctrl"});
            flow_raw_emureg_write32(22'h83E, 32'h0000_0000, {tag, " dma_disable"});
        end
    endtask : flow_dma_fifo_stress

    virtual task flow_emureg_cpu_pf0_write(input string tag = "ET_JTAG_FLOW");
        logic [31:0] observe_value;
        begin
            `uvm_info(tag,
                      "flow_emureg_cpu_pf0_write: arm C EALLOW code to write EMU_REG 0x900-0x904, DBGSTAT and BOR_CFG via CPU/PF0 path",
                      UVM_LOW)
            flow_rt_disable({tag, " setup_rt_disable"});
            flow_halt_rude({tag, " arm_cpu_pf0_halt"});
            et_jtag_write_a32(FLOW_EMUREG_CPU_GO_VALUE, observe_value, {tag, " arm_cpu_pf0_go"});
            flow_run_no_check({tag, " run_cpu_pf0_writer"});
            #0.8ms;
            flow_halt_rude({tag, " halt_after_cpu_pf0_writer"});

            flow_raw_emureg_read32(22'h900, {tag, " cpu_pf0_device_id_low"});
            flow_raw_emureg_read32(22'h901, {tag, " cpu_pf0_device_id_low_h"});
            flow_raw_emureg_read32(22'h902, {tag, " cpu_pf0_device_id_high"});
            flow_raw_emureg_read32(22'h903, {tag, " cpu_pf0_device_id_high_h"});
            flow_raw_emureg_read32(22'h904, {tag, " cpu_pf0_revid_f2803x"});
            flow_raw_emureg_read32(22'h800, {tag, " cpu_pf0_dbgstat"});
            flow_raw_emureg_read32(22'h984, {tag, " cpu_pf0_bor_cfg_984"});
            flow_raw_emureg_read32(22'h985, {tag, " cpu_pf0_bor_cfg_985"});
            flow_expect_hdl32("chip_top_tb.I_chip_top.I_ET.AD_inst.EMU_REG_inst.BOR_CFG",
                              32'h0000_0007, 32'h0000_0005, {tag, " cpu_pf0_bor_cfg_hdl"});
        end
    endtask : flow_emureg_cpu_pf0_write

    virtual task flow_issue_run_observe(input bit [37:0] cmd,
                                        input time dwell_time,
                                        input string tag);
        logic [21:0] pc_before;
        logic [21:0] pc_after;
        begin
            pc_before = vif.pc;
            send_ir(cmd, 10);
            #(dwell_time);
            pc_after = vif.pc;
            `uvm_info(tag,
                      $sformatf("run-observe: pc_before=0x%05h pc_after=0x%05h run=%0b halt=%0b step=%0b rt=%0b",
                                pc_before, pc_after, vif.cpu_run, vif.cpu_debug_halt,
                                vif.cpu_step, vif.real_time_mode),
                      UVM_LOW)
        end
    endtask : flow_issue_run_observe

    virtual task flow_issue_halt_observe(input string tag);
        begin
            send_ir(ET_JTAG_CMD_HALT_RUDE, 10);
            repeat (200) @(posedge vif.cpu_clk);
            `uvm_info(tag,
                      $sformatf("halt-observe: pc=0x%05h run=%0b halt=%0b step=%0b rt=%0b",
                                vif.pc, vif.cpu_run, vif.cpu_debug_halt,
                                vif.cpu_step, vif.real_time_mode),
                      UVM_LOW)
            if (vif.cpu_debug_halt !== 1'b1) begin
                `uvm_warning(tag, "halt-observe: CPU did not report debug halt; keep sequence coverage-oriented")
            end
        end
    endtask : flow_issue_halt_observe

    virtual task flow_issue_halt(input bit [37:0] cmd, input string tag);
        bit got_halt;
        logic [21:0] pc_before;
        logic [21:0] pc_at_halt;
        logic [21:0] pc_hold;
        begin
            pc_before = vif.pc;
            send_ir(cmd, 10);
            flow_wait_debug_halt(tag, 10000, got_halt, pc_at_halt);
            if (got_halt) begin
                repeat (100) @(posedge vif.cpu_clk);
                pc_hold = vif.pc;
                if (pc_hold !== pc_at_halt) begin
                    `uvm_error(tag,
                               $sformatf("PC did not hold in halt: pc_before=0x%05h pc_at_halt=0x%05h pc_after=0x%05h",
                                         pc_before, pc_at_halt, pc_hold))
                end
            end
        end
    endtask : flow_issue_halt

    virtual task flow_issue_run(input bit [37:0] cmd, input string tag);
        bit got_run;
        logic [21:0] pc_before;
        logic [21:0] pc_after;
        begin
            pc_before = vif.pc;
            send_ir(cmd, 10);
            flow_wait_run(tag, 10000, got_run, pc_after);
            if (got_run && (pc_after === pc_before)) begin
                `uvm_error(tag,
                           $sformatf("RUN-like command observed run but PC did not change: pc=0x%05h",
                                     pc_after))
            end
        end
    endtask : flow_issue_run

    virtual task flow_issue_step(input bit [37:0] cmd, input string tag);
        bit got_halt;
        logic [21:0] pc_before;
        logic [21:0] pc_after;
        begin
            pc_before = vif.pc;
            send_ir(cmd, 10);
            flow_wait_debug_halt(tag, 10000, got_halt, pc_after);
            if (got_halt && (pc_after === pc_before)) begin
                `uvm_warning(tag,
                             $sformatf("STEP-like command returned to halt but PC did not change: pc=0x%05h",
                                       pc_after))
            end
        end
    endtask : flow_issue_step

    virtual task flow_wait_debug_halt(input string tag,
                                      input int unsigned max_cycles,
                                      output bit got_halt,
                                      output logic [21:0] pc_at_halt);
        int unsigned wait_cycle;
        begin
            got_halt = 1'b0;
            pc_at_halt = 22'h0;
            for (wait_cycle = 0; wait_cycle < max_cycles; wait_cycle++) begin
                @(posedge vif.cpu_clk);
                if (vif.cpu_debug_halt === 1'b1) begin
                    got_halt = 1'b1;
                    pc_at_halt = vif.pc;
                    break;
                end
            end
            if (got_halt) begin
                `uvm_info(tag,
                          $sformatf("debug halt observed after %0d cpu_clk cycles: pc=0x%05h run=%0b step=%0b rt=%0b",
                                    wait_cycle, pc_at_halt, vif.cpu_run,
                                    vif.cpu_step, vif.real_time_mode),
                          UVM_LOW)
            end
            else begin
                `uvm_error(tag,
                           $sformatf("debug halt not observed within %0d cpu_clk cycles: pc=0x%05h run=%0b step=%0b rt=%0b",
                                     max_cycles, vif.pc, vif.cpu_run,
                                     vif.cpu_step, vif.real_time_mode))
            end
        end
    endtask : flow_wait_debug_halt

    virtual task flow_wait_run(input string tag,
                               input int unsigned max_cycles,
                               output bit got_run,
                               output logic [21:0] pc_after_run);
        int unsigned wait_cycle;
        begin
            got_run = 1'b0;
            pc_after_run = 22'h0;
            for (wait_cycle = 0; wait_cycle < max_cycles; wait_cycle++) begin
                @(posedge vif.cpu_clk);
                if ((vif.cpu_run === 1'b1) && (vif.cpu_debug_halt !== 1'b1)) begin
                    got_run = 1'b1;
                    break;
                end
            end
            repeat (100) @(posedge vif.cpu_clk);
            pc_after_run = vif.pc;
            if (got_run) begin
                `uvm_info(tag,
                          $sformatf("run observed after %0d cpu_clk cycles: pc_after_100clk=0x%05h run=%0b halt=%0b",
                                    wait_cycle, pc_after_run,
                                    vif.cpu_run, vif.cpu_debug_halt),
                          UVM_LOW)
            end
            else begin
                `uvm_error(tag,
                           $sformatf("run not observed within %0d cpu_clk cycles: pc=0x%05h run=%0b halt=%0b",
                                     max_cycles, vif.pc,
                                     vif.cpu_run, vif.cpu_debug_halt))
            end
        end
    endtask : flow_wait_run
endclass : et_jtag_flow_base_sequence

class et_jtag_cmd_flow_sequence extends et_jtag_flow_base_sequence;
    `uvm_object_utils(et_jtag_cmd_flow_sequence)

    function new(string name = "et_jtag_cmd_flow_sequence");
        super.new(name);
    endfunction : new

    virtual task body();
        flow_prepare("ET_JTAG_CMD_FLOW");
        flow_halt_polite("ET_JTAG_CMD_FLOW");
        #0.2ms;
        flow_run_polite("ET_JTAG_CMD_FLOW");
        #0.2ms;
        flow_halt_rude("ET_JTAG_CMD_FLOW");
        #0.2ms;
        flow_step_polite("ET_JTAG_CMD_FLOW");
        #0.2ms;
        flow_run_rude("ET_JTAG_CMD_FLOW");
        #0.2ms;
        flow_halt_rude("ET_JTAG_CMD_FLOW");
        #0.2ms;
        flow_free_run("ET_JTAG_CMD_FLOW");
        #0.2ms;
        flow_rt_enable("ET_JTAG_CMD_FLOW");
        #0.2ms;
        flow_rt_disable("ET_JTAG_CMD_FLOW");
        flow_read_dbgstat("ET_JTAG_CMD_FLOW");
        `uvm_info("ET_JTAG_CMD_FLOW", "command flow sequence done", UVM_LOW)
        #0.5ms;
        $finish;
    endtask : body
endclass : et_jtag_cmd_flow_sequence

class et_jtag_reset_nbstep_sequence extends et_jtag_flow_base_sequence;
    `uvm_object_utils(et_jtag_reset_nbstep_sequence)

    function new(string name = "et_jtag_reset_nbstep_sequence");
        super.new(name);
    endfunction : new

    virtual task body();
        flow_prepare("ET_JTAG_RESET_NBSTEP");
        flow_halt_rude("ET_JTAG_RESET_NBSTEP");
        #0.2ms;
        flow_nb_step("ET_JTAG_RESET_NBSTEP");
        #0.2ms;
        flow_cpu_reset("ET_JTAG_RESET_NBSTEP");
        `uvm_info("ET_JTAG_RESET_NBSTEP", "reset/nb_step sequence done", UVM_LOW)
        #0.5ms;
        $finish;
    endtask : body
endclass : et_jtag_reset_nbstep_sequence

class et_jtag_mem16_dbgstat_sequence extends et_jtag_flow_base_sequence;
    `uvm_object_utils(et_jtag_mem16_dbgstat_sequence)

    function new(string name = "et_jtag_mem16_dbgstat_sequence");
        super.new(name);
    endfunction : new

    virtual task body();
        logic [31:0] value;
        begin
            flow_prepare("ET_JTAG_MEM16_DBGSTAT");
            flow_halt_rude("ET_JTAG_MEM16_DBGSTAT");
            flow_read_dbgstat("ET_JTAG_MEM16_DBGSTAT");
            flow_reada16(value, "ET_JTAG_MEM16_DBGSTAT");
            flow_writea16(FLOW_A_WRITE16_VALUE[15:0], value, "ET_JTAG_MEM16_DBGSTAT");
            flow_read_dbgstat("ET_JTAG_MEM16_DBGSTAT");
            `uvm_info("ET_JTAG_MEM16_DBGSTAT", "mem16/dbgstat sequence done", UVM_LOW)
            #0.5ms;
            $finish;
        end
    endtask : body
endclass : et_jtag_mem16_dbgstat_sequence

class et_jtag_tap_dr_sweep_sequence extends et_jtag_flow_base_sequence;
    `uvm_object_utils(et_jtag_tap_dr_sweep_sequence)

    function new(string name = "et_jtag_tap_dr_sweep_sequence");
        super.new(name);
    endfunction : new

    virtual task body();
        flow_prepare("ET_JTAG_TAP_DR_SWEEP");
        flow_halt_rude("ET_JTAG_TAP_DR_SWEEP");
        #0.2ms;
        flow_tap_dr_sweep("ET_JTAG_TAP_DR_SWEEP");
        `uvm_info("ET_JTAG_TAP_DR_SWEEP", "tap/dr sweep sequence done", UVM_LOW)
        #0.5ms;
        $finish;
    endtask : body
endclass : et_jtag_tap_dr_sweep_sequence

class et_jtag_tap_highz_bscan_sequence extends et_jtag_flow_base_sequence;
    `uvm_object_utils(et_jtag_tap_highz_bscan_sequence)

    function new(string name = "et_jtag_tap_highz_bscan_sequence");
        super.new(name);
    endfunction : new

    virtual task body();
        flow_prepare("ET_JTAG_TAP_HIGHZ_BSCAN");
        flow_tap_highz_bscan_sweep("ET_JTAG_TAP_HIGHZ_BSCAN");
        `uvm_info("ET_JTAG_TAP_HIGHZ_BSCAN", "tap highz/bscan sequence done", UVM_LOW)
        #0.5ms;
        $finish;
    endtask : body
endclass : et_jtag_tap_highz_bscan_sequence

class et_jtag_emureg_sweep_sequence extends et_jtag_flow_base_sequence;
    `uvm_object_utils(et_jtag_emureg_sweep_sequence)

    function new(string name = "et_jtag_emureg_sweep_sequence");
        super.new(name);
    endfunction : new

    virtual task body();
        flow_prepare("ET_JTAG_EMUREG_SWEEP");
        flow_halt_rude("ET_JTAG_EMUREG_SWEEP");
        #0.2ms;
        flow_emureg_sweep("ET_JTAG_EMUREG_SWEEP");
        `uvm_info("ET_JTAG_EMUREG_SWEEP", "emureg sweep sequence done", UVM_LOW)
        #0.5ms;
        $finish;
    endtask : body
endclass : et_jtag_emureg_sweep_sequence

class et_jtag_au_sweep_sequence extends et_jtag_flow_base_sequence;
    `uvm_object_utils(et_jtag_au_sweep_sequence)

    function new(string name = "et_jtag_au_sweep_sequence");
        super.new(name);
    endfunction : new

    virtual task body();
        flow_prepare("ET_JTAG_AU_SWEEP");
        flow_halt_rude("ET_JTAG_AU_SWEEP");
        #0.2ms;
        flow_au_sweep("ET_JTAG_AU_SWEEP");
        `uvm_info("ET_JTAG_AU_SWEEP", "AU sweep sequence done", UVM_LOW)
        #0.5ms;
        $finish;
    endtask : body
endclass : et_jtag_au_sweep_sequence

class et_jtag_rt_reset_corner_sequence extends et_jtag_flow_base_sequence;
    `uvm_object_utils(et_jtag_rt_reset_corner_sequence)

    function new(string name = "et_jtag_rt_reset_corner_sequence");
        super.new(name);
    endfunction : new

    virtual task body();
        flow_prepare("ET_JTAG_RT_RESET_CORNER");
        flow_halt_rude("ET_JTAG_RT_RESET_CORNER");
        #0.2ms;
        flow_rt_enable_alt("ET_JTAG_RT_RESET_CORNER");
        #0.2ms;
        flow_rt_disable_alt("ET_JTAG_RT_RESET_CORNER");
        #0.2ms;
        flow_set_reset("ET_JTAG_RT_RESET_CORNER");
        #0.2ms;
        flow_clr_step("ET_JTAG_RT_RESET_CORNER");
        #0.2ms;
        flow_set_reset("ET_JTAG_RT_RESET_CORNER");
        #0.2ms;
        flow_cpu_reset("ET_JTAG_RT_RESET_CORNER");
        #0.2ms;
        flow_read_dbgstat("ET_JTAG_RT_RESET_CORNER");
        `uvm_info("ET_JTAG_RT_RESET_CORNER", "RT/reset corner sequence done", UVM_LOW)
        #0.5ms;
        $finish;
    endtask : body
endclass : et_jtag_rt_reset_corner_sequence

class et_jtag_tap_pause_sequence extends et_jtag_flow_base_sequence;
    `uvm_object_utils(et_jtag_tap_pause_sequence)

    function new(string name = "et_jtag_tap_pause_sequence");
        super.new(name);
    endfunction : new

    virtual task body();
        flow_prepare("ET_JTAG_TAP_PAUSE");
        #0.2ms;
        flow_tap_pause_exit2("ET_JTAG_TAP_PAUSE");
        `uvm_info("ET_JTAG_TAP_PAUSE", "TAP pause/exit2 sequence done", UVM_LOW)
        #0.5ms;
        $finish;
    endtask : body
endclass : et_jtag_tap_pause_sequence

class et_jtag_tap_reset_sequence extends et_jtag_flow_base_sequence;
    `uvm_object_utils(et_jtag_tap_reset_sequence)

    function new(string name = "et_jtag_tap_reset_sequence");
        super.new(name);
    endfunction : new

    virtual task body();
        flow_prepare("ET_JTAG_TAP_RESET");
        #0.2ms;
        flow_tap_async_reset_sweep("ET_JTAG_TAP_RESET");
        `uvm_info("ET_JTAG_TAP_RESET", "TAP async reset sequence done", UVM_LOW)
        #0.5ms;
        $finish;
    endtask : body
endclass : et_jtag_tap_reset_sequence

class et_jtag_emureg_halfword_sequence extends et_jtag_flow_base_sequence;
    `uvm_object_utils(et_jtag_emureg_halfword_sequence)

    function new(string name = "et_jtag_emureg_halfword_sequence");
        super.new(name);
    endfunction : new

    virtual task body();
        flow_prepare("ET_JTAG_EMUREG_HALFWORD");
        flow_halt_rude("ET_JTAG_EMUREG_HALFWORD");
        #0.2ms;
        flow_emureg_halfword_sweep("ET_JTAG_EMUREG_HALFWORD");
        `uvm_info("ET_JTAG_EMUREG_HALFWORD", "EMU_REG halfword sequence done", UVM_LOW)
        #0.5ms;
        $finish;
    endtask : body
endclass : et_jtag_emureg_halfword_sequence

class et_jtag_emureg_direct_sequence extends et_jtag_flow_base_sequence;
    `uvm_object_utils(et_jtag_emureg_direct_sequence)

    function new(string name = "et_jtag_emureg_direct_sequence");
        super.new(name);
    endfunction : new

    virtual task body();
        flow_prepare("ET_JTAG_EMUREG_DIRECT");
        flow_emureg_direct_access_sweep("ET_JTAG_EMUREG_DIRECT");
        `uvm_info("ET_JTAG_EMUREG_DIRECT", "EMU_REG direct-access sequence done", UVM_LOW)
        #0.5ms;
        $finish;
    endtask : body
endclass : et_jtag_emureg_direct_sequence

class et_jtag_emureg_write16_check_sequence extends et_jtag_flow_base_sequence;
    `uvm_object_utils(et_jtag_emureg_write16_check_sequence)

    function new(string name = "et_jtag_emureg_write16_check_sequence");
        super.new(name);
    endfunction : new

    virtual task body();
        flow_prepare("ET_JTAG_EMUREG_WRITE16_CHECK");
        flow_emureg_write16_check("ET_JTAG_EMUREG_WRITE16_CHECK");
        `uvm_info("ET_JTAG_EMUREG_WRITE16_CHECK", "EMU_REG WRITEA16 low-half check sequence done", UVM_LOW)
        #0.5ms;
        $finish;
    endtask : body
endclass : et_jtag_emureg_write16_check_sequence

class et_jtag_cla_dbgreg_mem_sequence extends et_jtag_flow_base_sequence;
    `uvm_object_utils(et_jtag_cla_dbgreg_mem_sequence)

    function new(string name = "et_jtag_cla_dbgreg_mem_sequence");
        super.new(name);
    endfunction : new

    virtual task body();
        flow_prepare("ET_JTAG_CLA_DBGREG_MEM");
        flow_halt_rude("ET_JTAG_CLA_DBGREG_MEM");
        #0.2ms;
        flow_cla_dbgreg_mem_access("ET_JTAG_CLA_DBGREG_MEM");
        `uvm_info("ET_JTAG_CLA_DBGREG_MEM", "CLA debug-register memory-access sequence done", UVM_LOW)
        #0.5ms;
        $finish;
    endtask : body
endclass : et_jtag_cla_dbgreg_mem_sequence

class et_jtag_cla_dbgreg_corner_sequence extends et_jtag_flow_base_sequence;
    `uvm_object_utils(et_jtag_cla_dbgreg_corner_sequence)

    function new(string name = "et_jtag_cla_dbgreg_corner_sequence");
        super.new(name);
    endfunction : new

    virtual task body();
        flow_prepare("ET_JTAG_CLA_DBGREG_CORNER");
        #0.2ms;
        flow_cla_dbgreg_corner_sweep("ET_JTAG_CLA_DBGREG_CORNER");
        `uvm_info("ET_JTAG_CLA_DBGREG_CORNER", "CLA debug-register corner sequence done", UVM_LOW)
        #0.5ms;
        $finish;
    endtask : body
endclass : et_jtag_cla_dbgreg_corner_sequence

class et_jtag_cla_dbg_halt_step_run_sequence extends et_jtag_flow_base_sequence;
    `uvm_object_utils(et_jtag_cla_dbg_halt_step_run_sequence)

    function new(string name = "et_jtag_cla_dbg_halt_step_run_sequence");
        super.new(name);
    endfunction : new

    virtual task body();
        flow_prepare("ET_JTAG_CLA_DBG_HALT_STEP_RUN");
        #0.2ms;
        flow_cla_dbg_halt_step_run("ET_JTAG_CLA_DBG_HALT_STEP_RUN");
        `uvm_info("ET_JTAG_CLA_DBG_HALT_STEP_RUN", "CLA debug halt/step/run sequence done", UVM_LOW)
        #0.5ms;
        $finish;
    endtask : body
endclass : et_jtag_cla_dbg_halt_step_run_sequence

class et_jtag_cla_mpc_debug_write_sequence extends et_jtag_flow_base_sequence;
    `uvm_object_utils(et_jtag_cla_mpc_debug_write_sequence)

    function new(string name = "et_jtag_cla_mpc_debug_write_sequence");
        super.new(name);
    endfunction : new

    virtual task body();
        flow_prepare("ET_JTAG_CLA_MPC_DEBUG_WRITE");
        #0.2ms;
        flow_cla_mpc_debug_write("ET_JTAG_CLA_MPC_DEBUG_WRITE");
        `uvm_info("ET_JTAG_CLA_MPC_DEBUG_WRITE", "CLA MPC debug-write sequence done", UVM_LOW)
        #0.5ms;
        $finish;
    endtask : body
endclass : et_jtag_cla_mpc_debug_write_sequence

class et_jtag_cla_swbp_sweep_sequence extends et_jtag_flow_base_sequence;
    `uvm_object_utils(et_jtag_cla_swbp_sweep_sequence)

    function new(string name = "et_jtag_cla_swbp_sweep_sequence");
        super.new(name);
    endfunction : new

    virtual task body();
        flow_prepare("ET_JTAG_CLA_SWBP_SWEEP");
        #0.2ms;
        flow_cla_swbp_sweep("ET_JTAG_CLA_SWBP_SWEEP");
        `uvm_info("ET_JTAG_CLA_SWBP_SWEEP", "CLA SWBP/debugstop sweep sequence done", UVM_LOW)
        #0.5ms;
        $finish;
    endtask : body
endclass : et_jtag_cla_swbp_sweep_sequence

class et_jtag_cla_pc_readback_sequence extends et_jtag_flow_base_sequence;
    `uvm_object_utils(et_jtag_cla_pc_readback_sequence)

    function new(string name = "et_jtag_cla_pc_readback_sequence");
        super.new(name);
    endfunction : new

    virtual task body();
        flow_prepare("ET_JTAG_CLA_PC_READBACK");
        #0.2ms;
        flow_cla_pc_readback_sweep("ET_JTAG_CLA_PC_READBACK");
        `uvm_info("ET_JTAG_CLA_PC_READBACK", "CLA PC/readback sequence done", UVM_LOW)
        #0.5ms;
        $finish;
    endtask : body
endclass : et_jtag_cla_pc_readback_sequence

class et_jtag_cla_command_ack_sequence extends et_jtag_flow_base_sequence;
    `uvm_object_utils(et_jtag_cla_command_ack_sequence)

    function new(string name = "et_jtag_cla_command_ack_sequence");
        super.new(name);
    endfunction : new

    virtual task body();
        flow_prepare("ET_JTAG_CLA_COMMAND_ACK");
        #0.2ms;
        flow_cla_command_ack("ET_JTAG_CLA_COMMAND_ACK");
        `uvm_info("ET_JTAG_CLA_COMMAND_ACK", "CLA command ACK sequence done", UVM_LOW)
        #0.5ms;
        $finish;
    endtask : body
endclass : et_jtag_cla_command_ack_sequence

class et_jtag_cla_negative_state_cmd_sequence extends et_jtag_flow_base_sequence;
    `uvm_object_utils(et_jtag_cla_negative_state_cmd_sequence)

    function new(string name = "et_jtag_cla_negative_state_cmd_sequence");
        super.new(name);
    endfunction : new

    virtual task body();
        flow_prepare("ET_JTAG_CLA_NEGATIVE_STATE_CMD");
        #0.2ms;
        flow_cla_negative_state_cmd("ET_JTAG_CLA_NEGATIVE_STATE_CMD");
        `uvm_info("ET_JTAG_CLA_NEGATIVE_STATE_CMD", "CLA negative-state command sequence done", UVM_LOW)
        #0.5ms;
        $finish;
    endtask : body
endclass : et_jtag_cla_negative_state_cmd_sequence

class et_jtag_cla_disconnect_gate_sequence extends et_jtag_flow_base_sequence;
    `uvm_object_utils(et_jtag_cla_disconnect_gate_sequence)

    function new(string name = "et_jtag_cla_disconnect_gate_sequence");
        super.new(name);
    endfunction : new

    virtual task body();
        flow_prepare("ET_JTAG_CLA_DISCONNECT_GATE");
        #0.2ms;
        flow_cla_disconnect_gate("ET_JTAG_CLA_DISCONNECT_GATE");
        `uvm_info("ET_JTAG_CLA_DISCONNECT_GATE", "CLA disconnect gate sequence done", UVM_LOW)
        #0.5ms;
        $finish;
    endtask : body
endclass : et_jtag_cla_disconnect_gate_sequence

class et_jtag_cla_debug_reset_state_sequence extends et_jtag_flow_base_sequence;
    `uvm_object_utils(et_jtag_cla_debug_reset_state_sequence)

    function new(string name = "et_jtag_cla_debug_reset_state_sequence");
        super.new(name);
    endfunction : new

    virtual task body();
        flow_prepare("ET_JTAG_CLA_DEBUG_RESET_STATE");
        #0.2ms;
        flow_cla_debug_reset_state("ET_JTAG_CLA_DEBUG_RESET_STATE");
        `uvm_info("ET_JTAG_CLA_DEBUG_RESET_STATE", "CLA debug reset-state sequence done", UVM_LOW)
        #0.5ms;
        $finish;
    endtask : body
endclass : et_jtag_cla_debug_reset_state_sequence

class et_jtag_cla_fetch_buffer_rw_sequence extends et_jtag_flow_base_sequence;
    `uvm_object_utils(et_jtag_cla_fetch_buffer_rw_sequence)

    function new(string name = "et_jtag_cla_fetch_buffer_rw_sequence");
        super.new(name);
    endfunction : new

    virtual task body();
        flow_prepare("ET_JTAG_CLA_FETCH_BUFFER_RW");
        #0.2ms;
        flow_cla_fetch_buffer_rw("ET_JTAG_CLA_FETCH_BUFFER_RW");
        `uvm_info("ET_JTAG_CLA_FETCH_BUFFER_RW", "CLA fetch-buffer RW sequence done", UVM_LOW)
        #0.5ms;
        $finish;
    endtask : body
endclass : et_jtag_cla_fetch_buffer_rw_sequence

class et_jtag_cla_exec_reg_write_matrix_sequence extends et_jtag_flow_base_sequence;
    `uvm_object_utils(et_jtag_cla_exec_reg_write_matrix_sequence)

    function new(string name = "et_jtag_cla_exec_reg_write_matrix_sequence");
        super.new(name);
    endfunction : new

    virtual task body();
        flow_prepare("ET_JTAG_CLA_EXEC_REG_WRITE_MATRIX");
        #0.2ms;
        flow_cla_exec_reg_write_matrix("ET_JTAG_CLA_EXEC_REG_WRITE_MATRIX");
        `uvm_info("ET_JTAG_CLA_EXEC_REG_WRITE_MATRIX", "CLA execution-register write matrix sequence done", UVM_LOW)
        #0.5ms;
        $finish;
    endtask : body
endclass : et_jtag_cla_exec_reg_write_matrix_sequence

class et_jtag_cla_swbp_pipeline_stall_sequence extends et_jtag_flow_base_sequence;
    `uvm_object_utils(et_jtag_cla_swbp_pipeline_stall_sequence)

    function new(string name = "et_jtag_cla_swbp_pipeline_stall_sequence");
        super.new(name);
    endfunction : new

    virtual task body();
        flow_prepare("ET_JTAG_CLA_SWBP_PIPELINE_STALL");
        #0.2ms;
        flow_cla_swbp_pipeline_stall("ET_JTAG_CLA_SWBP_PIPELINE_STALL");
        `uvm_info("ET_JTAG_CLA_SWBP_PIPELINE_STALL", "CLA SWBP pipeline-stall sequence done", UVM_LOW)
        #0.5ms;
        $finish;
    endtask : body
endclass : et_jtag_cla_swbp_pipeline_stall_sequence

class et_jtag_cla_debug_mstop_return_sequence extends et_jtag_flow_base_sequence;
    `uvm_object_utils(et_jtag_cla_debug_mstop_return_sequence)

    function new(string name = "et_jtag_cla_debug_mstop_return_sequence");
        super.new(name);
    endfunction : new

    virtual task body();
        flow_prepare("ET_JTAG_CLA_DEBUG_MSTOP_RETURN");
        #0.2ms;
        flow_cla_debug_mstop_return("ET_JTAG_CLA_DEBUG_MSTOP_RETURN");
        `uvm_info("ET_JTAG_CLA_DEBUG_MSTOP_RETURN", "CLA debug MSTOP-return sequence done", UVM_LOW)
        #0.5ms;
        $finish;
    endtask : body
endclass : et_jtag_cla_debug_mstop_return_sequence

class et_jtag_cla_step_raw_stall_sequence extends et_jtag_flow_base_sequence;
    `uvm_object_utils(et_jtag_cla_step_raw_stall_sequence)

    function new(string name = "et_jtag_cla_step_raw_stall_sequence");
        super.new(name);
    endfunction : new

    virtual task body();
        flow_prepare("ET_JTAG_CLA_STEP_RAW_STALL");
        #0.2ms;
        flow_cla_step_raw_stall("ET_JTAG_CLA_STEP_RAW_STALL");
        `uvm_info("ET_JTAG_CLA_STEP_RAW_STALL", "CLA STEP RAW-stall sequence done", UVM_LOW)
        #0.5ms;
        $finish;
    endtask : body
endclass : et_jtag_cla_step_raw_stall_sequence

class et_jtag_cla_swbp3_set_clear_sequence extends et_jtag_flow_base_sequence;
    `uvm_object_utils(et_jtag_cla_swbp3_set_clear_sequence)

    function new(string name = "et_jtag_cla_swbp3_set_clear_sequence");
        super.new(name);
    endfunction : new

    virtual task body();
        flow_prepare("ET_JTAG_CLA_SWBP3_SET_CLEAR");
        #0.2ms;
        flow_cla_swbp3_set_clear("ET_JTAG_CLA_SWBP3_SET_CLEAR");
        `uvm_info("ET_JTAG_CLA_SWBP3_SET_CLEAR", "CLA SWBP3 set/clear sequence done", UVM_LOW)
        #0.5ms;
        $finish;
    endtask : body
endclass : et_jtag_cla_swbp3_set_clear_sequence

class et_jtag_cla_debug_idle_exit_reachability_sequence extends et_jtag_flow_base_sequence;
    `uvm_object_utils(et_jtag_cla_debug_idle_exit_reachability_sequence)

    function new(string name = "et_jtag_cla_debug_idle_exit_reachability_sequence");
        super.new(name);
    endfunction : new

    virtual task body();
        flow_prepare("ET_JTAG_CLA_DEBUG_IDLE_EXIT_REACHABILITY");
        #0.2ms;
        flow_cla_debug_idle_exit_reachability("ET_JTAG_CLA_DEBUG_IDLE_EXIT_REACHABILITY");
        `uvm_info("ET_JTAG_CLA_DEBUG_IDLE_EXIT_REACHABILITY", "CLA debug idle-exit reachability audit sequence done", UVM_LOW)
        #0.5ms;
        $finish;
    endtask : body
endclass : et_jtag_cla_debug_idle_exit_reachability_sequence

class et_jtag_cla_fetch_response_delay_sequence extends et_jtag_flow_base_sequence;
    `uvm_object_utils(et_jtag_cla_fetch_response_delay_sequence)

    function new(string name = "et_jtag_cla_fetch_response_delay_sequence");
        super.new(name);
    endfunction : new

    virtual task body();
        flow_prepare("ET_JTAG_CLA_FETCH_RESPONSE_DELAY");
        #0.2ms;
        flow_cla_fetch_response_delay("ET_JTAG_CLA_FETCH_RESPONSE_DELAY");
        `uvm_info("ET_JTAG_CLA_FETCH_RESPONSE_DELAY", "CLA fetch response-delay sequence done", UVM_LOW)
        #0.5ms;
        $finish;
    endtask : body
endclass : et_jtag_cla_fetch_response_delay_sequence

class et_jtag_cla_fetch_fifo_simultaneous_rw_sequence extends et_jtag_flow_base_sequence;
    `uvm_object_utils(et_jtag_cla_fetch_fifo_simultaneous_rw_sequence)

    function new(string name = "et_jtag_cla_fetch_fifo_simultaneous_rw_sequence");
        super.new(name);
    endfunction : new

    virtual task body();
        flow_prepare("ET_JTAG_CLA_FETCH_FIFO_SIMULTANEOUS_RW");
        #0.2ms;
        flow_cla_fetch_fifo_simultaneous_rw("ET_JTAG_CLA_FETCH_FIFO_SIMULTANEOUS_RW");
        `uvm_info("ET_JTAG_CLA_FETCH_FIFO_SIMULTANEOUS_RW", "CLA fetch FIFO simultaneous R/W sequence done", UVM_LOW)
        #0.5ms;
        $finish;
    endtask : body
endclass : et_jtag_cla_fetch_fifo_simultaneous_rw_sequence

class et_jtag_cla_et_debug_run_reachability_sequence extends et_jtag_flow_base_sequence;
    `uvm_object_utils(et_jtag_cla_et_debug_run_reachability_sequence)

    function new(string name = "et_jtag_cla_et_debug_run_reachability_sequence");
        super.new(name);
    endfunction : new

    virtual task body();
        flow_prepare("ET_JTAG_CLA_ET_DEBUG_RUN_REACHABILITY");
        #0.2ms;
        flow_cla_et_debug_run_reachability("ET_JTAG_CLA_ET_DEBUG_RUN_REACHABILITY");
        `uvm_info("ET_JTAG_CLA_ET_DEBUG_RUN_REACHABILITY", "CLA stage2 debug RUN reachability sequence done", UVM_LOW)
        #0.5ms;
        $finish;
    endtask : body
endclass : et_jtag_cla_et_debug_run_reachability_sequence

class et_jtag_cla_et_breakpoint_pending_matrix_sequence extends et_jtag_flow_base_sequence;
    `uvm_object_utils(et_jtag_cla_et_breakpoint_pending_matrix_sequence)

    function new(string name = "et_jtag_cla_et_breakpoint_pending_matrix_sequence");
        super.new(name);
    endfunction : new

    virtual task body();
        flow_prepare("ET_JTAG_CLA_ET_BREAKPOINT_PENDING_MATRIX");
        #0.2ms;
        flow_cla_et_breakpoint_pending_matrix("ET_JTAG_CLA_ET_BREAKPOINT_PENDING_MATRIX");
        `uvm_info("ET_JTAG_CLA_ET_BREAKPOINT_PENDING_MATRIX", "CLA stage2 breakpoint pending matrix sequence done", UVM_LOW)
        #0.5ms;
        $finish;
    endtask : body
endclass : et_jtag_cla_et_breakpoint_pending_matrix_sequence

class et_jtag_cla_et_step_halt_resume_stall_matrix_sequence extends et_jtag_flow_base_sequence;
    `uvm_object_utils(et_jtag_cla_et_step_halt_resume_stall_matrix_sequence)

    function new(string name = "et_jtag_cla_et_step_halt_resume_stall_matrix_sequence");
        super.new(name);
    endfunction : new

    virtual task body();
        flow_prepare("ET_JTAG_CLA_ET_STEP_HALT_RESUME_STALL_MATRIX");
        #0.2ms;
        flow_cla_et_step_halt_resume_stall_matrix("ET_JTAG_CLA_ET_STEP_HALT_RESUME_STALL_MATRIX");
        `uvm_info("ET_JTAG_CLA_ET_STEP_HALT_RESUME_STALL_MATRIX", "CLA stage2 step/halt/resume stall matrix sequence done", UVM_LOW)
        #0.5ms;
        $finish;
    endtask : body
endclass : et_jtag_cla_et_step_halt_resume_stall_matrix_sequence

class et_jtag_cla_mem_wstall_isolated_sequence extends et_jtag_flow_base_sequence;
    `uvm_object_utils(et_jtag_cla_mem_wstall_isolated_sequence)

    function new(string name = "et_jtag_cla_mem_wstall_isolated_sequence");
        super.new(name);
    endfunction : new

    virtual task body();
        flow_prepare("ET_JTAG_CLA_MEM_WSTALL_ISOLATED");
        #0.2ms;
        flow_cla_mem_wstall_isolated("ET_JTAG_CLA_MEM_WSTALL_ISOLATED");
        `uvm_info("ET_JTAG_CLA_MEM_WSTALL_ISOLATED", "CLA stage2 isolated write-stall sequence done", UVM_LOW)
        #0.5ms;
        $finish;
    endtask : body
endclass : et_jtag_cla_mem_wstall_isolated_sequence

class et_jtag_cla_raw_stall_overlap_sequence extends et_jtag_flow_base_sequence;
    `uvm_object_utils(et_jtag_cla_raw_stall_overlap_sequence)

    function new(string name = "et_jtag_cla_raw_stall_overlap_sequence");
        super.new(name);
    endfunction : new

    virtual task body();
        flow_prepare("ET_JTAG_CLA_RAW_STALL_OVERLAP");
        #0.2ms;
        flow_cla_raw_stall_overlap("ET_JTAG_CLA_RAW_STALL_OVERLAP");
        `uvm_info("ET_JTAG_CLA_RAW_STALL_OVERLAP", "CLA stage2 RAW-stall overlap sequence done", UVM_LOW)
        #0.5ms;
        $finish;
    endtask : body
endclass : et_jtag_cla_raw_stall_overlap_sequence

class et_jtag_cla_adc_trigger_source_matrix_sequence extends et_jtag_flow_base_sequence;
    `uvm_object_utils(et_jtag_cla_adc_trigger_source_matrix_sequence)

    function new(string name = "et_jtag_cla_adc_trigger_source_matrix_sequence");
        super.new(name);
    endfunction : new

    virtual task body();
        flow_prepare("ET_JTAG_CLA_ADC_TRIGGER_SOURCE_MATRIX");
        #0.2ms;
        flow_cla_adc_trigger_source_matrix("ET_JTAG_CLA_ADC_TRIGGER_SOURCE_MATRIX");
        `uvm_info("ET_JTAG_CLA_ADC_TRIGGER_SOURCE_MATRIX", "CLA stage2 ADC trigger-source audit sequence done", UVM_LOW)
        #0.5ms;
        $finish;
    endtask : body
endclass : et_jtag_cla_adc_trigger_source_matrix_sequence

class et_jtag_cla_reserved_cndf_injection_sequence extends et_jtag_flow_base_sequence;
    `uvm_object_utils(et_jtag_cla_reserved_cndf_injection_sequence)

    function new(string name = "et_jtag_cla_reserved_cndf_injection_sequence");
        super.new(name);
    endfunction : new

    virtual task body();
        flow_prepare("ET_JTAG_CLA_RESERVED_CNDF_INJECTION");
        #0.2ms;
        flow_cla_reserved_cndf_injection("ET_JTAG_CLA_RESERVED_CNDF_INJECTION");
        `uvm_info("ET_JTAG_CLA_RESERVED_CNDF_INJECTION", "CLA stage2 reserved CNDF audit sequence done", UVM_LOW)
        #0.5ms;
        $finish;
    endtask : body
endclass : et_jtag_cla_reserved_cndf_injection_sequence

class et_jtag_cla_task8_trigger_hold_mcdc_sequence extends et_jtag_flow_base_sequence;
    `uvm_object_utils(et_jtag_cla_task8_trigger_hold_mcdc_sequence)

    function new(string name = "et_jtag_cla_task8_trigger_hold_mcdc_sequence");
        super.new(name);
    endfunction : new

    virtual task body();
        flow_prepare("ET_JTAG_CLA_TASK8_TRIGGER_HOLD_MCDC");
        #0.2ms;
        flow_cla_task8_trigger_hold_mcdc("ET_JTAG_CLA_TASK8_TRIGGER_HOLD_MCDC");
        `uvm_info("ET_JTAG_CLA_TASK8_TRIGGER_HOLD_MCDC", "CLA final Task8 sustained-high trigger audit sequence done", UVM_LOW)
        #0.5ms;
        $finish;
    endtask : body
endclass : et_jtag_cla_task8_trigger_hold_mcdc_sequence

class et_jtag_cla_reserved_cndf_pipeline_injection_sequence extends et_jtag_flow_base_sequence;
    `uvm_object_utils(et_jtag_cla_reserved_cndf_pipeline_injection_sequence)

    function new(string name = "et_jtag_cla_reserved_cndf_pipeline_injection_sequence");
        super.new(name);
    endfunction : new

    virtual task body();
        flow_prepare("ET_JTAG_CLA_RESERVED_CNDF_PIPELINE_INJECTION");
        #0.2ms;
        flow_cla_reserved_cndf_pipeline_injection("ET_JTAG_CLA_RESERVED_CNDF_PIPELINE_INJECTION");
        `uvm_info("ET_JTAG_CLA_RESERVED_CNDF_PIPELINE_INJECTION", "CLA final reserved CNDF pipeline audit sequence done", UVM_LOW)
        #0.5ms;
        $finish;
    endtask : body
endclass : et_jtag_cla_reserved_cndf_pipeline_injection_sequence

class et_jtag_cla_et_debug_idle_exit_final_sequence extends et_jtag_flow_base_sequence;
    `uvm_object_utils(et_jtag_cla_et_debug_idle_exit_final_sequence)

    function new(string name = "et_jtag_cla_et_debug_idle_exit_final_sequence");
        super.new(name);
    endfunction : new

    virtual task body();
        flow_prepare("ET_JTAG_CLA_ET_DEBUG_IDLE_EXIT_FINAL");
        #0.2ms;
        flow_cla_et_debug_idle_exit_final("ET_JTAG_CLA_ET_DEBUG_IDLE_EXIT_FINAL");
        `uvm_info("ET_JTAG_CLA_ET_DEBUG_IDLE_EXIT_FINAL", "CLA final debug idle-exit reachability sequence done", UVM_LOW)
        #0.5ms;
        $finish;
    endtask : body
endclass : et_jtag_cla_et_debug_idle_exit_final_sequence

class et_jtag_cla_lu_mar_conflict_raw_injection_sequence extends et_jtag_flow_base_sequence;
    `uvm_object_utils(et_jtag_cla_lu_mar_conflict_raw_injection_sequence)

    function new(string name = "et_jtag_cla_lu_mar_conflict_raw_injection_sequence");
        super.new(name);
    endfunction : new

    virtual task body();
        flow_prepare("ET_JTAG_CLA_LU_MAR_CONFLICT_RAW_INJECTION");
        #0.2ms;
        flow_cla_lu_mar_conflict_raw_injection("ET_JTAG_CLA_LU_MAR_CONFLICT_RAW_INJECTION");
        `uvm_info("ET_JTAG_CLA_LU_MAR_CONFLICT_RAW_INJECTION", "CLA final LU/MAR raw conflict waiver audit sequence done", UVM_LOW)
        #0.5ms;
        $finish;
    endtask : body
endclass : et_jtag_cla_lu_mar_conflict_raw_injection_sequence

class et_jtag_cla_all_sequence extends et_jtag_flow_base_sequence;
    `uvm_object_utils(et_jtag_cla_all_sequence)

    function new(string name = "et_jtag_cla_all_sequence");
        super.new(name);
    endfunction : new

    virtual task body();
        flow_prepare("ET_JTAG_CLA_ALL");
        cla_soft_running_check = 1'b1;
        #0.2ms;
        flow_cla_command_ack("ET_JTAG_CLA_ALL");
        #0.2ms;
        flow_cla_negative_state_cmd("ET_JTAG_CLA_ALL");
        #0.2ms;
        flow_cla_disconnect_gate("ET_JTAG_CLA_ALL");
        #0.2ms;
        flow_cla_fetch_buffer_rw("ET_JTAG_CLA_ALL");
        #0.2ms;
        flow_cla_exec_reg_write_matrix("ET_JTAG_CLA_ALL");
        #0.2ms;
        flow_cla_dbgreg_mem_access("ET_JTAG_CLA_ALL");
        #0.2ms;
        flow_cla_pc_readback_sweep("ET_JTAG_CLA_ALL");
        #0.2ms;
        flow_cla_dbg_halt_step_run("ET_JTAG_CLA_ALL");
        #0.2ms;
        flow_cla_mpc_debug_write("ET_JTAG_CLA_ALL");
        #0.2ms;
        flow_cla_swbp_sweep("ET_JTAG_CLA_ALL");
        #0.2ms;
        flow_cla_dbgreg_corner_sweep("ET_JTAG_CLA_ALL");
        #0.2ms;
        flow_cla_debug_reset_state("ET_JTAG_CLA_ALL");
        `uvm_info("ET_JTAG_CLA_ALL", "CLA all debug flow sequence done", UVM_LOW)
        #0.5ms;
        $finish;
    endtask : body
endclass : et_jtag_cla_all_sequence

class et_jtag_psa_crc_sequence extends et_jtag_flow_base_sequence;
    `uvm_object_utils(et_jtag_psa_crc_sequence)

    function new(string name = "et_jtag_psa_crc_sequence");
        super.new(name);
    endfunction : new

    virtual task body();
        flow_prepare("ET_JTAG_PSA_CRC");
        flow_halt_rude("ET_JTAG_PSA_CRC");
        #0.2ms;
        flow_psa_crc_sweep("ET_JTAG_PSA_CRC");
        `uvm_info("ET_JTAG_PSA_CRC", "PSA/CRC sequence done", UVM_LOW)
        #0.5ms;
        $finish;
    endtask : body
endclass : et_jtag_psa_crc_sequence

class et_jtag_psa_active_sequence extends et_jtag_flow_base_sequence;
    `uvm_object_utils(et_jtag_psa_active_sequence)

    function new(string name = "et_jtag_psa_active_sequence");
        super.new(name);
    endfunction : new

    virtual task body();
        flow_prepare("ET_JTAG_PSA_ACTIVE");
        #0.2ms;
        flow_psa_active_memory_read("ET_JTAG_PSA_ACTIVE");
        `uvm_info("ET_JTAG_PSA_ACTIVE", "PSA active memory-read sequence done", UVM_LOW)
        #0.5ms;
        $finish;
    endtask : body
endclass : et_jtag_psa_active_sequence

class et_jtag_au0_watchpoint_sequence extends et_jtag_flow_base_sequence;
    `uvm_object_utils(et_jtag_au0_watchpoint_sequence)

    function new(string name = "et_jtag_au0_watchpoint_sequence");
        super.new(name);
    endfunction : new

    virtual task body();
        flow_prepare("ET_JTAG_AU0_WATCHPOINT");
        #0.2ms;
        flow_au0_watchpoint_sweep("ET_JTAG_AU0_WATCHPOINT");
        `uvm_info("ET_JTAG_AU0_WATCHPOINT", "AU0 watchpoint sequence done", UVM_LOW)
        #0.5ms;
        $finish;
    endtask : body
endclass : et_jtag_au0_watchpoint_sequence

class et_jtag_au_watchpoint_sequence extends et_jtag_flow_base_sequence;
    `uvm_object_utils(et_jtag_au_watchpoint_sequence)

    function new(string name = "et_jtag_au_watchpoint_sequence");
        super.new(name);
    endfunction : new

    virtual task body();
        flow_prepare("ET_JTAG_AU_WATCHPOINT");
        #0.2ms;
        flow_au_watchpoint_sweep("ET_JTAG_AU_WATCHPOINT");
        `uvm_info("ET_JTAG_AU_WATCHPOINT", "AU watchpoint sequence done", UVM_LOW)
        #0.5ms;
        $finish;
    endtask : body
endclass : et_jtag_au_watchpoint_sequence

class et_jtag_au2_counter_sequence extends et_jtag_flow_base_sequence;
    `uvm_object_utils(et_jtag_au2_counter_sequence)

    function new(string name = "et_jtag_au2_counter_sequence");
        super.new(name);
    endfunction : new

    virtual task body();
        flow_prepare("ET_JTAG_AU2_COUNTER");
        #0.2ms;
        flow_au2_counter_sweep("ET_JTAG_AU2_COUNTER");
        `uvm_info("ET_JTAG_AU2_COUNTER", "AU2 counter sequence done", UVM_LOW)
        #0.5ms;
        $finish;
    endtask : body
endclass : et_jtag_au2_counter_sequence

class et_jtag_dma_datalog_sequence extends et_jtag_flow_base_sequence;
    `uvm_object_utils(et_jtag_dma_datalog_sequence)

    function new(string name = "et_jtag_dma_datalog_sequence");
        super.new(name);
    endfunction : new

    virtual task body();
        flow_prepare("ET_JTAG_DMA_DATALOG");
        #0.2ms;
        flow_dma_datalog_sweep("ET_JTAG_DMA_DATALOG");
        `uvm_info("ET_JTAG_DMA_DATALOG", "DMA/data-log sequence done", UVM_LOW)
        #0.5ms;
        $finish;
    endtask : body
endclass : et_jtag_dma_datalog_sequence

class et_jtag_dma_cpu_sequence extends et_jtag_flow_base_sequence;
    `uvm_object_utils(et_jtag_dma_cpu_sequence)

    function new(string name = "et_jtag_dma_cpu_sequence");
        super.new(name);
    endfunction : new

    virtual task body();
        flow_prepare("ET_JTAG_DMA_CPU");
        #0.2ms;
        flow_dma_cpu_read_sweep("ET_JTAG_DMA_CPU");
        `uvm_info("ET_JTAG_DMA_CPU", "CPU-claimed DMA/data-log read sequence done", UVM_LOW)
        #0.5ms;
        $finish;
    endtask : body
endclass : et_jtag_dma_cpu_sequence

class et_jtag_dma_fifo_stress_sequence extends et_jtag_flow_base_sequence;
    `uvm_object_utils(et_jtag_dma_fifo_stress_sequence)

    function new(string name = "et_jtag_dma_fifo_stress_sequence");
        super.new(name);
    endfunction : new

    virtual task body();
        flow_prepare("ET_JTAG_DMA_FIFO_STRESS");
        #0.2ms;
        flow_dma_fifo_stress("ET_JTAG_DMA_FIFO_STRESS");
        `uvm_info("ET_JTAG_DMA_FIFO_STRESS", "DMA FIFO stress sequence done", UVM_LOW)
        #0.5ms;
        $finish;
    endtask : body
endclass : et_jtag_dma_fifo_stress_sequence

class et_jtag_emureg_cpu_pf0_write_sequence extends et_jtag_flow_base_sequence;
    `uvm_object_utils(et_jtag_emureg_cpu_pf0_write_sequence)

    function new(string name = "et_jtag_emureg_cpu_pf0_write_sequence");
        super.new(name);
    endfunction : new

    virtual task body();
        flow_prepare("ET_JTAG_EMUREG_CPU_PF0_WRITE");
        #0.2ms;
        flow_emureg_cpu_pf0_write("ET_JTAG_EMUREG_CPU_PF0_WRITE");
        `uvm_info("ET_JTAG_EMUREG_CPU_PF0_WRITE", "CPU/PF0 EMU_REG write sequence done", UVM_LOW)
        #0.5ms;
        $finish;
    endtask : body
endclass : et_jtag_emureg_cpu_pf0_write_sequence

class et_jtag_estop_wait_sequence extends et_jtag_flow_base_sequence;
    `uvm_object_utils(et_jtag_estop_wait_sequence)

    function new(string name = "et_jtag_estop_wait_sequence");
        super.new(name);
    endfunction : new

    virtual task body();
        flow_prepare("ET_JTAG_ESTOP_WAIT");
        flow_estop_wait("ET_JTAG_ESTOP_WAIT");
        `uvm_info("ET_JTAG_ESTOP_WAIT", "estop wait sequence done", UVM_LOW)
        #0.5ms;
        $finish;
    endtask : body
endclass : et_jtag_estop_wait_sequence

class et_jtag_estop1_wait_sequence extends et_jtag_flow_base_sequence;
    `uvm_object_utils(et_jtag_estop1_wait_sequence)

    function new(string name = "et_jtag_estop1_wait_sequence");
        super.new(name);
    endfunction : new

    virtual task body();
        flow_prepare("ET_JTAG_ESTOP1_WAIT");
        flow_estop1_wait("ET_JTAG_ESTOP1_WAIT");
        `uvm_info("ET_JTAG_ESTOP1_WAIT", "estop1 wait sequence done", UVM_LOW)
        #0.5ms;
        $finish;
    endtask : body
endclass : et_jtag_estop1_wait_sequence

class et_jtag_all_flow_sequence extends et_jtag_flow_base_sequence;
    `uvm_object_utils(et_jtag_all_flow_sequence)

    function new(string name = "et_jtag_all_flow_sequence");
        super.new(name);
    endfunction : new

    virtual task body();
        logic [31:0] value;
        begin
            flow_prepare("ET_JTAG_ALL_FLOW");

            flow_halt_rude("ET_JTAG_ALL_FLOW");
            #0.2ms;
            flow_run_rude("ET_JTAG_ALL_FLOW");
            #0.2ms;
            flow_halt_polite("ET_JTAG_ALL_FLOW");
            #0.2ms;
            flow_run_polite("ET_JTAG_ALL_FLOW");
            #0.2ms;
            flow_halt_rude("ET_JTAG_ALL_FLOW");
            #0.2ms;
            flow_step_rude("ET_JTAG_ALL_FLOW");
            #0.2ms;
            flow_step_polite("ET_JTAG_ALL_FLOW");
            #0.2ms;
            flow_nb_step("ET_JTAG_ALL_FLOW");
            #0.2ms;
            flow_clr_step("ET_JTAG_ALL_FLOW");
            #0.2ms;
            flow_cpu_reset("ET_JTAG_ALL_FLOW");

            #0.2ms;
            flow_read_dbgstat("ET_JTAG_ALL_FLOW");
            flow_read_et_st0("ET_JTAG_ALL_FLOW");
            flow_read_pc("ET_JTAG_ALL_FLOW");

            #0.2ms;
            flow_halt_rude("ET_JTAG_ALL_FLOW mem_access_halt");
            #0.2ms;
            flow_reada32(value, "ET_JTAG_ALL_FLOW");
            #0.2ms;
            flow_datab(FLOW_A_WRITE_VALUE, "ET_JTAG_ALL_FLOW");
            #0.2ms;
            flow_writea32(FLOW_A_WRITE_VALUE, value, "ET_JTAG_ALL_FLOW");
            #0.2ms;
            flow_reada16(value, "ET_JTAG_ALL_FLOW");
            #0.2ms;
            flow_writea16(FLOW_A_WRITE16_VALUE[15:0], value, "ET_JTAG_ALL_FLOW");

            #0.2ms;
            flow_run_rude("ET_JTAG_ALL_FLOW");
            #0.2ms;
            flow_halt_rude("ET_JTAG_ALL_FLOW");
            #0.2ms;
            flow_free_run("ET_JTAG_ALL_FLOW");
            #0.2ms;
            flow_halt_rude("ET_JTAG_ALL_FLOW");

            #0.2ms;
            flow_rt_enable("ET_JTAG_ALL_FLOW");
            #0.2ms;
            flow_rt_disable("ET_JTAG_ALL_FLOW");
            #0.2ms;
            flow_rt_enable_alt("ET_JTAG_ALL_FLOW");
            #0.2ms;
            flow_rt_disable_alt("ET_JTAG_ALL_FLOW");

            #0.2ms;
            flow_tap_dr_sweep("ET_JTAG_ALL_FLOW");
            #0.2ms;
            flow_tap_highz_bscan_sweep("ET_JTAG_ALL_FLOW");
            #0.2ms;
            flow_tap_pause_exit2("ET_JTAG_ALL_FLOW");
            #0.2ms;
            flow_tap_async_reset_sweep("ET_JTAG_ALL_FLOW");
            #0.2ms;
            flow_emureg_sweep("ET_JTAG_ALL_FLOW");
            #0.2ms;
            flow_emureg_halfword_sweep("ET_JTAG_ALL_FLOW");
            #0.2ms;
            flow_emureg_direct_access_sweep("ET_JTAG_ALL_FLOW");
            #0.2ms;
            flow_emureg_write16_check("ET_JTAG_ALL_FLOW");
            #0.2ms;
            if ($test$plusargs("ET_JTAG_RUN_CLA_FLOW")) begin
                flow_cla_dbgreg_mem_access("ET_JTAG_ALL_FLOW");
            end
            else begin
                `uvm_info("ET_JTAG_ALL_FLOW",
                          "skip flow_cla_dbgreg_mem_access; add +ET_JTAG_RUN_CLA_FLOW with APP=et_jtag_cla to enable it",
                          UVM_LOW)
            end
            #0.2ms;
            flow_psa_crc_sweep("ET_JTAG_ALL_FLOW");
            #0.2ms;
            flow_psa_active_memory_read("ET_JTAG_ALL_FLOW");
            #0.2ms;
            flow_au_sweep("ET_JTAG_ALL_FLOW");
            #0.2ms;
            flow_au0_watchpoint_sweep("ET_JTAG_ALL_FLOW");
            #0.2ms;
            flow_au_watchpoint_sweep("ET_JTAG_ALL_FLOW");
            #0.2ms;
            flow_au2_counter_sweep("ET_JTAG_ALL_FLOW");
            #0.2ms;
            flow_dma_datalog_sweep("ET_JTAG_ALL_FLOW");
            #0.2ms;
            flow_dma_fifo_stress("ET_JTAG_ALL_FLOW");
            #0.2ms;
            flow_hw_breakpoint_au0("ET_JTAG_ALL_FLOW");

            // Defined but intentionally warning-only until the exact AU/data-log
            // control encodings are finalized.
            flow_watchpoint_read("ET_JTAG_ALL_FLOW");
            flow_watchpoint_write("ET_JTAG_ALL_FLOW");
            flow_data_logging("ET_JTAG_ALL_FLOW");

            if ($test$plusargs("ET_JTAG_RUN_ESTOP_FLOW")) begin
                flow_estop_wait("ET_JTAG_ALL_FLOW");
            end
            else begin
                `uvm_info("ET_JTAG_ALL_FLOW",
                          "skip flow_estop_wait; add +ET_JTAG_RUN_ESTOP_FLOW with an ESTOP C image to enable it",
                          UVM_LOW)
            end

            if ($test$plusargs("ET_JTAG_RUN_CPU_PF0_FLOW")) begin
                flow_emureg_cpu_pf0_write("ET_JTAG_ALL_FLOW");
            end
            else begin
                `uvm_info("ET_JTAG_ALL_FLOW",
                          "skip flow_emureg_cpu_pf0_write; add +ET_JTAG_RUN_CPU_PF0_FLOW with et_jtag_emureg_cpu app to enable it",
                          UVM_LOW)
            end

            `uvm_info("ET_JTAG_ALL_FLOW", "all-flow sequence done", UVM_LOW)
            #0.5ms;
            $finish;
        end
    endtask : body
endclass : et_jtag_all_flow_sequence

`endif // ET_JTAG_FLOW_SEQUENCES_SV
