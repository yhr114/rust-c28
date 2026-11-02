// Which rust_mode body actually executes for the first call (tag=0)?
// Sets breakpoints on all three bodies, then reports the first hit and the
// return-value register at the shared tail.
importPackage(Packages.com.ti.debug.engine.scripting)
importPackage(Packages.com.ti.ccstudio.scripting.environment)
importPackage(Packages.java.lang)

var script = ScriptingEnvironment.instance()
script.setScriptTimeout(90000)
var server = script.getServer("DebugServer.1")
server.setConfig(arguments[1])
var session = server.openSession("*", "*")
session.target.connect()
session.target.reset()
session.memory.loadProgram(arguments[0])

var fMode = session.symbol.getAddress("rust_mode")
var fCtl = session.symbol.getAddress("rust_control")
var fSum = session.symbol.getAddress("rust_sum_slice")

function val(e) { try { return session.expression.evaluate(e) } catch (x) { return -1 } }

// Stop at rust_control entry, then step through the call chain by setting
// breakpoints on the three body entry points of rust_mode.
var bp = session.breakpoint.add(fCtl)
session.expression.evaluate("PC = code_start")
session.target.run(); session.target.halt()
session.breakpoint.remove(bp)
System.out.println("CTL ACC=0x" + val("ACC").toString(16) + " XAR4=0x" + val("XAR4").toString(16) + " SP=0x" + val("SP").toString(16))

var hits = []
for (var i = 0; i < 4; i++) {
    var bpAdd = session.breakpoint.add(fMode + 0x1b)   // Add body: AL=3
    var bpDbl = session.breakpoint.add(fMode + 0x0e)   // Double body
    var bpSub = session.breakpoint.add(fMode + 0x1e)   // Subtract body
    var bpTail = session.breakpoint.add(fMode + 0x21)  // shared tail: AL=@AH
    try { session.target.run(); session.target.halt(); } catch (e) { }
    var pc = val("PC")
    var which = "?"
    if (pc === fMode + 0x1b) which = "ADD"
    else if (pc === fMode + 0x0e) which = "DOUBLE"
    else if (pc === fMode + 0x1e) which = "SUB"
    else if (pc === fMode + 0x21) which = "TAIL"
    hits.push(which)
    System.out.println("MODE-STEP " + i + " hit=" + which + " PC=0x" + pc.toString(16) +
        " ACC=0x" + val("ACC").toString(16) + " AL=0x" + val("AL").toString(16) +
        " AH=0x" + val("AH").toString(16) + " AR5=0x" + val("AR5").toString(16))
    session.breakpoint.remove(bpAdd); session.breakpoint.remove(bpDbl)
    session.breakpoint.remove(bpSub); session.breakpoint.remove(bpTail)
    if (which === "TAIL") break
}
System.out.println("HITS=" + hits.join(","))
var r0 = session.expression.evaluate("HW_RUST_RESULT[0]")
System.out.println("RESULT0=" + r0)
session.terminate()
server.stop()
