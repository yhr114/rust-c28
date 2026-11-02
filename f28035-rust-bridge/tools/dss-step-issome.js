// Step-by-step trace of core's Option::<u16>::is_some on the failing input.
// Breaks after each interesting instruction and dumps AL/AH/ACC/XAR0.
importPackage(Packages.com.ti.debug.engine.scripting)
importPackage(Packages.com.ti.ccstudio.scripting.environment)
importPackage(Packages.java.lang)

var script = ScriptingEnvironment.instance()
script.setScriptTimeout(180000)
var server = script.getServer("DebugServer.1")
server.setConfig(arguments[1])
var session = server.openSession("*", "*")
session.target.connect()
session.target.reset()
session.memory.loadProgram(arguments[0])

function at(label, addr) {
    var bp = session.breakpoint.add(addr)
    session.target.run()
    session.target.halt()
    session.breakpoint.remove(bp)
    var al = session.expression.evaluate("AL")
    var ah = session.expression.evaluate("AH")
    var acc = session.expression.evaluate("ACC")
    var x0 = session.expression.evaluate("XAR0")
    var x7 = session.expression.evaluate("XAR7")
    var pc = session.expression.evaluate("PC")
    System.out.println(label + " PC=0x" + pc.toString(16) + " AL=0x" + al.toString(16) +
        " AH=0x" + ah.toString(16) + " ACC=0x" + acc.toString(16) +
        " XAR0=0x" + x0.toString(16) + " XAR7=0x" + x7.toString(16))
}

var fn = session.symbol.getAddress("probe_is_some_temp")
System.out.println("probe_is_some_temp=0x" + fn.toString(16))

// run to the is_some call first
var bpCall = session.breakpoint.add(fn + 0x23)
session.expression.evaluate("PC = code_start")
session.target.run()
session.target.halt()
session.breakpoint.remove(bpCall)
System.out.println("reached call")

// is_some body (linked at 0x802e):
//   0x8033 MOV AL,*+XAR7[0]   <- the tag load
//   0x8034 MOVB AH,#0
//   0x803f AND AL,AR0
//   0x8047 SUBL ACC,XT
//   0x8048 B 31,EQ  (taken -> 0x8067 = false path; not taken -> 0x804c = true path)
//   0x804c MOVB AL,#1
//   0x8067 (false path)
at("after-load ", 0x8034)
at("after-and  ", 0x8040)
at("after-subl ", 0x8049)
at("true-path  ", 0x804d)
at("false-path ", 0x8068)
session.target.disconnect()
