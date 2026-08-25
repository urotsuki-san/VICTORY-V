package vv32_pkg;
  localparam logic [5:0] OP_NOP      = 6'h00;
  localparam logic [5:0] OP_MOV      = 6'h01;
  localparam logic [5:0] OP_MOVI     = 6'h02;
  localparam logic [5:0] OP_LUI      = 6'h03;
  localparam logic [5:0] OP_ADD      = 6'h04;
  localparam logic [5:0] OP_ADDI     = 6'h05;
  localparam logic [5:0] OP_SUB      = 6'h06;
  localparam logic [5:0] OP_MUL      = 6'h07;
  localparam logic [5:0] OP_AND      = 6'h08;
  localparam logic [5:0] OP_ANDI     = 6'h09;
  localparam logic [5:0] OP_OR       = 6'h0a;
  localparam logic [5:0] OP_ORI      = 6'h0b;
  localparam logic [5:0] OP_XOR      = 6'h0c;
  localparam logic [5:0] OP_XORI     = 6'h0d;
  localparam logic [5:0] OP_SHL      = 6'h0e;
  localparam logic [5:0] OP_SHR      = 6'h0f;
  localparam logic [5:0] OP_SAR      = 6'h10;
  localparam logic [5:0] OP_CMPEQ    = 6'h11;
  localparam logic [5:0] OP_CMPLT    = 6'h12;
  localparam logic [5:0] OP_CMPULT   = 6'h13;
  localparam logic [5:0] OP_BRZ      = 6'h14;
  localparam logic [5:0] OP_BRNZ     = 6'h15;
  localparam logic [5:0] OP_JAL      = 6'h16;
  localparam logic [5:0] OP_JALR     = 6'h17;
  localparam logic [5:0] OP_HALT     = 6'h18;
  localparam logic [5:0] OP_TRAP     = 6'h19;
  localparam logic [5:0] OP_CSRR     = 6'h1a;
  localparam logic [5:0] OP_CSRW     = 6'h1b;
  localparam logic [5:0] OP_EI       = 6'h1c;
  localparam logic [5:0] OP_DI       = 6'h1d;
  localparam logic [5:0] OP_VRET     = 6'h1e;

  localparam logic [5:0] OP_CROOT    = 6'h20;
  localparam logic [5:0] OP_CBOUNDS  = 6'h21;
  localparam logic [5:0] OP_CPERM    = 6'h22;
  localparam logic [5:0] OP_CINC     = 6'h23;
  localparam logic [5:0] OP_CGETTAG  = 6'h24;
  localparam logic [5:0] OP_CGETPERM = 6'h25;
  localparam logic [5:0] OP_CLDB     = 6'h26;
  localparam logic [5:0] OP_CLDBU    = 6'h27;
  localparam logic [5:0] OP_CLDH     = 6'h28;
  localparam logic [5:0] OP_CLDHU    = 6'h29;
  localparam logic [5:0] OP_CLDW     = 6'h2a;
  localparam logic [5:0] OP_CSTB     = 6'h2b;
  localparam logic [5:0] OP_CSTH     = 6'h2c;
  localparam logic [5:0] OP_CSTW     = 6'h2d;
  localparam logic [5:0] OP_VDECLASS = 6'h2e;
  localparam logic [5:0] OP_VLOCK    = 6'h2f;

  localparam logic [5:0] OP_VTRY     = 6'h30;
  localparam logic [5:0] OP_VCHK     = 6'h31;
  localparam logic [5:0] OP_VIC      = 6'h32;
  localparam logic [5:0] OP_VABT     = 6'h33;
  localparam logic [5:0] OP_VERR     = 6'h34;
  localparam logic [5:0] OP_WFI      = 6'h35;

  localparam logic [4:0] CAP_R = 5'h01;
  localparam logic [4:0] CAP_W = 5'h02;
  localparam logic [4:0] CAP_X = 5'h04;
  localparam logic [4:0] CAP_S = 5'h08;
  localparam logic [4:0] CAP_D = 5'h10;

  localparam logic [15:0] CSR_VSTATUS       = 16'h0000;
  localparam logic [15:0] CSR_VTVEC         = 16'h0001;
  localparam logic [15:0] CSR_VEPC          = 16'h0002;
  localparam logic [15:0] CSR_VCAUSE        = 16'h0003;
  localparam logic [15:0] CSR_VBADADDR      = 16'h0004;
  localparam logic [15:0] CSR_VCYCLE        = 16'h0005;
  localparam logic [15:0] CSR_VINSTRET      = 16'h0006;
  localparam logic [15:0] CSR_VERROR        = 16'h0007;
  localparam logic [15:0] CSR_VREGION_COUNT = 16'h0008;
  localparam logic [15:0] CSR_VREGION_LIMIT = 16'h0009;

  localparam logic [15:0] CAUSE_NONE                  = 16'd0;
  localparam logic [15:0] CAUSE_ILLEGAL_INSTRUCTION   = 16'd1;
  localparam logic [15:0] CAUSE_INSTRUCTION_ALIGNMENT = 16'd2;
  localparam logic [15:0] CAUSE_CAPABILITY_TAG        = 16'd3;
  localparam logic [15:0] CAUSE_CAPABILITY_BOUNDS     = 16'd4;
  localparam logic [15:0] CAUSE_CAPABILITY_PERMISSION = 16'd5;
  localparam logic [15:0] CAUSE_SECRET_FLOW           = 16'd6;
  localparam logic [15:0] CAUSE_ROOT_LOCKED            = 16'd7;
  localparam logic [15:0] CAUSE_REGION_NESTED          = 16'd8;
  localparam logic [15:0] CAUSE_REGION_STORE_QUOTA     = 16'd9;
  localparam logic [15:0] CAUSE_REGION_BUDGET          = 16'd10;
  localparam logic [15:0] CAUSE_EXPLICIT_TRAP          = 16'd11;
  localparam logic [15:0] CAUSE_DECLASSIFY_DENIED      = 16'd12;
  localparam logic [15:0] CAUSE_INTERRUPT              = 16'd13;
  localparam logic [15:0] CAUSE_DATA_ALIGNMENT         = 16'd14;
  localparam logic [15:0] CAUSE_MEMORY_RANGE           = 16'd15;
  localparam logic [15:0] CAUSE_REGION_REQUIRED        = 16'd16;

  typedef enum logic [3:0] {
    ST_FETCH  = 4'd0,
    ST_EXEC   = 4'd1,
    ST_LOAD   = 4'd2,
    ST_STORE  = 4'd3,
    ST_COMMIT = 4'd4,
    ST_WFI    = 4'd5,
    ST_HALT   = 4'd6
  } vv32_state_t;
endpackage
