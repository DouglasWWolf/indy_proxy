//====================================================================================
//                        ------->  Revision History  <------
//====================================================================================
//
//   Date     Who   Ver  Changes
//====================================================================================
// 22-Nov-26  DWW     1  Initial creation
//====================================================================================

/*
    Provides AXI register access to a TEC and the two temperature sensors 
    that it uses

    For sensor-error reporting:
        Bit 0 = I2C error occurred, both internal and external temperatures are invalid
        Bit 1 = A diode error occurred, external temperature is invalid
*/


module tec_ctl # (parameter AW=8)
(
    input clk, resetn,

    // Internal temperatures of temperature sensors
    input[7:0]  internal_temp_0, internal_temp_1,

    // External temperatures of temperature sensors
    input[9:0]  external_temp_0, external_temp_1,

    // Error reporting from the temperature sensors
    input[1:0] sensor_err_0, sensor_err_1,

    // These are used to clear sensor errors
    output reg[1:0] clear_sensor_err_stb_0,
    output reg[1:0] clear_sensor_err_stb_1,

    //================== This is an AXI4-Lite slave interface ==================
        
    // "Specify write address"              -- Master --    -- Slave --
    input[AW-1:0]                           S_AXI_AWADDR,   
    input                                   S_AXI_AWVALID,  
    input[   2:0]                           S_AXI_AWPROT,
    output                                                  S_AXI_AWREADY,


    // "Write Data"                         -- Master --    -- Slave --
    input[31:0]                             S_AXI_WDATA,      
    input                                   S_AXI_WVALID,
    input[ 3:0]                             S_AXI_WSTRB,
    output                                                  S_AXI_WREADY,

    // "Send Write Response"                -- Master --    -- Slave --
    output[1:0]                                             S_AXI_BRESP,
    output                                                  S_AXI_BVALID,
    input                                   S_AXI_BREADY,

    // "Specify read address"               -- Master --    -- Slave --
    input[AW-1:0]                           S_AXI_ARADDR,     
    input[   2:0]                           S_AXI_ARPROT,     
    input                                   S_AXI_ARVALID,
    output                                                  S_AXI_ARREADY,

    // "Read data back to master"           -- Master --    -- Slave --
    output[31:0]                                            S_AXI_RDATA,
    output                                                  S_AXI_RVALID,
    output[ 1:0]                                            S_AXI_RRESP,
    input                                   S_AXI_RREADY
    //==========================================================================
);  


//=========================  AXI Register Map  =============================


/*
    @register Temp sensor 0: internal temperature
    @rdesc    In degrees C
    @rtype    RO    
*/
localparam REG_TS0_INT_C   = 0;


/*
    @register Temp sensor 1: internal temperature
    @rdesc    In degrees C
    @rtype    RO    
*/
localparam REG_TS1_INT_C   = 1;

/*
    @register Temp sensor 0: external temperature
    @rdesc    In 100ths of a degree C
    @rtype    RO    
*/
localparam REG_TS0_EXT_C   = 2;


/*
    @register Temp sensor 1: external temperature
    @rdesc    In 100ths of a degree C
    @rtype    RO
*/
localparam REG_TS1_EXT_C   = 3;

/*
    @register Temp sensor 0: errors
    @rdesc    Bit 0: 1 = I2C error
    @rdesc    Bit 1: 1 = Diode error
    @rtype    W1C    
*/
localparam REG_TS0_ERROR   = 4;

/*
    @register Temp sensor 1: errors
    @rdesc    Bit 0: 1 = I2C error
    @rdesc    Bit 1: 1 = Diode error
    @rtype    W1C
*/
localparam REG_TS1_ERROR   = 5;
//==========================================================================


//==========================================================================
// We'll communicate with the AXI4-Lite Slave core with these signals.
//==========================================================================
// AXI Slave Handler Interface for write requests
wire[  31:0]  ashi_windx;     // Input   Write register-index
wire[AW-1:0]  ashi_waddr;     // Input:  Write-address
wire[  31:0]  ashi_wdata;     // Input:  Write-data
wire          ashi_write;     // Input:  1 = Handle a write request
reg [   1:0]  ashi_wresp;     // Output: Write-response (OKAY, DECERR, SLVERR)
wire          ashi_widle;     // Output: 1 = Write state machine is idle

// AXI Slave Handler Interface for read requests
wire[  31:0]  ashi_rindx;     // Input   Read register-index
wire[AW-1:0]  ashi_raddr;     // Input:  Read-address
wire          ashi_read;      // Input:  1 = Handle a read request
reg [  31:0]  ashi_rdata;     // Output: Read data
reg [   1:0]  ashi_rresp;     // Output: Read-response (OKAY, DECERR, SLVERR);
wire          ashi_ridle;     // Output: 1 = Read state machine is idle
//==========================================================================

// The state of the state-machines that handle AXI4-Lite read and AXI4-Lite write
reg ashi_write_state, ashi_read_state;

// The AXI4 slave state machines are idle when in state 0 and their "start" signals are low
assign ashi_widle = (ashi_write == 0) && (ashi_write_state == 0);
assign ashi_ridle = (ashi_read  == 0) && (ashi_read_state  == 0);
   
// These are the valid values for ashi_rresp and ashi_wresp
localparam OKAY   = 0;
localparam SLVERR = 2;
localparam DECERR = 3;

