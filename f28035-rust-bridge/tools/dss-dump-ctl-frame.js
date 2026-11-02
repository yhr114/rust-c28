importPackage(Packages.com.ti.debug.engine.scripting)
importPackage(Packages.com.ti.ccstudio.scripting.environment)
importPackage(Packages.java.lang)

// At the LRETR of the SECOND rust_control call, dump the words around SP: the
// return address must be [SP-2],[SP-1].
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
session.expression.evaluate("PC = code_start")

var bp = session.breakpoint.add(ctl + 0x0b)
for (var hit = 1; hit <= 2; hit++) {
    session.target.run()
    if (hit === 1) { session.breakpoint.remove(bp); bp = session.breakpoint.add(ctl + 0x0b) }
}
session.breakpoint.remove(bp)
session.target.halt()
var sp = session.expression.evaluate("SP")
System.out.println("CTL-LRETR2 SP=" + sp + " XAR5=" + session.expression.evaluate("AR5") +
                   " ACC=" + session.expression.evaluate("ACC"))
for (var off = -4; off <= 4; off++) {
    var addr = sp + off
    System.out.println("W[" + off + "] @" + addr + " = " +
        session.expression.evaluate("*(unsigned int *)0x" + addr.toString(16)))
}
session.terminate()
server.stop()
