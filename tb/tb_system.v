`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// Системний тестбенч (крок 6): верхній рівень лише подає такт 100 МГц, скидання
// і сам генерує сигнал на порт sig_in (період 100 тактів = 1 МГц, 50% імпульс,
// зсув 3 нс відносно такту, щоб сигнал був асинхронним). Програму з freq_main.c
// виконує MicroBlaze (реальний .elf).
//
// Очікування: вікно 1000 тактів, період 100 -> COUNT = 10 (рівно), тож програма
// рахує f = 10 * 100 000 000 / 1000 = 1 000 000 Гц.
// Тестбенч друкує всі транзакції AXI4-Lite до IP і перевіряє підсумок.
//////////////////////////////////////////////////////////////////////////////

module tb_system;

    reg sys_clk = 1'b0;
    always #5 sys_clk = ~sys_clk;               // 100 МГц
    reg reset  = 1'b0;                          // активний НИЗЬКИЙ
    reg sig_in = 1'b0;

    design_1_wrapper dut (
        .sys_clk (sys_clk),
        .reset   (reset),
        .sig_in  (sig_in)
    );

    // ---------- сигнал sig_in: період 100 тактів ----------
    integer cnt = 0;
    always @(posedge sys_clk) begin
        cnt    <= (cnt == 99) ? 0 : cnt + 1;
        sig_in <= #3 (cnt < 50);
    end

    // ---------- шляхи до внутрішніх сигналів IP (для друку й перевірки) ----------
    wire        s_awvalid = dut.design_1_i.freq_counter_0.s_axi_awvalid;
    wire        s_awready = dut.design_1_i.freq_counter_0.s_axi_awready;
    wire [3:0]  s_awaddr  = dut.design_1_i.freq_counter_0.s_axi_awaddr;
    wire        s_wvalid  = dut.design_1_i.freq_counter_0.s_axi_wvalid;
    wire        s_wready  = dut.design_1_i.freq_counter_0.s_axi_wready;
    wire [31:0] s_wdata   = dut.design_1_i.freq_counter_0.s_axi_wdata;
    wire        s_arvalid = dut.design_1_i.freq_counter_0.s_axi_arvalid;
    wire        s_arready = dut.design_1_i.freq_counter_0.s_axi_arready;
    wire [3:0]  s_araddr  = dut.design_1_i.freq_counter_0.s_axi_araddr;
    wire        s_rvalid  = dut.design_1_i.freq_counter_0.s_axi_rvalid;
    wire        s_rready  = dut.design_1_i.freq_counter_0.s_axi_rready;
    wire [31:0] s_rdata   = dut.design_1_i.freq_counter_0.s_axi_rdata;
    wire        ip_status = dut.design_1_i.freq_counter_0.inst.status;
    wire [31:0] ip_count  = dut.design_1_i.freq_counter_0.inst.count;

    integer n_wr = 0, n_rd = 0, n_status_polls = 0;
    reg [3:0] last_ar;

    always @(posedge sys_clk) begin
        if (s_awvalid && s_awready)
            $display("[%0t ns] AXI write address  0x%0h", $time/1000, s_awaddr);
        if (s_wvalid && s_wready) begin
            n_wr = n_wr + 1;
            $display("[%0t ns] AXI write data     0x%0h", $time/1000, s_wdata);
        end
        if (s_arvalid && s_arready) begin
            last_ar = s_araddr;
            n_rd = n_rd + 1;
            if (s_araddr == 4'hC) n_status_polls = n_status_polls + 1;
        end
        if (s_rvalid && s_rready && last_ar != 4'hC)
            $display("[%0t ns] AXI read  reg 0x%0h = %0d", $time/1000, last_ar, s_rdata);
    end

    // ---------- сценарій ----------
    integer errors = 0;
    task chk;
        input cond;
        input [8*56:1] name;
        begin
            if (cond) $display("PASS: %0s", name);
            else begin
                $display("FAIL: %0s", name);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        reset = 1'b0;
        #1000;
        reset = 1'b1;
        $display("[%0t ns] reset released", $time/1000);

        wait (ip_status === 1'b1);              // IP повідомив про завершення вимірювання
        repeat (20) @(posedge sys_clk);
        $display("[%0t ns] measurement finished", $time/1000);

        chk(ip_count === 32'd10, "COUNT = 10 for period 100, window 1000");
        chk(n_wr == 2, "program wrote 2 registers (WINDOW, CTRL)");
        chk(n_status_polls >= 1, "program polled STATUS");

        // дати програмі дочитати COUNT
        repeat (200) @(posedge sys_clk);
        chk(n_rd >= n_status_polls + 1, "program read COUNT");

        if (errors == 0) $display("Test passed !");
        else             $display("Test FAILED: %0d errors", errors);
        $finish;
    end

    initial begin
        #2000000;
        $display("TIMEOUT: the program did not complete the measurement");
        $finish;
    end

endmodule
