
//=============================================================================
//                   ------->  Revision History  <------
//=============================================================================
//
//   Date     Who   Ver  Changes
//=============================================================================
// 21-Nov-26  DWW     1  Initial creation
//=============================================================================

/*
    This provides a convenient interface to the Xilinx AXI-IIC IP core
*/


module i2c_master #(parameter AW=32, DW=32, AXI_BASE = 32'h4080_0000, FREQ_HZ = 250000000)
(
    input clk,
    input resetn,

    // I2C address of the device we're talking to
    input     [ 6:0] i2c_addr,
    
    // All device-register read/write operations are at least one byte.
    // This field is used to extend that to up to 8 bytes
    input     [ 2:0] extra_bytes,
    
    // The register address within the device
    input     [ 7:0] reg_addr,
    
    // Data to be written to a device register
    input     [63:0] wdata,
    
    // Data read from a device register
    output reg[63:0] rdata,

    // Used to report error conditions
    output reg[3:0] i2c_error,

    // CMD_READ or CMD_WRITE
    input      cmd,
    
    // Start executing the command.  Only valid when idle is 1
    input      cmd_start_stb,

    // If this is asserted, "rdata" and "wdata" are big-endian
    input      big_endian,

    // When this is true, system is idle and ready for a new command
    output     idle,

    //====================  An AXI-Lite Master Interface  ======================
    // "Specify write address"          -- Master --    -- Slave --
    output [AW-1:0]                     M_AXI_AWADDR,   
    output                              M_AXI_AWVALID,  
    output    [2:0]                     M_AXI_AWPROT,
    input                                               M_AXI_AWREADY,

    // "Write Data"                     -- Master --    -- Slave --
    output [DW-1:0]                     M_AXI_WDATA,
    output [DW/8-1:0]                   M_AXI_WSTRB,      
    output                              M_AXI_WVALID,
    input                                               M_AXI_WREADY,

    // "Send Write Response"            -- Master --    -- Slave --
    input  [1:0]                                        M_AXI_BRESP,
    input                                               M_AXI_BVALID,
    output                              M_AXI_BREADY,

    // "Specify read address"           -- Master --    -- Slave --
    output [AW-1:0]                     M_AXI_ARADDR,     
    output [   2:0]                     M_AXI_ARPROT,
    output                              M_AXI_ARVALID,
    input                                               M_AXI_ARREADY,

    // "Read data back to master"       -- Master --    -- Slave --
    input [DW-1:0]                                      M_AXI_RDATA,
    input                                               M_AXI_RVALID,
    input [1:0]                                         M_AXI_RRESP,
    output                              M_AXI_RREADY
    //==========================================================================
);

// These are the legal values of port "cmd"
localparam CMD_READ  = 0;
localparam CMD_WRITE = 1;

// This is the width of an FSM state
localparam FSMW=8;

// Our call/return stack is up to 2 deep
localparam STACK_DEPTH = 2;

// The state of the state machine
reg[FSMW-1:0] fsm_state;

// This is a call stack
reg[FSMW*STACK_DEPTH-1:0] stack;

// Ordinary stackable call and return operations
`define call(x) stack<=(stack<<FSMW)|(fsm_state+1);fsm_state<=x
`define return  fsm_state<=stack[FSMW-1:0];stack<=(stack>>FSMW)

// Various AXI-IIC related constants
localparam I2C_RD = 1;
localparam I2C_WR = 0;
localparam I2C_START = 10'h100;
localparam  I2C_STOP = 10'h200;
localparam CR_ENABLE       = 1;
localparam SR_BB       = 8'h04;
localparam SR_RX_EMPTY = 8'h40;
localparam SR_TX_EMPTY = 8'h80;
localparam ISR_ARB_LOST = 1;
localparam ISR_TX_ERROR = 2;

// Errors that are stored in i2c_error
localparam ERR_ARB_LOST  = 1;
localparam ERR_NACK_RCVD = 2;
localparam ERR_TIMEOUT   = 3;

