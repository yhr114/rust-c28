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
var entryProbe = session.breakpoint.add(session.symbol.getAddress("bnd_shl"))
session.expression.evaluate("PC = code_start")
session.target.run()
System.out.println("CORE_EX_ENTRY_PC=" + session.expression.evaluate("PC"))
session.breakpoint.remove(entryProbe)
var bp = session.breakpoint.add(done)
session.target.run()
session.breakpoint.remove(bp)
session.target.halt()

// Expected values follow tools/hw_rust_core_ex_driver_f.c and the host test
// module in backend/llvm-c28x/test/Rust/b1-hw-core-ex.rs.
var expected = [0x1234, 0x2468, 0x8000, 0x3400, 0x1234, 0x091A, 0x0000, 0x1235,
                0x0000, 0x1233, 1, 0, 1, 0, 0xB4, 0]
var names = [
    "shl(0x1234,16)", "shl(0x1234,17)", "shl(0xFFFF,31)", "shl_lo(0x1234,8)",
    "shr(0x1234,16)", "shr(0x1234,17)", "shr(0x1234,31)", "u32_addhi(0x1234,0xFFFF)",
    "u32_addhi(0xFFFF,0xFFFF)", "u32_subhi(0x1234,1)", "u32_cmp(1,1)", "u32_cmp(1,2)",
    "i16_cmp(0xFFFF,0)", "i16_cmp(0,0xFFFF)", "marker", "pad"
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
        throw new Error("broad core exercise group F RAM test mismatch")
    }
}
var pc = session.expression.evaluate("PC")
if (pc != done) {
    throw new Error("execution did not stop at hw_done")
}
System.out.println("PASS: broad core exercise group F (u32/i32 boundary, variable shifts) on F28035")
session.terminate()
server.stop()
