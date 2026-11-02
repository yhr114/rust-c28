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
var entryProbe = session.breakpoint.add(session.symbol.getAddress("core_ex_index"))
session.expression.evaluate("PC = code_start")
session.target.run()
System.out.println("CORE_EX_ENTRY_PC=" + session.expression.evaluate("PC"))
session.breakpoint.remove(entryProbe)
var bp = session.breakpoint.add(done)
session.target.run()
session.breakpoint.remove(bp)
session.target.halt()

// Expected values are pinned by the host test module in
// backend/llvm-c28x/test/Rust/b1-hw-core-ex.rs (rustc --test, 13/13 pass).
var expected = [132, 0xB3]
var names = ["core_ex_index", "marker"]
var results = []
for (var i = 0; i < expected.length; i++) {
    results.push(session.expression.evaluate("HW_CORE_RESULT[" + i + "]"))
}
System.out.println("CORE_EX_RESULTS=" + results)
for (var i = 0; i < expected.length; i++) {
    if (results[i] != expected[i]) {
        System.out.println("MISMATCH " + names[i] + ": got " + results[i] +
                           " want " + expected[i])
        throw new Error("broad core exercise group C RAM test mismatch")
    }
}
var pc = session.expression.evaluate("PC")
if (pc != done) {
    throw new Error("execution did not stop at hw_done")
}
System.out.println("PASS: broad core exercise group C (bounds-checked get/get_mut/split_at) on F28035")
session.terminate()
server.stop()
