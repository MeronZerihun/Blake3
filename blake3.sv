
// Translated from VHDL blake3.vhd to Verilog using ChatGPT
// This is a straightforward behavioral translation (intended for synthesis or simulation).
// Note: uses Verilog-2001 style; some tools may require SystemVerilog for variable part-selects.
// Ports and behavior mirror the original VHDL implementation.

module blake3 (
    input        i_clk,
    input        i_reset, 
    input [255:0] i_chain,
    input [511:0] i_mblock,
    input [63:0]  i_counter,
    input [31:0]  i_numbytes,
    input [31:0]  i_dflags,
    input        i_valid,
    output logic  [511:0] o_hash,
    output logic         o_valid
);

    // State machine
    typedef enum logic [2:0] { STATE_IDLE=3'd0, STATE_PREPARE=3'd1, STATE_GCOL=3'd2, STATE_GDIAG=3'd3, STATE_OUTPUT=3'd4 } state_t;
    state_t state, state_n;
    logic [2:0] r_round;

    // Internal registers
    logic [31:0] v [0:15]; // initial state v0...v15
    logic [511:0] r_mblock;
    logic [511:0] r_mblock_buf;

    // Constants (initialization vector)
    localparam [31:0] c_IV [0:7] = {
        32'h6a09e667,
        32'hbb67ae85,
        32'h3c6ef372,
        32'ha54ff53a,
        32'h510e527f,
        32'h9b05688c,
        32'h1f83d9ab,
        32'h5be0cd19
    };

    // Message schedule
    localparam [3:0] c_SCHEDULE [0:15] = {
        4'd2,4'd6,4'd3,4'd10,4'd7,4'd0,4'd4,4'd13,
        4'd1,4'd11,4'd12,4'd5,4'd9,4'd14,4'd15,4'd8
    };

    // Helper: rotate right 32-bit
    function [31:0] ror32;
        input [31:0] x;
        input integer n;
        begin
            // Assume 8-bit, 0100 1100 n: 6 (0011 0001) -> ...01 | 0100 1100 00 = 0011 0001 ()
            ror32 = (x >> n) | (x << (32 - n));
        end
    endfunction

   
    // The VHDL used impure functions that read v and r_mblock directly.
    // We'll implement equivalent functions that reference module regs directly.
    // G-function internals (Page 5)
    function [31:0] f_A1; // v[A] + v[B] + m[M]
        input integer A;
        input integer B;
        input integer M;
        begin
            // f_A1 = v[A] + v[B] + r_mblock[(M*32)+32-1:(M)*32];
            case (M)
                0:  f_A1 = v[A] + v[B] + r_mblock[31:0];
                1:  f_A1 = v[A] + v[B] + r_mblock[63:32];
                2:  f_A1 = v[A] + v[B] + r_mblock[95:64];
                3:  f_A1 = v[A] + v[B] + r_mblock[127:96];
                4:  f_A1 = v[A] + v[B] + r_mblock[159:128];
                5:  f_A1 = v[A] + v[B] + r_mblock[191:160];
                6:  f_A1 = v[A] + v[B] + r_mblock[223:192];
                7:  f_A1 = v[A] + v[B] + r_mblock[255:224];
                8:  f_A1 = v[A] + v[B] + r_mblock[287:256];
                9:  f_A1 = v[A] + v[B] + r_mblock[319:288];
                10: f_A1 = v[A] + v[B] + r_mblock[351:320];
                11: f_A1 = v[A] + v[B] + r_mblock[383:352];
                12: f_A1 = v[A] + v[B] + r_mblock[415:384];
                13: f_A1 = v[A] + v[B] + r_mblock[447:416];
                14: f_A1 = v[A] + v[B] + r_mblock[479:448];
                15: f_A1 = v[A] + v[B] + r_mblock[511:480];
            endcase
        end
    endfunction

    function [31:0] f_D1; // (v[D] xor f_A1(...)) ror 16
        input integer A; input integer B; input integer D; input integer M;
        begin
            f_D1 = ror32( (v[D] ^ f_A1(A,B,M-1)), 16 );
        end
    endfunction

    function [31:0] f_C1;
        input integer A; input integer B; input integer C; input integer D; input integer M;
        begin
            f_C1 = v[C] + f_D1(A,B,D,M);
        end
    endfunction

    function [31:0] f_B1;
        input integer A; input integer B; input integer C; input integer D; input integer M;
        begin
            f_B1 = ror32( (v[B] ^ f_C1(A,B,C,D,M)), 12 );
        end
    endfunction

    function [31:0] f_A2;
        input integer A; input integer B; input integer C; input integer D; input [4:0] M;
        begin
            // Note: VHDL used an extra access to r_mblock with different indices; replicate exactly:
            // f_A2 := f_A1 + f_B1 + r_mblock((32*v_M)+31 downto (v_M)*32);
            case (M)
                0:  f_A2 = f_A1(A,B,M-1) + f_B1(A,B,C,D,M) + r_mblock[31:0];
                1:  f_A2 = f_A1(A,B,M-1) + f_B1(A,B,C,D,M) + r_mblock[63:32];
                2:  f_A2 = f_A1(A,B,M-1) + f_B1(A,B,C,D,M) + r_mblock[95:64];
                3:  f_A2 = f_A1(A,B,M-1) + f_B1(A,B,C,D,M) + r_mblock[127:96];
                4:  f_A2 = f_A1(A,B,M-1) + f_B1(A,B,C,D,M) + r_mblock[159:128];
                5:  f_A2 = f_A1(A,B,M-1) + f_B1(A,B,C,D,M) + r_mblock[191:160];
                6:  f_A2 = f_A1(A,B,M-1) + f_B1(A,B,C,D,M) + r_mblock[223:192];
                7:  f_A2 = f_A1(A,B,M-1) + f_B1(A,B,C,D,M) + r_mblock[255:224];
                8:  f_A2 = f_A1(A,B,M-1) + f_B1(A,B,C,D,M) + r_mblock[287:256];
                9:  f_A2 = f_A1(A,B,M-1) + f_B1(A,B,C,D,M) + r_mblock[319:288];
                10: f_A2 = f_A1(A,B,M-1) + f_B1(A,B,C,D,M) + r_mblock[351:320];
                11: f_A2 = f_A1(A,B,M-1) + f_B1(A,B,C,D,M) + r_mblock[383:352];
                12: f_A2 = f_A1(A,B,M-1) + f_B1(A,B,C,D,M) + r_mblock[415:384];
                13: f_A2 = f_A1(A,B,M-1) + f_B1(A,B,C,D,M) + r_mblock[447:416];
                14: f_A2 = f_A1(A,B,M-1) + f_B1(A,B,C,D,M) + r_mblock[479:448];
                15: f_A2 = f_A1(A,B,M-1) + f_B1(A,B,C,D,M) + r_mblock[511:480];
            endcase
        end
    endfunction

    function [31:0] f_D2;
        input integer A; input integer B; input integer C; input integer D; input integer M;
        begin
            f_D2 = ror32( (f_D1(A,B,D,M) ^ f_A2(A,B,C,D,M)), 8 );
        end
    endfunction

    function [31:0] f_C2;
        input integer A; input integer B; input integer C; input integer D; input integer M;
        begin
            f_C2 = f_C1(A,B,C,D,M) + f_D2(A,B,C,D,M);
        end
    endfunction

    function [31:0] f_B2;
        input integer A; input integer B; input integer C; input integer D; input integer M;
        begin
            f_B2 = ror32( (f_B1(A,B,C,D,M) ^ f_C2(A,B,C,D,M)), 7 );
        end
    endfunction

    
    // State transition
    always_ff @(posedge i_clk) begin
        if (i_reset) begin
            state <= STATE_IDLE;
        end else begin
            state <= state_n;
        end
    end

    // Next stage transition
    always_comb begin
        state_n = state;
        case (state)
            STATE_IDLE: if (i_valid) state_n = STATE_PREPARE;
            STATE_PREPARE: state_n = STATE_GCOL;
            STATE_GCOL: state_n = STATE_GDIAG;
            STATE_GDIAG: 
                if (r_round == 3'd6) begin 
                    state_n = STATE_OUTPUT; 
                end else begin 
                    // New round
                    state_n = STATE_GCOL;
                end
            STATE_OUTPUT: state_n = STATE_IDLE;
        endcase
    end
    

    // Reset and main state machine
    always_ff @(posedge i_clk) begin
        if (i_reset) begin
            o_valid <= 1'b0;
            o_hash <= 512'b0;
            // clear regs
            r_round <= 3'd0;
            r_mblock <= 512'b0;
            r_mblock_buf <= 512'b0;
            for (int i=0; i<16; i=i+1) v[i] <= 32'b0;
        end else begin
            case (state)
                STATE_IDLE: begin
                    if (i_valid) begin
                        o_valid <= 1'b0;
                    end
                end

                STATE_PREPARE: begin
                    // Sample inputs into internal regs and initialize v
                    v[0] <= i_chain[31 : 0];
                    v[1] <= i_chain[63 : 32];
                    v[2] <= i_chain[95 : 64];
                    v[3] <= i_chain[127 : 96];
                    v[4] <= i_chain[159 : 128];
                    v[5] <= i_chain[191 : 160];
                    v[6] <= i_chain[223 : 192];
                    v[7] <= i_chain[255 : 224];

                    v[8] <= c_IV[0];
                    v[9] <= c_IV[1];
                    v[10] <= c_IV[2];
                    v[11] <= c_IV[3];

                    // inject counter, numbytes, dflags into v[12..15] like original:
                    v[12] <= i_counter[31:0];
                    v[13] <= i_counter[63:32];
                    v[14] <= i_numbytes;
                    v[15] <= i_dflags;
                    r_round <= 3'd0;
                    r_mblock <= i_mblock;
                    r_mblock_buf <= i_mblock;
                end

                STATE_GCOL: begin
                    // G0(v0, v4, v8, v12)
                    v[0]  <= f_A2(0, 4, 8, 12, 1);
                    v[4]  <= f_D2(0, 4, 8, 12, 1);
                    v[8]  <= f_C2(0, 4, 8, 12, 1);
                    v[12] <= f_B2(0, 4, 8, 12, 1);

                    // G1(v1, v5, v9, v13)
                    v[1]  <= f_A2(1, 5, 9, 13, 3);
                    v[5]  <= f_D2(1, 5, 9, 13, 3);
                    v[9]  <= f_C2(1, 5, 9, 13, 3);
                    v[13] <= f_B2(1, 5, 9, 13, 3);

                    // G2(v2, v6, v10, v14)
                    v[2]  <= f_A2(2, 6, 10, 14, 5);
                    v[6]  <= f_D2(2, 6, 10, 14, 5);
                    v[10] <= f_C2(2, 6, 10, 14, 5);
                    v[14] <= f_B2(2, 6, 10, 14, 5);

                    // G3(v3, v7, v11, v15)
                    v[3]  <= f_A2(3, 7, 11, 15, 7);
                    v[7]  <= f_D2(3, 7, 11, 15, 7);
                    v[11] <= f_C2(3, 7, 11, 15, 7);
                    v[15] <= f_B2(3, 7, 11, 15, 7);

                    // Done - move to diagonals
                    r_mblock_buf <= r_mblock;
                    
                end

                STATE_GDIAG: begin
                    // G4(v1, v6, v11, v12)
                    v[0]  <= f_A2(0, 5, 10, 15, 9);
                    v[5]  <= f_B2(0, 5, 10, 15, 9);
                    v[10] <= f_C2(0, 5, 10, 15, 9);
                    v[15] <= f_D2(0, 5, 10, 15, 9);

                    // G5(v1, v6, v11, v12)
                    v[1]  <= f_A2(1, 6, 11, 12, 11);
                    v[6]  <= f_B2(1, 6, 11, 12, 11);
                    v[11] <= f_C2(1, 6, 11, 12, 11);
                    v[12] <= f_D2(1, 6, 11, 12, 11);

                    // G6(v2, v7, v8, v13)
                    v[2]  <= f_A2(2, 7, 8, 13, 13);
                    v[7]  <= f_B2(2, 7, 8, 13, 13);
                    v[8]  <= f_C2(2, 7, 8, 13, 13);
                    v[13] <= f_D2(2, 7, 8, 13, 13);

                    // G7(v3, v4, v9, v14)
                    v[3]  <= f_A2(3, 4, 9, 14, 15);
                    v[4]  <= f_B2(3, 4, 9, 14, 15);
                    v[9]  <= f_C2(3, 4, 9, 14, 15);
                    v[14] <= f_D2(3, 4, 9, 14, 15);

                    r_round <= r_round + 1;
                    if (r_round == 3'd6) begin
                        r_round <= 3'd0;
                    end else begin
                        // Permutate msg key schedule for next round
                        r_mblock[31:0]    <= r_mblock_buf[c_SCHEDULE[0]*32+32-1  : c_SCHEDULE[0]*32];
                        r_mblock[63:32]   <= r_mblock_buf[c_SCHEDULE[1]*32+32-1  : c_SCHEDULE[1]*32];
                        r_mblock[95:64]   <= r_mblock_buf[c_SCHEDULE[2]*32+32-1  : c_SCHEDULE[2]*32];
                        r_mblock[127:96]  <= r_mblock_buf[c_SCHEDULE[3]*32+32-1  : c_SCHEDULE[3]*32];
                        r_mblock[159:128] <= r_mblock_buf[c_SCHEDULE[4]*32+32-1  : c_SCHEDULE[4]*32];
                        r_mblock[191:160] <= r_mblock_buf[c_SCHEDULE[5]*32+32-1  : c_SCHEDULE[5]*32];
                        r_mblock[223:192] <= r_mblock_buf[c_SCHEDULE[6]*32+32-1  : c_SCHEDULE[6]*32];
                        r_mblock[255:224] <= r_mblock_buf[c_SCHEDULE[7]*32+32-1  : c_SCHEDULE[7]*32];
                        r_mblock[287:256] <= r_mblock_buf[c_SCHEDULE[8]*32+32-1  : c_SCHEDULE[8]*32];
                        r_mblock[319:288] <= r_mblock_buf[c_SCHEDULE[9]*32+32-1  : c_SCHEDULE[9]*32];
                        r_mblock[351:320] <= r_mblock_buf[c_SCHEDULE[10]*32+32-1 : c_SCHEDULE[10]*32];
                        r_mblock[383:352] <= r_mblock_buf[c_SCHEDULE[11]*32+32-1 : c_SCHEDULE[11]*32];
                        r_mblock[415:384] <= r_mblock_buf[c_SCHEDULE[12]*32+32-1 : c_SCHEDULE[12]*32];
                        r_mblock[447:416] <= r_mblock_buf[c_SCHEDULE[13]*32+32-1 : c_SCHEDULE[13]*32];
                        r_mblock[479:448] <= r_mblock_buf[c_SCHEDULE[14]*32+32-1 : c_SCHEDULE[14]*32];
                        r_mblock[511:480] <= r_mblock_buf[c_SCHEDULE[15]*32+32-1 : c_SCHEDULE[15]*32];
                    
                    end
                end

                STATE_OUTPUT: begin
                    o_hash[31:0]    <= v[0] ^ v[8];
                    o_hash[63:32]   <= v[1] ^ v[9];
                    o_hash[95:64]   <= v[2] ^ v[10];
                    o_hash[127:96]  <= v[3] ^ v[11];
                    o_hash[159:128] <= v[4] ^ v[12];
                    o_hash[191:160] <= v[5] ^ v[13];
                    o_hash[223:192] <= v[6] ^ v[14];
                    o_hash[255:224] <= v[7] ^ v[15];

                    o_hash[287:256] <= v[8]  ^ i_chain[31:0];
                    o_hash[319:288] <= v[9]  ^ i_chain[63:32];
                    o_hash[351:320] <= v[10] ^ i_chain[95:64];
                    o_hash[383:352] <= v[11] ^ i_chain[127:96];
                    o_hash[415:384] <= v[12] ^ i_chain[159:128];
                    o_hash[447:416] <= v[13] ^ i_chain[191:160];
                    o_hash[479:448] <= v[14] ^ i_chain[223:192];
                    o_hash[511:480] <= v[15] ^ i_chain[255:224];

                    o_valid <= 1'b1;

                end
            endcase
        end
    end

endmodule
