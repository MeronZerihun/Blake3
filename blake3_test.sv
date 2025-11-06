
module blake3_tb;

    logic w_clk, w_reset;
    // DUT signals (sizes taken from VHDL)
    logic  [255:0] c_CHAIN;
    logic  [511:0] c_MBLOCK;
    logic  [63:0]  c_COUNTER;
    logic  [31:0]  c_NUMBYTES;
    logic  [31:0]  c_DFLAGS;
    logic          r_i_valid;

    logic [511:0] r_hash;
    logic         r_o_valid;
    logic [511:0] c_HASH;

    logic correct;

    // Instantiate DUT
    blake3 dut (
        .i_clk      (w_clk),
        .i_reset    (w_reset),
        .i_chain    (c_CHAIN),
        .i_mblock   (c_MBLOCK),
        .i_counter  (c_COUNTER),
        .i_numbytes (c_NUMBYTES),
        .i_dflags   (c_DFLAGS),
        .i_valid    (r_i_valid),
        .o_hash     (r_hash),
        .o_valid    (r_o_valid)
    );

    assign correct = ~r_o_valid || (r_hash === c_HASH);

    // CLOCK_PERIOD is defined on the commandline by the makefile
    always begin
        #(`CLOCK_PERIOD/2.0);
        w_clk = ~w_clk;
        if (!correct) begin
            $display("@@@ Incorrect at time %4.0f", $time);
            $display("@@@ r_hash:%h ", r_hash);
            $finish;
        end
    end

    // Some students have had problems just using "@(posedge done)" because their
    // "done" signals glitch (even though they are the output of a register). This
    // prevents that by making sure "done" is high at the clock edge.
    task wait_until_done;
        forever begin : wait_loop
            @(posedge r_o_valid);
            @(negedge w_clk);
            if (r_o_valid) begin
                disable wait_until_done;
            end
        end
    endtask

    initial begin

        $monitor("Time:%5d mblock: %h r_hash:%h c_hash: %h state: %b", 
                 $time, c_MBLOCK, r_hash, c_HASH, dut.state);

        w_clk = 0;
        w_reset = 1;
        r_i_valid = 0;
        c_CHAIN = 256'h0;
        c_MBLOCK = 512'h0;
        c_COUNTER = 64'h0;
        c_NUMBYTES = 32'h0;
        c_DFLAGS = 32'h0;

        // Initializing inputs
        c_HASH = {
            32'hc5b847a2,
            32'ha79985ee, 
            32'hdb01f61a,
            32'h9faa4c9c,
            32'h93e4deb5,
            32'hfe181271, 
            32'h045cc222,
            32'h2dd63f6b,
            32'hfeb91efd,
            32'h23c0a324,
            32'h8731c94d,
            32'hc2603efb,
            32'h12d6ede4,
            32'h0900e3ac,
            32'h7d358ae7,
            32'he2c6dc92
        };

        // IV7 - IV0
        c_CHAIN = {
            32'h5be0cd19, 
            32'h1f83d9ab, 
            32'h9b05688c, 
            32'h510e527f,
            32'ha54ff53a, 
            32'h3c6ef372, 
            32'hbb67ae85, 
            32'h6a09e667
        };
        
        c_MBLOCK = {
            384'b0,                
            32'h0000000a,
            32'h21646c72,
            32'h6f57206f,
            32'h6c6c6548
        }; 

        c_COUNTER = 64'b0;
        c_NUMBYTES = 13;
        // Setting flags: CHUNK_START, CHUNK_END, ROOT
        c_DFLAGS = 32'b0000_0000_0000_0000_0000_0000_0000_1011;

        @(negedge w_clk);
        r_i_valid = 1;
        w_reset = 0;
        wait_until_done();

        // Wait for output
        $display("Passed; r_o_valid=%b r_hash=%h c_hash=%h", r_o_valid, r_hash, c_HASH);

        $finish;
    end

endmodule
