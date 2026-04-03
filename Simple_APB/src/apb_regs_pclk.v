// =============================================================================
// Name:     apb_regs_pclk
// Date:     2026.04.03
// Authors:  xlyan <dragonyxl.eminence@gmail.com>
//
// Function:
// - pclk domain registers for APB reg_file
// - RW regs [NUM_RW_REGS]: APB writes and reads directly
// - RO shadow [NUM_RO_REGS]: updated from slv_clk domain via CDC pulse
// - Generates rw_update_pulse when APB writes a RW register
// =============================================================================

module apb_regs_pclk #(
	parameter DATA_WIDTH   = 32,
	parameter NUM_REGS     = 15,
	parameter NUM_RO_REGS  = 5,
	parameter NUM_RW_REGS  = 10,
	parameter IDX_WIDTH    = 4
) (
	input  wire                  pclk,
	input  wire                  prstn,

	// Port A: APB read/write
	input  wire                  wr_en,
	input  wire [IDX_WIDTH-1:0]  addr,
	input  wire [DATA_WIDTH-1:0] wr_data,
	output wire [DATA_WIDTH-1:0] rd_data,
	output wire                  err,

	// RW CDC: notify slv_clk that a RW reg was written
	output reg                   rw_update_pulse,
	output wire [DATA_WIDTH-1:0] rw_reg_out [0:NUM_RW_REGS-1],

	// RO shadow: updated from slv_clk via CDC
	input  wire                  ro_update_pulse,
	input  wire [DATA_WIDTH-1:0] ro_reg_in [0:NUM_RO_REGS-1]
);

	// -------------------------------------------------------------------------
	// Address mapping helpers
	// -------------------------------------------------------------------------
	// RO_MASK: bit[i]=1 if reg[i] is read-only
	// NUM_RO_REGS=5 => (1<<5)-1 = 16'b0000_0000_0001_1111
	localparam [2**IDX_WIDTH-1:0] RO_MASK    = (1 << NUM_RO_REGS) - 1;

	// VALID_MASK: bit[i]=1 if reg[i] exists
	// NUM_REGS=15 => (1<<15)-1 = 16'b0111_1111_1111_1111
	localparam [2**IDX_WIDTH-1:0] VALID_MASK = (1 << NUM_REGS)    - 1;

	// RW_BASE: first RW register index, used to offset into rw_regs[]
	// NUM_RO_REGS=5, IDX_WIDTH=4 => RW_BASE = 4'd5
	localparam [IDX_WIDTH-1:0]    RW_BASE    = NUM_RO_REGS[IDX_WIDTH-1:0];

	wire is_valid;
	wire is_ro;
	wire [IDX_WIDTH-1:0] rw_idx;

	assign is_valid = VALID_MASK[addr];   // 1-bit lookup: is this address a valid register?
	assign is_ro    = RO_MASK[addr];      // 1-bit lookup: is this address read-only?
	assign rw_idx   = addr - RW_BASE;     // convert global addr to rw_regs[] index
	assign err      = ~is_valid | (wr_en & is_valid & is_ro);

	// -------------------------------------------------------------------------
	// RW registers (pclk domain, APB writes here)
	// -------------------------------------------------------------------------
	reg [DATA_WIDTH-1:0] rw_regs [0:NUM_RW_REGS-1];

	integer i;
	always @(posedge pclk or negedge prstn) begin
		if (!prstn) begin
			for (i = 0; i < NUM_RW_REGS; i = i + 1)
				rw_regs[i] <= {DATA_WIDTH{1'b0}};
			rw_update_pulse <= 1'b0;
		end else begin
			rw_update_pulse <= 1'b0;
			if (wr_en && is_valid && !is_ro) begin
				rw_regs[rw_idx] <= wr_data;
				rw_update_pulse <= 1'b1;
			end
		end
	end

	// Expose RW regs for CDC transfer to slv_clk
	genvar g;
	generate
		for (g = 0; g < NUM_RW_REGS; g = g + 1) begin : rw_out
			assign rw_reg_out[g] = rw_regs[g];
		end
	endgenerate

	// -------------------------------------------------------------------------
	// RO shadow registers (pclk domain, updated from slv_clk via CDC)
	// -------------------------------------------------------------------------
	reg [DATA_WIDTH-1:0] ro_shadow [0:NUM_RO_REGS-1];

	always @(posedge pclk or negedge prstn) begin
		if (!prstn) begin
			for (i = 0; i < NUM_RO_REGS; i = i + 1)
				ro_shadow[i] <= {DATA_WIDTH{1'b0}};
		end else if (ro_update_pulse) begin
			for (i = 0; i < NUM_RO_REGS; i = i + 1)
				ro_shadow[i] <= ro_reg_in[i];
		end
	end

	// -------------------------------------------------------------------------
	// Read mux: RO shadow [0..4], RW regs [5..14]
	// -------------------------------------------------------------------------
	assign rd_data = is_ro ? ro_shadow[addr] : rw_regs[rw_idx];

endmodule
