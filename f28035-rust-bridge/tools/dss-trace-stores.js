// What does the FIRST rust_control call actually return?  Stop at the
// driver's first result store (main+0x1d) and read AL, then continue to the
// second store and read AL again  -- isolates "callee returned garbage" from
// "later corruption".
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

var mainFn = session.symbol.getAddress("main")
var stores = [0x1d, 0x25, 0x2d, 0x35]   // MOV @0xN, AL after each call
System.out.println("main=0x" + mainFn.toString(16))

session.expression.evaluate("PC = code_start")
for (var i = 0; i < stores.length; i++) {
    var addr = mainFn + stores[i]
    var bp = session.breakpoint.add(addr)
    try { session.target.run(); session.target.halt(); } catch (e) { }
    var pc = session.expression.evaluate("PC")
    var al = session.expression.evaluate("AL")
    var acc = session.expression.evaluate("ACC")
    var sp = session.expression.evaluate("SP")
    System.out.println("STORE" + i + " PC=0x" + pc.toString(16) + " AL=" + al + " ACC=0x" +
        acc.toString(16) + " SP=0x" + sp.toString(16))
    session.breakpoint.remove(bp)
    if (pc !== addr) { System.out.println("  (did not reach store " + i + ")"); break }
}
for (var k = 0; k < 5; k++) {
    System.out.println("RESULT[" + k + "]=" + session.expression.evaluate("HW_RUST_RESULT[" + k + "]"))
}
session.terminate()
server.stop()
