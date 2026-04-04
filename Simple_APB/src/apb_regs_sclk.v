// =============================================================================
// Name:     apb_regs_sclk
// Date:     2026.04.03
// Authors:  xlyan <dragonyxl.eminence@gmail.com>
//
// Function:
// - slv_clk domain registers for APB reg_file
// - RO regs [NUM_RO_REGS]: local_wr writes here
// - RW shadow [NUM_RW_REGS]: updated from pclk domain via CDC pulse
// - Generates ro_update_pulse when local writes a RO register
// - Slave logic reads via addr + rd_data (same style as pclk side)
// =============================================================================

module apb_regs_sclk #(
	parameter DATA_WIDTH   = 32,
	parameter NUM_RO_REGS  = 5,
	parameter NUM_RW_REGS  = 10,
	parameter IDX_WIDTH    = 4
) (
	input  wire                  sclk,
	input  wire                  srstn,

	// Local write port (only writes RO regs)
	input  wire                  local_wr_en,
	input  wire [IDX_WIDTH-1:0]  local_wr_addr,
	input  wire [DATA_WIDTH-1:0] local_wr_data,

	// Local read port (slave logic reads any reg)
	input  wire [IDX_WIDTH-1:0]  local_rd_addr,
	output wire [DATA_WIDTH-1:0] local_rd_data,

	// RO CDC: notify pclk that a RO reg was written
	output reg                   ro_update_pulse,
	output wire [DATA_WIDTH-1:0] ro_reg_out [0:NUM_RO_REGS-1],

	// RW shadow: updated from pclk via CDC
	input  wire                  rw_update_pulse,
	input  wire [DATA_WIDTH-1:0] rw_reg_in [0:NUM_RW_REGS-1]
);

	// RW_BASE: first RW register index, used to offset into rw_shadow[]
	// NUM_RO_REGS=5, IDX_WIDTH=4 => RW_BASE = 4'd5
	localparam [IDX_WIDTH-1:0]    RW_BASE = NUM_RO_REGS[IDX_WIDTH-1:0];

	// RO_MASK: bit[i]=1 if reg[i] is read-only (belongs to ro_regs[])
	// NUM_RO_REGS=5 => (1<<5)-1 = 16'b0000_0000_0001_1111
	localparam [2**IDX_WIDTH-1:0] RO_MASK = (1 << NUM_RO_REGS) - 1;

	// VALID_MASK: bit[i]=1 if reg[i] exists
	localparam [2**IDX_WIDTH-1:0] VALID_MASK = (1 << (NUM_RO_REGS + NUM_RW_REGS)) - 1;

	// -------------------------------------------------------------------------
	// RO registers (slv_clk domain, local writes here)
	// -------------------------------------------------------------------------
	reg [DATA_WIDTH-1:0] ro_regs [0:NUM_RO_REGS-1];

	integer i;
	always @(posedge sclk or negedge srstn) begin
		if (!srstn) begin
			for (i = 0; i < NUM_RO_REGS; i = i + 1)
				ro_regs[i] <= {DATA_WIDTH{1'b0}};
			ro_update_pulse <= 1'b0;
		end else begin
			ro_update_pulse <= 1'b0;
			if (local_wr_en && RO_MASK[local_wr_addr]) begin
				ro_regs[local_wr_addr] <= local_wr_data;
				ro_update_pulse <= 1'b1;
			end
		end
	end

	// Expose RO regs for CDC transfer to pclk
	genvar g;
	generate
		for (g = 0; g < NUM_RO_REGS; g = g + 1) begin : ro_out
			assign ro_reg_out[g] = ro_regs[g];
		end
	endgenerate

	// -------------------------------------------------------------------------
	// RW shadow registers (slv_clk domain, updated from pclk via CDC)
	// -------------------------------------------------------------------------
	reg [DATA_WIDTH-1:0] rw_shadow [0:NUM_RW_REGS-1];

	always @(posedge sclk or negedge srstn) begin
		if (!srstn) begin
			for (i = 0; i < NUM_RW_REGS; i = i + 1)
				rw_shadow[i] <= {DATA_WIDTH{1'b0}};
		end else if (rw_update_pulse) begin
			for (i = 0; i < NUM_RW_REGS; i = i + 1)
				rw_shadow[i] <= rw_reg_in[i];
		end
	end

	// -------------------------------------------------------------------------
	// Read mux: RO regs [0..4], RW shadow [5..14]
	// -------------------------------------------------------------------------
	assign local_rd_data = !VALID_MASK[local_rd_addr] ? {DATA_WIDTH{1'b0}}              :
	                       RO_MASK[local_rd_addr]    ? ro_regs[local_rd_addr]           :
	                                                   rw_shadow[local_rd_addr - RW_BASE];

endmodule
