importPackage(Packages.com.ti.debug.engine.scripting)
importPackage(Packages.com.ti.ccstudio.scripting.environment)
importPackage(Packages.java.lang)

// Record the exact instruction sequence executed inside rust_mode for the first
// rust_control(tag=0) call, together with AL/AH/AR7 at every stop, so a wrong
// branch target or an unset scratch register shows up directly.
var script = ScriptingEnvironment.instance()
script.setScriptTimeout(120000)
var server = script.getServer("DebugServer.1")
server.setConfig(arguments[1])
var session = server.openSession("*", "*")
session.target.connect()
session.target.reset()
session.memory.loadProgram(arguments[0])

var mode = session.symbol.getAddress("rust_mode")
var done = session.symbol.getAddress("hw_done")
session.expression.evaluate("PC = code_start")

// Stop at the first rust_mode entry.
var bpMode = session.breakpoint.add(mode)
session.target.run()
session.breakpoint.remove(bpMode)

// Breakpoints on every word of the function body (byte addresses are word*2
// for code, so the DSS address is the word address directly).
var bps = {}
for (var off = 0; off <= 0x24; off++) {
    bps[off] = session.breakpoint.add(mode + off)
}
var trace = []
for (var i = 0; i < 60; i++) {
    var pc = session.expression.evaluate("PC")
    var off = pc - mode
    trace.push(("0x" + off.toString(16)) + " AL=" + session.expression.evaluate("AL") +
               " AH=" + session.expression.evaluate("AH") +
               " AR7=" + session.expression.evaluate("AR7"))
    if (bps[off] !== undefined) {
        session.breakpoint.remove(bps[off])
        delete bps[off]
    }
    if (off === 0x1a || off === 0x23 || off < 0)
        break
    session.target.run()
}
for (var k = 0; k < trace.length; k++)
    System.out.println("STEP " + trace[k])
System.out.println("MODE_BASE=" + mode + " DONE=" + done +
                   " PC=" + session.expression.evaluate("PC"))
session.terminate()
server.stop()
