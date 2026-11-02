importPackage(Packages.com.ti.debug.engine.scripting)
importPackage(Packages.com.ti.ccstudio.scripting.environment)
importPackage(Packages.java.lang)

// Stop at the driver's first result store and read what ABI value is about to
// be written, plus SP at that moment.
var script = ScriptingEnvironment.instance()
script.setScriptTimeout(60000)
var server = script.getServer("DebugServer.1")
server.setConfig(arguments[1])
var session = server.openSession("*", "*")
session.target.connect()
session.target.reset()
session.memory.loadProgram(arguments[0])

var main = session.symbol.getAddress("main")
var done = session.symbol.getAddress("hw_done")
session.expression.evaluate("PC = code_start")

// main+0x1d = "MOV @0x0, AL" (first HW_RUST_RESULT[0] store).
var bp = session.breakpoint.add(main + 0x1d)
session.target.run()
session.breakpoint.remove(bp)
session.target.halt()
System.out.println("AT-STORE1 PC=" + session.expression.evaluate("PC") +
                   " AL=" + session.expression.evaluate("AL") +
                   " ACC=" + session.expression.evaluate("ACC") +
                   " SP=" + session.expression.evaluate("SP") +
                   " RES0=" + session.expression.evaluate("HW_RUST_RESULT[0]"))

var bp2 = session.breakpoint.add(main + 0x25)
session.target.run()
session.breakpoint.remove(bp2)
session.target.halt()
System.out.println("AT-STORE2 AL=" + session.expression.evaluate("AL") +
                   " SP=" + session.expression.evaluate("SP") +
                   " RES0=" + session.expression.evaluate("HW_RUST_RESULT[0]"))

var bp3 = session.breakpoint.add(main + 0x2d)
session.target.run()
session.breakpoint.remove(bp3)
session.target.halt()
System.out.println("AT-STORE3 AL=" + session.expression.evaluate("AL") +
                   " SP=" + session.expression.evaluate("SP"))

var bp4 = session.breakpoint.add(main + 0x34)
session.target.run()
session.breakpoint.remove(bp4)
session.target.halt()
System.out.println("AT-STORE4 AL=" + session.expression.evaluate("AL") +
                   " SP=" + session.expression.evaluate("SP"))

var bp5 = session.breakpoint.add(done)
session.target.run()
session.breakpoint.remove(bp5)
session.target.halt()
var res = []
for (var i = 0; i < 6; i++) res.push(session.expression.evaluate("HW_RUST_RESULT[" + i + "]"))
System.out.println("AT-DONE RESULTS=" + res + " PC=" + session.expression.evaluate("PC") +
                   " SP=" + session.expression.evaluate("SP") + " DONE=" + done)
session.terminate()
server.stop()
