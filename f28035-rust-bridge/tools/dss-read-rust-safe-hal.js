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
var entry = session.symbol.getAddress("rust_safe_gpio34_low")
var entryProbe = session.breakpoint.add(entry)
session.expression.evaluate("PC = code_start")
session.target.run()
System.out.println("HAL_ENTRY_PC=" + session.expression.evaluate("PC"))
session.breakpoint.remove(entryProbe)
var bp = session.breakpoint.add(done)
session.target.run()
session.breakpoint.remove(bp)
session.target.halt()

var pc = session.expression.evaluate("PC")
var muxBefore = session.expression.evaluate("HW_RUST_RESULT[0]")
var muxAfter = session.expression.evaluate("HW_RUST_RESULT[1]")
var dirBefore = session.expression.evaluate("HW_RUST_RESULT[2]")
var dirAfter = session.expression.evaluate("HW_RUST_RESULT[3]")
var datAfter = session.expression.evaluate("HW_RUST_RESULT[4]")
var marker = session.expression.evaluate("HW_RUST_RESULT[5]")
var probeFlags = session.expression.evaluate("HW_RUST_RESULT[6]")
var inputDir = session.expression.evaluate("HW_RUST_RESULT[7]")
var inputQsel = session.expression.evaluate("HW_RUST_RESULT[8]")
var inputPud = session.expression.evaluate("HW_RUST_RESULT[9]")
var inputDat = session.expression.evaluate("HW_RUST_RESULT[10]")
System.out.println("PC=" + pc + " DONE=" + done)
System.out.println("SAFE_HAL_RESULTS=" + [muxBefore, muxAfter, dirBefore, dirAfter, datAfter, marker])
System.out.println("SAFE_HAL_INPUT=" + [probeFlags, inputDir, inputQsel, inputPud, inputDat])
if (pc != done) {
    throw new Error("Safe HAL direct-object program did not reach hw_done")
}
if ((muxAfter & 0x30) != 0) {
    throw new Error("GPBMUX1 bits 5:4 not cleared for GPIO34: " + muxAfter)
}
if ((dirAfter & 0x04) != 0x04) {
    throw new Error("GPBDIR bit 2 not set for GPIO34 output: " + dirAfter)
}
if ((datAfter & 0x04) != 0) {
    throw new Error("GPBDAT bit 2 not low after Safe HAL set_low: " + datAfter)
}
if (marker != 0xB2) {
    throw new Error("done marker mismatch: " + marker)
}
if ((probeFlags & 3) != 1 || ((probeFlags >> 2) & 3) != 0) {
    throw new Error("GPIO0 MUX route/readback failed: " + probeFlags)
}
if ((inputDir & 4) != 0 || ((inputQsel >> 4) & 3) != 2 || (inputPud & 4) != 0) {
    throw new Error("GPIO34 input configuration differs from PAC expectation")
}
if (((probeFlags >> 4) & 1) != ((inputDat >> 2) & 1)) {
    throw new Error("Rust GPIO34 input sample differs from GPBDAT")
}
System.out.println("PASS: Safe HAL GPIO0 MUX and GPIO34 input/output via patched-rustc direct object on F28035")
session.terminate()
server.stop()
