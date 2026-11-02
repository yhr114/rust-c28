importPackage(Packages.com.ti.debug.engine.scripting)
importPackage(Packages.com.ti.ccstudio.scripting.environment)
importPackage(Packages.java.lang)

// Trace the first rust_control call: entry registers, the tag/sum pair handed to
// rust_mode, the value rust_mode returns, and the driver's first store.
var script = ScriptingEnvironment.instance()
script.setScriptTimeout(60000)
var server = script.getServer("DebugServer.1")
server.setConfig(arguments[1])
var session = server.openSession("*", "*")
session.target.connect()
session.target.reset()
session.memory.loadProgram(arguments[0])

function at(name) { return session.symbol.getAddress(name) }
var ctl = at("rust_control")
var mode = at("rust_mode")
var done = at("hw_done")

session.expression.evaluate("PC = code_start")

var bp = session.breakpoint.add(ctl)
session.target.run()
session.breakpoint.remove(bp)
System.out.println("CTL-ENTRY PC=" + session.expression.evaluate("PC") +
                   " ACC=" + session.expression.evaluate("ACC") +
                   " AR4=" + session.expression.evaluate("AR4") +
                   " AR5=" + session.expression.evaluate("AR5") +
                   " SP=" + session.expression.evaluate("SP"))

var bp2 = session.breakpoint.add(mode)
session.target.run()
session.breakpoint.remove(bp2)
System.out.println("MODE-ENTRY AL=" + session.expression.evaluate("AL") +
                   " AH=" + session.expression.evaluate("AH") +
                   " ACC=" + session.expression.evaluate("ACC") +
                   " SP=" + session.expression.evaluate("SP"))

// Step over rust_mode: break on the instruction after its call site by
// stopping at hw_done for the whole program and reading the results.
var bp3 = session.breakpoint.add(done)
session.target.run()
session.breakpoint.remove(bp3)
session.target.halt()
var res = []
for (var i = 0; i < 6; i++)
    res.push(session.expression.evaluate("HW_RUST_RESULT[" + i + "]"))
System.out.println("RESULTS=" + res + " PC=" + session.expression.evaluate("PC") +
                   " DONE=" + done)
session.terminate()
server.stop()
