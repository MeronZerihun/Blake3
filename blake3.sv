
// Clock Period (Slack met): 8ns/cycle
// Time = 8ns/cycle * (3 + (2 * 7)) cycles = 136ns
module blake3 (
    input        clock,
    input        reset, 
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
    typedef enum logic [2:0] { STATE_IDLE, STATE_PREPARE, STATE_GCOL, STATE_GDIAG, STATE_OUTPUT } state_t;
    state_t state, state_n;
    logic [2:0] round;

    logic [31:0] v [0:15]; 
    logic [511:0] mblock;
    logic [511:0] mblock_buf;

    // Initialization vector
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
            ror32 = (x >> n) | (x << (32 - n));
        end
    endfunction

   
    // G-function internals (Page 5)
    function [31:0] f_A1; 
        input integer A;
        input integer B;
        input integer M;
        begin
            case (M)
                0:  f_A1 = v[A] + v[B] + mblock[31:0];
                1:  f_A1 = v[A] + v[B] + mblock[63:32];
                2:  f_A1 = v[A] + v[B] + mblock[95:64];
                3:  f_A1 = v[A] + v[B] + mblock[127:96];
                4:  f_A1 = v[A] + v[B] + mblock[159:128];
                5:  f_A1 = v[A] + v[B] + mblock[191:160];
                6:  f_A1 = v[A] + v[B] + mblock[223:192];
                7:  f_A1 = v[A] + v[B] + mblock[255:224];
                8:  f_A1 = v[A] + v[B] + mblock[287:256];
                9:  f_A1 = v[A] + v[B] + mblock[319:288];
                10: f_A1 = v[A] + v[B] + mblock[351:320];
                11: f_A1 = v[A] + v[B] + mblock[383:352];
                12: f_A1 = v[A] + v[B] + mblock[415:384];
                13: f_A1 = v[A] + v[B] + mblock[447:416];
                14: f_A1 = v[A] + v[B] + mblock[479:448];
                15: f_A1 = v[A] + v[B] + mblock[511:480];
            endcase
        end
    endfunction

    function [31:0] f_D1;
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
            case (M)
                0:  f_A2 = f_A1(A,B,M-1) + f_B1(A,B,C,D,M) + mblock[31:0];
                1:  f_A2 = f_A1(A,B,M-1) + f_B1(A,B,C,D,M) + mblock[63:32];
                2:  f_A2 = f_A1(A,B,M-1) + f_B1(A,B,C,D,M) + mblock[95:64];
                3:  f_A2 = f_A1(A,B,M-1) + f_B1(A,B,C,D,M) + mblock[127:96];
                4:  f_A2 = f_A1(A,B,M-1) + f_B1(A,B,C,D,M) + mblock[159:128];
                5:  f_A2 = f_A1(A,B,M-1) + f_B1(A,B,C,D,M) + mblock[191:160];
                6:  f_A2 = f_A1(A,B,M-1) + f_B1(A,B,C,D,M) + mblock[223:192];
                7:  f_A2 = f_A1(A,B,M-1) + f_B1(A,B,C,D,M) + mblock[255:224];
                8:  f_A2 = f_A1(A,B,M-1) + f_B1(A,B,C,D,M) + mblock[287:256];
                9:  f_A2 = f_A1(A,B,M-1) + f_B1(A,B,C,D,M) + mblock[319:288];
                10: f_A2 = f_A1(A,B,M-1) + f_B1(A,B,C,D,M) + mblock[351:320];
                11: f_A2 = f_A1(A,B,M-1) + f_B1(A,B,C,D,M) + mblock[383:352];
                12: f_A2 = f_A1(A,B,M-1) + f_B1(A,B,C,D,M) + mblock[415:384];
                13: f_A2 = f_A1(A,B,M-1) + f_B1(A,B,C,D,M) + mblock[447:416];
                14: f_A2 = f_A1(A,B,M-1) + f_B1(A,B,C,D,M) + mblock[479:448];
                15: f_A2 = f_A1(A,B,M-1) + f_B1(A,B,C,D,M) + mblock[511:480];
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
    always_ff @(posedge clock) begin
        if (reset) begin
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
                if (round == 3'd6) begin 
                    state_n = STATE_OUTPUT; 
                end else begin 
                    // New round
                    state_n = STATE_GCOL;
                end
            STATE_OUTPUT: state_n = STATE_IDLE;
        endcase
    end
    

    // Reset and main state machine
    always_ff @(posedge clock) begin
        if (reset) begin
            o_valid <= 1'b0;
            o_hash <= 512'b0;
            round <= 3'd0;
            mblock <= 512'b0;
            mblock_buf <= 512'b0;
            for (int i=0; i<16; i=i+1) v[i] <= 32'b0;
        end else begin
            case (state)
                STATE_IDLE: begin
                    if (i_valid) begin
                        o_valid <= 1'b0;
                    end
                end

                STATE_PREPARE: begin
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

                    v[12] <= i_counter[31:0];
                    v[13] <= i_counter[63:32];
                    v[14] <= i_numbytes;
                    v[15] <= i_dflags;
                    round <= 3'd0;
                    mblock <= i_mblock;
                    mblock_buf <= i_mblock;
                end

                STATE_GCOL: begin
                    // G0(v0, v4, v8, v12)
                    v[0]  <= f_A2(0, 4, 8, 12, 1);
                    v[4] <= f_B2(0, 4, 8, 12, 1);
                    v[8]  <= f_C2(0, 4, 8, 12, 1);
                    v[12]  <= f_D2(0, 4, 8, 12, 1);

                    // G1(v1, v5, v9, v13)
                    v[1]  <= f_A2(1, 5, 9, 13, 3);
                    v[5]  <= f_B2(1, 5, 9, 13, 3);
                    v[9]  <= f_C2(1, 5, 9, 13, 3);
                    v[13] <= f_D2(1, 5, 9, 13, 3);

                    // G2(v2, v6, v10, v14)
                    v[2]  <= f_A2(2, 6, 10, 14, 5);
                    v[6]  <= f_B2(2, 6, 10, 14, 5);
                    v[10] <= f_C2(2, 6, 10, 14, 5);
                    v[14] <= f_D2(2, 6, 10, 14, 5);

                    // G3(v3, v7, v11, v15)
                    v[3]  <= f_A2(3, 7, 11, 15, 7);
                    v[7]  <= f_B2(3, 7, 11, 15, 7);
                    v[11] <= f_C2(3, 7, 11, 15, 7);
                    v[15] <= f_D2(3, 7, 11, 15, 7);

                    // Update mblock_buf to the permuted message block
                    mblock_buf <= mblock;
                    
                end

                STATE_GDIAG: begin
                    // G4(v0, v5, v10, v15)
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

                    round <= round + 1;
                    if (round == 3'd6) begin
                        round <= 3'd0;
                    end else begin
                        // Permutate msg key schedule for next round
                        mblock[31:0]    <= mblock_buf[c_SCHEDULE[0]*32+32-1  : c_SCHEDULE[0]*32];
                        mblock[63:32]   <= mblock_buf[c_SCHEDULE[1]*32+32-1  : c_SCHEDULE[1]*32];
                        mblock[95:64]   <= mblock_buf[c_SCHEDULE[2]*32+32-1  : c_SCHEDULE[2]*32];
                        mblock[127:96]  <= mblock_buf[c_SCHEDULE[3]*32+32-1  : c_SCHEDULE[3]*32];
                        mblock[159:128] <= mblock_buf[c_SCHEDULE[4]*32+32-1  : c_SCHEDULE[4]*32];
                        mblock[191:160] <= mblock_buf[c_SCHEDULE[5]*32+32-1  : c_SCHEDULE[5]*32];
                        mblock[223:192] <= mblock_buf[c_SCHEDULE[6]*32+32-1  : c_SCHEDULE[6]*32];
                        mblock[255:224] <= mblock_buf[c_SCHEDULE[7]*32+32-1  : c_SCHEDULE[7]*32];
                        mblock[287:256] <= mblock_buf[c_SCHEDULE[8]*32+32-1  : c_SCHEDULE[8]*32];
                        mblock[319:288] <= mblock_buf[c_SCHEDULE[9]*32+32-1  : c_SCHEDULE[9]*32];
                        mblock[351:320] <= mblock_buf[c_SCHEDULE[10]*32+32-1 : c_SCHEDULE[10]*32];
                        mblock[383:352] <= mblock_buf[c_SCHEDULE[11]*32+32-1 : c_SCHEDULE[11]*32];
                        mblock[415:384] <= mblock_buf[c_SCHEDULE[12]*32+32-1 : c_SCHEDULE[12]*32];
                        mblock[447:416] <= mblock_buf[c_SCHEDULE[13]*32+32-1 : c_SCHEDULE[13]*32];
                        mblock[479:448] <= mblock_buf[c_SCHEDULE[14]*32+32-1 : c_SCHEDULE[14]*32];
                        mblock[511:480] <= mblock_buf[c_SCHEDULE[15]*32+32-1 : c_SCHEDULE[15]*32];
                    
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
