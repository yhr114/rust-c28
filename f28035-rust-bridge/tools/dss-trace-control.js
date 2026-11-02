// Value-level trace of the first control call: entry args, the sum before
// return, and the mode-call arguments.  Prints raw register values so the
// first divergence from the expected (sum=20, tag=0, result=23) is visible.
importPackage(Packages.com.ti.debug.engine.scripting)
importPackage(Packages.com.ti.ccstudio.scripting.environment)
importPackage(Packages.java.lang)

var script = ScriptingEnvironment.instance()
script.setScriptTimeout(120000)
var server = script.getServer("DebugServer.1")
server.setConfig(arguments[1])
var session = server.openSession("*", "*")
session.target.connect()
session.target.reset()
session.memory.loadProgram(arguments[0])

var fSum = session.symbol.getAddress("rust_sum_slice")
var fCtl = session.symbol.getAddress("rust_control")
var fMode = session.symbol.getAddress("rust_mode")
System.out.println("sum=0x" + fSum.toString(16) + " ctl=0x" + fCtl.toString(16) + " mode=0x" + fMode.toString(16))

function dump(label) {
    var pc = session.expression.evaluate("PC")
    var acc = session.expression.evaluate("ACC")
    var ar1 = session.expression.evaluate("AR1")
    var ar5 = session.expression.evaluate("AR5")
    var x4 = session.expression.evaluate("XAR4")
    var sp = session.expression.evaluate("SP")
    System.out.println(label + " PC=0x" + pc.toString(16) + " ACC=0x" + acc.toString(16) +
        " AR1=0x" + ar1.toString(16) + " AR5=0x" + ar5.toString(16) +
        " XAR4=0x" + x4.toString(16) + " SP=0x" + sp.toString(16))
}

// 1. entry of the first call
var bp = session.breakpoint.add(fCtl)
session.expression.evaluate("PC = code_start")
session.target.run()
session.target.halt()
session.breakpoint.remove(bp)
dump("CTL-ENTRY")

// 2. sum entry
bp = session.breakpoint.add(fSum)
session.target.run()
session.target.halt()
session.breakpoint.remove(bp)
dump("SUM-ENTRY")

// 3. sum just before LRETR (offset 0x34 is the return-value materialisation)
bp = session.breakpoint.add(fSum + 0x34)
session.target.run()
session.target.halt()
session.breakpoint.remove(bp)
dump("SUM-RET")

// 4. mode entry (the args tell us what rust_control passed on)
bp = session.breakpoint.add(fMode)
session.target.run()
session.target.halt()
session.breakpoint.remove(bp)
dump("MODE-ENTRY")

// 5. mode return: stop at the last instruction before LRETR by stepping with
//    temporary breakpoints is unreliable; instead run to the driver's store.
var done = session.symbol.getAddress("hw_done")
bp = session.breakpoint.add(done)
try { session.target.run(); session.target.halt(); } catch (e) { System.out.println("run to done: " + e) }
session.breakpoint.remove(bp)
dump("AT-DONE")
var r0 = session.expression.evaluate("HW_RUST_RESULT[0]")
System.out.println("RESULT0=" + r0)

session.terminate()
server.stop()
