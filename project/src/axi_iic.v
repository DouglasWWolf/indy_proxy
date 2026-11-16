/*

    This file describes the registers of a Xilinx AXI IIC IP core
    and will be parsed by the xlate_vreg documentation system
    
*/

/*
    @register Global Interrupt Enable Register
    @rdesc     See Xilinx/AMD PG090
*/
localparam REG_GIE = 7;

/*
    @register Interrupt Status Register
    @rdesc     See Xilinx/AMD PG090
*/
localparam REG_ISR = 8;

/*
    @register Interrupt Enable Register
    @rdesc     See Xilinx/AMD PG090
*/
localparam REG_IER = 10;

/*
    @register Soft Reset Register
    @rdesc     See Xilinx/AMD PG090
*/
localparam REG_SOFTR = 16;

/*
    @register Control Register
    @rdesc     See Xilinx/AMD PG090
*/
localparam REG_CR = 64;

/*
    @register Status Register
    @rdesc     See Xilinx/AMD PG090
*/
localparam REG_SR = 65;

/*
    @register Transmit FIFO Register
    @rdesc     See Xilinx/AMD PG090
*/
localparam REG_TX_FIFO = 66;

/*
    @register Receive FIFO Register
    @rdesc     See Xilinx/AMD PG090
*/
localparam REG_RX_FIFO = 67;

/*
    @register Slave Address Register
    @rdesc     See Xilinx/AMD PG090
*/
localparam REG_ADR = 68;

/*
    @register Transmit FIFO Occupancy Register
    @rdesc     See Xilinx/AMD PG090
*/
localparam REG_TX_FIFO_OCY = 69;

/*
    @register Receive FIFO Occupancy Register
    @rdesc     See Xilinx/AMD PG090
*/
localparam REG_RX_FIFO_OCY = 70;

/*
    @register Slave Ten Bit Address Register
    @rdesc     See Xilinx/AMD PG090
*/
localparam REG_TEN_ADR = 71;

/*
    @register Receive FIFO Programmable Depth Interrupt Register
    @rdesc     See Xilinx/AMD PG090
*/
localparam REG_RX_FIFO_PIRQ = 72;

/*
    @register General Purpose Output Register
    @rdesc     See Xilinx/AMD PG090
*/
localparam REG_GPO = 73;