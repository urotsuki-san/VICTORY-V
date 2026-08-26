`timescale 1ns/1ps

module vv_cluster_bringup #(
  parameter integer CLK_HZ = 50_000_000,
  parameter integer UART_BAUD = 115_200,
  parameter integer P_RELEASE_CYCLES = 250_000,
  parameter integer E_RELEASE_CYCLES = 250_000
) (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        uart_rx_i,
  output logic        uart_tx_o,
  output logic [7:0]  led_o,

  output logic [63:0] debug_mailbox32_o,
  output logic [63:0] debug_mailbox_p_o,
  output logic [63:0] debug_mailbox_e_o,
  output logic        debug_halted32_o,
  output logic        debug_halted_p_o,
  output logic        debug_halted_e_o,
  output logic [31:0] debug_cause32_o,
  output logic [63:0] debug_cause_p_o,
  output logic [63:0] debug_cause_e_o,
  output logic        debug_p_released_o,
  output logic        debug_e_released_o
);
  localparam logic [63:0] RAM_LIMIT       = 64'h0000_0000_0001_0000;
  localparam logic [63:0] MMIO_BASE       = 64'h0000_0000_0001_0000;
  localparam logic [63:0] UART_TX         = MMIO_BASE + 64'h00;
  localparam logic [63:0] MAILBOX32       = MMIO_BASE + 64'h10;
  localparam logic [63:0] MAILBOX_P       = MMIO_BASE + 64'h18;
  localparam logic [63:0] MAILBOX_E       = MMIO_BASE + 64'h20;
  localparam logic [63:0] LED_REG         = MMIO_BASE + 64'h28;
  localparam logic [63:0] STATUS_REG      = MMIO_BASE + 64'h30;
  localparam logic [63:0] TIMEBASE_REG    = MMIO_BASE + 64'h38;
  localparam logic [63:0] TIMER_P_REG     = MMIO_BASE + 64'h40;
  localparam logic [63:0] TIMER_E_REG     = MMIO_BASE + 64'h48;
  localparam logic [63:0] IPI_SET_REG     = MMIO_BASE + 64'h50;
  localparam logic [63:0] IPI_CLEAR_REG   = MMIO_BASE + 64'h58;
  localparam logic [63:0] CORE_INFO_REG   = MMIO_BASE + 64'h60;

  localparam logic [63:0] CORE_INFO_VV32 = 64'h0000_0000_0020_3200;
  localparam logic [63:0] CORE_INFO_P    = 64'h0000_0000_0040_5001;
  localparam logic [63:0] CORE_INFO_E    = 64'h0000_0000_0040_4502;

  logic vv32_imem_req;
  logic [31:0] vv32_imem_addr;
  logic [31:0] vv32_imem_rdata;
  logic vv32_imem_ready;
  logic vv32_dmem_req;
  logic vv32_dmem_we;
  logic [31:0] vv32_dmem_addr;
  logic [31:0] vv32_dmem_wdata;
  logic [3:0] vv32_dmem_wstrb;
  logic [31:0] vv32_dmem_rdata;
  logic vv32_dmem_ready;
  logic vv32_halted;
  logic [31:0] vv32_debug_pc;
  logic [31:0] vv32_debug_cause;
  logic [31:0] vv32_debug_error;
  logic vv32_region_active;
  logic vv32_root_locked;

  logic p_imem_req;
  logic [63:0] p_imem_addr;
  logic [31:0] p_imem_rdata;
  logic p_imem_ready;
  logic p_dmem_req;
  logic p_dmem_we;
  logic [63:0] p_dmem_addr;
  logic [63:0] p_dmem_wdata;
  logic [7:0] p_dmem_wstrb;
  logic [63:0] p_dmem_rdata;
  logic p_dmem_ready;
  logic p_halted;
  logic [63:0] p_debug_pc;
  logic [63:0] p_debug_cause;
  logic [63:0] p_debug_error;
  logic p_region_active;
  logic p_root_locked;
  logic [15:0] p_cap_alloc;
  logic p_profile;

  logic e_imem_req;
  logic [63:0] e_imem_addr;
  logic [31:0] e_imem_rdata;
  logic e_imem_ready;
  logic e_dmem_req;
  logic e_dmem_we;
  logic [63:0] e_dmem_addr;
  logic [63:0] e_dmem_wdata;
  logic [7:0] e_dmem_wstrb;
  logic [63:0] e_dmem_rdata;
  logic e_dmem_ready;
  logic e_halted;
  logic [63:0] e_debug_pc;
  logic [63:0] e_debug_cause;
  logic [63:0] e_debug_error;
  logic e_region_active;
  logic e_root_locked;
  logic [15:0] e_cap_alloc;
  logic e_profile;

  logic vv32_ram_select;
  logic p_ram_select;
  logic e_ram_select;
  logic [31:0] vv32_ram_rdata;
  logic [63:0] p_ram_rdata;
  logic [63:0] e_ram_rdata;
  logic vv32_ram_ready;
  logic p_ram_ready;
  logic e_ram_ready;

  logic [31:0] vv32_mmio_rdata;
  logic [63:0] p_mmio_rdata;
  logic [63:0] e_mmio_rdata;
  logic vv32_mmio_ready;
  logic p_mmio_ready;
  logic e_mmio_ready;

  logic [63:0] mailbox32_q;
  logic [63:0] mailbox_p_q;
  logic [63:0] mailbox_e_q;
  logic [63:0] led_reg_q;

  logic [63:0] timebase_q;
  logic [63:0] timer_compare_p_q;
  logic [63:0] timer_compare_e_q;
  logic ipi_pending_p_q;
  logic ipi_pending_e_q;
  logic timer_pending_p;
  logic timer_pending_e;

  logic uart_req32;
  logic uart_req_p;
  logic uart_req_e;
  logic uart_grant32;
  logic uart_grant_p;
  logic uart_grant_e;
  logic uart_valid;
  logic [7:0] uart_data;
  logic uart_ready;
  logic uart_busy;
  logic [1:0] uart_last_q;

  logic p_release_q;
  logic e_release_q;
  logic [31:0] p_release_counter_q;
  logic [31:0] e_release_counter_q;

  wire p_rst_ni = rst_ni && p_release_q;
  wire e_rst_ni = rst_ni && e_release_q;
  wire p_irq = ipi_pending_p_q || timer_pending_p;
  wire e_irq = ipi_pending_e_q || timer_pending_e;
  wire unused_uart_rx = uart_rx_i;

  function automatic logic [63:0] merge64(
    input logic [63:0] old_value,
    input logic [63:0] new_value,
    input logic [7:0] strobe
  );
    integer byte_index;
    begin
      merge64 = old_value;
      for (byte_index = 0; byte_index < 8; byte_index = byte_index + 1) begin
        if (strobe[byte_index])
          merge64[byte_index*8 +: 8] = new_value[byte_index*8 +: 8];
      end
    end
  endfunction

  function automatic logic [63:0] merge32(
    input logic [63:0] old_value,
    input logic [31:0] new_value,
    input logic [3:0] strobe
  );
    integer byte_index;
    begin
      merge32 = old_value;
      for (byte_index = 0; byte_index < 4; byte_index = byte_index + 1) begin
        if (strobe[byte_index])
          merge32[byte_index*8 +: 8] = new_value[byte_index*8 +: 8];
      end
    end
  endfunction

  vv32_bringup_rom u_vv32_rom (
    .addr_i ({32'd0, vv32_imem_addr}),
    .data_o (vv32_imem_rdata)
  );

  vv64_p_bringup_rom u_p_rom (
    .addr_i (p_imem_addr),
    .data_o (p_imem_rdata)
  );

  vv64_e_bringup_rom u_e_rom (
    .addr_i (e_imem_addr),
    .data_o (e_imem_rdata)
  );

  assign vv32_imem_ready = vv32_imem_req;
  assign p_imem_ready = p_imem_req;
  assign e_imem_ready = e_imem_req;

  vv32_core #(
    .RESET_PC (32'h0000_0000),
    .DATA_MEMORY_BYTES (131072),
    .STORE_BUFFER_DEPTH (8)
  ) u_vv32 (
    .clk_i (clk_i),
    .rst_ni (rst_ni),
    .imem_req_o (vv32_imem_req),
    .imem_addr_o (vv32_imem_addr),
    .imem_rdata_i (vv32_imem_rdata),
    .imem_ready_i (vv32_imem_ready),
    .dmem_req_o (vv32_dmem_req),
    .dmem_we_o (vv32_dmem_we),
    .dmem_addr_o (vv32_dmem_addr),
    .dmem_wdata_o (vv32_dmem_wdata),
    .dmem_wstrb_o (vv32_dmem_wstrb),
    .dmem_rdata_i (vv32_dmem_rdata),
    .dmem_ready_i (vv32_dmem_ready),
    .irq_i (1'b0),
    .halted_o (vv32_halted),
    .debug_pc_o (vv32_debug_pc),
    .debug_cause_o (vv32_debug_cause),
    .debug_error_o (vv32_debug_error),
    .debug_region_active_o (vv32_region_active),
    .debug_root_locked_o (vv32_root_locked)
  );

  vv64_profiled_core #(
    .RESET_PC (64'h0000_0000_0000_0000),
    .DATA_MEMORY_BYTES (64'd131072),
    .PERFORMANCE_PROFILE (1'b1)
  ) u_vv64_p (
    .clk_i (clk_i),
    .rst_ni (p_rst_ni),
    .imem_req_o (p_imem_req),
    .imem_addr_o (p_imem_addr),
    .imem_rdata_i (p_imem_rdata),
    .imem_ready_i (p_imem_ready),
    .dmem_req_o (p_dmem_req),
    .dmem_we_o (p_dmem_we),
    .dmem_addr_o (p_dmem_addr),
    .dmem_wdata_o (p_dmem_wdata),
    .dmem_wstrb_o (p_dmem_wstrb),
    .dmem_rdata_i (p_dmem_rdata),
    .dmem_ready_i (p_dmem_ready),
    .irq_i (p_irq),
    .halted_o (p_halted),
    .debug_pc_o (p_debug_pc),
    .debug_cause_o (p_debug_cause),
    .debug_error_o (p_debug_error),
    .debug_region_active_o (p_region_active),
    .debug_root_locked_o (p_root_locked),
    .debug_cap_alloc_o (p_cap_alloc),
    .performance_profile_o (p_profile)
  );

  vv64_profiled_core #(
    .RESET_PC (64'h0000_0000_0000_0000),
    .DATA_MEMORY_BYTES (64'd131072),
    .PERFORMANCE_PROFILE (1'b0)
  ) u_vv64_e (
    .clk_i (clk_i),
    .rst_ni (e_rst_ni),
    .imem_req_o (e_imem_req),
    .imem_addr_o (e_imem_addr),
    .imem_rdata_i (e_imem_rdata),
    .imem_ready_i (e_imem_ready),
    .dmem_req_o (e_dmem_req),
    .dmem_we_o (e_dmem_we),
    .dmem_addr_o (e_dmem_addr),
    .dmem_wdata_o (e_dmem_wdata),
    .dmem_wstrb_o (e_dmem_wstrb),
    .dmem_rdata_i (e_dmem_rdata),
    .dmem_ready_i (e_dmem_ready),
    .irq_i (e_irq),
    .halted_o (e_halted),
    .debug_pc_o (e_debug_pc),
    .debug_cause_o (e_debug_cause),
    .debug_error_o (e_debug_error),
    .debug_region_active_o (e_region_active),
    .debug_root_locked_o (e_root_locked),
    .debug_cap_alloc_o (e_cap_alloc),
    .performance_profile_o (e_profile)
  );

  assign vv32_ram_select = vv32_dmem_req && ({32'd0, vv32_dmem_addr} < RAM_LIMIT);
  assign p_ram_select = p_dmem_req && (p_dmem_addr < RAM_LIMIT);
  assign e_ram_select = e_dmem_req && (e_dmem_addr < RAM_LIMIT);

  vv_sram #(
    .DATA_WIDTH (32),
    .ADDR_WIDTH (16)
  ) u_vv32_ram (
    .clk_i (clk_i),
    .rst_ni (rst_ni),
    .req_i (vv32_ram_select),
    .we_i (vv32_dmem_we),
    .addr_i ({32'd0, vv32_dmem_addr}),
    .wdata_i (vv32_dmem_wdata),
    .wstrb_i (vv32_dmem_wstrb),
    .rdata_o (vv32_ram_rdata),
    .ready_o (vv32_ram_ready)
  );

  vv_sram #(
    .DATA_WIDTH (64),
    .ADDR_WIDTH (16)
  ) u_p_ram (
    .clk_i (clk_i),
    .rst_ni (p_rst_ni),
    .req_i (p_ram_select),
    .we_i (p_dmem_we),
    .addr_i (p_dmem_addr),
    .wdata_i (p_dmem_wdata),
    .wstrb_i (p_dmem_wstrb),
    .rdata_o (p_ram_rdata),
    .ready_o (p_ram_ready)
  );

  vv_sram #(
    .DATA_WIDTH (64),
    .ADDR_WIDTH (16)
  ) u_e_ram (
    .clk_i (clk_i),
    .rst_ni (e_rst_ni),
    .req_i (e_ram_select),
    .we_i (e_dmem_we),
    .addr_i (e_dmem_addr),
    .wdata_i (e_dmem_wdata),
    .wstrb_i (e_dmem_wstrb),
    .rdata_o (e_ram_rdata),
    .ready_o (e_ram_ready)
  );

  assign uart_req32 = vv32_dmem_req && vv32_dmem_we &&
                      ({32'd0, vv32_dmem_addr} == UART_TX) && (vv32_dmem_wstrb != 4'd0);
  assign uart_req_p = p_dmem_req && p_dmem_we &&
                      (p_dmem_addr == UART_TX) && (p_dmem_wstrb != 8'd0);
  assign uart_req_e = e_dmem_req && e_dmem_we &&
                      (e_dmem_addr == UART_TX) && (e_dmem_wstrb != 8'd0);

  always_comb begin
    uart_grant32 = 1'b0;
    uart_grant_p = 1'b0;
    uart_grant_e = 1'b0;

    case (uart_last_q)
      2'd0: begin
        if (uart_req_p) uart_grant_p = 1'b1;
        else if (uart_req_e) uart_grant_e = 1'b1;
        else if (uart_req32) uart_grant32 = 1'b1;
      end
      2'd1: begin
        if (uart_req_e) uart_grant_e = 1'b1;
        else if (uart_req32) uart_grant32 = 1'b1;
        else if (uart_req_p) uart_grant_p = 1'b1;
      end
      default: begin
        if (uart_req32) uart_grant32 = 1'b1;
        else if (uart_req_p) uart_grant_p = 1'b1;
        else if (uart_req_e) uart_grant_e = 1'b1;
      end
    endcase
  end

  assign uart_valid = uart_grant32 || uart_grant_p || uart_grant_e;
  assign uart_data = uart_grant_p ? p_dmem_wdata[7:0] :
                     uart_grant_e ? e_dmem_wdata[7:0] : vv32_dmem_wdata[7:0];

  vv_uart_tx #(
    .CLK_HZ (CLK_HZ),
    .BAUD (UART_BAUD)
  ) u_uart_tx (
    .clk_i (clk_i),
    .rst_ni (rst_ni),
    .valid_i (uart_valid),
    .data_i (uart_data),
    .ready_o (uart_ready),
    .tx_o (uart_tx_o),
    .busy_o (uart_busy)
  );

  assign timer_pending_p = (timer_compare_p_q != 64'hffff_ffff_ffff_ffff) &&
                           (timebase_q >= timer_compare_p_q);
  assign timer_pending_e = (timer_compare_e_q != 64'hffff_ffff_ffff_ffff) &&
                           (timebase_q >= timer_compare_e_q);

  always_comb begin
    vv32_mmio_ready = 1'b0;
    vv32_mmio_rdata = 32'd0;
    if (vv32_dmem_req && !vv32_ram_select) begin
      vv32_mmio_ready = 1'b1;
      case ({32'd0, vv32_dmem_addr})
        UART_TX: begin
          vv32_mmio_ready = vv32_dmem_we ? (uart_grant32 && uart_ready) : 1'b1;
          vv32_mmio_rdata = {31'd0, uart_ready};
        end
        MAILBOX32: vv32_mmio_rdata = mailbox32_q[31:0];
        MAILBOX_P: vv32_mmio_rdata = mailbox_p_q[31:0];
        MAILBOX_E: vv32_mmio_rdata = mailbox_e_q[31:0];
        LED_REG: vv32_mmio_rdata = led_reg_q[31:0];
        STATUS_REG: vv32_mmio_rdata = {15'd0, timer_pending_e, timer_pending_p,
                                       ipi_pending_e_q, ipi_pending_p_q,
                                       e_release_q, p_release_q,
                                       e_root_locked, p_root_locked, vv32_root_locked,
                                       led_o};
        TIMEBASE_REG: vv32_mmio_rdata = timebase_q[31:0];
        TIMER_P_REG: vv32_mmio_rdata = timer_compare_p_q[31:0];
        TIMER_E_REG: vv32_mmio_rdata = timer_compare_e_q[31:0];
        CORE_INFO_REG: vv32_mmio_rdata = CORE_INFO_VV32[31:0];
        default: vv32_mmio_rdata = 32'd0;
      endcase
    end
  end

  always_comb begin
    p_mmio_ready = 1'b0;
    p_mmio_rdata = 64'd0;
    if (p_dmem_req && !p_ram_select) begin
      p_mmio_ready = 1'b1;
      case (p_dmem_addr)
        UART_TX: begin
          p_mmio_ready = p_dmem_we ? (uart_grant_p && uart_ready) : 1'b1;
          p_mmio_rdata = {63'd0, uart_ready};
        end
        MAILBOX32: p_mmio_rdata = mailbox32_q;
        MAILBOX_P: p_mmio_rdata = mailbox_p_q;
        MAILBOX_E: p_mmio_rdata = mailbox_e_q;
        LED_REG: p_mmio_rdata = led_reg_q;
        STATUS_REG: p_mmio_rdata = {47'd0, timer_pending_e, timer_pending_p,
                                    ipi_pending_e_q, ipi_pending_p_q,
                                    e_release_q, p_release_q,
                                    e_root_locked, p_root_locked, vv32_root_locked,
                                    led_o};
        TIMEBASE_REG: p_mmio_rdata = timebase_q;
        TIMER_P_REG: p_mmio_rdata = timer_compare_p_q;
        TIMER_E_REG: p_mmio_rdata = timer_compare_e_q;
        CORE_INFO_REG: p_mmio_rdata = CORE_INFO_P;
        default: p_mmio_rdata = 64'd0;
      endcase
    end
  end

  always_comb begin
    e_mmio_ready = 1'b0;
    e_mmio_rdata = 64'd0;
    if (e_dmem_req && !e_ram_select) begin
      e_mmio_ready = 1'b1;
      case (e_dmem_addr)
        UART_TX: begin
          e_mmio_ready = e_dmem_we ? (uart_grant_e && uart_ready) : 1'b1;
          e_mmio_rdata = {63'd0, uart_ready};
        end
        MAILBOX32: e_mmio_rdata = mailbox32_q;
        MAILBOX_P: e_mmio_rdata = mailbox_p_q;
        MAILBOX_E: e_mmio_rdata = mailbox_e_q;
        LED_REG: e_mmio_rdata = led_reg_q;
        STATUS_REG: e_mmio_rdata = {47'd0, timer_pending_e, timer_pending_p,
                                    ipi_pending_e_q, ipi_pending_p_q,
                                    e_release_q, p_release_q,
                                    e_root_locked, p_root_locked, vv32_root_locked,
                                    led_o};
        TIMEBASE_REG: e_mmio_rdata = timebase_q;
        TIMER_P_REG: e_mmio_rdata = timer_compare_p_q;
        TIMER_E_REG: e_mmio_rdata = timer_compare_e_q;
        CORE_INFO_REG: e_mmio_rdata = CORE_INFO_E;
        default: e_mmio_rdata = 64'd0;
      endcase
    end
  end

  assign vv32_dmem_ready = vv32_ram_select ? vv32_ram_ready : vv32_mmio_ready;
  assign p_dmem_ready = p_ram_select ? p_ram_ready : p_mmio_ready;
  assign e_dmem_ready = e_ram_select ? e_ram_ready : e_mmio_ready;
  assign vv32_dmem_rdata = vv32_ram_select ? vv32_ram_rdata : vv32_mmio_rdata;
  assign p_dmem_rdata = p_ram_select ? p_ram_rdata : p_mmio_rdata;
  assign e_dmem_rdata = e_ram_select ? e_ram_rdata : e_mmio_rdata;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      mailbox32_q <= 64'd0;
      mailbox_p_q <= 64'd0;
      mailbox_e_q <= 64'd0;
      led_reg_q <= 64'd0;
      timebase_q <= 64'd0;
      timer_compare_p_q <= 64'hffff_ffff_ffff_ffff;
      timer_compare_e_q <= 64'hffff_ffff_ffff_ffff;
      ipi_pending_p_q <= 1'b0;
      ipi_pending_e_q <= 1'b0;
      uart_last_q <= 2'd2;
      p_release_q <= 1'b0;
      e_release_q <= 1'b0;
      p_release_counter_q <= 32'd0;
      e_release_counter_q <= 32'd0;
    end else begin
      timebase_q <= timebase_q + 64'd1;

      if (uart_valid && uart_ready) begin
        if (uart_grant32) uart_last_q <= 2'd0;
        else if (uart_grant_p) uart_last_q <= 2'd1;
        else uart_last_q <= 2'd2;
      end

      if (!p_release_q) begin
        if ((mailbox32_q[7:0] == 8'h32) ||
            (p_release_counter_q + 32'd1 >= P_RELEASE_CYCLES)) begin
          p_release_q <= 1'b1;
        end else begin
          p_release_counter_q <= p_release_counter_q + 32'd1;
        end
      end

      if (!e_release_q && p_release_q) begin
        if ((mailbox_p_q[7:0] == 8'h50) ||
            (e_release_counter_q + 32'd1 >= E_RELEASE_CYCLES)) begin
          e_release_q <= 1'b1;
        end else begin
          e_release_counter_q <= e_release_counter_q + 32'd1;
        end
      end

      if (vv32_dmem_req && vv32_mmio_ready && vv32_dmem_we) begin
        case ({32'd0, vv32_dmem_addr})
          MAILBOX32: mailbox32_q <= merge32(mailbox32_q, vv32_dmem_wdata, vv32_dmem_wstrb);
          MAILBOX_P: mailbox_p_q <= merge32(mailbox_p_q, vv32_dmem_wdata, vv32_dmem_wstrb);
          MAILBOX_E: mailbox_e_q <= merge32(mailbox_e_q, vv32_dmem_wdata, vv32_dmem_wstrb);
          LED_REG: led_reg_q <= merge32(led_reg_q, vv32_dmem_wdata, vv32_dmem_wstrb);
          TIMER_P_REG: timer_compare_p_q <= merge32(timer_compare_p_q, vv32_dmem_wdata, vv32_dmem_wstrb);
          TIMER_E_REG: timer_compare_e_q <= merge32(timer_compare_e_q, vv32_dmem_wdata, vv32_dmem_wstrb);
          IPI_SET_REG: begin
            if (vv32_dmem_wdata[0]) ipi_pending_p_q <= 1'b1;
            if (vv32_dmem_wdata[1]) ipi_pending_e_q <= 1'b1;
          end
          IPI_CLEAR_REG: begin
            if (vv32_dmem_wdata[0]) ipi_pending_p_q <= 1'b0;
            if (vv32_dmem_wdata[1]) ipi_pending_e_q <= 1'b0;
          end
          default: ;
        endcase
      end

      if (p_dmem_req && p_mmio_ready && p_dmem_we) begin
        case (p_dmem_addr)
          MAILBOX32: mailbox32_q <= merge64(mailbox32_q, p_dmem_wdata, p_dmem_wstrb);
          MAILBOX_P: mailbox_p_q <= merge64(mailbox_p_q, p_dmem_wdata, p_dmem_wstrb);
          MAILBOX_E: mailbox_e_q <= merge64(mailbox_e_q, p_dmem_wdata, p_dmem_wstrb);
          LED_REG: led_reg_q <= merge64(led_reg_q, p_dmem_wdata, p_dmem_wstrb);
          TIMER_P_REG: timer_compare_p_q <= merge64(timer_compare_p_q, p_dmem_wdata, p_dmem_wstrb);
          TIMER_E_REG: timer_compare_e_q <= merge64(timer_compare_e_q, p_dmem_wdata, p_dmem_wstrb);
          IPI_SET_REG: begin
            if (p_dmem_wdata[0]) ipi_pending_p_q <= 1'b1;
            if (p_dmem_wdata[1]) ipi_pending_e_q <= 1'b1;
          end
          IPI_CLEAR_REG: begin
            if (p_dmem_wdata[0]) ipi_pending_p_q <= 1'b0;
            if (p_dmem_wdata[1]) ipi_pending_e_q <= 1'b0;
          end
          default: ;
        endcase
      end

      if (e_dmem_req && e_mmio_ready && e_dmem_we) begin
        case (e_dmem_addr)
          MAILBOX32: mailbox32_q <= merge64(mailbox32_q, e_dmem_wdata, e_dmem_wstrb);
          MAILBOX_P: mailbox_p_q <= merge64(mailbox_p_q, e_dmem_wdata, e_dmem_wstrb);
          MAILBOX_E: mailbox_e_q <= merge64(mailbox_e_q, e_dmem_wdata, e_dmem_wstrb);
          LED_REG: led_reg_q <= merge64(led_reg_q, e_dmem_wdata, e_dmem_wstrb);
          TIMER_P_REG: timer_compare_p_q <= merge64(timer_compare_p_q, e_dmem_wdata, e_dmem_wstrb);
          TIMER_E_REG: timer_compare_e_q <= merge64(timer_compare_e_q, e_dmem_wdata, e_dmem_wstrb);
          IPI_SET_REG: begin
            if (e_dmem_wdata[0]) ipi_pending_p_q <= 1'b1;
            if (e_dmem_wdata[1]) ipi_pending_e_q <= 1'b1;
          end
          IPI_CLEAR_REG: begin
            if (e_dmem_wdata[0]) ipi_pending_p_q <= 1'b0;
            if (e_dmem_wdata[1]) ipi_pending_e_q <= 1'b0;
          end
          default: ;
        endcase
      end
    end
  end

  always_comb begin
    led_o[0] = (mailbox32_q[7:0] == 8'h32);
    led_o[1] = (mailbox_p_q[7:0] == 8'h50);
    led_o[2] = (mailbox_e_q[7:0] == 8'h45);
    led_o[3] = vv32_halted;
    led_o[4] = p_halted;
    led_o[5] = e_halted;
    led_o[6] = (vv32_debug_cause != 32'd0) ||
               (p_debug_cause != 64'd0) ||
               (e_debug_cause != 64'd0);
    led_o[7] = uart_busy;
  end

  assign debug_mailbox32_o = mailbox32_q;
  assign debug_mailbox_p_o = mailbox_p_q;
  assign debug_mailbox_e_o = mailbox_e_q;
  assign debug_halted32_o = vv32_halted;
  assign debug_halted_p_o = p_halted;
  assign debug_halted_e_o = e_halted;
  assign debug_cause32_o = vv32_debug_cause;
  assign debug_cause_p_o = p_debug_cause;
  assign debug_cause_e_o = e_debug_cause;
  assign debug_p_released_o = p_release_q;
  assign debug_e_released_o = e_release_q;
endmodule
