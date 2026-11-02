// Probe the SECOND hit of a symbol: the first call to rust_stack_args comes
// from the TI C driver (known good), the second from rust_bb_args / rust_nested
// (the Rust caller under test).  Dump argument registers and the stack words
// that hold the incoming stack arguments.
importPackage(Packages.com.ti.debug.engine.scripting)
importPackage(Packages.com.ti.ccstudio.scripting.environment)
importPackage(Packages.java.lang)

var script = ScriptingEnvironment.instance()
script.setScriptTimeout(60000)
var server = script.getServer("DebugServer.1")
server.setConfig(arguments[1])
var session = server.openSession("*", "*")
session.target.connect()
session.target.reset()
session.memory.loadProgram(arguments[0])

var sym = arguments[2]
var hits = parseInt(arguments[3] ? arguments[3] : "2")
var addr = session.symbol.getAddress(sym)
System.out.println("PROBE=" + sym + " addr=" + addr + " waiting for hit " + hits)

session.expression.evaluate("PC = code_start")
var bp = session.breakpoint.add(addr)
for (var i = 0; i < hits; i++) {
    session.target.run()
}
session.target.halt()

var sp = session.expression.evaluate("SP")
System.out.println("ENTRY=" + sym + " SP=" + sp +
                   " AL=" + session.expression.evaluate("AL") +
                   " AH=" + session.expression.evaluate("AH") +
                   " ACC=" + session.expression.evaluate("ACC") +
                   " AR4=" + session.expression.evaluate("AR4") +
                   " AR5=" + session.expression.evaluate("AR5") +
                   " AR0=" + session.expression.evaluate("AR0") +
                   " AR1=" + session.expression.evaluate("AR1") +
                   " AR2=" + session.expression.evaluate("AR2"))
// Word-addressed stack: dump SP-10 .. SP+4 words.
for (var off = -10; off <= 4; off++) {
    var v = session.memory.readData(0, sp + off, 1, 2, false)[0]
    System.out.println("STK[" + off + "] @" + (sp + off) + " = " + v)
}
session.breakpoint.remove(bp)
session.terminate()
server.stop()
