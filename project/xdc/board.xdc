
# ---------------------------------------------------------------------------
# Pin definitions
# ---------------------------------------------------------------------------


#===============================================================================
#                            Clocks & system signals
#===============================================================================

#
# Presume the clocks have 300ps of jitter to force place&route to allow more margin on timing
#
set_system_jitter 0.300

#
# 200 Mhz init clock
#
set_property -dict {PACKAGE_PIN G16  IOSTANDARD LVDS}   [get_ports init_clk_clk_n]
set_property -dict {PACKAGE_PIN G17  IOSTANDARD LVDS}   [get_ports init_clk_clk_p]


#
# PCIe endpoint refclk
#
set_property -dict {PACKAGE_PIN U29}          [get_ports pcie_refclk_clk_p]
set_property -dict {PACKAGE_PIN U30}          [get_ports pcie_refclk_clk_n]  
create_clock -period 10.000 -name pcie_sysclk [get_ports pcie_refclk_clk_p]
#set_clock_groups -name group_pcie_sysclk -asynchronous -group [get_clocks pcie_sysclk]


#
# LEDs
#
#set_property -dict {PACKAGE_PIN AW26  IOSTANDARD LVCMOS18} [ get_ports LED[0] ]
#set_property -dict {PACKAGE_PIN AW23  IOSTANDARD LVCMOS18} [ get_ports LED[1] ]
#set_property -dict {PACKAGE_PIN AW25  IOSTANDARD LVCMOS18} [ get_ports LED[2] ]
#set_property -dict {PACKAGE_PIN AU23  IOSTANDARD LVCMOS18} [ get_ports LED[3] ]
#set_property -dict {PACKAGE_PIN AU25  IOSTANDARD LVCMOS18} [ get_ports LED[4] ]
#set_property -dict {PACKAGE_PIN AV23  IOSTANDARD LVCMOS18} [ get_ports LED[5] ]
#set_property -dict {PACKAGE_PIN AW24  IOSTANDARD LVCMOS18} [ get_ports LED[6] ]
#set_property -dict {PACKAGE_PIN AV25  IOSTANDARD LVCMOS18} [ get_ports LED[7] ]

set_property -dict {PACKAGE_PIN AW24  IOSTANDARD LVCMOS18} [ get_ports qsfp1_up ]
set_property -dict {PACKAGE_PIN AV25  IOSTANDARD LVCMOS18} [ get_ports qsfp0_up ]


#
# Clock inputs for QSFP 0
#
set_property PACKAGE_PIN AE29 [get_ports qsfp0_clk_clk_p]
set_property PACKAGE_PIN AE30 [get_ports qsfp0_clk_clk_n]


#
# Clock inputs for QSFP 1
#
set_property PACKAGE_PIN AB27 [get_ports qsfp1_clk_clk_p]
set_property PACKAGE_PIN AB28 [get_ports qsfp1_clk_clk_n]

#
# QSFP control and status
#
#set_property -dict {PACKAGE_PIN AW13  IOSTANDARD LVCMOS18} [ get_ports qsfp_present_l[0] ]
#set_property -dict {PACKAGE_PIN AV12  IOSTANDARD LVCMOS18} [ get_ports qsfp_present_l[1] ]

set_property -dict {PACKAGE_PIN AM12  IOSTANDARD LVCMOS18} [ get_ports qsfp_rst_l[0] ]
set_property -dict {PACKAGE_PIN AR11  IOSTANDARD LVCMOS18} [ get_ports qsfp_rst_l[1] ]

set_property -dict {PACKAGE_PIN AN12  IOSTANDARD LVCMOS18} [ get_ports qsfp_lp[0] ]
set_property -dict {PACKAGE_PIN AM13  IOSTANDARD LVCMOS18} [ get_ports qsfp_lp[1] ]



#
# Fan tachometers
#
set_property -dict {PACKAGE_PIN N15  IOSTANDARD LVCMOS18} [ get_ports FPGA_FAN_TACH ]
set_property -dict {PACKAGE_PIN AT14 IOSTANDARD LVCMOS18} [ get_ports PCB_FAN_TACH  ]



