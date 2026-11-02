// Read the return-address slot at the mode's LRETR for both calls.
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
var fMode = session.symbol.getAddress("rust_mode")
function rd(e) { try { return session.expression.evaluate(e) } catch (x) { return -1 } }
function h(v) { try { return v.toString(16) } catch (x) { return "?" } }

session.expression.evaluate("PC = code_start")
var bp = session.breakpoint.add(fMode + 0x1a)
for (var i = 0; i < 3; i++) {
    try { session.target.run(); session.target.halt(); } catch (e) { System.out.println("run " + i + " err"); break }
    var pc = rd("PC")
    if (pc !== fMode + 0x1a) { System.out.println("STOP" + i + " unexpected PC=0x" + h(pc)); break }
    var sp = rd("SP")
    System.out.println("LRETR" + i + " SP=0x" + h(sp) +
        " [sp-1]=0x" + h(rd("*(unsigned short*)(" + (sp - 1) + ")")) +
        " [sp-2]=0x" + h(rd("*(unsigned short*)(" + (sp - 2) + ")")) +
        " [sp-3]=0x" + h(rd("*(unsigned short*)(" + (sp - 3) + ")")) +
        " expect=0x" + h(fCtl + 9))
}
session.breakpoint.remove(bp)
session.terminate()
server.stop()
