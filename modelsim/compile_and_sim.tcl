vlib work

vlog -work work ../verilog/spi_slave.v
vcom -work work tb_spi_slave.vhd

vsim work.tb_spi_slave

add wave *

run -all
wave zoom full