// This is how we report a broken sensor
localparam BROKEN = 0;

//==========================================================================
// Compute temperatures in Celsius
//==========================================================================
reg[31:0] external_c[0:1], internal_c[0:1];
always @(posedge clk) begin
    external_c[0] <= (external_temp_0 * 25) - 6400;
    external_c[1] <= (external_temp_1 * 25) - 6400;
    internal_c[0] <= (internal_temp_0) - 64;
    internal_c[1] <= (internal_temp_1) - 64;
end
//==========================================================================


//==========================================================================
// This state machine handles AXI4-Lite write requests
//==========================================================================
always @(posedge clk) begin

    // These strobe high for a single cycle at a time
    clear_sensor_err_stb_0 <= 0;
    clear_sensor_err_stb_1 <= 0;

    // If we're in reset, initialize important registers
    if (resetn == 0) begin
        ashi_write_state  <= 0;
    end
    
    // Otherwise, we're not in reset...
    else case (ashi_write_state)
        
        // If an AXI write-request has occured...
        0:  if (ashi_write) begin
       
                // Assume for the moment that the result will be OKAY
                ashi_wresp <= OKAY;              
            
                // ashi_windex = index of register to be written
                case (ashi_windx)
               
                    REG_TS0_ERROR:  clear_sensor_err_stb_0 <= ashi_wdata;
                    REG_TS1_ERROR:  clear_sensor_err_stb_1 <= ashi_wdata;

                    // Writes to any other register are a decode-error
                    default: ashi_wresp <= DECERR;
                endcase
            end

        // Dummy state, doesn't do anything
        1: ashi_write_state <= 0;

    endcase
end
//==========================================================================



//==========================================================================
// World's simplest state machine for handling AXI4-Lite read requests
//==========================================================================
always @(posedge clk) begin

    // If we're in reset, initialize important registers
    if (resetn == 0) begin
        ashi_read_state <= 0;
    end
    
    // If we're not in reset, and a read-request has occured...        
    else if (ashi_read) begin
   
        // Assume for the moment that the result will be OKAY
        ashi_rresp <= OKAY;              
        
        // ashi_rindex = index of register to be read
        case (ashi_rindx)
            
            // Allow a read from any valid register                
            REG_TS0_INT_C:  ashi_rdata <= (sensor_err_0[0]) ? BROKEN : internal_c[0];
            REG_TS1_INT_C:  ashi_rdata <= (sensor_err_1[0]) ? BROKEN : internal_c[1];
            REG_TS0_EXT_C:  ashi_rdata <= (sensor_err_0)    ? BROKEN : external_c[0];
            REG_TS1_EXT_C:  ashi_rdata <= (sensor_err_1)    ? BROKEN : external_c[1];
            REG_TS0_ERROR:  ashi_rdata <= sensor_err_0;
            REG_TS1_ERROR:  ashi_rdata <= sensor_err_1;

            // Reads of any other register are a decode-error
            default:
                begin
                    ashi_rresp <= DECERR;
                    ashi_rdata <= 0;
                end

        endcase
    end
end
//==========================================================================



//==========================================================================
// This connects us to an AXI4-Lite slave core
//==========================================================================
axi4_lite_slave#(.AW(AW)) i_axi4lite_slave
(
    .clk            (clk),
    .resetn         (resetn),
    
    // AXI AW channel
    .AXI_AWADDR     (S_AXI_AWADDR),
    .AXI_AWPROT     (S_AXI_AWPROT),
    .AXI_AWVALID    (S_AXI_AWVALID),   
    .AXI_AWREADY    (S_AXI_AWREADY),
    
    // AXI W channel
    .AXI_WDATA      (S_AXI_WDATA),
    .AXI_WVALID     (S_AXI_WVALID),
    .AXI_WSTRB      (S_AXI_WSTRB),
    .AXI_WREADY     (S_AXI_WREADY),

    // AXI B channel
    .AXI_BRESP      (S_AXI_BRESP),
    .AXI_BVALID     (S_AXI_BVALID),
    .AXI_BREADY     (S_AXI_BREADY),

    // AXI AR channel
    .AXI_ARADDR     (S_AXI_ARADDR), 
    .AXI_ARPROT     (S_AXI_ARPROT),
    .AXI_ARVALID    (S_AXI_ARVALID),
    .AXI_ARREADY    (S_AXI_ARREADY),

    // AXI R channel
    .AXI_RDATA      (S_AXI_RDATA),
    .AXI_RVALID     (S_AXI_RVALID),
    .AXI_RRESP      (S_AXI_RRESP),
    .AXI_RREADY     (S_AXI_RREADY),

    // ASHI write-request registers
    .ASHI_WADDR     (ashi_waddr),
    .ASHI_WINDX     (ashi_windx),
    .ASHI_WDATA     (ashi_wdata),
    .ASHI_WRITE     (ashi_write),
    .ASHI_WRESP     (ashi_wresp),
    .ASHI_WIDLE     (ashi_widle),

    // ASHI read registers
    .ASHI_RADDR     (ashi_raddr),
    .ASHI_RINDX     (ashi_rindx),
    .ASHI_RDATA     (ashi_rdata),
    .ASHI_READ      (ashi_read ),
    .ASHI_RRESP     (ashi_rresp),
    .ASHI_RIDLE     (ashi_ridle)
);
//==========================================================================



endmodule
