`timescale 1ns/1ps
`include "uvm_macros.svh"
import uvm_pkg::*;
import inand_pkg::*;

// =========================================================================
// 1. Physical Interface Definition
// =========================================================================
interface inand_if (input logic clk, input logic rst_n);
  
  logic        cmd_stb;
  logic [5:0]  cmd_code;
  logic [31:0] lba;
  logic        wr_en;
  logic [7:0]  dat_in;
  logic [7:0]  dat_out;
  logic        dat_vld;
  logic        ready;

  clocking drv_cb @(posedge clk);
    default input #1ns output #1ns;
    output cmd_stb, cmd_code, lba, wr_en, dat_in;
    input  dat_out, dat_vld, ready;
  endclocking

  clocking mon_cb @(posedge clk);
    default input #0ns output #1ns;
    input  cmd_stb, cmd_code, lba, wr_en, dat_in, dat_out, dat_vld, ready;
  endclocking

  modport tb_drv (clocking drv_cb, input rst_n);
  modport tb_mon (clocking mon_cb, input rst_n);
endinterface

// =========================================================================
// 2. UVM Sequence Item (Transaction)
// =========================================================================
class inand_sequence_item extends uvm_sequence_item;
  rand emmc_cmd_e   cmd;
  rand bit [31:0]   lba;
  rand byte         data[];

  `uvm_object_utils_begin(inand_sequence_item)
    `uvm_field_enum(emmc_cmd_e, cmd, UVM_ALL_ON)
    `uvm_field_int(lba, UVM_ALL_ON)
  `uvm_object_utils_end

  // Restricted LBA range to guarantee write/read collisions for Scoreboard verification
  constraint c_lba { lba inside {[0 : 3]}; }
  constraint c_cmd_dist { cmd dist { CMD_READ_SINGLE_BLOCK := 50, CMD_WRITE_SINGLE_BLOCK := 50 }; }
  constraint c_data_size { if (cmd == CMD_WRITE_SINGLE_BLOCK) data.size() == 512; else data.size() == 0; }

  function void post_randomize();
    if (cmd == CMD_WRITE_SINGLE_BLOCK) begin
      foreach (data[i]) data[i] = $urandom();
    end
  endfunction

  function new(string name = "inand_sequence_item");
    super.new(name);
  endfunction
endclass

// =========================================================================
// 3. UVM Sequence
// =========================================================================
class inand_sequence extends uvm_sequence #(inand_sequence_item);
  `uvm_object_utils(inand_sequence)

  int num_trans = 20;

  function new(string name = "inand_sequence");
    super.new(name);
  endfunction

  task body();
    repeat (num_trans) begin
      inand_sequence_item req = inand_sequence_item::type_id::create("req");
      start_item(req);
      if (!req.randomize()) `uvm_fatal("SEQ", "Randomization failed!")
      finish_item(req);
    end
  endtask
endclass

