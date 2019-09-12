package spi_slave

import chisel3._
import chisel3.util._
import chisel3.iotesters.{PeekPokeTester, Driver}
import chisel3.experimental.{withClock}

class spi_slave(val cfg_length : Int = 8, val mon_length : Int = 8) extends Module {
    val io = IO(new Bundle{
      val mosi = Input(UInt(1.W))
      val cs   = Input(UInt(1.W))
      val miso = Output(UInt(1.W))
      val sclk = Input(Clock())
      val config_out = Output(UInt(cfg_length.W))
      val monitor_in = Input(UInt(mon_length.W))
    })

    def risingEdge(x: Bool) = x && !RegNext(x)

    val spi_enabled = !io.cs.toBool
    //val inv_sclk = (!clock.asUInt.toBool).asClock()
    val inv_sclk = (!io.sclk.asUInt.toBool).asClock()

    // Here' my two cents
    //
    // SPI registers
    val shiftingConfig = withClock(inv_sclk){ Reg(UInt(cfg_length.W)) }
    val stateConfig = Reg(UInt(cfg_length.W))
    val shiftingMonitor = withClock(inv_sclk){ Reg(UInt(mon_length.W)) }
    val misoPosEdgeBuffer = withClock(io.sclk){ Reg(UInt(1.W)) }
    
    // "shifting" assignmentks
    val nextShiftingConfig = (shiftingConfig << 1) | io.mosi
    val nextShiftingMonitor = (shiftingMonitor << 1) | shiftingConfig(cfg_length-1)

    // upon CS line being low
    when (spi_enabled) {
      shiftingConfig := nextShiftingConfig
      shiftingMonitor := nextShiftingMonitor
      misoPosEdgeBuffer := shiftingMonitor(mon_length-1)
      io.miso := misoPosEdgeBuffer
    } .otherwise {
      io.miso := 0.U
    }

    // first cycle of internal clock after CS rises again
    when (risingEdge(io.cs.toBool)){
      stateConfig := shiftingConfig
      shiftingMonitor := io.monitor_in
    }

    // provide a snapshot of Config register to the chip
    io.config_out := stateConfig
}

object spi_slave extends App {
    chisel3.Driver.execute(args, () => new spi_slave)
}

class unit_tester(c: spi_slave) extends PeekPokeTester(c) {
}

object unit_test extends App {
    iotesters.Driver.execute(args, () => new spi_slave){
            c=>new unit_tester(c)
    }
}
