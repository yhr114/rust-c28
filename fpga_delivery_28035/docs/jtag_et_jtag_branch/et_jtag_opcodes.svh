`ifndef ET_JTAG_OPCODES_SVH
`define ET_JTAG_OPCODES_SVH

localparam bit [37:0] ET_JTAG_IR_BYPASS       = 38'h3F_FFFF_FFFF;
localparam bit [37:0] ET_JTAG_CMD_HALT_RUDE   = 38'h3B_0000_80FF;
localparam bit [37:0] ET_JTAG_CMD_HALT_POLITE = 38'h3B_0000_80DF;
localparam bit [37:0] ET_JTAG_CMD_STEP_RUDE   = 38'h3B_0000_81FF;
localparam bit [37:0] ET_JTAG_CMD_STEP_POLITE = 38'h3B_0000_81DF;
localparam bit [37:0] ET_JTAG_CMD_RUN_RUDE    = 38'h3B_0000_86FF;
localparam bit [37:0] ET_JTAG_CMD_RUN_POLITE  = 38'h3B_0000_86DF;
localparam bit [37:0] ET_JTAG_CMD_FREE_RUN    = 38'h3B_0000_87FF;
localparam bit [37:0] ET_JTAG_CMD_RT_ENABLE   = 38'h3B_0000_00DF;
localparam bit [37:0] ET_JTAG_CMD_RT_DISABLE  = 38'h3B_0000_00FF;
localparam bit [37:0] ET_JTAG_CMD_SET_RESET   = 38'h3D_0000_0060;
localparam bit [37:0] ET_JTAG_CMD_RESET_STEP  = 38'h3B_0000_85FF;
localparam bit [37:0] ET_JTAG_CMD_RT_ENABLE_ALT  = 38'h3D_0000_0003;
localparam bit [37:0] ET_JTAG_CMD_RT_DISABLE_ALT = 38'h3D_0000_0002;

localparam bit [37:0] ET_JTAG_IR_EXTEST        = {6'h00, 32'h0000_0000};
localparam bit [37:0] ET_JTAG_IR_PRELOAD       = {6'h01, 32'h0000_0000};
localparam bit [37:0] ET_JTAG_IR_IDCODE        = {6'h04, 32'h0000_0000};
localparam bit [37:0] ET_JTAG_IR_HIGHZ         = {6'h05, 32'h0000_0000};
localparam bit [37:0] ET_JTAG_IR_TESTMODE      = {6'h06, 32'h0000_0000};
localparam bit [37:0] ET_JTAG_IR_DC_STRBS      = {6'h3E, 32'h0000_00AA};

localparam bit [5:0]  ET_JTAG_IR_WRITEA16_OP  = 6'h31;
localparam bit [5:0]  ET_JTAG_IR_WRITEA32_OP  = 6'h32;
localparam bit [5:0]  ET_JTAG_IR_DATAB_OP     = 6'h33;
localparam bit [5:0]  ET_JTAG_IR_READA16_OP   = 6'h35;
localparam bit [5:0]  ET_JTAG_IR_READA32_OP   = 6'h36;
localparam bit [5:0]  ET_JTAG_IR_DMA_WDATA_OP = 6'h3C;
localparam bit [5:0]  ET_JTAG_IR_DLOG_RCMD0_OP = 6'h38;
localparam bit [5:0]  ET_JTAG_IR_DLOG_RCMD1_OP = 6'h39;
localparam bit [5:0]  ET_JTAG_IR_DLOG_RCMD2_OP = 6'h3A;

`endif // ET_JTAG_OPCODES_SVH