// =========================================================================
// 4. UVM Driver
// =========================================================================
class inand_driver extends uvm_driver #(inand_sequence_item);
  `uvm_component_utils(inand_driver)

  virtual inand_if vif;

  function new(string name = "inand_driver", uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual inand_if)::get(this, "", "vif", vif))
      `uvm_fatal("DRV", "Failed to get virtual interface from config_db!")
  endfunction

  task run_phase(uvm_phase phase);
    @(vif.drv_cb);
    vif.drv_cb.cmd_stb <= 1'b0;
    vif.drv_cb.wr_en   <= 1'b0;
    vif.drv_cb.dat_in  <= 8'h0;

    forever begin
      seq_item_port.get_next_item(req);
      drive_transaction(req);
      seq_item_port.item_done();
    end
  endtask

  task drive_transaction(inand_sequence_item tr);
    wait(vif.drv_cb.ready == 1'b1);
    
    @(vif.drv_cb);
    vif.drv_cb.cmd_stb  <= 1'b1;
    vif.drv_cb.cmd_code <= tr.cmd;
    vif.drv_cb.lba      <= tr.lba;

    @(vif.drv_cb);
    vif.drv_cb.cmd_stb <= 1'b0;

    if (tr.cmd == CMD_WRITE_SINGLE_BLOCK) begin
      foreach (tr.data[i]) begin
        @(vif.drv_cb);
        vif.drv_cb.wr_en  <= 1'b1;
        vif.drv_cb.dat_in <= tr.data[i];
      end
      @(vif.drv_cb);
      vif.drv_cb.wr_en <= 1'b0;
    end
    else if (tr.cmd == CMD_READ_SINGLE_BLOCK) begin
      repeat (512) @(vif.drv_cb);
    end
    
    repeat(2) @(vif.drv_cb);
  endtask
endclass

// =========================================================================
// 5. UVM Monitor
// =========================================================================
class inand_monitor extends uvm_monitor;
  `uvm_component_utils(inand_monitor)

  virtual inand_if vif;
  uvm_analysis_port #(inand_sequence_item) analysis_port;

  function new(string name = "inand_monitor", uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    analysis_port = new("analysis_port", this);
    if (!uvm_config_db#(virtual inand_if)::get(this, "", "vif", vif))
      `uvm_fatal("MON", "Failed to get virtual interface from config_db!")
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      inand_sequence_item tr;
      

      @(posedge vif.mon_cb.cmd_stb);
      tr = inand_sequence_item::type_id::create("tr");
      tr.cmd = emmc_cmd_e'(vif.mon_cb.cmd_code);
      tr.lba = vif.mon_cb.lba;


      if (tr.cmd == CMD_WRITE_SINGLE_BLOCK) begin
        tr.data = new[512];
        while (!vif.mon_cb.wr_en) begin
          @(vif.mon_cb);
        end
        for (int i = 0; i < 512; i++) begin
          tr.data[i] = vif.mon_cb.dat_in;
          if (i < 511) begin
            @(vif.mon_cb);
          end
        end
      end

      else if (tr.cmd == CMD_READ_SINGLE_BLOCK) begin
        tr.data = new[512];        
        while (!vif.mon_cb.dat_vld) begin
          @(vif.mon_cb);
        end
        for (int i = 0; i < 512; i++) begin
          tr.data[i] = vif.mon_cb.dat_out;
          if (i < 511) begin
            @(vif.mon_cb);
          end
        end
      end

      analysis_port.write(tr);
    end
  endtask
endclass
    
// =========================================================================
// 6. UVM Scoreboard
// =========================================================================
class inand_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(inand_scoreboard)

  uvm_analysis_imp #(inand_sequence_item, inand_scoreboard) item_collected_export;
  byte ref_memory[int][512];
  int transaction_count = 0;

  function new(string name = "inand_scoreboard", uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    item_collected_export = new("item_collected_export", this);
  endfunction

  virtual function void write(inand_sequence_item tr);
    transaction_count++;

    if (tr.cmd == CMD_WRITE_SINGLE_BLOCK) begin
      ref_memory[tr.lba] = tr.data;
      `uvm_info("SCB", $sformatf("Write Transaction #%0d Recorded at LBA 0x%0h", transaction_count, tr.lba), UVM_LOW)
    end 
    else if (tr.cmd == CMD_READ_SINGLE_BLOCK) begin
      if (!ref_memory.exists(tr.lba)) begin
        foreach (tr.data[i]) begin
          if (tr.data[i] !== 8'h00)
            `uvm_error("SCB", $sformatf("LBA 0x%0h was never written, expected all 0s!", tr.lba))
        end
      end else begin
        foreach (tr.data[i]) begin
          if (tr.data[i] !== ref_memory[tr.lba][i]) begin
            `uvm_error("SCB", $sformatf("SCOREBOARD MISMATCH! LBA 0x%0h | Byte[%0d]: Expected 0x%0h, Got 0x%0h", 
                       tr.lba, i, ref_memory[tr.lba][i], tr.data[i]))
          end
        end
      end
      `uvm_info("SCB", $sformatf("Read Transaction #%0d at LBA 0x%0h verified [PASS]", transaction_count, tr.lba), UVM_LOW)
    end
  endfunction
endclass

// =========================================================================
// 7. UVM Agent
// =========================================================================
class inand_agent extends uvm_agent;
  `uvm_component_utils(inand_agent)

  inand_driver     drv;
  inand_monitor    mon;
  uvm_sequencer #(inand_sequence_item) sqr;

  function new(string name = "inand_agent", uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    mon = inand_monitor::type_id::create("mon", this);
    if (get_is_active() == UVM_ACTIVE) begin
      drv = inand_driver::type_id::create("drv", this);
      sqr = uvm_sequencer#(inand_sequence_item)::type_id::create("sqr", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (get_is_active() == UVM_ACTIVE) begin
      drv.seq_item_port.connect(sqr.seq_item_export);
    end
  endfunction
endclass

// =========================================================================
// 8. UVM Environment
// =========================================================================
class inand_env extends uvm_env;
  `uvm_component_utils(inand_env)

  inand_agent      agent;
  inand_scoreboard scb;

  function new(string name = "inand_env", uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    agent = inand_agent::type_id::create("agent", this);
    scb   = inand_scoreboard::type_id::create("scb", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    agent.mon.analysis_port.connect(scb.item_collected_export);
  endfunction
endclass

// =========================================================================
// 9. UVM Test
// =========================================================================
class inand_test extends uvm_test;
  `uvm_component_utils(inand_test)

  inand_env env;

  function new(string name = "inand_test", uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = inand_env::type_id::create("env", this);
  endfunction

  task run_phase(uvm_phase phase);
    inand_sequence seq;
    
    phase.raise_objection(this);
    `uvm_info("TEST", "Starting eMMC UVM Test Sequence...", UVM_LOW)
    
    seq = inand_sequence::type_id::create("seq");
    seq.start(env.agent.sqr);
    
    #50000ns; // Drain time
    phase.drop_objection(this);
    `uvm_info("TEST", "eMMC UVM Test Sequence Completed.", UVM_LOW)
  endtask
endclass

// =========================================================================
// 10. Top-Level Harness Module
// =========================================================================
module tb_top;
  logic clk;
  logic rst_n;

  always #5 clk = ~clk;

  inand_if n_if (.clk(clk), .rst_n(rst_n));

  inand_dut dut (
    .clk      (clk),
    .rst_n    (rst_n),
    .cmd_stb  (n_if.cmd_stb),
    .cmd_code (n_if.cmd_code),
    .lba      (n_if.lba),
    .wr_en    (n_if.wr_en),
    .dat_in   (n_if.dat_in),
    .dat_out  (n_if.dat_out),
    .dat_vld  (n_if.dat_vld),
    .ready    (n_if.ready)
  );

  initial begin
    clk   = 0;
    rst_n = 0;
    #25;
    rst_n = 1;
  end

  initial begin
    uvm_config_db #(virtual inand_if)::set(null, "*", "vif", n_if);
    run_test("inand_test");
  end

  initial begin
    $dumpfile("dump.vcd");
    $dumpvars(0, tb_top);
  end
endmodule