// Copyright 2017 Embecosm Limited <www.embecosm.com>
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

// RAM and MM wrapper for RI5CY
// Contributor: Jeremy Bennett <jeremy.bennett@embecosm.com>
//              Robert Balas <balasr@student.ethz.ch>
//
// This maps the dp_ram module to the instruction and data ports of the RI5CY
// processor core and some pseudo peripherals

module mm_ram
    #(parameter RAM_ADDR_WIDTH = 16,
      parameter DEBUG = 0)
    (input logic                      clk_i,
     input logic                      rst_ni,

     input logic                      instr_req_i,
     input logic [RAM_ADDR_WIDTH-1:0] instr_addr_i,
     output logic [127:0]             instr_rdata_o,
     output logic                     instr_rvalid_o,
     output logic                     instr_gnt_o,

     input logic                      data_req_i,
     input logic [31:0]               data_addr_i,
     input logic                      data_we_i,
     input logic [3:0]                data_be_i,
     input logic [31:0]               data_wdata_i,
     output logic [31:0]              data_rdata_o,
     output logic                     data_rvalid_o,
     output logic                     data_gnt_o,

     output logic                     tests_passed_o);

    // mux for read and writes
    enum logic [1:0]{RAM, MM, ERR} select_rdata_d, select_rdata_q;
    logic [31:0]                   data_addr_aligned;

    // signals to ram
    logic                          ram_data_req;
    logic [RAM_ADDR_WIDTH-1:0]     ram_data_addr;
    logic [31:0]                   ram_data_wdata;
    logic [31:0]                   ram_data_rdata;
    logic                          ram_data_we;
    logic [3:0]                    ram_data_be;

    // uhh, align?
    always_comb data_addr_aligned = {data_addr_i[31:2], 2'b0};

    // handle the mapping of read and writes to either memory or pseudo
    // peripherals (currently just a redirection of writes to stdout)
    always_comb begin
        ram_data_req   = '0;
        ram_data_addr  = '0;
        ram_data_wdata = '0;
        ram_data_we    = '0;
        ram_data_be    = '0;
        select_rdata_d = RAM;

        if (data_req_i) begin
            if (data_we_i) begin // handle writes
                if (DEBUG)
                    $display("write addr=0x%08x: data=0x%08x",
                             data_addr_aligned, data_wdata_i);

                if (data_addr_i < 64 * 1024) begin
                    ram_data_req = data_req_i;
                    ram_data_addr = data_addr_i[RAM_ADDR_WIDTH-1:0];
                    ram_data_wdata = data_wdata_i;
                    ram_data_we = data_we_i;
                    ram_data_be = data_be_i;

                end else if (data_addr_i == 32'h1000_0000) begin

                    if (DEBUG) begin
                        if (32 <= data_wdata_i && data_wdata_i < 128)
                            $display("OUT: '%c'", data_wdata_i[7:0]);
                        else
                            $display("OUT: %3d", data_wdata_i);

                    end else begin
                        $write("%c", data_wdata_i[7:0]);

                    end

                end else if (data_addr_i == 32'h200_0000) begin
                    if (data_wdata_i == 123456789)
                        tests_passed_o = 1;

                end else begin
                    $display("out of bounds write to %08x", data_addr_i);
                    $finish;
                end

            end else begin // handle reads
                // we handle debug (if (DEBUG)...) reads directly at the sources
                if (data_addr_i < 64 * 1024) begin
                    select_rdata_d = RAM;

                    ram_data_req = data_req_i;
                    ram_data_addr = data_addr_i[RAM_ADDR_WIDTH-1:0];
                    ram_data_wdata = data_wdata_i;
                    ram_data_we = data_we_i;
                    ram_data_be = data_be_i;

                end else
                    select_rdata_d = ERR;

            end
        end
    end

    always_comb begin: read_mux
        data_rdata_o = '0;

        if(select_rdata_q == RAM) begin
            data_rdata_o = ram_data_rdata;
        end else if (select_rdata_q == ERR) begin
            $display("out of bounds read from %08x", data_addr_i);
            $finish;
        end
    end


    // instantiate the ram
    dp_ram
        #(.ADDR_WIDTH (RAM_ADDR_WIDTH),
          .DEBUG (DEBUG))
    dp_ram_i
        (
         .clk_i     ( clk_i         ),

         .en_a_i    ( instr_req_i   ),
         .addr_a_i  ( instr_addr_i  ),
         .wdata_a_i ( '0            ),	// Not writing so ignored
         .rdata_a_o ( instr_rdata_o ),
         .we_a_i    ( '0            ),
         .be_a_i    ( 4'b1111       ),	// Always want 32-bits

         .en_b_i    ( ram_data_req    ),
         .addr_b_i  ( ram_data_addr   ),
         .wdata_b_i ( ram_data_wdata  ),
         .rdata_b_o ( ram_data_rdata  ),
         .we_b_i    ( ram_data_we     ),
         .be_b_i    ( ram_data_be     ));

    // do the handshacking stuff by assuming we always react in one cycle
    assign data_gnt_o  = data_req_i;
    assign instr_gnt_o = instr_req_i;

    always_ff @(posedge clk_i) begin
        data_rvalid_o  <= data_req_i;
        instr_rvalid_o <= instr_req_i;
    end

    always_ff @(posedge clk_i, negedge rst_ni) begin
        if (~rst_ni) begin
            select_rdata_q <= RAM;
        end else begin
            select_rdata_q <= select_rdata_d;
        end
    end

endmodule // ram
