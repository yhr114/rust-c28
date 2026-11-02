importPackage(Packages.com.ti.debug.engine.scripting)
importPackage(Packages.com.ti.ccstudio.scripting.environment)
importPackage(Packages.java.lang)

// Dump the stack window right after lp_byte_stack stores t[0] = 0x77, so the
// word the store actually touched can be compared with the word the load reads.
var script = ScriptingEnvironment.instance()
script.setScriptTimeout(60000)
var server = script.getServer("DebugServer.1")
server.setConfig(arguments[1])
var session = server.openSession("*", "*")
session.target.connect()
session.target.reset()
session.memory.loadProgram(arguments[0])

var fn = session.symbol.getAddress("lp_byte_stack")
session.expression.evaluate("PC = code_start")
var bp = session.breakpoint.add(fn + 0x19)
session.target.run()
session.breakpoint.remove(bp)
session.target.halt()

var sp = session.expression.evaluate("SP")
System.out.println("AFTER-STORE SP=" + sp + " XAR7=" +
                   session.expression.evaluate("XAR7") + " AR0=" +
                   session.expression.evaluate("AR0") + " AL=" +
                   session.expression.evaluate("AL"))
for (var off = -5; off <= 2; off++) {
    var addr = sp + off
    System.out.println("WORD[" + off + "] @" + addr + " = " +
        session.expression.evaluate("*(unsigned int *)0x" + addr.toString(16)))
}
session.terminate()
server.stop()
