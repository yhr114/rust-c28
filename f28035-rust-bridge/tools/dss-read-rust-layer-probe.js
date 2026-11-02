importPackage(Packages.com.ti.debug.engine.scripting)
importPackage(Packages.com.ti.ccstudio.scripting.environment)
importPackage(Packages.java.lang)

// Read the layered B-1 probe: one line per layer so the first failing layer is
// obvious in the runner output.
var script = ScriptingEnvironment.instance()
script.setScriptTimeout(60000)
var server = script.getServer("DebugServer.1")
server.setConfig(arguments[1])
var session = server.openSession("*", "*")
session.target.connect()
session.target.reset()
session.memory.loadProgram(arguments[0])

var done = session.symbol.getAddress("hw_done")
session.expression.evaluate("PC = code_start")
var bp = session.breakpoint.add(done)
session.target.run()
session.breakpoint.remove(bp)
session.target.halt()

var names = ["echo(0x1234)", "cmp_eq(5,5)", "cmp_eq(5,6)", "if_zero(0)",
             "if_zero(7)", "mode(0,20)", "mode(1,20)", "mode(2,20)",
             "sum(data,4)", "byte_stack(0x77)", "byte_ptr", "word_ptr", "marker"]
var expected = [0x1234, 1, 0, 23, 40, 23, 40, 19, 20, 0x5A77, 0x33, 2, 0x1234]
var results = []
var failed = 0
for (var i = 0; i < expected.length; i++) {
    var v = session.expression.evaluate("HW_LAYER_RESULT[" + i + "]")
    results.push(v)
    var ok = (v == expected[i])
    if (!ok) failed++
    System.out.println("LAYER " + i + " " + names[i] + " = " + v +
                       " want " + expected[i] + (ok ? "  ok" : "  <-- WRONG"))
}
System.out.println("LAYER_RESULTS=" + results)
var pc = session.expression.evaluate("PC")
System.out.println("PC=" + pc + " DONE=" + done)
session.terminate()
server.stop()
if (failed > 0) {
    System.out.println("LAYER_FAIL count=" + failed)
}
