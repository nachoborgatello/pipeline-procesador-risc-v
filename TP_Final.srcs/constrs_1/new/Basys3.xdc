## Constraints para Basys3 Rev B - TP Final RISC-V Pipeline
## Basado en Basys3_Master.xdc

## ============================================================
## Clock signal - 100 MHz onboard oscillator
## ============================================================
## NOTA: el create_clock para este pin lo genera automaticamente el IP
## clk_wiz_0 (Clock Wizard) en su XDC interno. NO declararlo aca, porque
## causa dos primary clocks sobre el mismo pin (uno llamado "clk" del IP
## y otro llamado "sys_clk_pin" del usuario), lo que hace que el MMCM
## genere dos sets de output clocks (clk_out1_clk_wiz_0 y _1) y dispara
## "Critical Warning: clocks are related but have no common primary clock".
set_property -dict { PACKAGE_PIN W5   IOSTANDARD LVCMOS33 } [get_ports clk]

## ============================================================
## Reset - Boton central (btnC)
## ============================================================
set_property -dict { PACKAGE_PIN U18  IOSTANDARD LVCMOS33 } [get_ports rst]

## ============================================================
## USB-RS232 Interface (UART)
## ============================================================
set_property -dict { PACKAGE_PIN B18  IOSTANDARD LVCMOS33 } [get_ports uart_rx_i]
set_property -dict { PACKAGE_PIN A18  IOSTANDARD LVCMOS33 } [get_ports uart_tx_o]

## ============================================================
## I/O Timing Constraints
## ============================================================
## rst (boton btnC) es operado por una persona, no tiene relacion temporal
## con el clock. UART RX/TX van a 115200 baud (~8.7 us por bit), un universo
## mas lentas que el clock de 90 MHz. Estos paths son asincronicos por
## naturaleza y se declaran como false_path para que Vivado no los analice
## innecesariamente (silencia warnings TIMING-18 Bad Practice).
## Como rst y uart_rx_i ademas estan sincronizados con 2 FFs en top_level.v
## (atributo ASYNC_REG="TRUE"), el comportamiento contra metastabilidad esta
## garantizado.
set_false_path -from [get_ports rst]
set_false_path -from [get_ports uart_rx_i]
set_false_path -to   [get_ports uart_tx_o]

## ============================================================
## Configuration
## ============================================================
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 33 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
