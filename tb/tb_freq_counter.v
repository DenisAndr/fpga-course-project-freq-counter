`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// Тестбенч модуля freq_counter (без процесора): сам грає AXI4-Lite master,
// сам генерує sig_in, сам звіряє результат і друкує PASS / FAIL.
//
// ОЧІКУВАНІ ЗНАЧЕННЯ (пораховані вручну ДО запуску, див. також README):
//   T1  період 100 тактів, вікно 1000 тактів   -> COUNT = 1000 / 100 = 10 (рівно)
//   T2  період 40 тактів,  вікно 2000 тактів   -> COUNT = 2000 / 40  = 50 (рівно)
//   T3  період 100 тактів, вікно 250 тактів    -> COUNT = 2 або 3 (250 / 100 = 2,5):
//        якщо перший фронт потрапляє в перші ~50 тактів вікна -> 3 фронти
//        (p, p+100, p+200 < 250), якщо пізніше -> 2 фронти. Допустима множина {2, 3}.
//   T4  вікно 0 (граничний випадок)            -> STATUS = 1 одразу, COUNT = 0
//   T5  широкий імпульс: період 600, висока 400, вікно 1200 -> COUNT = 2 (по одному
//        на імпульс; лічильник рівня дав би ~800)
//   T6  під час вимірювання STATUS = 0, COUNT незмінний (лишається 2 з T5);
//        повторний запис у CTRL ігнорується; після завершення COUNT = 20
//        (період 100, вікно 2000) і вимірювання триває ~2000 тактів, а не довше
//   T7  після завершення COUNT і STATUS стабільні при повторних читаннях
//
// Параметр BROKEN=1 підставляє зламану копію freq_counter_broken (крок 3).
//////////////////////////////////////////////////////////////////////////////

module tb_freq_core #(
    parameter BROKEN = 0
);

    // ---------- такт, скидання ----------
    reg clk = 1'b0;
    always #5 clk = ~clk;                       // 100 МГц
    reg resetn = 1'b0;

    integer cyc = 0;                            // лічильник тактів для вимірювання часу
    always @(posedge clk) cyc <= cyc + 1;

    // ---------- сигнали AXI4-Lite ----------
    reg  [3:0]  awaddr  = 4'd0;
    reg         awvalid = 1'b0;
    wire        awready;
    reg  [31:0] wdata   = 32'd0;
    reg  [3:0]  wstrb   = 4'd0;
    reg         wvalid  = 1'b0;
    wire        wready;
    wire [1:0]  bresp;
    wire        bvalid;
    reg         bready  = 1'b0;
    reg  [3:0]  araddr  = 4'd0;
    reg         arvalid = 1'b0;
    wire        arready;
    wire [31:0] rdata;
    wire [1:0]  rresp;
    wire        rvalid;
    reg         rready  = 1'b0;
    reg         sig_in  = 1'b0;

    generate
        if (BROKEN) begin : g_dut
            freq_counter_broken dut (
                .s_axi_aclk(clk), .s_axi_aresetn(resetn),
                .s_axi_awaddr(awaddr), .s_axi_awvalid(awvalid), .s_axi_awready(awready),
                .s_axi_wdata(wdata), .s_axi_wstrb(wstrb), .s_axi_wvalid(wvalid), .s_axi_wready(wready),
                .s_axi_bresp(bresp), .s_axi_bvalid(bvalid), .s_axi_bready(bready),
                .s_axi_araddr(araddr), .s_axi_arvalid(arvalid), .s_axi_arready(arready),
                .s_axi_rdata(rdata), .s_axi_rresp(rresp), .s_axi_rvalid(rvalid), .s_axi_rready(rready),
                .sig_in(sig_in)
            );
        end else begin : g_dut
            freq_counter dut (
                .s_axi_aclk(clk), .s_axi_aresetn(resetn),
                .s_axi_awaddr(awaddr), .s_axi_awvalid(awvalid), .s_axi_awready(awready),
                .s_axi_wdata(wdata), .s_axi_wstrb(wstrb), .s_axi_wvalid(wvalid), .s_axi_wready(wready),
                .s_axi_bresp(bresp), .s_axi_bvalid(bvalid), .s_axi_bready(bready),
                .s_axi_araddr(araddr), .s_axi_arvalid(arvalid), .s_axi_arready(arready),
                .s_axi_rdata(rdata), .s_axi_rresp(rresp), .s_axi_rvalid(rvalid), .s_axi_rready(rready),
                .sig_in(sig_in)
            );
        end
    endgenerate

    // ---------- AXI4-Lite master: запис ----------
    task axi_write;
        input [3:0]  addr;
        input [31:0] data;
        reg     aw_done, w_done, b_done;
        integer guard;
        begin
            @(posedge clk); #1;
            awaddr = addr; awvalid = 1'b1;
            wdata  = data; wstrb = 4'hF; wvalid = 1'b1;
            bready = 1'b1;
            aw_done = 1'b0; w_done = 1'b0; b_done = 1'b0;
            guard = 0;
            while (!(aw_done && w_done) && guard < 100) begin
                @(posedge clk);
                if (awvalid && awready) aw_done = 1'b1;
                if (wvalid  && wready)  w_done  = 1'b1;
                #1;
                if (aw_done) awvalid = 1'b0;
                if (w_done)  wvalid  = 1'b0;
                guard = guard + 1;
            end
            guard = 0;
            while (!b_done && guard < 100) begin
                @(posedge clk);
                if (bvalid && bready) b_done = 1'b1;
                guard = guard + 1;
            end
            #1; bready = 1'b0;
        end
    endtask

    // ---------- AXI4-Lite master: читання ----------
    task axi_read;
        input  [3:0]  addr;
        output [31:0] data;
        reg     ar_done, r_done;
        integer guard;
        begin
            @(posedge clk); #1;
            araddr = addr; arvalid = 1'b1; rready = 1'b1;
            ar_done = 1'b0; r_done = 1'b0; guard = 0;
            while (!ar_done && guard < 100) begin
                @(posedge clk);
                if (arvalid && arready) ar_done = 1'b1;
                guard = guard + 1;
            end
            #1; arvalid = 1'b0;
            guard = 0;
            while (!r_done && guard < 100) begin
                @(posedge clk);
                if (rvalid && rready) begin
                    r_done = 1'b1;
                    data   = rdata;
                end
                guard = guard + 1;
            end
            #1; rready = 1'b0;
        end
    endtask

    // ---------- генератор sig_in (асинхронний: зсув 3 нс відносно такту) ----------
    integer sig_period = 100;                   // тактів
    integer sig_high   = 50;                    // тактів високого рівня на період
    reg     sig_en     = 1'b0;
    integer sig_cnt    = 0;
    always @(posedge clk) begin
        if (!sig_en) begin
            sig_cnt <= 0;
            sig_in  <= #3 1'b0;
        end else begin
            sig_cnt <= (sig_cnt == sig_period - 1) ? 0 : sig_cnt + 1;
            sig_in  <= #3 (sig_cnt < sig_high);
        end
    end

    task set_signal;
        input integer period;
        input integer high;
        begin
            sig_en = 1'b0;
            repeat (3) @(posedge clk);
            sig_period = period;
            sig_high   = high;
            sig_en     = 1'b1;
        end
    endtask

    // ---------- перевірки ----------
    integer errors = 0;
    task chk;
        input        cond;
        input [8*60:1] name;
        begin
            if (cond) $display("PASS: %0s", name);
            else begin
                $display("FAIL: %0s", name);
                errors = errors + 1;
            end
        end
    endtask

    // Одне вимірювання: WINDOW, CTRL=1, опитування STATUS, читання COUNT.
    task measure;
        input  [31:0] win;
        output [31:0] cnt;
        output [31:0] dur;                      // тактів від запису CTRL до STATUS=1
        reg [31:0] st;
        integer t0, guard;
        begin
            axi_write(4'h0, win);
            axi_write(4'h4, 32'd1);
            t0 = cyc; st = 32'd0; guard = 0;
            while (st[0] == 1'b0 && guard < win + 500) begin
                axi_read(4'hC, st);
                guard = guard + 1;
            end
            dur = cyc - t0;
            axi_read(4'h8, cnt);
        end
    endtask

    // ---------- сценарії ----------
    reg [31:0] v, c, d, c_prev;
    integer k, n2, n3;
    reg ok_set;

    initial begin : main_seq
        repeat (10) @(posedge clk);
        resetn = 1'b1;
        repeat (5) @(posedge clk);

        // --- T0: стан після скидання, регістри ---
        axi_read(4'hC, v); chk(v === 32'd0, "T0 after reset: STATUS = 0");
        axi_read(4'h8, v); chk(v === 32'd0, "T0 after reset: COUNT = 0");
        axi_write(4'h0, 32'h12345678);
        axi_read(4'h0, v); chk(v === 32'h12345678, "T0 WINDOW read back = written value");
        axi_read(4'h4, v); chk(v === 32'd0, "T0 CTRL reads 0");
        axi_write(4'h8, 32'hFFFFFFFF);          // запис у COUNT ігнорується
        axi_read(4'h8, v); chk(v === 32'd0, "T0 write to COUNT ignored");

        // --- T1: період 100, вікно 1000 -> 10 ---
        set_signal(100, 50);
        repeat (37) @(posedge clk);
        measure(32'd1000, c, d);
        chk(c === 32'd10, "T1 period 100, window 1000 -> COUNT = 10");

        // --- T2: період 40, вікно 2000 -> 50 ---
        set_signal(40, 20);
        repeat (13) @(posedge clk);
        measure(32'd2000, c, d);
        chk(c === 32'd50, "T2 period 40, window 2000 -> COUNT = 50");

        // --- T3: період 100, вікно 250 -> {2, 3}, обидва значення трапляються ---
        set_signal(100, 50);
        n2 = 0; n3 = 0; ok_set = 1'b1;
        for (k = 0; k < 10; k = k + 1) begin
            repeat (k * 10 + 3) @(posedge clk);  // зсув фази початку вікна відносно сигналу
            measure(32'd250, c, d);
            if (c === 32'd2) n2 = n2 + 1;
            else if (c === 32'd3) n3 = n3 + 1;
            else ok_set = 1'b0;
        end
        chk(ok_set, "T3 period 100, window 250: every COUNT is 2 or 3");
        chk(n2 > 0 && n3 > 0, "T3 both values 2 and 3 occur (phase dependent)");

        // --- T4: вікно 0 -> COUNT = 0, STATUS = 1 ---
        axi_write(4'h0, 32'd0);
        axi_write(4'h4, 32'd1);
        repeat (6) @(posedge clk);
        axi_read(4'hC, v); chk(v[0] === 1'b1, "T4 window 0: STATUS = 1 right away");
        axi_read(4'h8, v); chk(v === 32'd0, "T4 window 0: COUNT = 0");

        // --- T5: широкий імпульс рахується один раз ---
        set_signal(600, 400);
        repeat (21) @(posedge clk);
        measure(32'd1200, c, d);
        chk(c === 32'd2, "T5 wide pulse (400 high of 600): COUNT = 2");
        c_prev = c;

        // --- T6: STATUS = 0 і незмінний COUNT під час вимірювання; CTRL ігнорується ---
        set_signal(100, 50);
        repeat (11) @(posedge clk);
        axi_write(4'h0, 32'd2000);
        axi_write(4'h4, 32'd1);
        c = cyc;
        axi_read(4'hC, v); chk(v[0] === 1'b0, "T6 STATUS = 0 while measuring");
        axi_read(4'h8, v); chk(v === c_prev, "T6 COUNT unchanged while measuring");
        repeat (500) @(posedge clk);
        axi_write(4'h4, 32'd1);                  // повторний запуск у процесі: має ігноруватись
        d = 0;
        v = 32'd0;
        while (v[0] == 1'b0 && d < 3000) begin
            axi_read(4'hC, v);
            d = d + 1;
        end
        d = cyc - c;                              // тактів від запуску до STATUS = 1
        chk(d >= 2000 && d < 2040, "T6 CTRL write during run ignored (duration ~ window)");
        axi_read(4'h8, v); chk(v === 32'd20, "T6 period 100, window 2000 -> COUNT = 20");

        // --- T7: стабільність після завершення ---
        axi_read(4'h8, c); repeat (300) @(posedge clk); axi_read(4'h8, d);
        chk(c === d && c === 32'd20, "T7 COUNT stable after completion");
        axi_read(4'hC, v); chk(v[0] === 1'b1, "T7 STATUS stays 1");

        if (errors == 0) $display("Test passed !");
        else             $display("Test FAILED: %0d errors", errors);
        $finish;
    end

    initial begin
        #5000000;
        $display("TIMEOUT: test did not finish");
        $finish;
    end

endmodule

// Тонкі верхні модулі: звичайний тест і тест зламаної копії
module tb_freq_counter;
    tb_freq_core #(.BROKEN(0)) t ();
endmodule

module tb_freq_counter_broken;
    tb_freq_core #(.BROKEN(1)) t ();
endmodule
