//====================================================================================
//                        ------->  Revision History  <------
//====================================================================================
//
//   Date     Who   Ver  Changes
//====================================================================================
// 22-Nov-26  DWW     1  Initial creation
//====================================================================================

/*
    This serves as AXI register access to a 512-byte MC24C04 EEPROM that sits on
    the other side of an I2C interface

    An oddity of this particular EEPROM is that the top bit of the 9 bit address
    is stored into the bottom bit of the I2C device address.  This means that the
    bottom 256 bytes of the EEPROM are on I2C device 0x50, and the top 256 bytes
    of the EEPROM are on I2C device 0x51
*/


module eeprom_ctl # (parameter AW=8, FREQ_HZ = 250000000)
(
    input clk, resetn,

    output reg[ 6:0] i2c_addr,
    output reg[ 2:0] extra_bytes,
    output reg[ 7:0] reg_addr,
    output reg[63:0] wdata,
    output reg       cmd,
    output reg       cmd_start_stb,
    output reg       big_endian,
    
    input     [63:0] rdata,
    input     [ 3:0] i2c_error,
    input            idle,


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
    @register The 9-bit EEPROM address to read/write.  
    @rdesc    The lower two bits will be forced to zero in order to
    @rdesc    enforce 4-byte boundaries.
*/
localparam REG_ADDRESS    = 0;

/*
    @register Four bytes of data to be written to EEPROM
*/
localparam REG_WDATA      = 1;

/*
    @register EEPROM command:
    @rdesc    >   0 = Read from EEPROM, return little-endian data
    @rdesc    >   1 = Write  to EEPROM, using little-endian data
    @rdesc    >   2 = Read from EEPROM, return big-endian data
    @rdesc    >   3 = Write  to EEPROM, using big-endian data
    @rdesc    >
    @rdesc    >  EEPROM_IDLE must be high before you write to EEPROM_CMD!

*/
localparam REG_CMD        = 2;

/*
    @register Four bytes of data that were read from EEPROM
    @rtype    RO    
*/
localparam REG_RDATA      = 3;

/*
    @register If this is 1, the most recent read/write command is complete
    @rtype    RO    
*/
localparam REG_IDLE       = 4;

/*
    @register Once a read/write command completes, this reports any errors
    @rdesc    Non-zero means an error occurred
    @rdesc    0 = OK, 1 = arbitration lost, 2 = NACK received, 3 = timeout
    @rtype    RO
*/
localparam REG_ERROR      = 5;
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

// The MC24C04 requires a 5 ms delay after writing.   Here we add an extra 
// millisecond to that to account for the time it takes for the I2C transaction 
// to reach the EEPROM and for the EEPROM to begin its write-cycle
localparam WRITE_DELAY = 6 * FREQ_HZ / 1000;

// This is used to count-down the delay after writing to EEPROM
reg[31:0] write_timer;

// When this is asserted, the EEPROM is idle
wire eeprom_idle = idle && (write_timer == 0);

//==========================================================================
// This state machine handles AXI4-Lite write requests
//==========================================================================
always @(posedge clk) begin

    // This strobes high for a single cycle at a time
    cmd_start_stb <= 0;

    // When this countdown timer reaches zero, we can assume that the
    // EEPROM has completed the most recent write command
    if (write_timer) write_timer <= write_timer - 1;

    // If we're in reset, initialize important registers
    if (resetn == 0) begin
        i2c_addr          <= 7'h50;
        ashi_write_state  <= 0;
        extra_bytes       <= 3;
        reg_addr          <= 0;
        wdata             <= 0;
        cmd               <= 0;
        big_endian        <= 0;
        write_timer       <= 0;
    end
    
    // Otherwise, we're not in reset...
    else case (ashi_write_state)
        
        // If an AXI write-request has occured...
        0:  if (ashi_write) begin
       
                // Assume for the moment that the result will be OKAY
                ashi_wresp <= OKAY;              
            
                // ashi_windex = index of register to be written
                case (ashi_windx)

                    REG_ADDRESS:
                        begin
                            reg_addr    <= {ashi_wdata[7:2], 2'b0};
                            i2c_addr[0] <= ashi_wdata[8];
                        end

                    REG_WDATA:  wdata <= {32'b0, ashi_wdata};

                    REG_CMD:
                        if (eeprom_idle) begin
                            big_endian    <= ashi_wdata[1];
                            cmd           <= ashi_wdata[0];
                            cmd_start_stb <= 1;
                            write_timer   <= (ashi_wdata[0]) ? WRITE_DELAY : 0;
                        end else
                            ashi_wresp <= SLVERR;

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
    
    // If we're not in reset, and a read-request has occured...        
    end else if (ashi_read) begin
   
        // Assume for the moment that the result will be OKAY
        ashi_rresp <= OKAY;              
        
        // ashi_rindex = index of register to be read
        case (ashi_rindx)
            
            // Allow a read from any valid register                
            REG_ADDRESS:    ashi_rdata <= {i2c_addr[0], reg_addr};
            REG_WDATA  :    ashi_rdata <= wdata[31:0];
            REG_CMD    :    ashi_rdata <= {big_endian, cmd};
            REG_RDATA  :    ashi_rdata <= rdata[31:0];
            REG_IDLE   :    ashi_rdata <= eeprom_idle;
            REG_ERROR  :    ashi_rdata <= i2c_error;

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
