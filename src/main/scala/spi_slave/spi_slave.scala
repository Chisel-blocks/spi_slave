package spi_slave

import chisel3._
import chisel3.iotesters.{PeekPokeTester, Driver}
import chisel3.experimental.{withClock}

class spi_slave(val cfg_length : Int = 8) extends Module {
    val io = IO(new Bundle{
      val mosi = Input(UInt(1.W))
      val cs   = Input(UInt(1.W))
      val miso = Output(UInt(1.W))
      val inv_sclk = Input(Clock())
      val config_out = Output(UInt(cfg_length.W))
    })

    val spi_enabled = !io.cs.toBool

    withClock(io.inv_sclk){
      val state = Reg(UInt(cfg_length.W))
      val nextState = (state << 1) | io.mosi
      when (spi_enabled) {
          state := nextState
      }
    }

    io.config_out := state
    when (spi_enabled) { 
      io.miso := state(cfg_length-1)
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
