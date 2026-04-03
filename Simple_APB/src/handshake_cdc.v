module pulse_handshake(
//src domain
	input wire	clk_src,
	input wire	rstn_src,
	input wire	pulse_src,
	output wire	busy_src,
// dst domain
	input wire	clk_dst,
	input wire	rstn_dst,
	output wire pulse_dst
);
	reg 		req_toggle;
	// feedback is used to ack clear busy
	reg [1:0]	req_feedback_sync;
	reg [2:0]	req_sync;

	assign busy_src = req_feedback_sync[1] ^ req_toggle;

	always @(posedge clk_src or negedge rstn_src) begin
        if (!rstn_src) begin
			req_toggle <= 1'b0;
		end else begin
			if( !busy_src && pulse_src)
				req_toggle <= ~req_toggle;
		end
	end

    always @(posedge clk_dst or negedge rstn_dst) begin
        if (!rstn_dst) begin
            req_sync <= 3'b000;
        end else begin
            req_sync <= {req_sync[1:0], req_toggle};
        end
    end

	assign pulse_dst = req_sync[2] ^ req_sync[1];

    always @(posedge clk_src or negedge rstn_src) begin
        if (!rstn_src) begin
            req_feedback_sync <= 2'b00;
        end else begin
            req_feedback_sync <= {req_feedback_sync[0], req_sync[1]};
        end
    end

endmodule