// Compute the 300 ns SMBus data hold time at our clock frequency
localparam SMBUS_THDDAT = (64'd300 * FREQ_HZ) / 64'd1000000000;

// Transaction timeout is 20 milliseconds
localparam TRANSACT_TIMEOUT = 64'd20 * FREQ_HZ / 64'd1000;

//=============================================================================
// These are the registers in a Xilinx AXI IIC IP core.  See Xilinx PG090
//=============================================================================
localparam          IIC_GIE = AXI_BASE + 9'h01C;
localparam          IIC_ISR = AXI_BASE + 9'h020;
localparam          IIC_IER = AXI_BASE + 9'h028;
localparam        IIC_SOFTR = AXI_BASE + 9'h040;
localparam           IIC_CR = AXI_BASE + 9'h100;
localparam           IIC_SR = AXI_BASE + 9'h104;
localparam      IIC_TX_FIFO = AXI_BASE + 9'h108;
localparam      IIC_RX_FIFO = AXI_BASE + 9'h10C;
localparam          IIC_ADR = AXI_BASE + 9'h110;
localparam  IIC_TX_FIFO_OCY = AXI_BASE + 9'h114;
localparam  IIC_RX_FIFO_OCY = AXI_BASE + 9'h118;
localparam      IIC_TEN_ADR = AXI_BASE + 9'h11C;
localparam IIC_RX_FIFO_PIRQ = AXI_BASE + 9'h120;
localparam        IIC_THIGH = AXI_BASE + 9'h13C;
localparam         IIC_TLOW = AXI_BASE + 9'h140;
localparam       IIC_THDDAT = AXI_BASE + 9'h144;
//=============================================================================


//==================  The AXI Master Control Interface  ====================
// AMCI signals for performing AXI writes
reg [AW-1:0]  AMCI_WADDR;
reg [DW-1:0]  AMCI_WDATA;
reg           AMCI_WRITE;
wire[   1:0]  AMCI_WRESP;
wire          AMCI_WIDLE;

// AMCI signals for performing AXI reads
reg [AW-1:0]  AMCI_RADDR;
reg           AMCI_READ ;
wire[DW-1:0]  AMCI_RDATA;
wire[   1:0]  AMCI_RRESP;
wire          AMCI_RIDLE;
//==========================================================================


localparam FSM_IDLE          = 0;
localparam FSM_READ_REG      = 20;
localparam FSM_WRITE_REG     = 40;
localparam FSM_DISABLE_CORE  = 60;
localparam FSM_TRANSACT      = 80;
localparam FSM_TRANSACT_LOOP = 100;

// When this is one, the "FSM_TRANSACT" subroutine assumes we're
// performing a register write
reg is_write;

// The current value of the AXI-IIC ISR and SR registers
reg[7:0] isr, sr;

// General purpose counter
reg[7:0] counter;

// This is a countdown timer for determining transaction timeouts
reg[31:0] transaction_timer;

// This is asserted when we see the I2C bus become busy
reg       tx_started;

// Latched command parameters (captured when cmd_start_stb is asserted)
reg[ 6:0] latched_i2c_addr;
reg[ 2:0] latched_extra_bytes;
reg[ 7:0] latched_reg_addr;
reg[63:0] latched_wdata;
reg       latched_big_endian;

// Counts remaining bytes during multi-byte reads and writes
reg[ 2:0] bytes_left;

// Selects the active byte lane (0..7) in wdata/rdata based on endianness
wire[2:0] byte_index = latched_big_endian ? bytes_left : counter[2:0];

// "wdata_byte" = latched_wdata[byte_index]
wire[7:0] wdata_byte = latched_wdata[{byte_index, 3'b000} +: 8];

// This timer ensures that there is at least 5 microseconds between
// the time one transaction ends and the next one starts
reg[31:0] tbuf_timer;

// 5 microseconds satisfies the SMBus interface requirements
localparam[31:0] TBUF_TIME = 64'd5 * FREQ_HZ / 64'd1000000;

always @(posedge clk) begin

    // These strobe high for a single cycle at a time
    AMCI_WRITE <= 0;
    AMCI_READ  <= 0;

    // Always count down the transaction timer
    if (transaction_timer) transaction_timer <= transaction_timer - 1;

    // Count down the timer that spaces out transactions
    if (tbuf_timer) tbuf_timer <= tbuf_timer - 1;

    if (resetn == 0) begin
        fsm_state         <= FSM_IDLE;
        i2c_error         <= 0;
        rdata             <= 0;
        transaction_timer <= 0;
        tbuf_timer        <= 0;
    end

    else case(fsm_state)
        FSM_IDLE:
            if (cmd_start_stb) begin
                i2c_error           <= 0;
                tx_started          <= 0;
                latched_i2c_addr    <= i2c_addr;
                latched_extra_bytes <= extra_bytes;
                latched_reg_addr    <= reg_addr;
                latched_wdata       <= wdata;
                latched_big_endian  <= big_endian;
                if (cmd == CMD_READ)
                    fsm_state <= FSM_READ_REG;
                else
                    fsm_state <= FSM_WRITE_REG;
            end


        //---------------------------------------------------------------------
        // This block of states reads 1 to 8 bytes from a device register.
        // When big_endian=0, byte 0 (first on the wire) goes into rdata[7:0],
        // byte 1 into rdata[15:8], etc.  When big_endian=1, byte 0 goes into
        // the most significant active byte and the last byte into rdata[7:0].
        // Unused upper bytes of rdata are zero.
        //---------------------------------------------------------------------

        // Soft-reset the AXI-IIC core
        FSM_READ_REG:
            if (AMCI_WIDLE) begin
                is_write   <= 0;
                rdata      <= 0;
                AMCI_WADDR <= IIC_SOFTR;
                AMCI_WDATA <= 8'h0A;
                AMCI_WRITE <= 1;
                fsm_state  <= fsm_state + 1;
            end

        // Set the SMBus data hold time for our clock speed
        FSM_READ_REG + 1:
            if (AMCI_WIDLE) begin
                AMCI_WADDR <= IIC_THDDAT;
                AMCI_WDATA <= SMBUS_THDDAT;
                AMCI_WRITE <= 1;
                fsm_state  <= fsm_state + 1;
            end

        // Set the RX FIFO compare depth to max (15 + 1 = 16) so multi-byte
        // reads do not throttle SCL after byte 1
        FSM_READ_REG + 2:
            if (AMCI_WIDLE) begin
                AMCI_WADDR <= IIC_RX_FIFO_PIRQ;
                AMCI_WDATA <= 15;
                AMCI_WRITE <= 1;
                fsm_state  <= fsm_state + 1;
            end


        // Push START + device address + WRITE into the TX FIFO
        FSM_READ_REG + 3:
            if (AMCI_WIDLE) begin
                AMCI_WADDR <= IIC_TX_FIFO;
                AMCI_WDATA <= I2C_START | {latched_i2c_addr, 1'b0} | I2C_WR;
                AMCI_WRITE <= 1;
                fsm_state  <= fsm_state + 1;
            end

        // Push the target device register address into the TX FIFO
        FSM_READ_REG + 4:
            if (AMCI_WIDLE) begin
                AMCI_WADDR <= IIC_TX_FIFO;
                AMCI_WDATA <= latched_reg_addr;
                AMCI_WRITE <= 1;
                fsm_state  <= fsm_state + 1;
            end

        // Push repeated START + device address + READ into the TX FIFO
        FSM_READ_REG + 5:
            if (AMCI_WIDLE) begin
                AMCI_WADDR <= IIC_TX_FIFO;
                AMCI_WDATA <= I2C_START | {latched_i2c_addr, 1'b0} | I2C_RD;
                AMCI_WRITE <= 1;
                fsm_state  <= fsm_state + 1;
            end

        // Push the receive byte count (1..8) + STOP into the TX FIFO
        FSM_READ_REG + 6:
            if (AMCI_WIDLE) begin
                AMCI_WADDR <= IIC_TX_FIFO;
                AMCI_WDATA <= I2C_STOP | ({1'b0, latched_extra_bytes} + 4'd1);
                AMCI_WRITE <= 1;
                fsm_state  <= fsm_state + 1;
            end

        // Execute the queued I2C read transaction
        FSM_READ_REG + 7:
            if (AMCI_WIDLE) begin
                `call(FSM_TRANSACT);
            end

        // If the transaction failed, disable the core and return to idle;
        // otherwise prepare to fetch the received bytes from the RX FIFO
        FSM_READ_REG + 8:
            if (AMCI_WIDLE & AMCI_RIDLE) begin
                if (i2c_error != 0) begin
                    fsm_state <= FSM_DISABLE_CORE;
                end else begin
                    counter    <= 0;
                    bytes_left <= latched_extra_bytes;
                    fsm_state  <= fsm_state + 1;
                end
            end

        // Read the IIC status register to verify a byte is in the RX FIFO
        FSM_READ_REG + 9:
            if (AMCI_RIDLE) begin
                AMCI_RADDR <= IIC_SR;
                AMCI_READ  <= 1;
                fsm_state  <= fsm_state + 1;
            end

        // If RX FIFO is empty when we still expect a byte, the repeated-start
        // read was NACKed; otherwise read the next byte from RX FIFO
        FSM_READ_REG + 10:
            if (AMCI_RIDLE) begin
                if (AMCI_RDATA & SR_RX_EMPTY) begin
                    i2c_error <= ERR_NACK_RCVD;
                    fsm_state <= FSM_DISABLE_CORE;
                end else begin
                    AMCI_RADDR <= IIC_RX_FIFO;
                    AMCI_READ  <= 1;
                    fsm_state  <= fsm_state + 1;
                end
            end

        // Store the received byte into rdata and loop until all bytes are read
        FSM_READ_REG + 11:
            if (AMCI_RIDLE) begin
                rdata[{byte_index, 3'b000} +: 8] <= AMCI_RDATA[7:0];
                counter                          <= counter + 1;
                if (bytes_left == 0) begin
                    fsm_state <= FSM_IDLE;
                end else begin
                    bytes_left <= bytes_left - 1;
                    fsm_state  <= fsm_state - 2;
                end
            end
        //---------------------------------------------------------------------


        //---------------------------------------------------------------------
        // This block of states writes 1 to 8 bytes to a device register.
        // When big_endian=0, byte 0 (first on the wire) is taken from
        // wdata[7:0], byte 1 from wdata[15:8], etc.  When big_endian=1, byte 0
        // is taken from the most significant active byte down to wdata[7:0].
        //---------------------------------------------------------------------

        // Soft-reset the AXI-IIC core
        FSM_WRITE_REG:
            if (AMCI_WIDLE) begin
                is_write   <= 1;
                counter    <= 0;
                bytes_left <= latched_extra_bytes;
                AMCI_WADDR <= IIC_SOFTR;
                AMCI_WDATA <= 8'h0A;
                AMCI_WRITE <= 1;
                fsm_state  <= fsm_state + 1;
            end

        // Set the SMBus data hold time for our clock speed
        FSM_WRITE_REG + 1:
            if (AMCI_WIDLE) begin
                AMCI_WADDR <= IIC_THDDAT;
                AMCI_WDATA <= SMBUS_THDDAT;
                AMCI_WRITE <= 1;
                fsm_state  <= fsm_state + 1;
            end

        // Push START + device address + WRITE into the TX FIFO
        FSM_WRITE_REG + 2:
            if (AMCI_WIDLE) begin
                AMCI_WADDR <= IIC_TX_FIFO;
                AMCI_WDATA <= I2C_START | {latched_i2c_addr, 1'b0} | I2C_WR;
                AMCI_WRITE <= 1;
                fsm_state  <= fsm_state + 1;
            end

        // Push the target device register address into the TX FIFO
        FSM_WRITE_REG + 3:
            if (AMCI_WIDLE) begin
                AMCI_WADDR <= IIC_TX_FIFO;
                AMCI_WDATA <= latched_reg_addr;
                AMCI_WRITE <= 1;
                fsm_state  <= fsm_state + 1;
            end

        // Push 1 to 8 data bytes, asserting STOP on the last byte
        FSM_WRITE_REG + 4:
            if (AMCI_WIDLE) begin
                AMCI_WADDR <= IIC_TX_FIFO;
                AMCI_WDATA <= (bytes_left == 0) ? (I2C_STOP | wdata_byte)
                                                : wdata_byte;
                AMCI_WRITE <= 1;
                counter    <= counter + 1;
                if (bytes_left == 0)
                    fsm_state  <= fsm_state + 1;
                else
                    bytes_left <= bytes_left - 1;
            end

        // Execute the queued I2C write transaction
        FSM_WRITE_REG + 5:
            if (AMCI_WIDLE) begin
                `call(FSM_TRANSACT);
            end

        // Transaction complete; disable the core if an error occurred
        FSM_WRITE_REG + 6:
            if (AMCI_WIDLE & AMCI_RIDLE) begin
                if (i2c_error != 0)
                    fsm_state <= FSM_DISABLE_CORE;
                else
                    fsm_state <= FSM_IDLE;
            end
        //---------------------------------------------------------------------


        //---------------------------------------------------------------------
        // Disables the AXI-IIC core (IIC_CR = 0) after an error, then returns
        // to FSM_IDLE once the write completes
        //---------------------------------------------------------------------
        FSM_DISABLE_CORE:
            if (AMCI_WIDLE & AMCI_RIDLE) begin
                AMCI_WADDR <= IIC_CR;
                AMCI_WDATA <= 0;
                AMCI_WRITE <= 1;
                fsm_state  <= fsm_state + 1;
            end

        // Wait for the IIC_CR write to complete before returning to idle
        FSM_DISABLE_CORE + 1:
            if (AMCI_WIDLE) fsm_state <= FSM_IDLE;
        //---------------------------------------------------------------------


        //---------------------------------------------------------------------
        // This block of states performs an I2C transaction
        //---------------------------------------------------------------------

        // Read the IIC_ISR register
        FSM_TRANSACT:
            if (AMCI_WIDLE & AMCI_RIDLE & (tbuf_timer == 0)) begin
                AMCI_RADDR <= IIC_ISR;
                AMCI_READ  <= 1;
                fsm_state  <= fsm_state + 1;
            end

        // Now write that back to IIC_ISR.  This clears it.
        FSM_TRANSACT+1:
            if (AMCI_RIDLE) begin
                AMCI_WADDR <= IIC_ISR;
                AMCI_WDATA <= AMCI_RDATA;
                AMCI_WRITE <= 1;
                fsm_state  <= fsm_state + 1;
            end

        // Start the I2C transaction
        FSM_TRANSACT+2:
            if (AMCI_RIDLE & AMCI_WIDLE) begin
                AMCI_WADDR        <= IIC_CR;
                AMCI_WDATA        <= CR_ENABLE;
                AMCI_WRITE        <= 1;
                transaction_timer <= TRANSACT_TIMEOUT;
                fsm_state         <= FSM_TRANSACT_LOOP;
            end

        // Read the AXI-IIC SR register
        FSM_TRANSACT_LOOP:
            if (transaction_timer == 0) begin
                i2c_error <= ERR_TIMEOUT;
                `return;
            end
            else if (AMCI_WIDLE & AMCI_RIDLE) begin
                AMCI_RADDR <= IIC_SR;
                AMCI_READ  <= 1;
                fsm_state  <= fsm_state + 1;
            end

        // Store the SR register and read the ISR register
        FSM_TRANSACT_LOOP + 1:
            if (AMCI_RIDLE) begin
                sr         <= AMCI_RDATA;
                AMCI_RADDR <= IIC_ISR;
                AMCI_READ  <= 1;
                fsm_state  <= fsm_state + 1;
            end

        // Store the ISR register
        FSM_TRANSACT_LOOP + 2:
            if (AMCI_RIDLE) begin
                isr       <= AMCI_RDATA;
                fsm_state <= fsm_state + 1;
            end

        // Did we lose bus arbitration?
        FSM_TRANSACT_LOOP + 3:
            if (isr & ISR_ARB_LOST) begin
                i2c_error <= ERR_ARB_LOST;
                `return;
            end else if (tx_started == 0)
                fsm_state <= fsm_state + 1;
            else
                fsm_state <= fsm_state + 2;

        // Wait for the transaction to start.   We check for TX_EMPTY and 
        // TX_ERROR just in case a very short failed transaction occured 
        // and we missed BB going high
        FSM_TRANSACT_LOOP + 4:
            if ((sr & SR_BB) || (sr & SR_TX_EMPTY) || (isr & ISR_TX_ERROR)) begin
                tx_started <= 1;
                fsm_state  <= fsm_state + 1;
            end
            
            else fsm_state <= FSM_TRANSACT_LOOP;
           

        // Wait for the bus to become not busy
        FSM_TRANSACT_LOOP + 5:
            if ((sr & SR_BB)) begin
                fsm_state  <= FSM_TRANSACT_LOOP;
            end

            // Check for transmit errors during writes
            else if (is_write && (isr & ISR_TX_ERROR)) begin
                i2c_error  <= ERR_NACK_RCVD;
                tbuf_timer <= TBUF_TIME;
                `return;
            end

            // If TX_FIFO still has unsent bytes after BB=0, an
            // early NACK aborted it
            else if ((sr & SR_TX_EMPTY) == 0) begin
                i2c_error  <= ERR_NACK_RCVD;
                tbuf_timer <= TBUF_TIME;
                `return;
            end

            // If we get here, the bus is no longer busy and there
            // was no NACK received
            else begin
                i2c_error  <= 0;
                tbuf_timer <= TBUF_TIME;
                `return;
            end

        //---------------------------------------------------------------------


    endcase

end

// Tell the outside world when we're idle
assign idle = (fsm_state == FSM_IDLE) & (resetn == 1) & (cmd_start_stb == 0);


//==========================================================================
// This instantiates an AXI4-Lite master
//==========================================================================
axi4_lite_master # (.DW(DW), .AW(AW)) axi4_master
(
    // Clock and reset
    .clk            (clk),
    .resetn         (resetn),

    // AXI Master Control Interface for performing writes
    .AMCI_WADDR     (AMCI_WADDR),
    .AMCI_WDATA     (AMCI_WDATA),
    .AMCI_WRITE     (AMCI_WRITE),
    .AMCI_WRESP     (AMCI_WRESP),
    .AMCI_WIDLE     (AMCI_WIDLE),

    // AXI Master Control Interface for performing reads
    .AMCI_RADDR     (AMCI_RADDR),
    .AMCI_READ      (AMCI_READ ),
    .AMCI_RDATA     (AMCI_RDATA),
    .AMCI_RRESP     (AMCI_RRESP),
    .AMCI_RIDLE     (AMCI_RIDLE),

    // AXI4-Lite AW channel
    .AXI_AWADDR     (M_AXI_AWADDR ),
    .AXI_AWVALID    (M_AXI_AWVALID),
    .AXI_AWPROT     (M_AXI_AWPROT ),
    .AXI_AWREADY    (M_AXI_AWREADY),

    // AXI4-Lite W channel
    .AXI_WDATA      (M_AXI_WDATA  ),
    .AXI_WSTRB      (M_AXI_WSTRB  ),
    .AXI_WVALID     (M_AXI_WVALID ),
    .AXI_WREADY     (M_AXI_WREADY ),

    // AXI4-Lite B channel
    .AXI_BRESP      (M_AXI_BRESP  ),
    .AXI_BVALID     (M_AXI_BVALID ),
    .AXI_BREADY     (M_AXI_BREADY ),

    // AXI4-Lite AR channel
    .AXI_ARADDR     (M_AXI_ARADDR ),
    .AXI_ARPROT     (M_AXI_ARPROT ),
    .AXI_ARVALID    (M_AXI_ARVALID),
    .AXI_ARREADY    (M_AXI_ARREADY),

    .AXI_RDATA      (M_AXI_RDATA  ),
    .AXI_RVALID     (M_AXI_RVALID ),
    .AXI_RRESP      (M_AXI_RRESP  ),
    .AXI_RREADY     (M_AXI_RREADY )
);

//==========================================================================


endmodule

