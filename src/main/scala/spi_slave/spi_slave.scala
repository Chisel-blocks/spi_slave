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
    val monitor_in_reg =  Reg(Vec(monitor_length,UInt(1.W)))
        
    // Check the endianness
    //Requires condition
    when ( spi_enabled === 1.U) {
        serial_register(0):=io.mosi
        for ( i <- 1 until serial_register.length ) {
            serial_register(i):=serial_register(i-1)
        }
    }.otherwise {
        for ( i <- 0 until config_out_reg.getWidth ) {
            config_out_reg(i) := serial_register(i)
        }
        for ( i <- 0 until monitor_in_reg.getWidth ) {
            //println(i)
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
            |     monitor_length   [Int]     : Number of bits in the monitor register. Default 8
            |     h                       : This help 
          """.stripMargin
        val optsWithArg: List[String]=List(
            "-cfg_length",
            "-monitor_length"
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
        "monitor_length"->"8"
        ) 
    // Parse the options
    val (options,arguments)= getopts(defaultoptions,args.toList)
  
    chisel3.Driver.execute(arguments.toArray, () => 
            new spi_slave(
                cfg_length=options("cfg_length").toInt, 
                monitor_length=options("monitor_length").toInt
            )
    )
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
