importPackage(Packages.com.ti.debug.engine.scripting)
importPackage(Packages.com.ti.ccstudio.scripting.environment)
importPackage(Packages.java.lang)

// Diagnostic: dump the stack around SP at a Rust function's entry so the
// incoming stack-argument layout can be read off the target directly.
// Usage: dss.bat dss-probe-stkargs.js <out file> <ccxml> <symbol>
var script = ScriptingEnvironment.instance()
script.setScriptTimeout(30000)
var server = script.getServer("DebugServer.1")
server.setConfig(arguments[1])
var session = server.openSession("*", "*")
session.target.connect()
session.target.reset()
session.memory.loadProgram(arguments[0])

var sym = session.symbol.getAddress(arguments[2])
session.expression.evaluate("PC = code_start")
var bp = session.breakpoint.add(sym)
session.target.run()
session.breakpoint.remove(bp)
session.target.halt()

var sp = session.expression.evaluate("SP")
System.out.println("ENTRY=" + sym + " SP=" + sp +
                   " ACC=" + session.expression.evaluate("ACC") +
                   " AR4=" + session.expression.evaluate("AR4") +
                   " AR5=" + session.expression.evaluate("AR5"))
// Word-addressed stack: dump a wide window so the argument area is visible.
for (var off = -24; off <= 6; off++) {
    var addr = sp + off
    var val = session.expression.evaluate("*(unsigned int *)0x" + addr.toString(16))
    System.out.println("STK[" + off + "] @" + addr + " = " + val)
}
session.terminate()
server.stop()
