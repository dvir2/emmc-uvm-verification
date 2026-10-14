`timescale 1ns/1ps

// =========================================================================
// iNAND (eMMC Protocol) Verification Package
// =========================================================================
package inand_pkg;

  // JEDEC eMMC Standard Command Set (Subset for verification)
  typedef enum logic [5:0] {
    CMD_GO_IDLE_STATE        = 6'd0,   
    CMD_SEND_OP_COND         = 6'd1,   
    CMD_ALL_SEND_CID         = 6'd2,   
    CMD_SET_RELATIVE_ADDR    = 6'd3,   
    CMD_SELECT_DESELECT_CARD = 6'd7,   
    CMD_SEND_STATUS          = 6'd13,  
    CMD_READ_SINGLE_BLOCK    = 6'd17,  // Read a single 512-byte block at LBA
    CMD_WRITE_SINGLE_BLOCK   = 6'd24   // Write a single 512-byte block at LBA
  } emmc_cmd_e;

endpackage


// =========================================================================
// iNAND Controller DUT Model (eMMC Protocol & Block Storage)
// =========================================================================
module inand_dut (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        cmd_stb,      
  input  logic [5:0]  cmd_code,     
  input  logic [31:0] lba,          
  input  logic        wr_en,        
  input  logic [7:0]  dat_in,       
  output logic [7:0]  dat_out,      
  output logic        dat_vld,      
  output logic        ready         
);
  import inand_pkg::*;

  typedef byte block_t[512];
  block_t mem_blocks[int];

  typedef enum logic [1:0] {
    ST_IDLE,
    ST_WRITE_DATA,
    ST_READ_DATA
  } dut_state_e;

  dut_state_e current_state;
  int         byte_counter;
  bit [31:0]  active_lba;
  block_t     active_block;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      current_state <= ST_IDLE;
      ready         <= 1'b1;
      dat_vld       <= 1'b0;
      dat_out       <= 8'h0;
      byte_counter  <= 0;
      active_lba    <= 0;
    end else begin
      case (current_state)
        ST_IDLE: begin
          ready   <= 1'b1;
          dat_vld <= 1'b0;
          
          if (cmd_stb) begin
            active_lba <= lba;
            
            if (cmd_code == CMD_WRITE_SINGLE_BLOCK) begin
              ready         <= 1'b0;
              byte_counter  <= 0;
              current_state <= ST_WRITE_DATA;
            end 
            else if (cmd_code == CMD_READ_SINGLE_BLOCK) begin
              ready         <= 1'b0;
              byte_counter  <= 0;
              
              if (!mem_blocks.exists(lba)) begin
                foreach (active_block[i]) active_block[i] = 8'h0;
              end else begin
                active_block = mem_blocks[lba];
              end
              
              current_state <= ST_READ_DATA;
            end
          end
        end

        ST_WRITE_DATA: begin
          if (wr_en) begin
            active_block[byte_counter] = dat_in; 
            byte_counter++;
            
            if (byte_counter == 512) begin
              mem_blocks[active_lba] = active_block;
              ready         <= 1'b1;
              current_state <= ST_IDLE;
            end
          end
        end

        ST_READ_DATA: begin
          dat_vld <= 1'b1;
          dat_out <= active_block[byte_counter];
          byte_counter++;
          
          if (byte_counter == 512) begin
            dat_vld       <= 1'b0;
            ready         <= 1'b1;
            current_state <= ST_IDLE;
          end
        end

      endcase
    end
  end

endmodule