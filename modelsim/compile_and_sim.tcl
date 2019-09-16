vlib work

vlog -work work ../verilog/async_set_register.v
vlog -work work ../verilog/spi_slave.v
vcom -work work -2008 tb_spi_slave.vhd

vsim work.tb_spi_slave

add wave *
add wave tb_spi_slave:DUT:*

run -all
wave zoom full
