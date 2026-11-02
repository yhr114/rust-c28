importPackage(Packages.com.ti.debug.engine.scripting)
importPackage(Packages.com.ti.ccstudio.scripting.environment)
importPackage(Packages.java.lang)

// Follow SP through the SECOND rust_control call to find where the stack is lost.
var script = ScriptingEnvironment.instance()
script.setScriptTimeout(90000)
var server = script.getServer("DebugServer.1")
server.setConfig(arguments[1])
var session = server.openSession("*", "*")
session.target.connect()
session.target.reset()
session.memory.loadProgram(arguments[0])

function at(n) { return session.symbol.getAddress(n) }
var ctl = at("rust_control")
var sumf = at("rust_sum_slice")
var mode = at("rust_mode")
var main = at("main")

function sp(tag) {
    System.out.println(tag + " SP=" + session.expression.evaluate("SP") +
                       " PC=" + session.expression.evaluate("PC"))
}

session.expression.evaluate("PC = code_start")

// Main entry SP, then first call (we know it balances).
var bp = session.breakpoint.add(ctl)
session.target.run(); session.breakpoint.remove(bp); sp("CTL1-ENTRY")
bp = session.breakpoint.add(ctl)
session.target.run(); session.breakpoint.remove(bp); sp("CTL2-ENTRY")

// Inside call 2: sum_slice entry/exit, mode entry/exit.
bp = session.breakpoint.add(sumf)
session.target.run(); session.breakpoint.remove(bp); sp("SUM2-ENTRY")
bp = session.breakpoint.add(mode)
session.target.run(); session.breakpoint.remove(bp); sp("MODE2-ENTRY")
bp = session.breakpoint.add(ctl + 0x09)
session.target.run(); session.breakpoint.remove(bp); sp("CTL2-SUBBSP")
bp = session.breakpoint.add(ctl + 0x0b)
session.target.run(); session.breakpoint.remove(bp); sp("CTL2-LRETR")
bp = session.breakpoint.add(main + 0x25)
session.target.run(); session.breakpoint.remove(bp); sp("STORE2")
session.terminate()
server.stop()
