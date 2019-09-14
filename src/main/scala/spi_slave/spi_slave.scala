package spi_slave

import chisel3._
import chisel3.util._
import chisel3.iotesters.{PeekPokeTester, Driver}
import chisel3.experimental.{withClock, withReset, withClockAndReset}

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

    //val inv_sclk = (!clock.asUInt.toBool).asClock()
    val inv_sclk = (!io.sclk.asUInt.toBool).asClock()

    // Here' my two cents
    //
    // SPI registers
    val shiftingConfig = withClock(inv_sclk){ Reg(UInt(cfg_length.W)) }
    val stateConfig = Reg(UInt(cfg_length.W))
    val shiftingMonitor = withClock(inv_sclk){ Reg(UInt(mon_length.W)) }
    val misoPosEdgeBuffer = withClock(io.sclk){ Reg(UInt(1.W)) }
    val spiFirstCycle = withReset(io.cs.toBool){ RegInit(1.U(1.W)) }
    spiFirstCycle := 0.U
    
    // pre-shifted vectors for register assignment 
    val nextShiftingConfig = (shiftingConfig << 1) | io.mosi
    val monitorRegShifted = (shiftingMonitor << 1) | shiftingConfig(cfg_length-1)

    // juggling with the monitor register input
    val monitorMuxControl = !io.cs.toBool && spiFirstCycle.toBool
    val nextShiftingMonitor = Mux(monitorMuxControl, io.monitor_in, monitorRegShifted)
    shiftingMonitor := nextShiftingMonitor

    // SPI transfer happens during CS line being low
    when (!io.cs.toBool) {
      shiftingConfig := nextShiftingConfig
      misoPosEdgeBuffer := nextShiftingMonitor(mon_length-1)
      io.miso := misoPosEdgeBuffer
    } .otherwise {
        // first cycle of internal clock after CS rises again
        when (risingEdge(io.cs.toBool)){
          stateConfig := shiftingConfig
        }
        io.miso:=0.U(1.W)
    }

    // provide a snapshot of shifting Config register to the chip
    io.config_out := stateConfig
}


//This is the object to provide verilog
object spi_slave extends App {
    // Getopts parses the "Command line arguments for you"  
    def getopts(options : Map[String,String], 
        arguments: List[String]) : (Map[String,String], List[String]) = {
        //This the help
        val usage = """
            |Usage: spi_slave.spi_slave [-<option>]
            |
            | Options
            |     cfg_length       [Int]     : Number of bits in the config register. Default 8
            |     mon_length       [Int]     : Number of bits in the monitor register. Default 8
            |     h                          : This help 
          """.stripMargin
        val optsWithArg: List[String]=List(
            "-cfg_length",
            "-mon_length"
        )
        //Handling of flag-like options to be defined 
        arguments match {
            case "-h" :: tail => {
                println(usage)
                val (newopts, newargs) = getopts(options, tail)
                sys.exit
                (Map("h"->"") ++ newopts, newargs)
            }
            case option :: value :: tail if optsWithArg contains option => {
               val (newopts, newargs) = getopts(
                   options++Map(option.replace("-","") -> value), tail
               )
               (newopts, newargs)
            }
              case argument :: tail => {
                 val (newopts, newargs) = getopts(options,tail)
                 (newopts, argument.toString +: newargs)
              }
            case Nil => (options, arguments)
        }
    }
     
    // Default options
    val defaultoptions : Map[String,String]=Map(
        "cfg_length"->"8",
        "mon_length"->"8"
        ) 
    // Parse the options
    val (options,arguments)= getopts(defaultoptions,args.toList)
  
    chisel3.Driver.execute(arguments.toArray, () => 
            new spi_slave(
                cfg_length=options("cfg_length").toInt, 
                mon_length=options("mon_length").toInt
            )
    )
}

class unit_tester(c: spi_slave) extends PeekPokeTester(c) {
}

object unit_test extends App {
    iotesters.Driver.execute(args, () => new spi_slave){
            c=>new unit_tester(c)
    }
}
