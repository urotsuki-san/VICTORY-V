`timescale 1ns/1ps

module vv_dual_bringup #(
  parameter integer CLK_HZ = 50_000_000,
  parameter integer UART_BAUD = 115_200,
  parameter integer VV64_RELEASE_CYCLES = 250_000
) (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        uart_rx_i,
  output logic        uart_tx_o,
  output logic [7:0]  led_o,

  output logic [63:0] debug_mailbox32_o,
  output logic [63:0] debug_mailbox64_o,
  output logic        debug_halted32_o,
  output logic        debug_halted64_o,
  output logic [31:0] debug_cause32_o,
  output logic [63:0] debug_cause64_o
);
  localparam logic [63:0] RAM_LIMIT  = 64'h0000_0000_0001_0000;
  localparam logic [63:0] MMIO_BASE  = 64'h0000_0000_0001_0000;
  localparam logic [63:0] UART_TX    = MMIO_BASE + 64'h00;
  localparam logic [63:0] MAILBOX32  = MMIO_BASE + 64'h10;
  localparam logic [63:0] MAILBOX64  = MMIO_BASE + 64'h18;
  localparam logic [63:0] LED_REG    = MMIO_BASE + 64'h20;
  localparam logic [63:0] STATUS_REG = MMIO_BASE + 64'h28;

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

  logic vv64_imem_req;
  logic [63:0] vv64_imem_addr;
  logic [31:0] vv64_imem_rdata;
  logic vv64_imem_ready;
  logic vv64_dmem_req;
  logic vv64_dmem_we;
  logic [63:0] vv64_dmem_addr;
  logic [63:0] vv64_dmem_wdata;
  logic [7:0] vv64_dmem_wstrb;
  logic [63:0] vv64_dmem_rdata;
  logic vv64_dmem_ready;
  logic vv64_halted;
  logic [63:0] vv64_debug_pc;
  logic [63:0] vv64_debug_cause;
  logic [63:0] vv64_debug_error;
  logic vv64_region_active;
  logic vv64_root_locked;
  logic [15:0] vv64_cap_alloc;

  logic vv32_ram_select;
  logic vv64_ram_select;
  logic [31:0] vv32_ram_rdata;
  logic [63:0] vv64_ram_rdata;
  logic vv32_ram_ready;
  logic vv64_ram_ready;

  logic [31:0] vv32_mmio_rdata;
  logic [63:0] vv64_mmio_rdata;
  logic vv32_mmio_ready;
  logic vv64_mmio_ready;

  logic [63:0] mailbox32_q;
  logic [63:0] mailbox64_q;
  logic [31:0] led32_q;
  logic [63:0] led64_q;

  logic uart_req32;
  logic uart_req64;
  logic uart_grant32;
  logic uart_grant64;
  logic uart_valid;
  logic [7:0] uart_data;
  logic uart_ready;
  logic uart_busy;
  logic uart_round_robin_q;

  logic vv64_release_q;
  logic [31:0] vv64_release_counter_q;
  wire vv64_rst_ni = rst_ni && vv64_release_q;
  wire unused_uart_rx = uart_rx_i;

  vv32_bringup_rom u_vv32_rom (
    .addr_i ({32'd0, vv32_imem_addr}),
    .data_o (vv32_imem_rdata)
  );

  vv64_bringup_rom u_vv64_rom (
    .addr_i (vv64_imem_addr),
    .data_o (vv64_imem_rdata)
  );

  assign vv32_imem_ready = vv32_imem_req;
  assign vv64_imem_ready = vv64_imem_req;

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

  vv64_core #(
    .RESET_PC (64'h0000_0000_0000_0000),
    .DATA_MEMORY_BYTES (64'd131072),
    .STORE_BUFFER_DEPTH (8),
    .CAP_DIRECTORY_ENTRIES (32)
  ) u_vv64 (
    .clk_i (clk_i),
    .rst_ni (vv64_rst_ni),
    .imem_req_o (vv64_imem_req),
    .imem_addr_o (vv64_imem_addr),
    .imem_rdata_i (vv64_imem_rdata),
    .imem_ready_i (vv64_imem_ready),
    .dmem_req_o (vv64_dmem_req),
    .dmem_we_o (vv64_dmem_we),
    .dmem_addr_o (vv64_dmem_addr),
    .dmem_wdata_o (vv64_dmem_wdata),
    .dmem_wstrb_o (vv64_dmem_wstrb),
    .dmem_rdata_i (vv64_dmem_rdata),
    .dmem_ready_i (vv64_dmem_ready),
    .irq_i (1'b0),
    .halted_o (vv64_halted),
    .debug_pc_o (vv64_debug_pc),
    .debug_cause_o (vv64_debug_cause),
    .debug_error_o (vv64_debug_error),
    .debug_region_active_o (vv64_region_active),
    .debug_root_locked_o (vv64_root_locked),
    .debug_cap_alloc_o (vv64_cap_alloc)
  );

  assign vv32_ram_select = vv32_dmem_req && ({32'd0, vv32_dmem_addr} < RAM_LIMIT);
  assign vv64_ram_select = vv64_dmem_req && (vv64_dmem_addr < RAM_LIMIT);

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
  ) u_vv64_ram (
    .clk_i (clk_i),
    .rst_ni (vv64_rst_ni),
    .req_i (vv64_ram_select),
    .we_i (vv64_dmem_we),
    .addr_i (vv64_dmem_addr),
    .wdata_i (vv64_dmem_wdata),
    .wstrb_i (vv64_dmem_wstrb),
    .rdata_o (vv64_ram_rdata),
    .ready_o (vv64_ram_ready)
  );

  assign uart_req32 = vv32_dmem_req && vv32_dmem_we &&
                      ({32'd0, vv32_dmem_addr} == UART_TX) && (vv32_dmem_wstrb != 4'd0);
  assign uart_req64 = vv64_dmem_req && vv64_dmem_we &&
                      (vv64_dmem_addr == UART_TX) && (vv64_dmem_wstrb != 8'd0);

  always_comb begin
    uart_grant32 = 1'b0;
    uart_grant64 = 1'b0;
    if (uart_req32 && uart_req64) begin
      if (uart_round_robin_q)
        uart_grant64 = 1'b1;
      else
        uart_grant32 = 1'b1;
    end else if (uart_req32) begin
      uart_grant32 = 1'b1;
    end else if (uart_req64) begin
      uart_grant64 = 1'b1;
    end
  end

  assign uart_valid = uart_grant32 || uart_grant64;
  assign uart_data = uart_grant64 ? vv64_dmem_wdata[7:0] : vv32_dmem_wdata[7:0];

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

  always_comb begin
    vv32_mmio_ready = 1'b0;
    vv32_mmio_rdata = 32'd0;
    if (vv32_dmem_req && !vv32_ram_select) begin
      case ({32'd0, vv32_dmem_addr})
        UART_TX: begin
          vv32_mmio_ready = vv32_dmem_we ? (uart_grant32 && uart_ready) : 1'b1;
          vv32_mmio_rdata = {31'd0, uart_ready};
        end
        MAILBOX32: begin
          vv32_mmio_ready = 1'b1;
          vv32_mmio_rdata = mailbox32_q[31:0];
        end
        MAILBOX64: begin
          vv32_mmio_ready = 1'b1;
          vv32_mmio_rdata = mailbox64_q[31:0];
        end
        LED_REG: begin
          vv32_mmio_ready = 1'b1;
          vv32_mmio_rdata = led32_q;
        end
        STATUS_REG: begin
          vv32_mmio_ready = 1'b1;
          vv32_mmio_rdata = {24'd0, led_o};
        end
        default: begin
          vv32_mmio_ready = 1'b1;
          vv32_mmio_rdata = 32'd0;
        end
      endcase
    end
  end

  always_comb begin
    vv64_mmio_ready = 1'b0;
    vv64_mmio_rdata = 64'd0;
    if (vv64_dmem_req && !vv64_ram_select) begin
      case (vv64_dmem_addr)
        UART_TX: begin
          vv64_mmio_ready = vv64_dmem_we ? (uart_grant64 && uart_ready) : 1'b1;
          vv64_mmio_rdata = {63'd0, uart_ready};
        end
        MAILBOX32: begin
          vv64_mmio_ready = 1'b1;
          vv64_mmio_rdata = mailbox32_q;
        end
        MAILBOX64: begin
          vv64_mmio_ready = 1'b1;
          vv64_mmio_rdata = mailbox64_q;
        end
        LED_REG: begin
          vv64_mmio_ready = 1'b1;
          vv64_mmio_rdata = led64_q;
        end
        STATUS_REG: begin
          vv64_mmio_ready = 1'b1;
          vv64_mmio_rdata = {56'd0, led_o};
        end
        default: begin
          vv64_mmio_ready = 1'b1;
          vv64_mmio_rdata = 64'd0;
        end
      endcase
    end
  end

  assign vv32_dmem_ready = vv32_ram_select ? vv32_ram_ready : vv32_mmio_ready;
  assign vv64_dmem_ready = vv64_ram_select ? vv64_ram_ready : vv64_mmio_ready;
  assign vv32_dmem_rdata = vv32_ram_select ? vv32_ram_rdata : vv32_mmio_rdata;
  assign vv64_dmem_rdata = vv64_ram_select ? vv64_ram_rdata : vv64_mmio_rdata;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      mailbox32_q <= 64'd0;
      mailbox64_q <= 64'd0;
      led32_q <= 32'd0;
      led64_q <= 64'd0;
      uart_round_robin_q <= 1'b0;
      vv64_release_q <= 1'b0;
      vv64_release_counter_q <= 32'd0;
    end else begin
      if (uart_valid && uart_ready)
        uart_round_robin_q <= uart_grant32;

      if (!vv64_release_q) begin
        if ((mailbox32_q[7:0] == 8'h32) ||
            (vv64_release_counter_q + 32'd1 >= VV64_RELEASE_CYCLES)) begin
          vv64_release_q <= 1'b1;
        end else begin
          vv64_release_counter_q <= vv64_release_counter_q + 32'd1;
        end
      end

      if (vv32_dmem_req && vv32_mmio_ready && vv32_dmem_we) begin
        case ({32'd0, vv32_dmem_addr})
          MAILBOX32: begin
            if (vv32_dmem_wstrb[0]) mailbox32_q[7:0] <= vv32_dmem_wdata[7:0];
            if (vv32_dmem_wstrb[1]) mailbox32_q[15:8] <= vv32_dmem_wdata[15:8];
            if (vv32_dmem_wstrb[2]) mailbox32_q[23:16] <= vv32_dmem_wdata[23:16];
            if (vv32_dmem_wstrb[3]) mailbox32_q[31:24] <= vv32_dmem_wdata[31:24];
          end
          MAILBOX64: begin
            if (vv32_dmem_wstrb[0]) mailbox64_q[7:0] <= vv32_dmem_wdata[7:0];
            if (vv32_dmem_wstrb[1]) mailbox64_q[15:8] <= vv32_dmem_wdata[15:8];
            if (vv32_dmem_wstrb[2]) mailbox64_q[23:16] <= vv32_dmem_wdata[23:16];
            if (vv32_dmem_wstrb[3]) mailbox64_q[31:24] <= vv32_dmem_wdata[31:24];
          end
          LED_REG: begin
            if (vv32_dmem_wstrb[0]) led32_q[7:0] <= vv32_dmem_wdata[7:0];
            if (vv32_dmem_wstrb[1]) led32_q[15:8] <= vv32_dmem_wdata[15:8];
            if (vv32_dmem_wstrb[2]) led32_q[23:16] <= vv32_dmem_wdata[23:16];
            if (vv32_dmem_wstrb[3]) led32_q[31:24] <= vv32_dmem_wdata[31:24];
          end
          default: ;
        endcase
      end

      if (vv64_dmem_req && vv64_mmio_ready && vv64_dmem_we) begin
        case (vv64_dmem_addr)
          MAILBOX32: begin
            if (vv64_dmem_wstrb[0]) mailbox32_q[7:0] <= vv64_dmem_wdata[7:0];
            if (vv64_dmem_wstrb[1]) mailbox32_q[15:8] <= vv64_dmem_wdata[15:8];
            if (vv64_dmem_wstrb[2]) mailbox32_q[23:16] <= vv64_dmem_wdata[23:16];
            if (vv64_dmem_wstrb[3]) mailbox32_q[31:24] <= vv64_dmem_wdata[31:24];
            if (vv64_dmem_wstrb[4]) mailbox32_q[39:32] <= vv64_dmem_wdata[39:32];
            if (vv64_dmem_wstrb[5]) mailbox32_q[47:40] <= vv64_dmem_wdata[47:40];
            if (vv64_dmem_wstrb[6]) mailbox32_q[55:48] <= vv64_dmem_wdata[55:48];
            if (vv64_dmem_wstrb[7]) mailbox32_q[63:56] <= vv64_dmem_wdata[63:56];
          end
          MAILBOX64: begin
            if (vv64_dmem_wstrb[0]) mailbox64_q[7:0] <= vv64_dmem_wdata[7:0];
            if (vv64_dmem_wstrb[1]) mailbox64_q[15:8] <= vv64_dmem_wdata[15:8];
            if (vv64_dmem_wstrb[2]) mailbox64_q[23:16] <= vv64_dmem_wdata[23:16];
            if (vv64_dmem_wstrb[3]) mailbox64_q[31:24] <= vv64_dmem_wdata[31:24];
            if (vv64_dmem_wstrb[4]) mailbox64_q[39:32] <= vv64_dmem_wdata[39:32];
            if (vv64_dmem_wstrb[5]) mailbox64_q[47:40] <= vv64_dmem_wdata[47:40];
            if (vv64_dmem_wstrb[6]) mailbox64_q[55:48] <= vv64_dmem_wdata[55:48];
            if (vv64_dmem_wstrb[7]) mailbox64_q[63:56] <= vv64_dmem_wdata[63:56];
          end
          LED_REG: begin
            if (vv64_dmem_wstrb[0]) led64_q[7:0] <= vv64_dmem_wdata[7:0];
            if (vv64_dmem_wstrb[1]) led64_q[15:8] <= vv64_dmem_wdata[15:8];
            if (vv64_dmem_wstrb[2]) led64_q[23:16] <= vv64_dmem_wdata[23:16];
            if (vv64_dmem_wstrb[3]) led64_q[31:24] <= vv64_dmem_wdata[31:24];
            if (vv64_dmem_wstrb[4]) led64_q[39:32] <= vv64_dmem_wdata[39:32];
            if (vv64_dmem_wstrb[5]) led64_q[47:40] <= vv64_dmem_wdata[47:40];
            if (vv64_dmem_wstrb[6]) led64_q[55:48] <= vv64_dmem_wdata[55:48];
            if (vv64_dmem_wstrb[7]) led64_q[63:56] <= vv64_dmem_wdata[63:56];
          end
          default: ;
        endcase
      end
    end
  end

  always_comb begin
    led_o[0] = (mailbox32_q[7:0] == 8'h32);
    led_o[1] = (mailbox64_q[7:0] == 8'h64);
    led_o[2] = vv32_halted;
    led_o[3] = vv64_halted;
    led_o[4] = vv32_root_locked;
    led_o[5] = vv64_root_locked;
    led_o[6] = (vv32_debug_cause != 32'd0) || (vv64_debug_cause != 64'd0);
    led_o[7] = uart_busy;
  end

  assign debug_mailbox32_o = mailbox32_q;
  assign debug_mailbox64_o = mailbox64_q;
  assign debug_halted32_o = vv32_halted;
  assign debug_halted64_o = vv64_halted;
  assign debug_cause32_o = vv32_debug_cause;
  assign debug_cause64_o = vv64_debug_cause;
endmodule
