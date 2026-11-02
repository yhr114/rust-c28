// Read the MOV/byte addressing semantics probe results.
// Driver stores: [0]=m16 round-trip, [1]=movb round-trip,
// [2]=byte-store+16bit-load, [3]=16bit-store+byte-load, [4]=marker
importPackage(Packages.com.ti.debug.engine.scripting)
importPackage(Packages.com.ti.ccstudio.scripting.environment)
importPackage(Packages.java.lang)

var script = ScriptingEnvironment.instance()
script.setScriptTimeout(120000)
var server = script.getServer("DebugServer.1")
server.setConfig(arguments[1])
var session = server.openSession("*", "*")
session.target.connect()
session.target.reset()
session.memory.loadProgram(arguments[0])

var done = session.symbol.getAddress("hw_done")
var entry = session.symbol.getAddress("main")
var result = session.symbol.getAddress("HW_PROBE_RESULT")
System.out.println("hw_done=0x" + done.toString(16) + " main=0x" + entry.toString(16) + " result=0x" + result.toString(16))
var bp = session.breakpoint.add(done)
session.expression.evaluate("PC = code_start")
session.target.run()
session.target.halt()
session.breakpoint.remove(bp)
var vals = []
for (var i = 0; i < 5; i++) {
    vals.push(session.expression.evaluate("*(unsigned*)0x" + (result + i).toString(16)))
}
System.out.println("SEM_RESULTS=" + vals.join(","))
// expected if all four forms address the same location: 0x77,0x77,0x77,0x77
System.out.println("interp: m16_rt=" + vals[0].toString(16) + " mb_rt=" + vals[1].toString(16) +
    " mbSt_m16Ld=" + vals[2].toString(16) + " m16St_mbLd=" + vals[3].toString(16))
// where did the 16-bit store land?  probe wrote AX=0x5A77 via MOV *+XAR7[0]
System.out.println("word@0x500=" + session.expression.evaluate("*(unsigned*)0x500").toString(16) +
    " word@0x501=" + session.expression.evaluate("*(unsigned*)0x501").toString(16) +
    " word@0x280=" + session.expression.evaluate("*(unsigned*)0x280").toString(16) +
    " word@0x281=" + session.expression.evaluate("*(unsigned*)0x281").toString(16))
session.target.disconnect()
