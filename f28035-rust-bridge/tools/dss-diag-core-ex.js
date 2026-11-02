importPackage(Packages.com.ti.debug.engine.scripting)
importPackage(Packages.com.ti.ccstudio.scripting.environment)
importPackage(Packages.java.lang)

var script = ScriptingEnvironment.instance()
script.setScriptTimeout(20000)
var server = script.getServer("DebugServer.1")
server.setConfig(arguments[1])
var session = server.openSession("*", "*")
session.target.connect()
session.target.reset()
session.memory.loadProgram(arguments[0])
session.expression.evaluate("PC = code_start")
try {
    session.target.run()
} catch (e) {
    System.out.println("run timed out or halted: " + e)
}
try { session.target.halt() } catch (e2) { }
var pc = session.expression.evaluate("PC")
System.out.println("PC_AFTER_HANG=0x" + pc.toString(16))
var syms = ["core_ex_option", "core_ex_result", "core_ex_mem", "core_ex_cmp",
            "core_ex_closure", "core_ex_pattern", "hw_done", "code_start"]
for (var i = 0; i < syms.length; i++) {
    var a = session.symbol.getAddress(syms[i])
    System.out.println("SYM " + syms[i] + " = 0x" + a.toString(16))
}
var results = []
for (var i = 0; i < 7; i++) {
    results.push(session.expression.evaluate("HW_CORE_RESULT[" + i + "]"))
}
System.out.println("HW_CORE_RESULT=" + results)
session.terminate()
server.stop()
