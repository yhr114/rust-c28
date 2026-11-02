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
var entryProbe = session.breakpoint.add(session.symbol.getAddress("beq"))
session.expression.evaluate("PC = code_start")
session.target.run()
System.out.println("CORE_EX_ENTRY_PC=" + session.expression.evaluate("PC"))
session.breakpoint.remove(entryProbe)
var bp = session.breakpoint.add(done)
session.target.run()
session.breakpoint.remove(bp)
session.target.halt()

// Expected values follow tools/hw_rust_core_ex_driver_e.c and the host test
// module in backend/llvm-c28x/test/Rust/b1-hw-core-ex.rs.
var expected = [1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 5, 9, 0, 0xB3]
var names = [
    "beq(3,3)", "beq(3,4)", "blt(2,5)", "blt(5,2)",
    "beq8(0x107,0x207)", "beq8(0x107,0x208)", "beq1(1)", "beq1(2)",
    "some_of(1)", "some_of(0)", "none_of(0)", "none_of(1)",
    "unwrap_of(1)", "unwrap_of(0)", "not_of(0)", "marker"
]
var results = []
for (var i = 0; i < expected.length; i++) {
    results.push(session.expression.evaluate("HW_CORE_RESULT[" + i + "]"))
}
System.out.println("CORE_EX_RESULTS=" + results)
for (var i = 0; i < expected.length; i++) {
    if (results[i] != expected[i]) {
        System.out.println("MISMATCH " + names[i] + ": got " + results[i] +
                           " want " + expected[i])
        throw new Error("broad core exercise group E RAM test mismatch")
    }
}
var pc = session.expression.evaluate("PC")
if (pc != done) {
    throw new Error("execution did not stop at hw_done")
}
System.out.println("PASS: broad core exercise group E (boolean comparisons, Option tags) on F28035")
session.terminate()
server.stop()
