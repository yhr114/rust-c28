// Ground truth for probe_is_some_temp's is_some call.
// Stop at the LCR (fn+0x23), dump the pointer argument, SP, and the memory
// is_some is about to read, then step into is_some and dump its load address.
// CCS expressions for C28x use WORD addresses (verified with dss-mem-read.js).
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

function regs(label) {
    var sp = session.expression.evaluate("SP")
    var x4 = session.expression.evaluate("XAR4")
    var x0 = session.expression.evaluate("XAR0")
    var x7 = session.expression.evaluate("XAR7")
    var al = session.expression.evaluate("AL")
    var ah = session.expression.evaluate("AH")
    var pc = session.expression.evaluate("PC")
    System.out.println(label + " PC=0x" + pc.toString(16) + " SP=0x" + sp.toString(16) +
        " XAR4=0x" + x4.toString(16) + " XAR0=0x" + x0.toString(16) +
        " XAR7=0x" + x7.toString(16) + " AL=0x" + al.toString(16) + " AH=0x" + ah.toString(16))
    return { sp: sp, x4: x4, x0: x0, x7: x7 }
}
function wordAt(addr) {
    return session.expression.evaluate("*(unsigned short*)0x" + addr.toString(16))
}
function wordDump(label, from, n) {
    var s = label + ":"
    for (var i = 0; i < n; i++) {
        var v = wordAt(from + i)
        s += " [0x" + (from + i).toString(16) + "]=" + v.toString(16)
    }
    System.out.println(s)
}

var fn = session.symbol.getAddress("probe_is_some_temp")
var bp = session.breakpoint.add(fn + 0x23)
session.expression.evaluate("PC = code_start")
session.target.run()
session.target.halt()
session.breakpoint.remove(bp)
var r = regs("AT-CALL")

// is_some computes XAR7 = XAR4 >> 1 and loads the word there.
var loadWord = Math.floor(r.x4 / 2)
System.out.println("is_some will load word 0x" + loadWord.toString(16) + " (XAR4/2)")
wordDump("frame-words", r.sp - 6, 10)
wordDump("load-window", loadWord - 1, 4)

// step into is_some: its load is at 0x8033 (MOV AL,*+XAR7[0])
var bpLoad = session.breakpoint.add(0x8033)
session.target.run()
session.target.halt()
session.breakpoint.remove(bpLoad)
var r2 = regs("IN-IS_SOME")
wordDump("is_some-XAR7-window", r2.x7 - 1, 4)

// after the call returns: PC = fn+0x25 (LCR is two words)
var bpRet = session.breakpoint.add(fn + 0x25)
session.target.run()
session.target.halt()
session.breakpoint.remove(bpRet)
regs("AFTER-CALL")
session.target.disconnect()
