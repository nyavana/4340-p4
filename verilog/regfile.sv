`include "sys_defs.svh"

module regfile (
    input             clock,
    input [4:0]       read_idx_1,
    input [4:0]       read_idx_2,
    input [4:0]       read_idx_3,
    input [4:0]       read_idx_4,
    input             write_en_0,
    input [4:0]       write_idx_0,
    input [`XLEN-1:0] write_data_0,
    input             write_en_1,
    input [4:0]       write_idx_1,
    input [`XLEN-1:0] write_data_1,
    output logic [`XLEN-1:0] read_out_1,
    output logic [`XLEN-1:0] read_out_2,
    output logic [`XLEN-1:0] read_out_3,
    output logic [`XLEN-1:0] read_out_4
);

    logic [31:1] [`XLEN-1:0] registers;

    function automatic [`XLEN-1:0] rf_read(
        input [4:0] idx
    );
        begin
            if (idx == `ZERO_REG)
                rf_read = '0;
            else if (write_en_1 && (write_idx_1 == idx) && (write_idx_1 != `ZERO_REG))
                rf_read = write_data_1;
            else if (write_en_0 && (write_idx_0 == idx) && (write_idx_0 != `ZERO_REG))
                rf_read = write_data_0;
            else
                rf_read = registers[idx];
        end
    endfunction

    always_comb begin
        read_out_1 = rf_read(read_idx_1);
        read_out_2 = rf_read(read_idx_2);
        read_out_3 = rf_read(read_idx_3);
        read_out_4 = rf_read(read_idx_4);
    end

    always_ff @(posedge clock) begin
        if (write_en_0 && (write_idx_0 != `ZERO_REG))
            registers[write_idx_0] <= write_data_0;
        if (write_en_1 && (write_idx_1 != `ZERO_REG))
            registers[write_idx_1] <= write_data_1;
    end
endmodule
