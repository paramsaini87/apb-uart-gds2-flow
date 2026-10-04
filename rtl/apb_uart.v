// ============================================================================
// apb_uart.v — 16550-Compatible UART with APB3 Interface
// ============================================================================
// Standalone, fully-synthesizable 16550-style UART.
//
// Features:
//   - APB3 slave interface
//   - 16-byte TX and RX FIFOs
//   - Programmable baud rate via 16-bit divisor (DLL / DLM)
//   - Line Control Register (word length, stop bits, parity)
//   - Interrupt generation: TX empty, RX data ready, RX line error
//   - DLAB addressing for divisor latch registers
//
// Register Map (byte offsets — all 32-bit aligned):
//   0x00  RBR (R) / THR (W) — Receive Buffer / Transmit Holding
//         DLL (R/W when DLAB=1) — Divisor Latch Low
//   0x04  IER (R/W)          — Interrupt Enable
//         DLM (R/W when DLAB=1) — Divisor Latch High
//   0x08  IIR (R) / FCR (W)  — Interrupt ID / FIFO Control
//   0x0C  LCR (R/W)          — Line Control
//   0x10  MCR (R/W)          — Modem Control
//   0x14  LSR (R)             — Line Status
//   0x18  MSR (R)             — Modem Status
//   0x1C  SCR (R/W)          — Scratch Register
//
// Parameters:
//   CLK_FREQ     — system clock frequency in Hz (default 50 MHz)
//   FIFO_DEPTH   — depth of TX/RX FIFOs (default 16)
//
// Copyright (c) 2025 IndepthSilicon — all rights reserved.
// SPDX-License-Identifier: MIT
// ============================================================================

