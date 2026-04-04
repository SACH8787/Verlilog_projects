# ----------------------------------------------------------------------------
# Clock signal
# ----------------------------------------------------------------------------
set_property PACKAGE_PIN W5 [get_ports clk]							
set_property IOSTANDARD LVCMOS33 [get_ports clk]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports clk]

# ----------------------------------------------------------------------------
# USB-UART RX (Receives Python data from laptop)
# ----------------------------------------------------------------------------
set_property PACKAGE_PIN B18 [get_ports uart_rx]						
set_property IOSTANDARD LVCMOS33 [get_ports uart_rx]

# ----------------------------------------------------------------------------
# Center Button (Active-high Reset)
# ----------------------------------------------------------------------------
set_property PACKAGE_PIN U18 [get_ports btnc]						
set_property IOSTANDARD LVCMOS33 [get_ports btnc]

# ----------------------------------------------------------------------------
# 16 Onboard LEDs 
# (LED 0 = Normal, LED 7 = Done, LED 15 = Abnormal)
# ----------------------------------------------------------------------------
set_property PACKAGE_PIN U16 [get_ports {led[0]}]					
set_property IOSTANDARD LVCMOS33 [get_ports {led[0]}]

set_property PACKAGE_PIN E19 [get_ports {led[1]}]					
set_property IOSTANDARD LVCMOS33 [get_ports {led[1]}]

set_property PACKAGE_PIN U19 [get_ports {led[2]}]					
set_property IOSTANDARD LVCMOS33 [get_ports {led[2]}]

set_property PACKAGE_PIN V19 [get_ports {led[3]}]					
set_property IOSTANDARD LVCMOS33 [get_ports {led[3]}]

set_property PACKAGE_PIN W18 [get_ports {led[4]}]					
set_property IOSTANDARD LVCMOS33 [get_ports {led[4]}]

set_property PACKAGE_PIN U15 [get_ports {led[5]}]					
set_property IOSTANDARD LVCMOS33 [get_ports {led[5]}]

set_property PACKAGE_PIN U14 [get_ports {led[6]}]					
set_property IOSTANDARD LVCMOS33 [get_ports {led[6]}]

set_property PACKAGE_PIN V14 [get_ports {led[7]}]					
set_property IOSTANDARD LVCMOS33 [get_ports {led[7]}]

set_property PACKAGE_PIN V13 [get_ports {led[8]}]					
set_property IOSTANDARD LVCMOS33 [get_ports {led[8]}]

set_property PACKAGE_PIN V3 [get_ports {led[9]}]					
set_property IOSTANDARD LVCMOS33 [get_ports {led[9]}]

set_property PACKAGE_PIN W3 [get_ports {led[10]}]					
set_property IOSTANDARD LVCMOS33 [get_ports {led[10]}]

set_property PACKAGE_PIN U3 [get_ports {led[11]}]					
set_property IOSTANDARD LVCMOS33 [get_ports {led[11]}]

set_property PACKAGE_PIN P3 [get_ports {led[12]}]					
set_property IOSTANDARD LVCMOS33 [get_ports {led[12]}]

set_property PACKAGE_PIN N3 [get_ports {led[13]}]					
set_property IOSTANDARD LVCMOS33 [get_ports {led[13]}]

set_property PACKAGE_PIN P1 [get_ports {led[14]}]					
set_property IOSTANDARD LVCMOS33 [get_ports {led[14]}]

set_property PACKAGE_PIN L1 [get_ports {led[15]}]					
set_property IOSTANDARD LVCMOS33 [get_ports {led[15]}]

## ================================================================
## AD8232 XDC additions for Basys3 (xc7a35tcpg236-1)
## ================================================================

## -- JXADC analogue input (AD8232 OUTPUT pin) --------------------
set_property PACKAGE_PIN J3 [get_ports vauxp6]
set_property IOSTANDARD LVCMOS33 [get_ports vauxp6]

set_property PACKAGE_PIN K3 [get_ports vauxn6]
set_property IOSTANDARD LVCMOS33 [get_ports vauxn6]

## -- Lead-off detect (AD8232 LO+ and LO-) ----------------------
set_property PACKAGE_PIN J1  [get_ports lo_plus]
set_property IOSTANDARD LVCMOS33 [get_ports lo_plus]
set_property PULLDOWN TRUE [get_ports lo_plus]

set_property PACKAGE_PIN L2  [get_ports lo_minus]
set_property IOSTANDARD LVCMOS33 [get_ports lo_minus]
set_property PULLDOWN TRUE [get_ports lo_minus]

## -- BTNL: left button = start ECG capture ----------------------
set_property PACKAGE_PIN W19 [get_ports btnl]
set_property IOSTANDARD LVCMOS33 [get_ports btnl]

## -- SW15: mode select (0=UART, 1=AD8232) -----------------------
set_property PACKAGE_PIN R2  [get_ports sw15]
set_property IOSTANDARD LVCMOS33 [get_ports sw15]

## -- CFGBVS (required for XADC, suppresses DRC warning) --------
set_property CFGBVS VCCO        [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]