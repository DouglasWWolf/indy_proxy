//====================================================================================
//                        ------->  Revision History  <------
//====================================================================================
//
//   Date     Who   Ver  Changes
//====================================================================================
// 26-Feb-26  DWW     1  Initial creation
//====================================================================================

/*

    Provides an orderly power-up/power-down for sensor-chip on Indy

    The rules:
       When in manual control mode, power rails can be brought up and down with
       both the sequencing and timing under script/software control

       When transitioning from manual mode to auto mode, all power rails are
       turned off, *EVEN IF THE POWER_CTL BIT IS ON*.  We do this in order to avoid
       the situation where the RTL turns off the power rails and then immediately
       slams them back on and causes voltage spikes

       When in auto-control mode, turning the POWER_CTL bit on causes an orderly
       power up of the sensor chip.   Turning the POWER_CTL bit off causes an
       orderly power-down of the sensor-chip.  

       If we are in auto-control mode and either the clamp opens or chip-detect
       suddenly reports "not present", all power rails are slammed off.  This
       behavior can be modified by setting the "ignore_clamp" and/or "ignore_chip"
       bits in REG_DETECT_CTL.

*/


module chip_power_ctl #
(
    parameter AW=8,
    parameter FREQ_HZ = 250000000
)
(
    input clk, resetn,

    // The sensor-module clamp, active low
    input async_clamp,

    // Tells us if a chip is present, active low
    input async_chip_detect,

    // The four power supplies for the sensor chip
    output reg chip_vddio, chip_vdd, chip_vddlvds, chip_vdda,

    // The reset pin for the sensor chip
    output chip_reset_n,

    // This is an active-low output enable for the level-translator
    // that does voltage translation between the FPGA and sensor-chip
    output reg lvl_trsl_oe_n = 1,

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
    @register Controls chip power rails and level shifter.
    @rdesc    For all fields 1=on and 0=off
    @field power_ctl  1 0 RW 0  Automatic power on/off
    @field manual     1 1 RW 0  Disable auto and enables bits 2 thru 6
    @field vddio      1 2 RW 0  VDDIO power rail
    @field vdd        1 3 RW 0  VDD power rail
    @field vddlvds    1 4 RW 0  VDDLVDS power rail
    @field vdda       1 5 RW 0  VDDA power rail
    @field levelshift 1 6 RW 0  Level shifter

*/
localparam REG_POWER_CTL = 0;


/*
    @register Sensor chip power on state
    @rdesc    1 = The sensor chip is on
    @rdesc    0 = The sensor chip is off
    @rdesc    After turning power on or off, it may take a moment
    @rdesc    before that is reflected in this register
    @rtype    ro
*/
localparam REG_POWER_STATE = 1;

/*
    @register Sensor chip reset state
    @rdesc    1 = The sensor chip is held in reset
    @rdesc    0 = The sensor chip reset is released
*/
localparam REG_RESET = 2;


/*
    @register Determines whether the chip-detect and clamp are ignored
    @field  ignore_clamp  1 0 RW  0  1=Ignore clamp, 0=Open clamp cuts power
    @field  ignore_chip   1 1 RW  0  1=Ignore chip,  0=Missing chip cuts power
*/
localparam REG_DETECT_CTL = 3;

/*
    @register Reports clamp state
    @field    clamp_state  1 0 RO  N/A 1=Open, 0=Closed
    @field    clamp_opened 1 1 W1C 0   1 = The clamp was opened, write 1 to clear
    @field    chip_absent  1 2 RO  N/A 1=No chip, 0=Chip present 
*/
localparam REG_DETECT = 4;

/*
    @register Sensor chip power on sequencing - 
    @rdesc    The number of ms to wait after enabling VDDIO
*/
localparam REG_VDDIO_RISE_MS = 8;


/*
    @register Sensor chip power on sequencing - 
    @rdesc    The number of ms to wait after enabling VDD
*/
localparam REG_VDD_RISE_MS = 9;


/*
    @register Sensor chip power on sequencing - 
    @rdesc    The number of ms to wait after enabling VDDLVDS
*/
localparam REG_VDDLVDS_RISE_MS = 10;


/*
    @register Sensor chip power on sequencing - 
    @rdesc    The number of ms to wait after enabling VDDA
*/
localparam REG_VDDA_RISE_MS = 11;


/*
    @register Sensor chip power off sequencing - 
    @rdesc    The number of ms to wait after disabling VDDIO
*/
localparam REG_VDDIO_FALL_MS = 16;


/*
    @register Sensor chip power off sequencing - 
    @rdesc    The number of ms to wait after disabling VDD
*/
localparam REG_VDD_FALL_MS = 17;


/*
    @register Sensor chip power off sequencing - 
    @rdesc    The number of ms to wait after disabling VDDLVDS
*/
localparam REG_VDDLVDS_FALL_MS = 18;


/*
    @register Sensor chip power off sequencing - 
    @rdesc    The number of ms to wait after disabling VDDA
*/
localparam REG_VDDA_FALL_MS = 19;


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

// The number of clock cycles in 1 millisecond
localparam ONE_MS = FREQ_HZ / 1000;

// Constants for driving the various chip pins
localparam POWER_OFF = 0;
localparam POWER_ON  = 1;
localparam LEVELSHIFT_ENABLED  = 0;
localparam LEVELSHIFT_DISABLED = 1;
localparam CLAMP_OPEN   = 1;
localparam CLAMP_CLOSED = 0;
localparam CHIP_ABSENT  = 1;


// This register provides a power override for various signals that
// are otherwise managed automatically
reg[6:0] power;
localparam BIT_POWER_CTL  = 0;
localparam BIT_OVERRIDE   = 1;
localparam BIT_VDDIO      = 2;
localparam BIT_VDD        = 3;
localparam BIT_VDDLVDS    = 4;
localparam BIT_VDDA       = 5;
localparam BIT_LEVELSHIFT = 6;

// The "async_clamp" and "async_chip_detect" inputs, sync'd and debounced
wire clamp, chip_detect;

// Make a convenient name for the overall power on/off switch
wire chip_power_ctl = power[BIT_POWER_CTL];

// The rise and fall times (in milliseconds) of the various voltage rails
reg[31:0]   vddio_rise_ms;
reg[31:0]     vdd_rise_ms;
reg[31:0] vddlvds_rise_ms;
reg[31:0]    vdda_rise_ms;
reg[31:0]   vddio_fall_ms;
reg[31:0]     vdd_fall_ms;
reg[31:0] vddlvds_fall_ms;
reg[31:0]    vdda_fall_ms;

reg clear_power_ctl_stb;
reg chip_power_state;
reg[4:0] cpsm_state;

// output port "chip_reset_n" is 1 if and only if these are both 1.
reg[1:0] chip_enable;
assign chip_reset_n = (chip_enable == 2'b11);

// This is set whenever we detect that the clamp has been opened
reg clamp_opened;

// When this strobes high, "clamp_opened" is reset to 0
reg clear_clamp_stb;

// If this is 1, the clamp opening doesn't kill power
reg ignore_clamp;

// If this is 1, a missing chip doesn't kill power
reg ignore_chip;

// This determines whether we must immediately kill power
wire fault =  (clamp       == CLAMP_OPEN  & !ignore_clamp)|
              (chip_detect == CHIP_ABSENT & !ignore_chip );

// We may automatically control power when these are all true:
//   (1) We're not clearing the "power[BIT_POWER_CTL]" flag
//   (2) We don't have a fault
//   (3) Power control isn't being manually overridden
wire auto_power = (!clear_power_ctl_stb) & (!fault) & (!power[BIT_OVERRIDE]);

//=============================================================================
// Here we set "clamp_opened" any time we see the clamp transition from
// closed to open.
//
// Additionally, we clear "clamp_opened" if we see "clear_clamp_stb" 
// assert
//
// This sticky "clamp_opened" bit gives software a way to occasionally
// poll us to determine whether someone opened the clamp, even if they 
// subsequently closed it again
//=============================================================================
reg prior_clamp;
always @(posedge clk) begin
    
    prior_clamp <= clamp;
    
    if (resetn == 0) begin
        clamp_opened <= 0;
    end

    else if (clamp == CLAMP_OPEN && prior_clamp == CLAMP_CLOSED)
        clamp_opened <= 1;

    else if (clear_clamp_stb)
        clamp_opened <= 0;

end
//=============================================================================

//=============================================================================
// Keep track of the prior value of power[BIT_OVERRIDE]
//=============================================================================
reg prior_manual_ctl;
always @(posedge clk) begin
    if (resetn == 0)
        prior_manual_ctl <= 0;
    else
        prior_manual_ctl <= power[BIT_OVERRIDE];
end
//=============================================================================


// Are we restoring power control from manual to automatic?
wire auto_power_restored = (prior_manual_ctl & !power[BIT_OVERRIDE]);

//=============================================================================
// This state machine manages the power pins and level shifter
//=============================================================================
reg[31:0] sleep;
//-----------------------------------------------------------------------------
always @(posedge clk) begin

    // This strobes high for a single cycle at a time
    clear_power_ctl_stb <= 0;

    // Count down timer
    if (sleep) sleep <= sleep -1;

    if (resetn == 0) begin
        chip_enable[0]   <= 0;
        chip_vddio       <= POWER_OFF;
        chip_vdd         <= POWER_OFF;
        chip_vddlvds     <= POWER_OFF;
        chip_vdda        <= POWER_OFF;
        chip_power_state <= 0;
        lvl_trsl_oe_n    <= LEVELSHIFT_DISABLED;
        cpsm_state       <= 0;
        sleep            <= 0;
    end

    // If there's a chip fault or if we are restoring automatic control of
    // power, immediately kill power to the chip and level shifter
    else if (!power[BIT_OVERRIDE] & (fault | auto_power_restored)) begin
        chip_vddio          <= POWER_OFF;
        chip_vdd            <= POWER_OFF;
        chip_vddlvds        <= POWER_OFF;
        chip_vdda           <= POWER_OFF;
        lvl_trsl_oe_n       <= LEVELSHIFT_DISABLED;
        chip_enable[0]      <= 0;
        chip_power_state    <= 0;
        clear_power_ctl_stb <= 1;
        cpsm_state          <= 0;
    end

    else if (power[BIT_OVERRIDE]) begin
        chip_vddio     <= power[BIT_VDDIO     ] ? POWER_ON           : POWER_OFF;
        chip_vdd       <= power[BIT_VDD       ] ? POWER_ON           : POWER_OFF;
        chip_vddlvds   <= power[BIT_VDDLVDS   ] ? POWER_ON           : POWER_OFF;
        chip_vdda      <= power[BIT_VDDA      ] ? POWER_ON           : POWER_OFF;
        lvl_trsl_oe_n  <= power[BIT_LEVELSHIFT] ? LEVELSHIFT_ENABLED : LEVELSHIFT_DISABLED;
        chip_enable[0] <= 1;  // Allow chip_reset_n to be controlled by REG_RESET
        cpsm_state     <= 0;
        sleep          <= 0;
    end

    else case (cpsm_state)

           
        0:  // Are we powering up the chip?         
            if (auto_power && chip_power_ctl == 1 && chip_power_state == 0) begin
                chip_enable[0] <= 0;
                lvl_trsl_oe_n  <= LEVELSHIFT_DISABLED;
                sleep          <= 0;
                cpsm_state     <= 10;
            end
                
            // Are we powering down the chip?
            else if (auto_power && chip_power_ctl == 0 && chip_power_state == 1) begin
                chip_enable[0] <= 0;
                lvl_trsl_oe_n  <= LEVELSHIFT_DISABLED;
                sleep          <= 100;
                cpsm_state     <= 20;
            end
        

        // Here we power up the chip
        10: if (sleep == 0) begin
                chip_vddio <= POWER_ON;
                sleep      <= vddio_rise_ms * ONE_MS;
                cpsm_state <= cpsm_state + 1;
            end

        11: if (sleep == 0) begin
                chip_vdd   <= POWER_ON;
                sleep      <= vdd_rise_ms * ONE_MS;
                cpsm_state <= cpsm_state + 1;
            end

        12: if (sleep == 0) begin
                chip_vddlvds <= POWER_ON;
                sleep        <= vddlvds_rise_ms * ONE_MS;
                cpsm_state   <= cpsm_state + 1;
            end

        13: if (sleep == 0) begin
                chip_vdda  <= POWER_ON;
                sleep      <= vdda_rise_ms * ONE_MS;
                cpsm_state <= cpsm_state + 1;
            end

        14: if (sleep == 0) begin
                lvl_trsl_oe_n    <= LEVELSHIFT_ENABLED;
                chip_enable[0]   <= 1;
                chip_power_state <= 1;
                cpsm_state       <= 0;
            end


        // This is the power-down sequence
        20: if (sleep == 0) begin
                chip_vdda  <= POWER_OFF;
                sleep      <= vdda_fall_ms * ONE_MS;
                cpsm_state <= cpsm_state + 1;
            end

        21: if (sleep == 0) begin
                chip_vddlvds <= POWER_OFF;
                sleep        <= vddlvds_fall_ms * ONE_MS;
                cpsm_state   <= cpsm_state + 1;
            end

        22: if (sleep == 0) begin
                chip_vdd   <= POWER_OFF;
                sleep      <= vdd_fall_ms * ONE_MS;
                cpsm_state <= cpsm_state + 1;
            end

        23: if (sleep == 0) begin
                chip_vddio <= POWER_OFF;
                sleep      <= vddio_fall_ms * ONE_MS;
                cpsm_state <= cpsm_state + 1;
            end

        24: if (sleep == 0) begin
                chip_power_state <= 0;
                cpsm_state  <= 0;
            end

    endcase

end
//=============================================================================



//==========================================================================
// This state machine handles AXI4-Lite write requests
//==========================================================================
always @(posedge clk) begin

    // These strobes high for a single cycle at a time
    clear_clamp_stb <= 0;

    // If power control is being forcibly turned off, make it so
    if (clear_power_ctl_stb) power[BIT_POWER_CTL] <= 0;

    // If we're in reset, initialize important registers
    if (resetn == 0) begin
        ashi_write_state  <= 0;
        power             <= 0;
        chip_enable[1]    <= 1;
        ignore_clamp      <= 0;
        ignore_chip       <= 0;

          vddio_rise_ms <= 10;
            vdd_rise_ms <= 10;
        vddlvds_rise_ms <= 10;
           vdda_rise_ms <= 10;
          
          vddio_fall_ms <= 500;
            vdd_fall_ms <= 1000;
        vddlvds_fall_ms <= 50;
           vdda_fall_ms <= 50;
    end

    // Otherwise, we're not in reset...
    else case (ashi_write_state)
        
        // If an AXI write-request has occured...
        0:  if (ashi_write) begin
       
                // Assume for the moment that the result will be OKAY
                ashi_wresp <= OKAY;              
            
                // ashi_windex = index of register to be written
                case (ashi_windx)
                    REG_POWER_CTL:       power           <= ashi_wdata;        
                    REG_RESET:           chip_enable[1]  <= (ashi_wdata == 0);  
                    REG_DETECT:          clear_clamp_stb <= ashi_wdata[1];     
                    REG_DETECT_CTL:      {ignore_chip, ignore_clamp} <= ashi_wdata;

                    REG_VDD_RISE_MS:          vdd_rise_ms <= ashi_wdata;
                    REG_VDDIO_RISE_MS:      vddio_rise_ms <= ashi_wdata;
                    REG_VDDLVDS_RISE_MS:  vddlvds_rise_ms <= ashi_wdata;
                    REG_VDDA_RISE_MS:        vdda_rise_ms <= ashi_wdata;

                    REG_VDD_FALL_MS:          vdd_fall_ms <= ashi_wdata;
                    REG_VDDIO_FALL_MS:      vddio_fall_ms <= ashi_wdata;
                    REG_VDDLVDS_FALL_MS:  vddlvds_fall_ms <= ashi_wdata;
                    REG_VDDA_FALL_MS:        vdda_fall_ms <= ashi_wdata;

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
            REG_POWER_CTL:       ashi_rdata <= power;
            REG_POWER_STATE:     ashi_rdata <= chip_power_state;
            REG_RESET:           ashi_rdata <= (chip_enable == 2'b11) ? 0:1;
            REG_DETECT_CTL:      ashi_rdata <= {ignore_chip, ignore_clamp};
            REG_DETECT:          ashi_rdata <= {
                                                chip_detect,
                                                clamp_opened,
                                                clamp
                                               };

            REG_VDD_RISE_MS:     ashi_rdata <=     vdd_rise_ms;
            REG_VDDIO_RISE_MS:   ashi_rdata <=   vddio_rise_ms;
            REG_VDDLVDS_RISE_MS: ashi_rdata <= vddlvds_rise_ms;
            REG_VDDA_RISE_MS:    ashi_rdata <=    vdda_rise_ms;

            REG_VDD_FALL_MS:     ashi_rdata <=     vdd_fall_ms;
            REG_VDDIO_FALL_MS:   ashi_rdata <=   vddio_fall_ms;
            REG_VDDLVDS_FALL_MS: ashi_rdata <= vddlvds_fall_ms;
            REG_VDDA_FALL_MS:    ashi_rdata <=    vdda_fall_ms;

            // Reads of any other register are a decode-error
            default: ashi_rresp <= DECERR;

        endcase
    end
end
//==========================================================================




//==========================================================================
// Synchronize and debounce the input pins
//==========================================================================
switch_debounce#(.FREQ_HZ(FREQ_HZ), .INIT_STATE(CLAMP_OPEN)) u_db0
(
    .clk        (clk),
    .async_in   (async_clamp),
    .sw_out     (clamp)
);

switch_debounce#(.FREQ_HZ(FREQ_HZ), .INIT_STATE(CHIP_ABSENT)) u_db1
(
    .clk        (clk),
    .async_in   (async_chip_detect),
    .sw_out     (chip_detect)
);
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