#
#  Sensor chip power rail enables
#
set_property -dict {PACKAGE_PIN AW10  IOSTANDARD LVCMOS18} [get_ports CHIP_RESET_N];  # IO Bank 65
set_property -dict {PACKAGE_PIN B9    IOSTANDARD LVCMOS18} [get_ports CHIP_VDDIO  ];  # IO Bank 91
set_property -dict {PACKAGE_PIN B10   IOSTANDARD LVCMOS18} [get_ports CHIP_VDDA   ];  # IO Bank 91 
set_property -dict {PACKAGE_PIN B11   IOSTANDARD LVCMOS18} [get_ports CHIP_VDDLVDS];  # IO Bank 91 
set_property -dict {PACKAGE_PIN A18   IOSTANDARD LVCMOS18} [get_ports CHIP_VDD    ];  # IO Bank 71
#set_property -dict {PACKAGE_PIN B30   IOSTANDARD LVCMOS18           } [get_ports CHIP_DETECT_8M];  # IO Bank 71



#
#  This enables a level translator for SPI pins on the sensor-chip (active low)
#
set_property -dict {PACKAGE_PIN A4  IOSTANDARD LVCMOS18} [get_ports LVL_TRSL_OE_N];  # IO Bank 90



#
#  UCI ADC bus - contains 3 LTC-1867L ADCs
#
set_property -dict {PACKAGE_PIN C25   IOSTANDARD LVCMOS18} [get_ports UCI_ADC_CSN[0]];
set_property -dict {PACKAGE_PIN R15   IOSTANDARD LVCMOS18} [get_ports UCI_ADC_CSN[1]];
set_property -dict {PACKAGE_PIN K25   IOSTANDARD LVCMOS18} [get_ports UCI_ADC_CSN[2]];
set_property -dict {PACKAGE_PIN J13   IOSTANDARD LVCMOS18} [get_ports UCI_ADC_MISO  ];
set_property -dict {PACKAGE_PIN C24   IOSTANDARD LVCMOS18} [get_ports UCI_ADC_MOSI  ];
set_property -dict {PACKAGE_PIN J23   IOSTANDARD LVCMOS18} [get_ports UCI_ADC_SCK   ];


#
#  DIG ADC bus - contains 2 LTC-1867L ADCs
#
set_property -dict {PACKAGE_PIN AT11  IOSTANDARD LVCMOS18} [get_ports DIG_ADC_CSN[0]];
set_property -dict {PACKAGE_PIN AR13  IOSTANDARD LVCMOS18} [get_ports DIG_ADC_CSN[1]];
set_property -dict {PACKAGE_PIN C13   IOSTANDARD LVCMOS18} [get_ports DIG_ADC_MISO  ];
set_property -dict {PACKAGE_PIN AK16  IOSTANDARD LVCMOS18} [get_ports DIG_ADC_MOSI  ];
set_property -dict {PACKAGE_PIN AP10  IOSTANDARD LVCMOS18} [get_ports DIG_ADC_SCK   ];


#
#  AUX ADC bus - contains 1 LTC-1867L 
#
set_property -dict {PACKAGE_PIN AL17 IOSTANDARD LVCMOS18} [get_ports AUX_ADC_CSN   ];
set_property -dict {PACKAGE_PIN AU14 IOSTANDARD LVCMOS18} [get_ports AUX_ADC_MISO  ];
set_property -dict {PACKAGE_PIN AT12 IOSTANDARD LVCMOS18} [get_ports AUX_ADC_MOSI  ];
set_property -dict {PACKAGE_PIN AN16 IOSTANDARD LVCMOS18} [get_ports AUX_ADC_SCK   ];


