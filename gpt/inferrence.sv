// inferrence — τ ≡
// Concept and notation: Ailo Nordsletta. Design, implementation and tests: OpenAI Codex.
// Signed by: OpenAI Codex
// 𝼃et'┬  ≡ ┴'ket  > pixie dance. In this model the dance is the corrective
// bit flip on read; cet is the screen that displays the decoded value.
//
// Four model blocks, one protected 4-bit word each. A write creates a codeword.
// A read decodes it. A confirmed media failure retires the selected block until reset.
// Per word, ECC corrects one flipped bit and flags any two. More flips can alias.
// This is volatile digital logic; the Kingston NV3's physical NAND is outside this model.
//
// Run from the repository root with Icarus Verilog:
//   iverilog -g2012 -DINFERR_TEST -s inferrence_test -o inferrence.vvp gpt/inferrence.sv
//   vvp inferrence.vvp

`timescale 1ns/1ps
module inferrence (
    input  wire       clk, reset, will_write, media_failed,
    input  wire [1:0] block_id,
    input  wire [3:0] payload,
    output wire       retired, read_valid, corrected, uncorrectable,
    output wire [3:0] result
);
    reg [7:0] words [0:3];
    reg [3:0] occupied, bad_blocks;

    // Extended Hamming (8,4), even parity. Check bits occupy positions 1, 2 and 4.
    wire p1 = payload[0] ^ payload[1] ^ payload[3];
    wire p2 = payload[0] ^ payload[2] ^ payload[3];
    wire p4 = payload[1] ^ payload[2] ^ payload[3];
    wire [6:0] body = {payload[3:1], p4, payload[0], p2, p1};
    assign retired = bad_blocks[block_id];

    always @(posedge clk) begin
        if (reset) begin
            occupied   <= 4'b0;
            bad_blocks <= 4'b0;
        end else if (media_failed) begin
            bad_blocks[block_id] <= 1'b1;
        end else if (will_write && !retired) begin
            words[block_id]    <= {^body, body};
            occupied[block_id] <= 1'b1;
        end
    end

    wire [7:0] word_in = words[block_id];
    wire [2:0] syndrome = {^(word_in & 8'h78), ^(word_in & 8'h66), ^(word_in & 8'h55)};
    wire odd_parity = ^word_in;
    wire readable = occupied[block_id] && !retired;
    assign uncorrectable = readable && !odd_parity && (syndrome != 0);
    assign read_valid = readable && !uncorrectable;
    assign corrected = readable && odd_parity;

    // Syndrome zero + odd parity identifies the overall parity bit (index 7).
    wire [2:0] error_bit = syndrome - 3'd1;
    wire [7:0] decoded = corrected ? (word_in ^ (8'b1 << error_bit)) : word_in;
    assign result = read_valid ? {decoded[6:4], decoded[2]} : 4'b0;
endmodule

`ifdef INFERR_TEST
module inferrence_test;
    reg clk = 0, reset = 0, will_write = 0, media_failed = 0;
    reg [1:0] block_id = 0;
    reg [3:0] payload = 0;
    wire retired, read_valid, corrected, uncorrectable;
    wire [3:0] result;
    inferrence dut (.*);
    task tick;
        #1 clk = 1; #1 clk = 0; #1;
    endtask

    integer n, i, j;
    reg [7:0] saved;
    initial begin
        reset = 1; tick; reset = 0;
        if ({retired, read_valid, result} !== 6'b0) $fatal(1, "Reset");
        for (n = 0; n < 16; n = n + 1) begin
            payload = n[3:0]; will_write = 1; tick; will_write = 0;
            if ({read_valid, corrected, uncorrectable, result} !== {3'b100, payload})
                $fatal(1, "Clean read: payload %h", payload);
            saved = dut.words[block_id];
            for (i = 0; i < 8; i = i + 1) begin
                dut.words[block_id] = saved ^ (8'b1 << i); #1;
                if ({read_valid, corrected, uncorrectable, result} !== {3'b110, payload})
                    $fatal(1, "Single-bit fault: payload %h, bit %0d", payload, i);
                for (j = i + 1; j < 8; j = j + 1) begin
                    dut.words[block_id] = saved ^ (8'b1 << i) ^ (8'b1 << j); #1;
                    if ({retired, read_valid, corrected, uncorrectable, result} !== 8'h10)
                        $fatal(1, "Double-bit fault: payload %h, bits %0d/%0d", payload, i, j);
                end
            end
        end
        dut.words[block_id] = saved; payload = 0; tick;
        if (result !== 4'hf) $fatal(1, "Read modified the stored value");
        media_failed = 1; will_write = 1; tick; media_failed = 0; tick;
        if ({retired, read_valid} !== 2'b10 || dut.words[block_id] !== saved)
            $fatal(1, "Failed block accepted a write");
        block_id = 1; payload = 6; tick; will_write = 0;
        if ({retired, read_valid, result} !== {2'b01, 4'h6}) $fatal(1, "Healthy block");
        dut.words[block_id] = dut.words[block_id] ^ 8'h04; #1;
        if ({read_valid, corrected, result} !== {2'b11, 4'h6}) $fatal(1, "Screen example");
        $display("cet | wrote %04b | flipped one data bit | corrected read %04b", payload, result);
        block_id = 0; tick;
        if (retired !== 1'b1) $fatal(1, "Retirement did not persist");
        $display("PASS: 16 values created, 128 single-bit faults corrected, 448 double-bit faults detected; failed block isolated.");
        $finish;
    end
endmodule
`endif
