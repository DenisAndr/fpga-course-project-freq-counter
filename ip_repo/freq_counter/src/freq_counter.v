`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// freq_counter -- частотомір: рахує передні фронти зовнішнього сигналу sig_in
// за вимірювальне вікно, задане в тактах. Регістровий інтерфейс AXI4-Lite.
//
// Регістри (32 біти, зсув від базової адреси):
//   0x00 WINDOW  запис/читання  тривалість вікна в тактах, [31:0]
//   0x04 CTRL    запис          запис 1 у розряд [0] запускає вимірювання
//                               (читання дає 0; запис під час вимірювання ігнорується)
//   0x08 COUNT   читання        кількість фронтів за останнє завершене вікно
//   0x0C STATUS  читання        [0] = 1: вимірювання завершене, COUNT дійсний
// Запис у COUNT/STATUS ігнорується (відповідь OKAY).
//
// Поведінка:
//   - вікно = рівно WINDOW тактів s_axi_aclk, починається на такт після запуску;
//   - STATUS=0 від запуску до кінця вікна; COUNT не змінюється до наступного
//     завершеного вимірювання;
//   - sig_in асинхронний -> 2-ступеневий синхронізатор, потім детектор фронту:
//     один широкий імпульс дає один фронт;
//   - WINDOW=0: вимірювання завершується одразу, COUNT=0, STATUS=1.
// Обчислення частоти (COUNT / тривалість вікна) виконує програма на C.
//////////////////////////////////////////////////////////////////////////////

module freq_counter (
    // ---- AXI4-Lite slave (тактовий вхід clk = s_axi_aclk) ----
    input  wire        s_axi_aclk,
    input  wire        s_axi_aresetn,

    input  wire [3:0]  s_axi_awaddr,
    input  wire        s_axi_awvalid,
    output wire        s_axi_awready,

    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output wire        s_axi_wready,

    output wire [1:0]  s_axi_bresp,
    output wire        s_axi_bvalid,
    input  wire        s_axi_bready,

    input  wire [3:0]  s_axi_araddr,
    input  wire        s_axi_arvalid,
    output wire        s_axi_arready,

    output wire [31:0] s_axi_rdata,
    output wire [1:0]  s_axi_rresp,
    output wire        s_axi_rvalid,
    input  wire        s_axi_rready,

    // ---- вимірюваний сигнал (зовнішній, асинхронний) ----
    input  wire        sig_in
);

    wire clk    = s_axi_aclk;
    wire resetn = s_axi_aresetn;

    // ------------------------------------------------------------------
    // Запис по AXI4-Lite: канали AW і W можуть приходити в будь-якому порядку,
    // тож кожен запам'ятовується окремо; запис виконується, коли є обидва.
    // ------------------------------------------------------------------
    reg         aw_got, w_got, bvalid;
    reg  [3:0]  awaddr_q;
    reg  [31:0] wdata_q;
    reg  [3:0]  wstrb_q;
    wire        do_write = aw_got && w_got && !bvalid;

    assign s_axi_awready = !aw_got && !bvalid;
    assign s_axi_wready  = !w_got  && !bvalid;
    assign s_axi_bvalid  = bvalid;
    assign s_axi_bresp   = 2'b00;

    always @(posedge clk) begin
        if (!resetn) begin
            aw_got <= 1'b0;
            w_got  <= 1'b0;
            bvalid <= 1'b0;
        end else begin
            if (s_axi_awvalid && s_axi_awready) begin
                aw_got   <= 1'b1;
                awaddr_q <= s_axi_awaddr;
            end
            if (s_axi_wvalid && s_axi_wready) begin
                w_got   <= 1'b1;
                wdata_q <= s_axi_wdata;
                wstrb_q <= s_axi_wstrb;
            end
            if (do_write) begin
                aw_got <= 1'b0;
                w_got  <= 1'b0;
                bvalid <= 1'b1;
            end else if (bvalid && s_axi_bready) begin
                bvalid <= 1'b0;
            end
        end
    end

    // ---- регістри ----
    reg  [31:0] window;          // 0x00
    // запуск: запис 1 у CTRL[0]; діє в тому ж такті, що й запис (STATUS скидається одразу)
    wire        start_now = do_write && (awaddr_q[3:2] == 2'd1) && wstrb_q[0] && wdata_q[0];
    reg  [31:0] count;           // 0x08
    reg         status;          // 0x0C [0]

    always @(posedge clk) begin
        if (!resetn) begin
            window <= 32'd0;
        end else begin
            if (do_write) begin
                case (awaddr_q[3:2])
                    2'd0: begin
                        if (wstrb_q[0]) window[7:0]   <= wdata_q[7:0];
                        if (wstrb_q[1]) window[15:8]  <= wdata_q[15:8];
                        if (wstrb_q[2]) window[23:16] <= wdata_q[23:16];
                        if (wstrb_q[3]) window[31:24] <= wdata_q[31:24];
                    end
                    default: ;                         // CTRL (див. start_now), COUNT, STATUS
                endcase
            end
        end
    end

    // ------------------------------------------------------------------
    // Читання по AXI4-Lite
    // ------------------------------------------------------------------
    reg         rvalid;
    reg  [31:0] rdata;

    assign s_axi_arready = !rvalid;
    assign s_axi_rvalid  = rvalid;
    assign s_axi_rdata   = rdata;
    assign s_axi_rresp   = 2'b00;

    always @(posedge clk) begin
        if (!resetn) begin
            rvalid <= 1'b0;
            rdata  <= 32'd0;
        end else begin
            if (s_axi_arvalid && s_axi_arready) begin
                rvalid <= 1'b1;
                case (s_axi_araddr[3:2])
                    2'd0:    rdata <= window;
                    2'd1:    rdata <= 32'd0;           // CTRL -- лише запис
                    2'd2:    rdata <= count;
                    default: rdata <= {31'd0, status};
                endcase
            end else if (rvalid && s_axi_rready) begin
                rvalid <= 1'b0;
            end
        end
    end

    // ------------------------------------------------------------------
    // Вхід sig_in: 2-ступеневий синхронізатор + детектор переднього фронту
    // ------------------------------------------------------------------
    (* ASYNC_REG = "TRUE" *) reg sync1, sync2;
    reg sync3;
    always @(posedge clk) begin
        if (!resetn) begin
            sync1 <= 1'b0;
            sync2 <= 1'b0;
            sync3 <= 1'b0;
        end else begin
            sync1 <= sig_in;
            sync2 <= sync1;
            sync3 <= sync2;
        end
    end
    wire rise = sync2 & ~sync3;                         // 0 -> 1 один такт

    // ------------------------------------------------------------------
    // Вимірювання
    // ------------------------------------------------------------------
    reg         busy;
    reg  [31:0] win_cnt;
    reg  [31:0] edge_cnt;

    always @(posedge clk) begin
        if (!resetn) begin
            busy     <= 1'b0;
            win_cnt  <= 32'd0;
            edge_cnt <= 32'd0;
            count    <= 32'd0;
            status   <= 1'b0;
        end else if (start_now && !busy) begin
            if (window == 32'd0) begin
                count  <= 32'd0;                        // нульове вікно: одразу готово
                status <= 1'b1;
            end else begin
                busy     <= 1'b1;
                status   <= 1'b0;
                win_cnt  <= window;
                edge_cnt <= 32'd0;
            end
        end else if (busy) begin
            if (rise) edge_cnt <= edge_cnt + 32'd1;
            win_cnt <= win_cnt - 32'd1;
            if (win_cnt == 32'd1) begin                 // останній такт вікна
                busy   <= 1'b0;
                count  <= edge_cnt + {31'd0, rise};     // з урахуванням фронту цього такту
                status <= 1'b1;
            end
        end
    end

endmodule
