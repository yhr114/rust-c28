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
var bp = session.breakpoint.add(done)
session.expression.evaluate("PC = code_start")
session.target.run()
session.breakpoint.remove(bp)
session.target.halt()

// The two statics are the regression target: a null/zero entry means the
// static address relocation was dropped at compile time.
var table = session.symbol.getAddress("TABLE")
var dataPtr = session.symbol.getAddress("DATA_PTR")
System.out.println("TABLE@0x" + table.toString(16) + " DATA_PTR@0x" + dataPtr.toString(16))
System.out.println("TABLE[0]=" + session.expression.evaluate("*(unsigned long*)TABLE") +
                   " TABLE[1]=" + session.expression.evaluate("*((unsigned long*)TABLE+1)") +
                   " DATA_PTR=" + session.expression.evaluate("*(unsigned long*)DATA_PTR"))

var expected = [16, 13, 11, 12, 21, 40, 11, 0x5C]
var names = ["use_table(5)", "use_ref(4)", "use_data_ptr()", "C TABLE[0](3)+TABLE[1](4)",
             "fn_a(20)", "fn_b(20)", "C *DATA_PTR", "marker"]
var r = []
for (var i = 0; i < expected.length; i++) {
    r.push(session.expression.evaluate("HW_STATIC_RESULT[" + i + "]"))
}
System.out.println("STATIC_RESULTS=" + r)
for (var i = 0; i < expected.length; i++) {
    if (r[i] != expected[i]) {
        System.out.println("MISMATCH " + names[i] + ": got " + r[i] + " want " + expected[i])
        throw new Error("static-address sample mismatch")
    }
}
var pc = session.expression.evaluate("PC")
if (pc != done) {
    throw new Error("execution did not stop at hw_done")
}
System.out.println("PASS: static function-pointer table, &TABLE reference and addended DATA_PTR on F28035")
session.terminate()
server.stop()
