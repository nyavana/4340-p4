/////////////////////////////////////////////////////////////////////////
//                                                                     //
//   Modulename :  dcache.sv                                           //
//                                                                     //
//  Description :  2-way set-associative, write-back, write-allocate   //
//                 data cache. Total capacity stays 256 bytes:         //
//                 32 lines x 64 bits = 16 sets x 2 ways.              //
//                                                                     //
//                 Address layout:                                     //
//                   addr[2:0]  : byte offset (always 0 in CACHE_MODE) //
//                   addr[6:3]  : set index (4 bits, 16 sets)          //
//                   addr[15:7] : tag (9 bits)                         //
//                                                                     //
//                 Each set has one LRU bit. On a miss, an invalid way //
//                 is used first; otherwise the set's LRU way is the   //
//                 eviction victim. On a hit or fill, the accessed way //
//                 becomes MRU, so the LRU bit flips to the other way. //
//                                                                     //
/////////////////////////////////////////////////////////////////////////

`include "verilog/sys_defs.svh"

`define DCACHE_SETS     (`DCACHE_LINES / `DCACHE_WAYS)
`define DCACHE_SET_BITS $clog2(`DCACHE_SETS)
`define DCACHE_TAG_BITS (13 - `DCACHE_SET_BITS)

typedef struct packed {
    logic [63:0]                  data;
    logic [`DCACHE_TAG_BITS-1:0]  tags;
    logic                         valid;
    logic                         dirty;
} DCACHE_ENTRY;

module dcache (
    input clock,
    input reset,

    // ---- From memory ----
    input  [3:0]  Dmem2proc_response,
    input  [63:0] Dmem2proc_data,
    input  [3:0]  Dmem2proc_tag,

    // ---- CPU side: held until proc_done ----
    input  logic              proc_load,
    input  logic              proc_store,
    input  logic [`XLEN-1:0]  proc_addr,
    input  logic [63:0]       proc_wr_data,
    input  logic [7:0]        proc_wr_be,

    output logic [63:0]       proc_rd_data,
    output logic              proc_done,
    output logic              proc_busy,

    // ---- To memory ----
    output logic [1:0]        proc2Dmem_command,
    output logic [`XLEN-1:0]  proc2Dmem_addr,
    output logic [63:0]       proc2Dmem_data
);

    typedef enum logic [2:0] {
        DC_IDLE,
        DC_EVICT_REQ,
        DC_FETCH_REQ,
        DC_FETCH_WAIT
    } dc_state_t;

    dc_state_t state, next_state;

    DCACHE_ENTRY dcache_data [0:`DCACHE_SETS-1][0:`DCACHE_WAYS-1];
    logic        lru_way     [0:`DCACHE_SETS-1];

    logic              req_load_reg;
    logic              req_store_reg;
    logic [`XLEN-1:0]  req_addr_reg;
    logic [63:0]       req_wr_data_reg;
    logic [7:0]        req_wr_be_reg;

    logic [3:0]        mem_tag_reg;
    logic [63:0]       evict_data_reg;
    logic [`XLEN-1:0]  evict_addr_reg;
    logic              victim_way_reg;

    wire [`DCACHE_TAG_BITS-1:0] req_tag;
    wire [`DCACHE_SET_BITS-1:0] req_index;
    assign {req_tag, req_index} = proc_addr[15:3];

    wire [`DCACHE_TAG_BITS-1:0] reg_tag;
    wire [`DCACHE_SET_BITS-1:0] reg_index;
    assign {reg_tag, reg_index} = req_addr_reg[15:3];

    logic hit;
    logic hit_way;
    logic victim_way;
    logic victim_dirty;
    logic [63:0] victim_data;
    logic [`DCACHE_TAG_BITS-1:0] victim_tag;

    integer way_i;
    always_comb begin
        hit         = 1'b0;
        hit_way     = 1'b0;
        victim_way  = lru_way[req_index];
        victim_dirty = 1'b0;
        victim_data  = '0;
        victim_tag   = '0;

        for (way_i = 0; way_i < `DCACHE_WAYS; way_i++) begin
            if (dcache_data[req_index][way_i].valid &&
                (dcache_data[req_index][way_i].tags == req_tag)) begin
                hit     = 1'b1;
                hit_way = way_i[0];
            end
        end

        if (!dcache_data[req_index][0].valid) begin
            victim_way = 1'b0;
        end else if (!dcache_data[req_index][1].valid) begin
            victim_way = 1'b1;
        end

        victim_dirty = dcache_data[req_index][victim_way].valid &&
                       dcache_data[req_index][victim_way].dirty;
        victim_data  = dcache_data[req_index][victim_way].data;
        victim_tag   = dcache_data[req_index][victim_way].tags;
    end

    wire idle_req  = (state == DC_IDLE) && (proc_load || proc_store);
    wire miss_done = (state == DC_FETCH_WAIT) &&
                     (Dmem2proc_tag == mem_tag_reg) &&
                     (mem_tag_reg != 4'b0);

    assign proc_done = (idle_req && hit) || miss_done;
    assign proc_busy = (state != DC_IDLE);

    always_comb begin
        proc_rd_data = '0;
        if (idle_req && proc_load && hit) begin
            proc_rd_data = dcache_data[req_index][hit_way].data;
        end else if (miss_done && req_load_reg) begin
            proc_rd_data = Dmem2proc_data;
        end
    end

    always_comb begin
        proc2Dmem_command = BUS_NONE;
        proc2Dmem_addr    = '0;
        proc2Dmem_data    = '0;
        case (state)
            DC_EVICT_REQ: begin
                proc2Dmem_command = BUS_STORE;
                proc2Dmem_addr    = evict_addr_reg;
                proc2Dmem_data    = evict_data_reg;
            end
            DC_FETCH_REQ: begin
                proc2Dmem_command = BUS_LOAD;
                proc2Dmem_addr    = {req_addr_reg[`XLEN-1:3], 3'b0};
            end
            default: ;
        endcase
    end

    always_comb begin
        next_state = state;
        case (state)
            DC_IDLE: begin
                if (idle_req && !hit) begin
                    if (victim_dirty)
                        next_state = DC_EVICT_REQ;
                    else
                        next_state = DC_FETCH_REQ;
                end
            end
            DC_EVICT_REQ: begin
                if (Dmem2proc_response != 4'b0)
                    next_state = DC_FETCH_REQ;
            end
            DC_FETCH_REQ: begin
                if (Dmem2proc_response != 4'b0)
                    next_state = DC_FETCH_WAIT;
            end
            DC_FETCH_WAIT: begin
                if (miss_done)
                    next_state = DC_IDLE;
            end
            default: next_state = DC_IDLE;
        endcase
    end

    always_ff @(posedge clock) begin
        integer set_i, way_j, b;
        if (reset) begin
            state           <= DC_IDLE;
            req_load_reg    <= 1'b0;
            req_store_reg   <= 1'b0;
            req_addr_reg    <= '0;
            req_wr_data_reg <= '0;
            req_wr_be_reg   <= '0;
            mem_tag_reg     <= 4'b0;
            evict_data_reg  <= '0;
            evict_addr_reg  <= '0;
            victim_way_reg  <= 1'b0;
            for (set_i = 0; set_i < `DCACHE_SETS; set_i++) begin
                lru_way[set_i] <= 1'b0;
                for (way_j = 0; way_j < `DCACHE_WAYS; way_j++) begin
                    dcache_data[set_i][way_j] <= '0;
                end
            end
        end else begin
            state <= next_state;

            if (state == DC_IDLE && idle_req && !hit) begin
                req_load_reg    <= proc_load;
                req_store_reg   <= proc_store;
                req_addr_reg    <= proc_addr;
                req_wr_data_reg <= proc_wr_data;
                req_wr_be_reg   <= proc_wr_be;
                victim_way_reg  <= victim_way;

                if (victim_dirty) begin
                    evict_data_reg <= victim_data;
                    evict_addr_reg <= {{(`XLEN-16){1'b0}},
                                       victim_tag,
                                       req_index, 3'b0};
                end
            end

            if (state == DC_FETCH_REQ && Dmem2proc_response != 4'b0)
                mem_tag_reg <= Dmem2proc_response;

            if (state == DC_IDLE && proc_store && hit) begin
                for (b = 0; b < 8; b++) begin
                    if (proc_wr_be[b]) begin
                        dcache_data[req_index][hit_way].data[b*8 +: 8]
                            <= proc_wr_data[b*8 +: 8];
                    end
                end
                dcache_data[req_index][hit_way].dirty <= 1'b1;
                lru_way[req_index] <= ~hit_way;
            end else if (state == DC_IDLE && proc_load && hit) begin
                lru_way[req_index] <= ~hit_way;
            end

            if (miss_done) begin
                dcache_data[reg_index][victim_way_reg].tags  <= reg_tag;
                dcache_data[reg_index][victim_way_reg].valid <= 1'b1;
                if (req_store_reg) begin
                    for (b = 0; b < 8; b++) begin
                        if (req_wr_be_reg[b]) begin
                            dcache_data[reg_index][victim_way_reg].data[b*8 +: 8]
                                <= req_wr_data_reg[b*8 +: 8];
                        end else begin
                            dcache_data[reg_index][victim_way_reg].data[b*8 +: 8]
                                <= Dmem2proc_data[b*8 +: 8];
                        end
                    end
                    dcache_data[reg_index][victim_way_reg].dirty <= 1'b1;
                end else begin
                    dcache_data[reg_index][victim_way_reg].data  <= Dmem2proc_data;
                    dcache_data[reg_index][victim_way_reg].dirty <= 1'b0;
                end
                lru_way[reg_index] <= ~victim_way_reg;
                mem_tag_reg <= 4'b0;
            end
        end
    end

endmodule // dcache