#
# FPGA outputs to control the sensor chip GPIO inputs
#
#set_property -dict {PACKAGE_PIN H12    IOSTANDARD LVCMOS18   SLEW SLOW } [get_ports CHIP_GPIO[0]];  # IO Bank 94
#set_property -dict {PACKAGE_PIN H10    IOSTANDARD LVCMOS18   SLEW SLOW } [get_ports CHIP_GPIO[1]];  # IO Bank 94  - glb_pre_sw
#set_property -dict {PACKAGE_PIN G11    IOSTANDARD LVCMOS18   SLEW SLOW } [get_ports CHIP_GPIO[2]];  # IO Bank 94  - disable_ncap
#set_property -dict {PACKAGE_PIN G10    IOSTANDARD LVCMOS18   SLEW SLOW } [get_ports CHIP_GPIO[3]];  # IO Bank 94
#set_property -dict {PACKAGE_PIN G12    IOSTANDARD LVCMOS18   SLEW SLOW } [get_ports CHIP_GPIO[4]];  # IO Bank 94



# Non-LVDS sensor-chip signals
set_property -dict {PACKAGE_PIN H12    IOSTANDARD LVCMOS18} [get_ports GPIO0        ];  # IO Bank 91
set_property -dict {PACKAGE_PIN G10    IOSTANDARD LVCMOS18} [get_ports GPIO3        ];  # IO Bank 91
set_property -dict {PACKAGE_PIN G12    IOSTANDARD LVCMOS18} [get_ports GPIO4        ];  # IO Bank 91
set_property -dict {PACKAGE_PIN D10    IOSTANDARD LVCMOS18} [get_ports GPIO15_DIR   ];  # IO Bank 91
set_property -dict {PACKAGE_PIN H13    IOSTANDARD LVCMOS18} [get_ports GPIO_BYTE_DIR];  # IO Bank 94
set_property -dict {PACKAGE_PIN D12    IOSTANDARD LVCMOS18} [get_ports CHIP_PA_SYNC ];  # CHIP_GPIO11 - IO Bank 90
set_property -dict {PACKAGE_PIN G11    IOSTANDARD LVCMOS18} [get_ports disable_ncap ];  # CHIP_GPIO2

#
# Userwave related signals
#
set_property -dict {PACKAGE_PIN C12    IOSTANDARD LVCMOS18} [get_ports rs0             ];  # GPIO12 - IO Bank 94
set_property -dict {PACKAGE_PIN A12    IOSTANDARD LVCMOS18} [get_ports rs256           ];  # GPIO14 - IO Bank 94
set_property -dict {PACKAGE_PIN C19    IOSTANDARD LVCMOS18} [get_ports vpretop_sw      ];  # 
set_property -dict {PACKAGE_PIN J18    IOSTANDARD LVCMOS18} [get_ports vprebot_sw      ];  # 
set_property -dict {PACKAGE_PIN H10    IOSTANDARD LVCMOS18} [get_ports glb_pre_sw      ];  # GPIO1
set_property -dict {PACKAGE_PIN H23    IOSTANDARD LVCMOS18} [get_ports liq_sw          ];  # 
set_property -dict {PACKAGE_PIN J11    IOSTANDARD LVCMOS18} [get_ports refn_sw         ];  # 
set_property -dict {PACKAGE_PIN J12    IOSTANDARD LVCMOS18} [get_ports refp_sw         ];  # 
set_property -dict {PACKAGE_PIN B12    IOSTANDARD LVCMOS18} [get_ports pre0            ];  # GPIO13
set_property -dict {PACKAGE_PIN D13    IOSTANDARD LVCMOS18} [get_ports pre256          ];  # GPIO15 
set_property -dict {PACKAGE_PIN B15    IOSTANDARD LVCMOS18} [get_ports uw_dac_spi_csld ];  # 
set_property -dict {PACKAGE_PIN A16    IOSTANDARD LVCMOS18} [get_ports uw_dac_spi_sck  ];  # 
set_property -dict {PACKAGE_PIN A17    IOSTANDARD LVCMOS18} [get_ports uw_dac_spi_mosi0];  # 
set_property -dict {PACKAGE_PIN B16    IOSTANDARD LVCMOS18} [get_ports uw_dac_spi_mosi1];  # 


#
# I2C M24C04 EEPROM signals
#
set_property -dict { PACKAGE_PIN R14 IOSTANDARD LVCMOS18 } [get_ports EEPROM_scl_io ];
set_property -dict { PACKAGE_PIN R13 IOSTANDARD LVCMOS18 } [get_ports EEPROM_sda_io ];



