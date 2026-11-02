importPackage(Packages.com.ti.debug.engine.scripting)
importPackage(Packages.com.ti.ccstudio.scripting.environment)
importPackage(Packages.java.lang)

// Read the byte-addressing probe results.  0x1234 is stored at word address
// 0x0600, then single bytes are read through char pointers placed at byte
// addresses 0x0C00/0x0C01 and through p[1] / p[i].
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

var names = ["byte@0x0C00", "byte@0x0C01", "p[1]", "p[i]", "marker"]
var results = []
for (var i = 0; i < names.length; i++) {
    results.push(session.expression.evaluate("RES[" + i + "]"))
}
System.out.println("BYTE_SEM=" + results)
for (var i = 0; i < names.length; i++) {
    System.out.println("  " + names[i] + " = 0x" + results[i].toString(16))
}
var pc = session.expression.evaluate("PC")
if (pc != done) {
    throw new Error("probe did not reach hw_done")
}
session.terminate()
server.stop()
