//====================================================================================
//                        ------->  Revision History  <------
//====================================================================================
//
//   Date     Who   Ver  Changes
//====================================================================================
// 22-Nov-26  DWW     1  Initial creation
//====================================================================================

/*
    This continuously configures/reads an NCT72D temperature sensor via I2C

    To compute the temperature in celsius
        Internal temperature in C = internal_temp - 64
        External temperature in C = external_temp/4 - 64

    Our NCT72D devices don't have either their /ALERT or /THERM outputs wired
    to anything, so we don't bother setting any temperature limit registers

    The datasheet for the NCT72D tells us that when reading the external
    temperature we must read the LSB before the MSB, so we do that.
*/


module nct72_mgr  # (parameter FREQ_HZ = 250000000)
(
    input clk, resetn,

    output reg[1:0]  error,  /* Bit 0 = I2C error, Bit 1 = Open Diode error */
    output reg[7:0]  internal_temp,
    output reg[9:0]  external_temp,
    input     [1:0]  clear_error_stb,

    // I2C interface
    output    [ 6:0] i2c_addr,
    output    [ 2:0] i2c_extra_bytes,
    output reg[ 7:0] i2c_reg_addr,
    output reg[63:0] i2c_wdata,
    output           i2c_cmd,
    output           i2c_start_stb,
    output           i2c_big_endian,
    input     [63:0] i2c_rdata,
    input     [ 3:0] i2c_error,
    input            i2c_idle
);

// This allows us to start a transaction with a single command
reg[1:0] i2c_start;
assign i2c_start_stb = i2c_start[1];
assign i2c_cmd       = i2c_start[0];

// The NCT72D doesn't support multi-byte read/writes
assign i2c_extra_bytes = 0;
assign i2c_big_endian  = 0;

// The I2C address of the NCT72D
assign i2c_addr = 7'h4D;

// These are the states of i2c_start
localparam I2C_READ  = 2'b10;
localparam I2C_WRITE = 2'b11;

// These are registers in the NCT72D temperature sensor
localparam NCT72_INT     =  0;   // NCT72D read internal temperature 
localparam NCT72_EXT_MSB =  1;   // NCT72D read external temperature MSB
localparam NCT72_STATUS  =  2;   // NCT72D read status register
localparam NCT72_CONFIG  =  9;   // NCT72D write configuration 
localparam NCT72_RATE    = 10;   // NCT72D write conversion rate
localparam NCT72_EXT_LSB = 16;   // NCT72D read external temperature LSB

// We delay 2 milliseconds between polling loops
localparam[31:0] POLL_DELAY = 64'd2 * FREQ_HZ / 64'd1000;

// A countdown timer
reg[31:0] timer;

//=============================================================================
// Do rising edge detection on the "idle" signal
//=============================================================================
reg prior_i2c_idle = 1;
always @(posedge clk) begin
    prior_i2c_idle <= (resetn) ? i2c_idle : 1;
end
wire idle_rising_edge = (prior_i2c_idle == 0) & (i2c_idle == 1);
//=============================================================================


//=============================================================================
// This is our main state machine.  Here we just loop forever, reading the
// NCT72 temperature and status registers
//=============================================================================
reg[1:0] external_lsb;
reg[2:0] fsm_state;
//----------------------------------------------------------------------------
always @(posedge clk) begin
    
    // This strobes high for a single cycle at a time
    i2c_start <= 0;

    // Clear the error bits when corresponding "clear_error_stb" bit is high
    if (clear_error_stb[0]) error[0] <= 0;
    if (clear_error_stb[1]) error[1] <= 0;

    if (resetn == 0) begin
        fsm_state     <= 0;
        error         <= 0;
        internal_temp <= 0;
        external_temp <= 0;
        i2c_reg_addr  <= 0;
        i2c_wdata     <= 0;
    end

    // If any of the below transactions completed and there was
    // an I2C error, cancel the next transaction and start the
    // entire loop over
    else if (idle_rising_edge && i2c_error) begin
        error[0]  <= 1;
        fsm_state <= 0;
    end

    else case(fsm_state)

        // Set the NCT72 configuration register to "extended temperature range"
        0:  if (i2c_idle) begin
                i2c_reg_addr <= NCT72_CONFIG;
                i2c_wdata    <= 4;
                i2c_start    <= I2C_WRITE;
                fsm_state    <= fsm_state + 1;
            end

        // Set the NCT72 Conversion rate to 16 conversions per second
        1:  if (i2c_idle) begin
                i2c_reg_addr <= NCT72_RATE;
                i2c_wdata    <= 8;
                i2c_start    <= I2C_WRITE;
                fsm_state    <= fsm_state + 1;
            end

        // Start a read of the internal temperature
        2:  if (i2c_idle) begin
                i2c_reg_addr <= NCT72_INT;
                i2c_start    <= I2C_READ;
                fsm_state    <= fsm_state + 1;
            end

        // Start a read of the status register
        3:  if (i2c_idle) begin
                internal_temp <= i2c_rdata[7:0];
                i2c_reg_addr  <= NCT72_STATUS;
                i2c_start     <= I2C_READ;
                fsm_state     <= fsm_state + 1;
            end


        // Start a read of external temperature LSB
        4:  if (i2c_idle) begin
                if (i2c_rdata[2])
                    error[1] <= 1;
                i2c_reg_addr <= NCT72_EXT_LSB;
                i2c_start    <= I2C_READ;
                fsm_state    <= fsm_state + 1;
            end

        // Start a read of external temperature MSB
        5:  if (i2c_idle) begin
                external_lsb <= i2c_rdata[7:6];
                i2c_reg_addr <= NCT72_EXT_MSB;
                i2c_start    <= I2C_READ;
                fsm_state    <= fsm_state + 1;
            end

        // Record the external temperature, then go delay a bit
        6:  if (i2c_idle) begin
                external_temp <= {i2c_rdata[7:0], external_lsb};                
                timer         <= POLL_DELAY;
                fsm_state     <= fsm_state + 1;
            end

        // Wait for the 2ms timer to expire then go back 
        // to the top of the loop.  This delay is just so that
        // the I2C bus isn't hammered 100% of the time
        7:  if (timer)
                timer <= timer - 1;
            else    
                fsm_state <= 2;

    endcase

end
//=============================================================================

endmodule