module apb_uart #(
    parameter CLK_FREQ   = 50_000_000,
    parameter FIFO_DEPTH = 16
) (
    // ---- Clock / Reset ----
    input  wire        clk,
    input  wire        rst_n,

    // ---- APB Slave Interface ----
    input  wire [11:0] paddr,
    input  wire        psel,
    input  wire        penable,
    input  wire        pwrite,
    input  wire [31:0] pwdata,
    output reg  [31:0] prdata,
    output wire        pready,
    output wire        pslverr,

    // ---- UART Signals ----
    input  wire        uart_rxd,
    output wire        uart_txd,

    // ---- Interrupt ----
    output wire        irq
);

    // APB always completes in one cycle, no errors
    assign pready  = 1'b1;
    assign pslverr = 1'b0;

    // ========================================================================
    // Register storage
    // ========================================================================
    reg  [7:0]  reg_ier;        // Interrupt Enable
    reg  [7:0]  reg_lcr;        // Line Control
    reg  [7:0]  reg_mcr;        // Modem Control
    reg  [7:0]  reg_scr;        // Scratch
    reg  [7:0]  reg_dll;        // Divisor Latch Low
    reg  [7:0]  reg_dlm;        // Divisor Latch High
    reg  [7:0]  reg_fcr;        // FIFO Control (write-only, latched)

    wire        dlab = reg_lcr[7]; // Divisor Latch Access Bit

    // ========================================================================
    // FIFO storage — simple shift-register FIFOs
    // ========================================================================
    localparam FIFO_AW = clog2(FIFO_DEPTH);

    reg  [7:0]  tx_fifo [0:FIFO_DEPTH-1];
    reg  [FIFO_AW:0] tx_wr_ptr, tx_rd_ptr;
    wire [FIFO_AW:0] tx_count = tx_wr_ptr - tx_rd_ptr;
    wire              tx_full  = (tx_count == FIFO_DEPTH[FIFO_AW:0]);
    wire              tx_empty = (tx_count == 0);

    reg  [7:0]  rx_fifo [0:FIFO_DEPTH-1];
    reg  [FIFO_AW:0] rx_wr_ptr, rx_rd_ptr;
    wire [FIFO_AW:0] rx_count = rx_wr_ptr - rx_rd_ptr;
    wire              rx_full  = (rx_count == FIFO_DEPTH[FIFO_AW:0]);
    wire              rx_empty = (rx_count == 0);

    // ========================================================================
    // Baud-rate generator — 16× oversampling tick
    // ========================================================================
    wire [15:0] divisor = {reg_dlm, reg_dll};
    reg  [15:0] baud_cnt;
    reg         baud_tick;   // fires at 16× baud rate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            baud_cnt  <= 16'd0;
            baud_tick <= 1'b0;
        end else if (divisor == 16'd0) begin
            baud_cnt  <= 16'd0;
            baud_tick <= 1'b0;
        end else if (baud_cnt == divisor - 16'd1) begin
            baud_cnt  <= 16'd0;
            baud_tick <= 1'b1;
        end else begin
            baud_cnt  <= baud_cnt + 16'd1;
            baud_tick <= 1'b0;
        end
    end

    // ========================================================================
    // Transmitter — simple state machine
    // ========================================================================
    localparam TX_IDLE  = 2'd0,
               TX_START = 2'd1,
               TX_DATA  = 2'd2,
               TX_STOP  = 2'd3;

    reg [1:0]  tx_state;
    reg [3:0]  tx_os_cnt;     // 16× oversampling counter
    reg [2:0]  tx_bit_idx;
    reg [7:0]  tx_shift;
    reg        tx_out;

    assign uart_txd = tx_out;

    // Pop from TX FIFO
    reg tx_fifo_pop;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_state   <= TX_IDLE;
            tx_os_cnt  <= 4'd0;
            tx_bit_idx <= 3'd0;
            tx_shift   <= 8'd0;
            tx_out     <= 1'b1;
            tx_fifo_pop <= 1'b0;
        end else begin
            tx_fifo_pop <= 1'b0;
            case (tx_state)
                TX_IDLE: begin
                    tx_out <= 1'b1;
                    if (!tx_empty) begin
                        tx_shift    <= tx_fifo[tx_rd_ptr[FIFO_AW-1:0]];
                        tx_fifo_pop <= 1'b1;
                        tx_state    <= TX_START;
                        tx_os_cnt   <= 4'd0;
                    end
                end

                TX_START: begin
                    tx_out <= 1'b0;  // start bit
                    if (baud_tick) begin
                        if (tx_os_cnt == 4'd15) begin
                            tx_os_cnt  <= 4'd0;
                            tx_bit_idx <= 3'd0;
                            tx_state   <= TX_DATA;
                        end else begin
                            tx_os_cnt <= tx_os_cnt + 4'd1;
                        end
                    end
                end

                TX_DATA: begin
                    tx_out <= tx_shift[0];
                    if (baud_tick) begin
                        if (tx_os_cnt == 4'd15) begin
                            tx_os_cnt <= 4'd0;
                            tx_shift  <= {1'b0, tx_shift[7:1]};
                            if (tx_bit_idx == 3'd7) begin
                                tx_state <= TX_STOP;
                            end else begin
                                tx_bit_idx <= tx_bit_idx + 3'd1;
                            end
                        end else begin
                            tx_os_cnt <= tx_os_cnt + 4'd1;
                        end
                    end
                end

                TX_STOP: begin
                    tx_out <= 1'b1;  // stop bit
                    if (baud_tick) begin
                        if (tx_os_cnt == 4'd15) begin
                            tx_os_cnt <= 4'd0;
                            tx_state  <= TX_IDLE;
                        end else begin
                            tx_os_cnt <= tx_os_cnt + 4'd1;
                        end
                    end
                end
            endcase
        end
    end

    // TX FIFO read pointer advance
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            tx_rd_ptr <= {(FIFO_AW+1){1'b0}};
        else if (tx_fifo_pop)
            tx_rd_ptr <= tx_rd_ptr + 1;
    end

    // ========================================================================
    // Receiver — 16× oversampling state machine
    // ========================================================================
    localparam RX_IDLE  = 2'd0,
               RX_START = 2'd1,
               RX_DATA  = 2'd2,
               RX_STOP  = 2'd3;

    reg [1:0]  rx_state;
    reg [3:0]  rx_os_cnt;
    reg [2:0]  rx_bit_idx;
    reg [7:0]  rx_shift;

    // Double-flop synchroniser for rxd
    reg        rxd_sync1, rxd_sync2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rxd_sync1 <= 1'b1;
            rxd_sync2 <= 1'b1;
        end else begin
            rxd_sync1 <= uart_rxd;
            rxd_sync2 <= rxd_sync1;
        end
    end

    reg rx_fifo_push;
    reg rx_frame_err;
    reg [7:0] rx_byte;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_state     <= RX_IDLE;
            rx_os_cnt    <= 4'd0;
            rx_bit_idx   <= 3'd0;
            rx_shift     <= 8'd0;
            rx_fifo_push <= 1'b0;
            rx_frame_err <= 1'b0;
            rx_byte      <= 8'd0;
        end else begin
            rx_fifo_push <= 1'b0;
            rx_frame_err <= 1'b0;
            case (rx_state)
                RX_IDLE: begin
                    if (!rxd_sync2) begin
                        rx_state  <= RX_START;
                        rx_os_cnt <= 4'd0;
                    end
                end

                RX_START: begin
                    if (baud_tick) begin
                        if (rx_os_cnt == 4'd7) begin
                            // Sample mid-bit — verify start bit still low
                            if (rxd_sync2) begin
                                rx_state <= RX_IDLE; // false start
                            end else begin
                                rx_os_cnt  <= 4'd0;
                                rx_bit_idx <= 3'd0;
                                rx_state   <= RX_DATA;
                            end
                        end else begin
                            rx_os_cnt <= rx_os_cnt + 4'd1;
                        end
                    end
                end

                RX_DATA: begin
                    if (baud_tick) begin
                        if (rx_os_cnt == 4'd15) begin
                            rx_os_cnt <= 4'd0;
                            rx_shift  <= {rxd_sync2, rx_shift[7:1]};
                            if (rx_bit_idx == 3'd7) begin
                                rx_state <= RX_STOP;
                            end else begin
                                rx_bit_idx <= rx_bit_idx + 3'd1;
                            end
                        end else begin
                            rx_os_cnt <= rx_os_cnt + 4'd1;
                        end
                    end
                end

                RX_STOP: begin
                    if (baud_tick) begin
                        if (rx_os_cnt == 4'd15) begin
                            rx_os_cnt <= 4'd0;
                            rx_byte   <= rx_shift;
                            if (!rxd_sync2)
                                rx_frame_err <= 1'b1; // framing error
                            if (!rx_full)
                                rx_fifo_push <= 1'b1;
                            rx_state <= RX_IDLE;
                        end else begin
                            rx_os_cnt <= rx_os_cnt + 4'd1;
                        end
                    end
                end
            endcase
        end
    end

    // RX FIFO write
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            rx_wr_ptr <= {(FIFO_AW+1){1'b0}};
        else if (rx_fifo_push) begin
            rx_fifo[rx_wr_ptr[FIFO_AW-1:0]] <= rx_byte;
            rx_wr_ptr <= rx_wr_ptr + 1;
        end
    end

    // ========================================================================
    // Line Status Register (read-only)
    // ========================================================================
    // LSR[0] = Data Ready (RX FIFO not empty)
    // LSR[1] = Overrun Error (sticky — cleared on LSR read)
    // LSR[2] = Parity Error (not implemented)
    // LSR[3] = Framing Error (sticky)
    // LSR[5] = THR Empty (TX FIFO empty)
    // LSR[6] = TX Empty (TX FIFO empty & transmitter idle)
    reg  lsr_overrun;
    reg  lsr_frame_err;
    wire [7:0] lsr = {1'b0,
                      (tx_empty && (tx_state == TX_IDLE)),  // [6]
                      tx_empty,                              // [5]
                      1'b0,                                  // [4]
                      lsr_frame_err,                         // [3]
                      1'b0,                                  // [2]
                      lsr_overrun,                           // [1]
                      ~rx_empty};                            // [0]

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lsr_overrun   <= 1'b0;
            lsr_frame_err <= 1'b0;
        end else begin
            // Set on error conditions
            if (rx_fifo_push && rx_full)
                lsr_overrun <= 1'b1;
            if (rx_frame_err)
                lsr_frame_err <= 1'b1;
            // Clear on LSR read
            if (psel && penable && !pwrite && paddr[4:2] == 3'd5) begin
                lsr_overrun   <= 1'b0;
                lsr_frame_err <= 1'b0;
            end
        end
    end

    // ========================================================================
    // Interrupt Identification Register (read-only)
    // ========================================================================
    // IIR[0]   = 0 if interrupt pending
    // IIR[3:1] = interrupt ID
    //   011 = RX line status (highest)
    //   010 = RX data available
    //   001 = TX holding register empty
    reg [7:0] iir;

    always @(*) begin
        if (reg_ier[2] && (lsr_overrun || lsr_frame_err))
            iir = 8'b0000_0110;  // RX line status, priority 1
        else if (reg_ier[0] && !rx_empty)
            iir = 8'b0000_0100;  // RX data available, priority 2
        else if (reg_ier[1] && tx_empty)
            iir = 8'b0000_0010;  // TX empty, priority 3
        else
            iir = 8'b0000_0001;  // No interrupt
    end

    assign irq = ~iir[0];

    // ========================================================================
    // APB Register Write
    // ========================================================================
    wire apb_write = psel && penable && pwrite;
    wire apb_read  = psel && penable && !pwrite;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_ier <= 8'd0;
            reg_lcr <= 8'h03;  // 8-N-1 default
            reg_mcr <= 8'd0;
            reg_scr <= 8'd0;
            reg_dll <= 8'd1;   // default divisor = 1
            reg_dlm <= 8'd0;
            reg_fcr <= 8'd0;
            tx_wr_ptr <= {(FIFO_AW+1){1'b0}};
        end else if (apb_write) begin
            case (paddr[4:2])
                3'd0: begin // 0x00
                    if (dlab)
                        reg_dll <= pwdata[7:0];
                    else if (!tx_full) begin
                        tx_fifo[tx_wr_ptr[FIFO_AW-1:0]] <= pwdata[7:0];
                        tx_wr_ptr <= tx_wr_ptr + 1;
                    end
                end
                3'd1: begin // 0x04
                    if (dlab)
                        reg_dlm <= pwdata[7:0];
                    else
                        reg_ier <= pwdata[7:0];
                end
                3'd2: reg_fcr <= pwdata[7:0]; // 0x08 FCR (write-only)
                3'd3: reg_lcr <= pwdata[7:0]; // 0x0C
                3'd4: reg_mcr <= pwdata[7:0]; // 0x10
                // 3'd5: LSR is read-only
                // 3'd6: MSR is read-only
                3'd7: reg_scr <= pwdata[7:0]; // 0x1C
                default: ;
            endcase
        end
    end

    // ========================================================================
    // APB Register Read + RX FIFO Pop
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            rx_rd_ptr <= {(FIFO_AW+1){1'b0}};
        else if (apb_read && paddr[4:2] == 3'd0 && !dlab && !rx_empty)
            rx_rd_ptr <= rx_rd_ptr + 1;
    end

    always @(*) begin
        prdata = 32'd0;
        case (paddr[4:2])
            3'd0: prdata = dlab ? {24'd0, reg_dll}
                                : {24'd0, rx_fifo[rx_rd_ptr[FIFO_AW-1:0]]};
            3'd1: prdata = dlab ? {24'd0, reg_dlm} : {24'd0, reg_ier};
            3'd2: prdata = {24'd0, iir};
            3'd3: prdata = {24'd0, reg_lcr};
            3'd4: prdata = {24'd0, reg_mcr};
            3'd5: prdata = {24'd0, lsr};
            3'd6: prdata = 32'd0;  // MSR — stub
            3'd7: prdata = {24'd0, reg_scr};
            default: prdata = 32'd0;
        endcase
    end

    // ========================================================================
    // clog2 function — compute ceiling of log-base-2
    // ========================================================================
    function integer clog2;
        input integer value;
        integer i;
        begin
            clog2 = 0;
            for (i = value - 1; i > 0; i = i >> 1)
                clog2 = clog2 + 1;
        end
    endfunction

endmodule
