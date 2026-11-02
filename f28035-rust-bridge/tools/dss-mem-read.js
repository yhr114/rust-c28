// Read raw hardware memory to settle the C28x data-addressing semantics:
// is `*+XAR7[k]` a byte offset from a word-addressed base, or does the AR
// hold a byte address?  Dump the candidate locations for both readings.
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

function rd(expr) {
    try {
        var v = session.expression.evaluate(expr)
        System.out.println(expr + " = 0x" + v.toString(16))
    } catch (e) {
        System.out.println(expr + " : ERROR " + e)
    }
}

// The Some(1u16) constant: word 0x8122 should read 0x0001 (bytes 01 00 01 00)
rd("*(unsigned short*)0x8122")
rd("*(unsigned short*)0x8120")
// T = [1,0,1,0] at word 0x802a (probe image .rodata)
rd("*(unsigned short*)0x802a")
rd("*(unsigned short*)0x802b")
// The "byte address" interpretations:
//   is_some deref *+XAR7[0] with XAR7=0x8122 as a BYTE addr -> word 0x4091
rd("*(unsigned short*)0x4091")
//   rodata probe *+XAR7[2] with XAR7=0x802a as a BYTE addr -> word 0x4016
rd("*(unsigned short*)0x4016")
// stack area around SP (0x200)
rd("*(unsigned short*)0x100")
rd("*(unsigned short*)0x102")
rd("*(unsigned short*)0x205")

session.terminate()
server.stop()
