package spi_slave

import chisel3._
import chisel3.iotesters.{PeekPokeTester, Driver}
import chisel3.experimental.{withClock}

class spi_slave(val cfg_length : Int = 8, val monitor_length : Int =8) extends Module {
    val io = IO(new Bundle{
      val mosi = Input(UInt(1.W))
      val cs   = Input(UInt(1.W))
      val miso = Output(UInt(1.W))
      val config_out = Output(UInt(cfg_length.W))
      val monitor_in = Input(UInt(monitor_length.W))
    })

    val spi_enabled = !io.cs.toBool
    val inv_sclk = (!clock.asUInt.toBool).asClock()

    val serial_register = withClock(inv_sclk){Reg(Vec(io.config_out.getWidth+io.monitor_in.getWidth,UInt(1.W)))}
    val config_out_reg =  Reg(Vec(cfg_length,UInt(1.W)))
    val monitor_in_reg =  Reg(Vec(cfg_length,UInt(1.W)))
        
    // Check the endianness
    when ( spi_enabled === 1.U) {
        serial_register(0):=io.mosi
        for ( i <- 1 until serial_register.length ) {
            serial_register(i):=serial_register(i-1)
        }
    }.otherwise {
        for ( i <- 0 until config_out_reg.getWidth ) {
            config_out_reg(i) := serial_register(i)
        }

        //Requires condition
        for ( i <- 0 until monitor_in_reg.getWidth ) {
            serial_register(config_out_reg.getWidth+i) := monitor_in_reg(i).asUInt()
        }
    }

    // Define assingment conditions
    io.config_out:=config_out_reg.asUInt()

    
    when (spi_enabled) { 
      //io.miso := state(cfg_length-1)
      io.miso := serial_register(cfg_length-1)
    }
    .otherwise {
      io.miso := 0.U
    }

}

object spi_slave extends App {
    chisel3.Driver.execute(args, () => new spi_slave)
}

class unit_tester(c: spi_slave) extends PeekPokeTester(c) {
  
    // tests that the mosi passes through the register not sooner than full cycle
    poke(c.io.mosi, 1)
    poke(c.io.cs, 1)
    for (i <- 0 to 2){
      step(1)
      expect(c.io.miso, 0)
    }

    poke(c.io.cs, 0)
    for (i <- 1 to 7){
      step(1)
      expect(c.io.miso, 0)
    }
    step(1)
    expect(c.io.miso, 1)
    step(1)
    expect(c.io.miso, 1)
}

object unit_test extends App {
    iotesters.Driver.execute(args, () => new spi_slave){
            c=>new unit_tester(c)
    }
}
