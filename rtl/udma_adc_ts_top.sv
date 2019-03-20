

module udma_adc_ts_top #(
  parameter L2_AWIDTH_NOAL  = 12,
  parameter UDMA_TRANS_SIZE = 16,
  parameter TRANS_SIZE      = 16,
  parameter TS_DATA_WIDTH   = 28,
  parameter TS_ID_LSB       = 28,
  parameter TS_NUM_CHS      = 8   )
(
  input  logic                       sys_clk_i,
  input  logic                       ts_clk_i,
  input  logic                       rst_ni,

  input  logic                [31:0] cfg_data_i,
  input  logic                 [4:0] cfg_addr_i,
  input  logic                       cfg_valid_i,
  input  logic                       cfg_rwn_i,
  output logic                [31:0] cfg_data_o,
  output logic                       cfg_ready_o,

  output logic  [L2_AWIDTH_NOAL-1:0] cfg_rx_startaddr_o,
  output logic [UDMA_TRANS_SIZE-1:0] cfg_rx_size_o,
  output logic                       cfg_rx_continuous_o,
  output logic                       cfg_rx_en_o,
  output logic                       cfg_rx_clr_o,
  input  logic                       cfg_rx_en_i,
  input  logic                       cfg_rx_pending_i,
  input  logic  [L2_AWIDTH_NOAL-1:0] cfg_rx_curr_addr_i,
  input  logic [UDMA_TRANS_SIZE-1:0] cfg_rx_bytes_left_i,
              
  output logic                 [1:0] data_rx_datasize_o,
  output logic                [31:0] data_rx_o,
  output logic                       data_rx_valid_o,
  input  logic                       data_rx_ready_i,

  // Timestamp signals
  input  logic      [TS_NUM_CHS-1:0] ts_valid_async_i,
  input  logic   [TS_DATA_WIDTH-1:0] ts_data_i
);


  localparam TS_ID_WIDTH = $clog2(TS_NUM_CHS);

  logic [2:0][TS_NUM_CHS-1:0] ts_data_valid_sync;
  logic      [TS_NUM_CHS-1:0] ts_vld_edge;
  logic   [TS_DATA_WIDTH-1:0] ts_data_sync;

  logic [2:0][TS_NUM_CHS-1:0] sys_data_valid_sync;
  logic      [TS_NUM_CHS-1:0] sys_vld_edge;
  logic                       sys_udma_valid_SP, sys_udma_valid_SN;
  logic                [31:0] sys_data_sync;
  logic                [31:0] sys_merged_data;
  logic     [TS_ID_WIDTH-1:0] sys_id_bin;

  assign data_rx_valid_o = sys_udma_valid_SP;
  assign data_rx_o       = sys_data_sync;


  // sync & edge detect of individual sync channels - ts clock side
  always_ff @(posedge ts_clk_i, negedge rst_ni) begin
    if ( rst_ni == 1'b0 ) begin
      ts_data_valid_sync    <= '0;
      ts_data_sync          <= '0;
    end
    else begin
      ts_data_valid_sync[0] <= ts_valid_async_i;
      ts_data_valid_sync[1] <= ts_data_valid_sync[0];
      ts_data_valid_sync[2] <= ts_data_valid_sync[1];

      if (|ts_vld_edge) ts_data_sync <= ts_data_i;

    end
  end

  // sync & edge detect of individual sync channels - sys clock side
  always_ff @(posedge sys_clk_i, negedge rst_ni) begin
    if ( rst_ni == 1'b0 ) begin
      sys_data_valid_sync    <= '0;
      sys_udma_valid_SP      <= '0;
      sys_data_sync          <= '0;
    end
    else begin
      sys_data_valid_sync[0] <= ts_data_valid_sync[2]; // handover between clock domains here
      sys_data_valid_sync[1] <= sys_data_valid_sync[0];
      sys_data_valid_sync[2] <= sys_data_valid_sync[1];
      sys_udma_valid_SP      <= sys_udma_valid_SN;

      if (|sys_vld_edge) sys_data_sync <= sys_merged_data;

    end
  end

  onehot_to_bin #(
    .ONEHOT_WIDTH (TS_NUM_CHS)
  ) onehot_to_bin_ch_id_i 
  (
    .onehot ( sys_vld_edge ),
    .bin    ( sys_id_bin )
  );

  assign ts_vld_edge  = (ts_data_valid_sync[1]  & ~ts_data_valid_sync[2])  | (~ts_data_valid_sync[1]  & ts_data_valid_sync[2]);
  assign sys_vld_edge = (sys_data_valid_sync[1] & ~sys_data_valid_sync[2]) | (~sys_data_valid_sync[1] & sys_data_valid_sync[2]);

  always_comb begin
    sys_merged_data = '0;
    sys_merged_data[TS_DATA_WIDTH-1:0]                 = ts_data_sync; // handover between clock domains here
    sys_merged_data[TS_ID_LSB+TS_ID_WIDTH-1:TS_ID_LSB] = sys_id_bin;
  end


  always_comb begin
    sys_udma_valid_SN = sys_udma_valid_SP;
    if (|sys_vld_edge)
      sys_udma_valid_SN = 1'b1;
    else if (data_rx_ready_i)
      sys_udma_valid_SN = 1'b0;
  end


  udma_adc_ts_reg_if #(
    .L2_AWIDTH_NOAL  ( L2_AWIDTH_NOAL  ),
    .UDMA_TRANS_SIZE ( UDMA_TRANS_SIZE ),
    .TRANS_SIZE      ( TRANS_SIZE      )
  ) udma_adc_ts_reg_if_i
  (
    .clk_i               ( sys_clk_i            ),
    .rstn_i              ( rst_ni               ),

    .cfg_data_i          ( cfg_data_i           ),
    .cfg_addr_i          ( cfg_addr_i           ),
    .cfg_valid_i         ( cfg_valid_i          ),
    .cfg_rwn_i           ( cfg_rwn_i            ),
    .cfg_data_o          ( cfg_data_o           ),
    .cfg_ready_o         ( cfg_ready_o          ),

    .cfg_rx_startaddr_o  ( cfg_rx_startaddr_o   ),
    .cfg_rx_size_o       ( cfg_rx_size_o        ),
    .cfg_rx_datasize_o   ( data_rx_datasize_o   ),
    .cfg_rx_continuous_o ( cfg_rx_continuous_o  ),
    .cfg_rx_en_o         ( cfg_rx_en_o          ),
    .cfg_rx_clr_o        ( cfg_rx_clr_o         ),
    .cfg_rx_en_i         ( cfg_rx_en_i          ),
    .cfg_rx_pending_i    ( cfg_rx_pending_i     ),
    .cfg_rx_curr_addr_i  ( cfg_rx_curr_addr_i   ),
    .cfg_rx_bytes_left_i ( cfg_rx_bytes_left_i  )
  );


endmodule