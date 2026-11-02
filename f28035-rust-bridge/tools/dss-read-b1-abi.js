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

// Entry probes: capture the argument registers at each Rust entry point so
// the runtime observation matches the cl2000 oracle (2026-10-20).  The sret
// path is exercised inside rust_sret_self_check (Rust->Rust); the entry
// probes below cover the cross-language ABI cases.
var ptrEntry = session.symbol.getAddress("rust_read_ptr")
var mixedEntry = session.symbol.getAddress("rust_mixed")
var applyEntry = session.symbol.getAddress("rust_apply")
var done = session.symbol.getAddress("hw_done")

session.expression.evaluate("PC = code_start")

// The first breakpoint must exist BEFORE the first run, otherwise the CPU
// runs away to the script timeout and every later PC reading is bogus.
var probe = session.breakpoint.add(ptrEntry)
session.target.run()
System.out.println("PTR_ENTRY PC=" + session.expression.evaluate("PC") +
                   " ACC=" + session.expression.evaluate("ACC") +
                   " AR4=" + session.expression.evaluate("AR4") +
                   " AR5=" + session.expression.evaluate("AR5"))
session.breakpoint.remove(probe)

probe = session.breakpoint.add(mixedEntry)
session.target.run()
System.out.println("MIXED_ENTRY PC=" + session.expression.evaluate("PC") +
                   " ACC=" + session.expression.evaluate("ACC") +
                   " AR4=" + session.expression.evaluate("AR4") +
                   " AR5=" + session.expression.evaluate("AR5"))
session.breakpoint.remove(probe)

probe = session.breakpoint.add(applyEntry)
session.target.run()
System.out.println("APPLY_ENTRY PC=" + session.expression.evaluate("PC") +
                   " ACC=" + session.expression.evaluate("ACC") +
                   " AR4=" + session.expression.evaluate("AR4"))
session.breakpoint.remove(probe)

var bp = session.breakpoint.add(done)
session.target.run()
session.breakpoint.remove(bp)
session.target.halt()

var pc = session.expression.evaluate("PC")
var r = []
for (var i = 0; i < 10; i++) {
    r.push(session.expression.evaluate("HW_RUST_RESULT[" + i + "]"))
}
System.out.println("PC=" + pc + " DONE=" + done)
System.out.println("ABI_RESULTS=" + r)
// Result layout (HW_RUST_RESULT):
//   [0] sret self-check ptr*3+len       = 0x5555
//   [1] pointer argument deref          = 0x1234
//   [2] weighted mixed a+*p*4+b*16      = 61
//   [3] indirect call ti_double(21)     = 42
//   [4] stack args 1+2+3+4+5+6          = 21
//   [5] cross-BB odd branch (a+e+f)+21  = 33
//   [6] cross-BB even branch (b+c+f)+21 = 32
//   [7] nested calls 21*3+21+6          = 90
//   [8] marker                          = 0xAB
//   [9] C->Rust 32-bit stack arg echo    = 0x12345678
if (pc != done || r[0] != 0x5555 || r[1] != 0x1234 ||
    r[2] != 61 || r[3] != 42 || r[4] != 21 ||
    r[5] != 33 || r[6] != 32 || r[7] != 90 || r[8] != 0xAB ||
    r[9] != 0x12345678) {
    throw new Error("ABI RAM/JTAG mismatch: " + r)
}
System.out.println("PASS: pointer pool XAR4, sret XAR6 (Rust->Rust), mixed AR5/XAR4/ACC, LCR *XARn, cross-BB stack access and nested calls on F28035")
session.terminate()
server.stop()
