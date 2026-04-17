/////////////////////////////////////////////////////////////////////////
//                                                                     //
//   Modulename :  dcache.sv                                           //
//                                                                     //
//  Description :  Direct-mapped, write-back, write-allocate data      //
//                 cache for milestone 3.                              //
//                                                                     //
//                 Geometry: 32 lines x 64 bits = 256 bytes (matches   //
//                 the project spec cap of 256 B per cache).           //
//                 Address layout (matches icache.sv):                 //
//                   addr[2:0]  : byte offset (always 0 in CACHE_MODE) //
//                   addr[7:3]  : line index (5 bits, 32 lines)        //
//                   addr[15:8] : tag (8 bits)                         //
//                                                                     //
//                 The CPU side holds proc_load/proc_store and the     //
//                 8-byte-aligned address until proc_done is asserted. //
//                 Sub-word handling lives outside the cache: the LSQ  //
//                 builds the byte-enable mask in proc_wr_be and       //
//                 picks the right slice out of proc_rd_data.          //
//                                                                     //
//                 State machine:                                      //
//                                                                     //
//                   IDLE ──hit──► IDLE (1 cycle)                      //
//                       └─miss, victim clean──► FETCH_REQ             //
//                       └─miss, victim dirty──► EVICT_REQ ──► FETCH_REQ
//                                                                     //
//                   FETCH_REQ ──response──► FETCH_WAIT                //
//                   FETCH_WAIT ──data tag──► IDLE (and assert done)   //
//                                                                     //
//                 Sub-word stores never write through to main memory  //
//                 directly: the cache absorbs them into the line and  //
//                 only the line eviction goes to memory as a full     //
//                 64-bit doubleword, which is what mem.sv accepts in  //
//                 CACHE_MODE.                                         //
//                                                                     //
/////////////////////////////////////////////////////////////////////////

`include "verilog/sys_defs.svh"

`define DCACHE_LINE_BITS $clog2(`DCACHE_LINES)

typedef struct packed {
    logic [63:0]                    data;
    logic [12-`DCACHE_LINE_BITS:0]  tags;   // 8 tag bits when DCACHE_LINES=32
    logic                           valid;
    logic                           dirty;
} DCACHE_ENTRY;

