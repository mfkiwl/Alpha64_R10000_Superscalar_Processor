/////////////////////////////////////////////////////////////////////////
//                                                                     //
//   Modulename :  pipeline.v                                          //
//                                                                     //
//  Description :  Top-level module of the verisimple pipeline;        //
//                 This instantiates and connects the 5 stages of the  //
//                 Verisimple pipeline togeather.                      //
//                                                                     //
//                                                                     //
/////////////////////////////////////////////////////////////////////////

`timescale 1ns/100ps

module pipeline (
  input         clock,                    // System clock
  input         reset,                    // System reset
  input [3:0]   mem2proc_response,        // Tag from memory about current request
  input [63:0]  mem2proc_data,            // Data coming back from memory
  input [3:0]   mem2proc_tag,              // Tag from memory about current reply
  output logic [1:0]  proc2mem_command,    // command sent to memory
  output logic [63:0] proc2mem_addr,      // Address sent to memory
  output logic [63:0] proc2mem_data,      // Data sent to memory
  output logic [3:0]  pipeline_completed_insts,
  output ERROR_CODE   pipeline_error_status,
  output logic [4:0]  pipeline_commit_wr_idx,
  output logic [63:0] pipeline_commit_wr_data,
  output logic        pipeline_commit_wr_en,
  output logic [63:0] pipeline_commit_NPC,
  // testing hooks (these must be exported so we can test
  // the synthesized version) data is tested by looking at
  // the final values in memory
  // Outputs from IF-Stage 
  output logic [63:0] if_NPC_out,
  output logic [31:0] if_IR_out,
  output logic        if_valid_inst_out,
  // Outputs from IF/ID Pipeline Register
  output logic [63:0] if_id_NPC,
  output logic [31:0] if_id_IR,
  output logic        if_id_valid_inst,
  // Outputs from ID/EX Pipeline Register
  output logic [63:0] id_ex_NPC,
  output logic [31:0] id_ex_IR,
  output logic        id_ex_valid_inst,
  // Outputs from EX/MEM Pipeline Register
  output logic [63:0] ex_mem_NPC,
  output logic [31:0] ex_mem_IR,
  output logic        ex_mem_valid_inst,
  // Outputs from MEM/WB Pipeline Register
  output logic [63:0] mem_wb_NPC,
  output logic [31:0] mem_wb_IR,
  output logic        mem_wb_valid_inst
);

  // Pipeline register enables
  logic   if_id_enable, id_ex_enable, ex_mem_enable, mem_wb_enable;

  // Outputs from IF stage
  IF_ID_PACKET if_packet_out;
  // Outputs from ID/EX Pipeline Register
  IF_ID_PACKET if_id_packet;

  // Outputs from ID stage
  ID_EX_PACKET id_packet_out;
  // Outputs from ID/EX Pipeline Register
  ID_EX_PACKET id_ex_packet;

  // Outputs from EX-Stage
  EX_MEM_PACKET ex_packet_out;
  // Outputs from EX/MEM Pipeline Register
  EX_MEM_PACKET ex_mem_packet;

  // Outputs from MEM-Stage
  MEM_WB_PACKET mem_packet_out;
  // Outputs from MEM/WB Pipeline Register
  MEM_WB_PACKET mem_wb_packet;

  // Outputs from WB-Stage  (These loop back to the register file in ID)
  WB_REG_PACKET wb_packet_out;

  // Memory interface/arbiter wires
  logic [63:0] proc2Dmem_addr, proc2Imem_addr;
  logic  [1:0] proc2Dmem_command, proc2Imem_command;
  logic  [3:0] Imem2proc_response, Dmem2proc_response;

  // Icache wires
  logic [63:0] cachemem_data;
  logic        cachemem_valid;
  logic  [4:0] Icache_rd_idx;
  logic  [7:0] Icache_rd_tag;
  logic  [4:0] Icache_wr_idx;
  logic  [7:0] Icache_wr_tag;
  logic        Icache_wr_en;
  logic [63:0] Icache_data_out, proc2Icache_addr;
  logic        Icache_valid_out;

  assign pipeline_completed_insts = {3'b0, mem_wb_packet.valid};
  assign pipeline_error_status    = mem_wb_packet.illegal  ? HALTED_ON_ILLEGAL :
                                    mem_wb_packet.halt     ? HALTED_ON_HALT :
                                    NO_ERROR;

  assign pipeline_commit_wr_idx  = wb_packet_out.wr_idx;
  assign pipeline_commit_wr_data = wb_packet_out.wr_data;
  assign pipeline_commit_wr_en   = wb_packet_out.wr_en;
  assign pipeline_commit_NPC     = mem_wb_NPC;

  assign proc2mem_command   = (proc2Dmem_command == BUS_NONE) ? proc2Imem_command:proc2Dmem_command;
  assign proc2mem_addr      = (proc2Dmem_command == BUS_NONE) ? proc2Imem_addr:proc2Dmem_addr;
  assign Dmem2proc_response = (proc2Dmem_command == BUS_NONE) ? 0 : mem2proc_response;
  assign Imem2proc_response = (proc2Dmem_command == BUS_NONE) ? mem2proc_response : 0;

  // Actual cache (data and tag RAMs)
  cache cachememory (// inputs
    .clock(clock),
    .reset(reset),
    .wr1_en(Icache_wr_en),
    .wr1_idx(Icache_wr_idx),
    .wr1_tag(Icache_wr_tag),
    .wr1_data(mem2proc_data),
    .rd1_idx(Icache_rd_idx),
    .rd1_tag(Icache_rd_tag),
    // outputs
    .rd1_data(cachemem_data),
    .rd1_valid(cachemem_valid)
  );
  // Cache controller
  icache icache_0(// inputs 
    .clock(clock),
    .reset(reset),
    .Imem2proc_response(Imem2proc_response),
    .Imem2proc_data(mem2proc_data),
    .Imem2proc_tag(mem2proc_tag),
    .proc2Icache_addr(proc2Icache_addr),
    .cachemem_data(cachemem_data),
    .cachemem_valid(cachemem_valid),
    // outputs
    .proc2Imem_command(proc2Imem_command),
    .proc2Imem_addr(proc2Imem_addr),
    .Icache_data_out(Icache_data_out),
    .Icache_valid_out(Icache_valid_out),
    .current_index(Icache_rd_idx),
    .current_tag(Icache_rd_tag),
    .last_index(Icache_wr_idx),
    .last_tag(Icache_wr_tag),
    .data_write_enable(Icache_wr_en)
  );
  //////////////////////////////////////////////////
  //                                              //
  //                  IF-Stage                    //
  //                                              //
  //////////////////////////////////////////////////
  assign if_NPC_out = if_packet_out.NPC;
  assign if_IR_out = if_packet_out.inst;
  assign if_valid_inst_out = if_packet_out.valid;
  if_stage if_stage_0 (
    // Inputs
    .clock (clock),
    .reset (reset),
    .mem_wb_packet_in(mem_wb_packet),
    .ex_mem_packet_in(ex_mem_packet),
    .Imem2proc_data(Icache_data_out),
    .Imem_valid(Icache_valid_out),
    // Outputs
    .proc2Imem_addr(proc2Icache_addr),
    .if_packet_out(if_packet_out)
  );
  //////////////////////////////////////////////////
  //                                              //
  //            IF/ID Pipeline Register           //
  //                                              //
  //////////////////////////////////////////////////
  assign if_id_NPC        = if_id_packet.NPC;
  assign if_id_IR         = if_id_packet.inst;
  assign if_id_valid_inst = if_id_packet.valid;
  assign if_id_enable = 1'b1; // always enabled
  // synopsys sync_set_reset "reset"
  always_ff @(posedge clock) begin
    if(reset) begin
      if_id_packet <= `SD `IF_ID_PACKET_RESET;
    end // if (reset)
    else if (if_id_enable) begin
        if_id_packet <= `SD if_packet_out; 
    end // if (if_id_enable)
  end // always
  //////////////////////////////////////////////////
  //                                              //
  //                  ID-Stage                    //
  //                                              //
  //////////////////////////////////////////////////
  id_stage id_stage_0 (// Inputs
    .clock(clock),
    .reset(reset),
    .if_id_packet_in(if_id_packet),
    .wb_reg_packet_in(wb_packet_out),

    // Outputs
    .id_packet_out(id_packet_out)
  );
  // Note: Decode signals for load-lock/store-conditional and "get CPU ID"
  //  instructions (id_{ldl,stc}_mem_out, id_cpuid_out) are not connected
  //  to anything because the provided EX and MEM stages do not implement
  //  these instructions.  You will have to implement these instructions
  //  if you plan to do a multicore project.
  //////////////////////////////////////////////////
  //                                              //
  //            ID/EX Pipeline Register           //
  //                                              //
  //////////////////////////////////////////////////
  assign id_ex_NPC        = id_ex_packet.NPC;
  assign id_ex_IR         = id_ex_packet.inst;
  assign id_ex_valid_inst = id_ex_packet.valid;
  assign id_ex_enable = 1'b1; // always enabled
  // synopsys sync_set_reset "reset"
  always_ff @(posedge clock) begin
    if (reset) begin
      id_ex_packet <= `SD `ID_EX_PACKET_RESET; 
    end else begin // if (reset)
      if (id_ex_enable) begin
        id_ex_packet <= `SD id_packet_out;
      end // if
    end // else: !if(reset)
  end // always
  //////////////////////////////////////////////////
  //                                              //
  //                  EX-Stage                    //
  //                                              //
  //////////////////////////////////////////////////
  ex_stage ex_stage_0 (
    // Inputs
    .clock(clock),
    .reset(reset),
    .id_ex_packet_in(id_ex_packet),
    // Outputs
    .ex_packet_out(ex_packet_out)
  );
  //////////////////////////////////////////////////
  //                                              //
  //           EX/MEM Pipeline Register           //
  //                                              //
  //////////////////////////////////////////////////
  assign ex_mem_NPC = ex_mem_packet.NPC;
  assign ex_mem_IR = ex_mem_packet.inst;
  assign ex_mem_valid_inst = ex_mem_packet.valid;
  assign ex_mem_enable = ~mem_packet_out.stall;
  // synopsys sync_set_reset "reset"
  always_ff @(posedge clock) begin
    if (reset) begin
      ex_mem_packet <= `SD `EX_MEM_PACKET_RESET;
    end else begin
      if (ex_mem_enable) begin
        // these are forwarded directly from ID/EX latches
        ex_mem_packet <= `SD ex_packet_out;
      end // if
    end // else: !if(reset)
  end // always
  //////////////////////////////////////////////////
  //                                              //
  //                 MEM-Stage                    //
  //                                              //
  //////////////////////////////////////////////////
  mem_stage mem_stage_0 (// Inputs
    .clock(clock),
    .reset(reset),
    .ex_mem_packet_in(ex_mem_packet),
    .Dmem2proc_data(mem2proc_data),
    .Dmem2proc_tag(mem2proc_tag),
    .Dmem2proc_response(Dmem2proc_response),
     // Outputs
    .mem_packet_out(mem_packet_out),
    .proc2Dmem_command(proc2Dmem_command),
    .proc2Dmem_addr(proc2Dmem_addr),
    .proc2Dmem_data(proc2mem_data)
  );
  //////////////////////////////////////////////////
  //                                              //
  //           MEM/WB Pipeline Register           //
  //                                              //
  //////////////////////////////////////////////////
  assign mem_wb_NPC        = mem_wb_packet.NPC;
  assign mem_wb_IR         = mem_wb_packet.inst;
  assign mem_wb_valid_inst = mem_wb_packet.valid;
  assign mem_wb_enable = 1'b1; // always enabled
  // synopsys sync_set_reset "reset"
  always_ff @(posedge clock) begin
    if (reset) begin
      mem_wb_packet <= `SD `MEM_WB_PACKET_RESET;
    end else begin
      if (mem_wb_enable) begin
        // these are forwarded directly from EX/MEM latches
        mem_wb_packet <= `SD mem_packet_out;
      end // if
    end // else: !if(reset)
  end // always
  //////////////////////////////////////////////////
  //                                              //
  //                  WB-Stage                    //
  //                                              //
  //////////////////////////////////////////////////
  wb_stage wb_stage_0 (
    // Inputs
    .clock(clock),
    .reset(reset),
    .mem_wb_packet_in(mem_wb_packet),
    // Outputs
    .wb_packet_out(wb_packet_out)
  );
endmodule  // module verisimple
