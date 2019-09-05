
// Dsp-block spi_slave
// Description here
// Inititally written by dsp-blocks initmodule.sh, 20190905
package spi_slave

//import chisel3.experimental._
import chisel3._
import chisel3.iotesters.{PeekPokeTester, Driver}
//import dsptools.{DspTester, DspTesterOptionsManager, DspTesterOptions}
//import dsptools.numbers._
//import breeze.math.Complex

//class spi_slave_io[T <:Data](proto: T,n: Int)
//   extends Bundle {
//        val A       = Input(Vec(n,proto))
//        val B       = Output(Vec(n,proto))
//        override def cloneType = (new spi_slave_io(proto.cloneType,n)).asInstanceOf[this.type]
//   }

class spi_slave extends Module {
    val io = IO(new Bundle{
      val mosi = Input(UInt(1.W))
      val cs   = Input(UInt(1.W))
      val miso = Output(UInt(1.W))
    })
    io.miso:= io.mosi & io.cs
}

//This gives you verilog
object spi_slave extends App {
    chisel3.Driver.execute(args, () => new spi_slave)

    //chisel3.Driver.execute(args, () => new spi_slave(
    //    proto=DspComplex(UInt(16.W),UInt(16.W)), n=8)
    //)
}

//This is a simple unit tester for demonstration purposes
class unit_tester(c: spi_slave ) extends PeekPokeTester(c) {
//Tests are here 
    poke(c.io.mosi, 1)
    poke(c.io.cs, 0)
    step(1)
    expect(c.io.miso,0)

    poke(c.io.mosi, 1)
    poke(c.io.cs, 1)
    step(1)
    expect(c.io.miso,1)
}

//This is the test driver 
object unit_test extends App {
    iotesters.Driver.execute(args, () => new spi_slave){
            c=>new unit_tester(c)
    }
}