module dcache (
    input clock,
    input reset,

    // ---- From memory ----
    input  [3:0]  Dmem2proc_response,  // non-zero when memory accepts a request
    input  [63:0] Dmem2proc_data,      // returned line on a load
    input  [3:0]  Dmem2proc_tag,       // non-zero on the cycle data is valid

    // ---- CPU side: held until proc_done ----
    input  logic              proc_load,
    input  logic              proc_store,
    input  logic [`XLEN-1:0]  proc_addr,    // must be 8-byte aligned
    input  logic [63:0]       proc_wr_data, // 64-bit aligned write payload
    input  logic [7:0]        proc_wr_be,   // per-byte write enable

    output logic [63:0]       proc_rd_data,
    output logic              proc_done,    // 1-cycle pulse on completion
    output logic              proc_busy,    // 1 while servicing a miss

    // ---- To memory ----
    output logic [1:0]        proc2Dmem_command,
    output logic [`XLEN-1:0]  proc2Dmem_addr,
    output logic [63:0]       proc2Dmem_data
);

    // ---- State ----
    typedef enum logic [2:0] {
        DC_IDLE,
        DC_EVICT_REQ,   // writing back a dirty victim
        DC_FETCH_REQ,   // requesting the missing line
        DC_FETCH_WAIT   // waiting for memory data
    } dc_state_t;

    dc_state_t state, next_state;

    // ---- Cache storage ----
    DCACHE_ENTRY [`DCACHE_LINES-1:0] dcache_data;

    // ---- Latched miss request ----
    logic              req_load_reg;
    logic              req_store_reg;
    logic [`XLEN-1:0]  req_addr_reg;
    logic [63:0]       req_wr_data_reg;
    logic [7:0]        req_wr_be_reg;

    logic [3:0]        mem_tag_reg;     // outstanding fetch tag
    logic [63:0]       evict_data_reg;  // dirty victim payload
    logic [`XLEN-1:0]  evict_addr_reg;  // dirty victim address

    // ---- Live address breakdown ----
    wire [12-`DCACHE_LINE_BITS:0] req_tag;
    wire [`DCACHE_LINE_BITS-1:0]  req_index;
    assign {req_tag, req_index} = proc_addr[15:3];

    // ---- Latched address breakdown (for the entry being filled) ----
    wire [12-`DCACHE_LINE_BITS:0] reg_tag;
    wire [`DCACHE_LINE_BITS-1:0]  reg_index;
    assign {reg_tag, reg_index} = req_addr_reg[15:3];

    // ---- Hit detection on the live request ----
    wire hit = dcache_data[req_index].valid &&
               (dcache_data[req_index].tags == req_tag);

    wire idle_req  = (state == DC_IDLE) && (proc_load || proc_store);
    wire miss_done = (state == DC_FETCH_WAIT) &&
                     (Dmem2proc_tag == mem_tag_reg) &&
                     (mem_tag_reg != 4'b0);

    assign proc_done = (idle_req && hit) || miss_done;
    assign proc_busy = (state != DC_IDLE);

    // ---- Read data path ----
    always_comb begin
        proc_rd_data = '0;
        if (idle_req && proc_load && hit) begin
            proc_rd_data = dcache_data[req_index].data;
        end else if (miss_done && req_load_reg) begin
            // The freshly fetched line is on the bus this cycle; the
            // sequential update writes it into the cache one edge later.
            proc_rd_data = Dmem2proc_data;
        end
    end

    // ---- Drive the memory bus ----
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

    // ---- Next state ----
    always_comb begin
        next_state = state;
        case (state)
            DC_IDLE: begin
                if (idle_req && !hit) begin
                    if (dcache_data[req_index].valid &&
                        dcache_data[req_index].dirty)
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

    // ---- Sequential update ----
    always_ff @(posedge clock) begin
        integer i;
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
            for (i = 0; i < `DCACHE_LINES; i++) begin
                dcache_data[i] <= '0;
            end
        end else begin
            state <= next_state;

            // Latch the miss when we leave IDLE
            if (state == DC_IDLE && idle_req && !hit) begin
                req_load_reg    <= proc_load;
                req_store_reg   <= proc_store;
                req_addr_reg    <= proc_addr;
                req_wr_data_reg <= proc_wr_data;
                req_wr_be_reg   <= proc_wr_be;
                if (dcache_data[req_index].valid &&
                    dcache_data[req_index].dirty) begin
                    evict_data_reg <= dcache_data[req_index].data;
                    // Reconstruct the original address: tag + index + 3b0
                    evict_addr_reg <= {{(`XLEN-16){1'b0}},
                                       dcache_data[req_index].tags,
                                       req_index, 3'b0};
                end
            end

            // Capture the response tag for the in-flight fetch
            if (state == DC_FETCH_REQ && Dmem2proc_response != 4'b0)
                mem_tag_reg <= Dmem2proc_response;

            // Store-on-hit: modify the line in place
            if (state == DC_IDLE && proc_store && hit) begin
                for (int b = 0; b < 8; b++) begin
                    if (proc_wr_be[b])
                        dcache_data[req_index].data[b*8 +: 8] <= proc_wr_data[b*8 +: 8];
                end
                dcache_data[req_index].dirty <= 1'b1;
            end

            // Fill on miss completion: install fetched data plus
            // (for store misses) overlay the latched store payload.
            if (miss_done) begin
                dcache_data[reg_index].tags  <= reg_tag;
                dcache_data[reg_index].valid <= 1'b1;
                if (req_store_reg) begin
                    for (int b = 0; b < 8; b++) begin
                        if (req_wr_be_reg[b])
                            dcache_data[reg_index].data[b*8 +: 8] <= req_wr_data_reg[b*8 +: 8];
                        else
                            dcache_data[reg_index].data[b*8 +: 8] <= Dmem2proc_data[b*8 +: 8];
                    end
                    dcache_data[reg_index].dirty <= 1'b1;
                end else begin
                    dcache_data[reg_index].data  <= Dmem2proc_data;
                    dcache_data[reg_index].dirty <= 1'b0;
                end
                mem_tag_reg <= 4'b0;
            end
        end
    end

endmodule // dcache
