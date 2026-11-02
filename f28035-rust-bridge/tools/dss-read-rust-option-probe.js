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
var done = session.symbol.getAddress("hw_done")
var entryProbe = session.breakpoint.add(session.symbol.getAddress("probe_is_some_temp"))
session.expression.evaluate("PC = code_start")
session.target.run()
System.out.println("PROBE_ENTRY_PC=" + session.expression.evaluate("PC"))
session.breakpoint.remove(entryProbe)
var bp = session.breakpoint.add(done)
session.target.run()
session.breakpoint.remove(bp)
session.target.halt()

// Expected: is_some on a promoted .rodata Some(1)=1, .rodata volatile byte=1,
// stack volatile byte=1, probe_all=1111, marker=0x5A5A
var expected = [1, 1, 1, 1111, 0x5A5A]
var names = [
    "is_some_temp", "deref_rodata", "deref_stack", "probe_all", "marker"
]
var results = []
for (var i = 0; i < expected.length; i++) {
    results.push(session.expression.evaluate("HW_PROBE_RESULT[" + i + "]"))
}
System.out.println("PROBE_RESULTS=" + results)
for (var i = 0; i < expected.length; i++) {
    if (results[i] != expected[i]) {
        System.out.println("MISMATCH " + names[i] + ": got " + results[i] +
                           " want " + expected[i])
        throw new Error("option/pointer deref probe mismatch")
    }
}
var pc = session.expression.evaluate("PC")
if (pc != done) {
    throw new Error("execution did not stop at hw_done")
}
System.out.println("PASS: Option/pointer-deref probe on F28035")
session.terminate()
server.stop()
