importPackage(Packages.com.ti.debug.engine.scripting)
importPackage(Packages.com.ti.ccstudio.scripting.environment)
importPackage(Packages.java.lang)

var script = ScriptingEnvironment.instance()
script.setScriptTimeout(30000)
var server = script.getServer("DebugServer.1")
server.setConfig(arguments[1])
var session = server.openSession("*", "*")
session.target.connect()
session.target.reset()
session.memory.loadProgram(arguments[0])
var done = session.symbol.getAddress("hw_done")
var controlEntry = session.symbol.getAddress("rust_control")
var sliceEntry = session.symbol.getAddress("rust_sum_slice")
var entryProbe = session.breakpoint.add(controlEntry)
session.expression.evaluate("PC = code_start")
session.target.run()
System.out.println("CONTROL_ENTRY_PC=" + session.expression.evaluate("PC") +
                   " ACC=" + session.expression.evaluate("ACC") +
                   " AR4=" + session.expression.evaluate("AR4") +
                   " AR5=" + session.expression.evaluate("AR5"))
session.breakpoint.remove(entryProbe)
var probe = session.breakpoint.add(sliceEntry)
session.target.run()
System.out.println("SLICE_ENTRY_PC=" + session.expression.evaluate("PC") +
                   " ACC=" + session.expression.evaluate("ACC") +
                   " AR4=" + session.expression.evaluate("AR4"))
System.out.println("RUST_DATA=" + [
    session.expression.evaluate("HW_RUST_DATA[0]"),
    session.expression.evaluate("HW_RUST_DATA[1]"),
    session.expression.evaluate("HW_RUST_DATA[2]"),
    session.expression.evaluate("HW_RUST_DATA[3]")])
session.breakpoint.remove(probe)
var bp = session.breakpoint.add(done)
session.target.run()
session.breakpoint.remove(bp)
session.target.halt()

var pc = session.expression.evaluate("PC")
var r0 = session.expression.evaluate("HW_RUST_RESULT[0]")
var r1 = session.expression.evaluate("HW_RUST_RESULT[1]")
var r2 = session.expression.evaluate("HW_RUST_RESULT[2]")
var directSum = session.expression.evaluate("HW_RUST_RESULT[3]")
var sum = session.expression.evaluate("HW_RUST_RESULT[4]")
var marker = session.expression.evaluate("HW_RUST_RESULT[5]")
System.out.println("PC=" + pc + " DONE=" + done)
System.out.println("RUST_CONTROL_RESULTS=" + [r0, r1, r2, directSum, sum, marker])
if (pc != done || r0 != 23 || r1 != 40 || r2 != 19 ||
    directSum != 20 || sum != 82 || marker != 0xB2) {
    throw new Error("Rust enum/slice/function-call RAM test mismatch")
}
System.out.println("PASS: real Rust enum, slice and function calls on F28035")
session.terminate()
server.stop()
