
// Clock Period (Slack met): 14.5ns/cycle (67 MHz)
// Time =  14.5ns/cycle * (1 + (1 * 7)) cycles = 116ns
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
    typedef enum logic [1:0] { STATE_IDLE, STATE_G } state_t;
    state_t state, state_n;
    logic [2:0] round;

    logic [31:0] v [0:15];
    logic [31:0] v_col [0:15]; 
    logic [31:0] v_next [0:15];
    logic [511:0] mblock;
    logic [511:0] mblock_next;

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
        input logic [31:0] v [0:15];
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
        input logic [31:0] v [0:15];
        input integer A; 
        input integer B; 
        input integer D; 
        input integer M;
        begin
            f_D1 = ror32( (v[D] ^ f_A1(v,A,B,M-1)), 16 );
        end
    endfunction

    function [31:0] f_C1;
        input logic [31:0] v [0:15];
        input integer A; 
        input integer B; 
        input integer C; 
        input integer D; 
        input integer M;
        begin
            f_C1 = v[C] + f_D1(v,A,B,D,M);
        end
    endfunction

    function [31:0] f_B1;
        input logic [31:0] v [0:15];
        input integer A; 
        input integer B; 
        input integer C; 
        input integer D; 
        input integer M;
        begin
            f_B1 = ror32( (v[B] ^ f_C1(v,A,B,C,D,M)), 12 );
        end
    endfunction

    function [31:0] f_A2;
        input logic [31:0] v [0:15];
        input integer A; 
        input integer B; 
        input integer C; 
        input integer D; 
        input [4:0] M;
        begin
            case (M)
                0:  f_A2 = f_A1(v,A,B,M-1) + f_B1(v,A,B,C,D,M) + mblock[31:0];
                1:  f_A2 = f_A1(v,A,B,M-1) + f_B1(v,A,B,C,D,M) + mblock[63:32];
                2:  f_A2 = f_A1(v,A,B,M-1) + f_B1(v,A,B,C,D,M) + mblock[95:64];
                3:  f_A2 = f_A1(v,A,B,M-1) + f_B1(v,A,B,C,D,M) + mblock[127:96];
                4:  f_A2 = f_A1(v,A,B,M-1) + f_B1(v,A,B,C,D,M) + mblock[159:128];
                5:  f_A2 = f_A1(v,A,B,M-1) + f_B1(v,A,B,C,D,M) + mblock[191:160];
                6:  f_A2 = f_A1(v,A,B,M-1) + f_B1(v,A,B,C,D,M) + mblock[223:192];
                7:  f_A2 = f_A1(v,A,B,M-1) + f_B1(v,A,B,C,D,M) + mblock[255:224];
                8:  f_A2 = f_A1(v,A,B,M-1) + f_B1(v,A,B,C,D,M) + mblock[287:256];
                9:  f_A2 = f_A1(v,A,B,M-1) + f_B1(v,A,B,C,D,M) + mblock[319:288];
                10: f_A2 = f_A1(v,A,B,M-1) + f_B1(v,A,B,C,D,M) + mblock[351:320];
                11: f_A2 = f_A1(v,A,B,M-1) + f_B1(v,A,B,C,D,M) + mblock[383:352];
                12: f_A2 = f_A1(v,A,B,M-1) + f_B1(v,A,B,C,D,M) + mblock[415:384];
                13: f_A2 = f_A1(v,A,B,M-1) + f_B1(v,A,B,C,D,M) + mblock[447:416];
                14: f_A2 = f_A1(v,A,B,M-1) + f_B1(v,A,B,C,D,M) + mblock[479:448];
                15: f_A2 = f_A1(v,A,B,M-1) + f_B1(v,A,B,C,D,M) + mblock[511:480];
            endcase
        end
    endfunction

    function [31:0] f_D2;
        input [31:0] v [0:15];
        input integer A; 
        input integer B; 
        input integer C; 
        input integer D; 
        input integer M;
        begin
            f_D2 = ror32( (f_D1(v,A,B,D,M) ^ f_A2(v,A,B,C,D,M)), 8 );
        end
    endfunction

    function [31:0] f_C2;
        input [31:0] v [0:15];
        input integer A; 
        input integer B; 
        input integer C; 
        input integer D; 
        input integer M;
        begin
            f_C2 = f_C1(v,A,B,C,D,M) + f_D2(v,A,B,C,D,M);
        end
    endfunction

    function [31:0] f_B2;
        input [31:0] v [0:15];
        input integer A; 
        input integer B; 
        input integer C; 
        input integer D; 
        input integer M;
        begin
            f_B2 = ror32( (f_B1(v,A,B,C,D,M) ^ f_C2(v,A,B,C,D,M)), 7 );
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
            STATE_IDLE: if (i_valid) state_n = STATE_G; 
            STATE_G: 
                if (round == 3'd6) begin 
                    state_n = STATE_IDLE; 
                end
        endcase
    end

    // Output logic
    always_comb begin

        v_col = v;

        // G-function per column
        v_col[0]  = f_A2(v, 0, 4, 8, 12, 1);
        v_col[4]  = f_B2(v, 0, 4, 8, 12, 1);
        v_col[8]  = f_C2(v, 0, 4, 8, 12, 1);
        v_col[12] = f_D2(v, 0, 4, 8, 12, 1);

        v_col[1]  = f_A2(v, 1, 5, 9, 13, 3);
        v_col[5]  = f_B2(v, 1, 5, 9, 13, 3);
        v_col[9]  = f_C2(v, 1, 5, 9, 13, 3);
        v_col[13] = f_D2(v, 1, 5, 9, 13, 3);

        v_col[2]  = f_A2(v, 2, 6, 10, 14, 5);
        v_col[6]  = f_B2(v, 2, 6, 10, 14, 5);
        v_col[10] = f_C2(v, 2, 6, 10, 14, 5);
        v_col[14] = f_D2(v, 2, 6, 10, 14, 5);

        v_col[3]  = f_A2(v, 3, 7, 11, 15, 7);
        v_col[7]  = f_B2(v, 3, 7, 11, 15, 7);
        v_col[11] = f_C2(v, 3, 7, 11, 15, 7);
        v_col[15] = f_D2(v, 3, 7, 11, 15, 7);

        // G-function per diagonal
        v_next[0]  = f_A2(v_col, 0, 5, 10, 15, 9);
        v_next[5]  = f_B2(v_col, 0, 5, 10, 15, 9);
        v_next[10] = f_C2(v_col, 0, 5, 10, 15, 9);
        v_next[15] = f_D2(v_col, 0, 5, 10, 15, 9);

        v_next[1]  = f_A2(v_col, 1, 6, 11, 12, 11);
        v_next[6]  = f_B2(v_col, 1, 6, 11, 12, 11);
        v_next[11] = f_C2(v_col, 1, 6, 11, 12, 11);
        v_next[12] = f_D2(v_col, 1, 6, 11, 12, 11);

        v_next[2]  = f_A2(v_col, 2, 7, 8, 13, 13);
        v_next[7]  = f_B2(v_col, 2, 7, 8, 13, 13);
        v_next[8]  = f_C2(v_col, 2, 7, 8, 13, 13);
        v_next[13] = f_D2(v_col, 2, 7, 8, 13, 13);

        v_next[3]  = f_A2(v_col, 3, 4, 9, 14, 15);
        v_next[4]  = f_B2(v_col, 3, 4, 9, 14, 15);
        v_next[9]  = f_C2(v_col, 3, 4, 9, 14, 15);
        v_next[14] = f_D2(v_col, 3, 4, 9, 14, 15);

        // Keyed Permutation
        for (int i = 0; i < 16; i++)
            mblock_next[i*32 +: 32] = mblock[c_SCHEDULE[i]*32 +: 32];

        if (round == 6) begin
            o_valid = 1'b1;
            o_hash[31:0]    = v_next[0] ^ v_next[8];
            o_hash[63:32]   = v_next[1] ^ v_next[9];
            o_hash[95:64]   = v_next[2] ^ v_next[10];
            o_hash[127:96]  = v_next[3] ^ v_next[11];
            o_hash[159:128] = v_next[4] ^ v_next[12];
            o_hash[191:160] = v_next[5] ^ v_next[13];
            o_hash[223:192] = v_next[6] ^ v_next[14];
            o_hash[255:224] = v_next[7] ^ v_next[15];

            o_hash[287:256] = v_next[8]  ^ i_chain[31:0];
            o_hash[319:288] = v_next[9]  ^ i_chain[63:32];
            o_hash[351:320] = v_next[10] ^ i_chain[95:64];
            o_hash[383:352] = v_next[11] ^ i_chain[127:96];
            o_hash[415:384] = v_next[12] ^ i_chain[159:128];
            o_hash[447:416] = v_next[13] ^ i_chain[191:160];
            o_hash[479:448] = v_next[14] ^ i_chain[223:192];
            o_hash[511:480] = v_next[15] ^ i_chain[255:224];
        end else begin
            o_valid = 0;
            o_hash = 512'b0;
        end

    end
    

    // Reset and main state machine
    always_ff @(posedge clock) begin
        if (reset) begin
            round <= 3'd0;
            mblock <= 512'b0;
            for (int i=0; i<16; i=i+1) v[i] <= 32'b0;
        end else begin
            case (state)
                STATE_IDLE: begin
                    if (i_valid) begin
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
                    end
                end
                STATE_G: begin
                    v <= v_next;
                    mblock <= mblock_next;
                    round <= round + 1;
                end
            endcase
        end
    end

endmodule
