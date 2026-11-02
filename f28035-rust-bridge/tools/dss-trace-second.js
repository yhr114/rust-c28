// Trace the SECOND rust_control call (tag=1 -> Double path) to find where it
// diverges.  Hits the control entry twice, then the sum entry, then the mode
// entry, dumping registers at each stop.
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

var fCtl = session.symbol.getAddress("rust_control")
var fSum = session.symbol.getAddress("rust_sum_slice")
var fMode = session.symbol.getAddress("rust_mode")

function dump(label) {
    var pc = session.expression.evaluate("PC")
    var acc = session.expression.evaluate("ACC")
    var x4 = session.expression.evaluate("XAR4")
    var sp = session.expression.evaluate("SP")
    var ar5 = session.expression.evaluate("AR5")
    System.out.println(label + " PC=0x" + pc.toString(16) + " ACC=0x" + acc.toString(16) +
        " AL=" + session.expression.evaluate("AL") + " AH=0x" + session.expression.evaluate("AH").toString(16) +
        " XAR4=0x" + x4.toString(16) + " AR5=0x" + ar5.toString(16) + " SP=0x" + sp.toString(16))
}

session.expression.evaluate("PC = code_start")
// first call: enter and leave via its store
var bp = session.breakpoint.add(fCtl)
session.target.run(); session.target.halt()
session.breakpoint.remove(bp)
dump("CTL1-ENTRY")
var bpStore = session.breakpoint.add(session.symbol.getAddress("main") + 0x1d)
session.target.run(); session.target.halt()
session.breakpoint.remove(bpStore)
dump("AFTER-CTL1")

// second call
bp = session.breakpoint.add(fCtl)
session.target.run(); session.target.halt()
session.breakpoint.remove(bp)
dump("CTL2-ENTRY")

bp = session.breakpoint.add(fSum)
session.target.run(); session.target.halt()
session.breakpoint.remove(bp)
dump("SUM2-ENTRY")

bp = session.breakpoint.add(fSum + 0x34)
session.target.run(); session.target.halt()
session.breakpoint.remove(bp)
dump("SUM2-RET")

bp = session.breakpoint.add(fMode)
session.target.run(); session.target.halt()
session.breakpoint.remove(bp)
dump("MODE2-ENTRY")

bp = session.breakpoint.add(fMode + 0x16)
session.target.run(); session.target.halt()
session.breakpoint.remove(bp)
dump("MODE2-LSL-DONE")

// run to the second result store
bp = session.breakpoint.add(session.symbol.getAddress("main") + 0x25)
try { session.target.run(); session.target.halt(); } catch (e) { System.out.println("run err " + e) }
session.breakpoint.remove(bp)
dump("AFTER-CTL2")
session.terminate()
server.stop()
