`ifndef __SYS_CONFIG_VH__
`define __SYS_CONFIG_VH__

`define NUM_ROB        8
`define NUM_PR         64
`define NUM_ALU        1
`define NUM_MULT       1
`define NUM_BR         1
`define NUM_ST         1
`define NUM_LD         1
`define NUM_FU         (`NUM_ALU + 2 + `NUM_MULT + NUM_BR)
`define NUM_ARCH_TABLE 32
`define NUM_MAP_TABLE  32

`endif