//====================================================================================
//                        ------->  Revision History  <------
//====================================================================================
//
//   Date     Who   Ver  Changes
//====================================================================================
// 15-Nov-26  DWW     1  Initial creation
//====================================================================================

/*
    This counts the number of rising edges on the input pin over the course 
    of one second
*/

module fan_tach # (parameter FREQ_HZ = 250000000)
(
    input clk,
    input async_tach_pin,
    output reg[15:0] tach_count
);


// Synchronized from async_tach_pin
wire tach_pin;

//=============================================================================
// Keep track of the previous value of the tachometer pin
//=============================================================================
reg prev_tach_pin;
//-----------------------------------------------------------------------------
always @(posedge clk) prev_tach_pin <= tach_pin;
//=============================================================================


//=============================================================================
// Count the number of rising edges of tach_pin that we see every second
//=============================================================================
reg[31:0] timer;
reg[15:0] edge_counter;
//-----------------------------------------------------------------------------
always @(posedge clk) begin

    if (timer == FREQ_HZ) begin
        tach_count   <= edge_counter;
        edge_counter <= 0;
        timer        <= 0;
    end 

    else begin
        timer <= timer + 1;
        if (prev_tach_pin == 0 && tach_pin == 1)
            edge_counter <= edge_counter + 1;
    end

end
//=============================================================================



//=============================================================================
// Synchronize "async_tach_pin" into "tach_pin"
//=============================================================================
xpm_cdc_single #
(
    .DEST_SYNC_FF  (4),
    .INIT_SYNC_FF  (0),
    .SIM_ASSERT_CHK(0),
    .SRC_INPUT_REG (0)
)
cdc0
(
    .src_clk (              ),
    .src_in  (async_tach_pin),
    .dest_clk(clk           ),
    .dest_out(tach_pin      )
);
//=============================================================================








endmodule
