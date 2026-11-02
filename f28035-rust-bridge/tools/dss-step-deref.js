// Breakpoint-based ground truth for probe_deref_stack: stop at the store
// (offset 0x18) and the load (offset 0x26), dump registers and the memory
// window around each target address before/after the store executes.
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

var fn = session.symbol.getAddress("probe_deref_stack")
System.out.println("probe_deref_stack=0x" + fn.toString(16))

function regs(label) {
    var sp = session.expression.evaluate("SP")
    var x0 = session.expression.evaluate("XAR0")
    var x7 = session.expression.evaluate("XAR7")
    var al = session.expression.evaluate("AL")
    var pc = session.expression.evaluate("PC")
    System.out.println(label + " PC=0x" + pc.toString(16) + " SP=0x" + sp.toString(16) +
        " XAR0=0x" + x0.toString(16) + " XAR7=0x" + x7.toString(16) + " AL=0x" + al.toString(16))
    return x7
}
function memDump(label, addr) {
    // read 8 words around addr (word address)
    var base = addr - 4
    var vals = session.memory.read(base, 8, 16)
    var s = label + " @word 0x" + base.toString(16) + ":"
    for (var i = 0; i < 8; i++) s += " " + vals[i].toString(16)
    System.out.println(s)
}

var bpEntry = session.breakpoint.add(fn)
session.expression.evaluate("PC = code_start")
session.target.run()
session.target.halt()
session.breakpoint.remove(bpEntry)
regs("ENTRY")

// breakpoint at the store (fn+0x18)
var bpStore = session.breakpoint.add(fn + 0x18)
session.target.run()
session.target.halt()
var x7s = regs("STORE")
memDump("BEFORE-STORE", x7s)
// continue one instruction: use run with a temp bp after the store
var bpAfter = session.breakpoint.add(fn + 0x19)
session.target.run()
session.target.halt()
regs("AFTER-STORE")
memDump("AFTER-STORE", x7s)
session.breakpoint.remove(bpAfter)
session.breakpoint.remove(bpStore)

// breakpoint at the load (fn+0x26)
var bpLoad = session.breakpoint.add(fn + 0x26)
session.target.run()
session.target.halt()
var x7l = regs("LOAD")
memDump("AT-LOAD", x7l)
// finish the load
var bpAfterL = session.breakpoint.add(fn + 0x27)
session.target.run()
session.target.halt()
regs("AFTER-LOAD")
session.breakpoint.remove(bpAfterL)
session.breakpoint.remove(bpLoad)

session.terminate()
server.stop()
