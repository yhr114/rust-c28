importPackage(Packages.com.ti.debug.engine.scripting);
importPackage(Packages.com.ti.ccstudio.scripting.environment);
importPackage(Packages.java.lang);

// 断点处读寄存器：定位"运行期值 vs 32 位字面量"比较中哪个操作数被破坏。
// usage: bp-regs.js <ccxml> <firmware.out> <addr1> [addr2] ...
if (arguments.length < 3) {
    System.err.println("usage: bp-regs.js <ccxml> <firmware.out> <addr...>");
    System.exit(2);
}
var environment = ScriptingEnvironment.instance();
environment.setScriptTimeout(60000);
var server = environment.getServer("DebugServer.1");
var session = null;

function reg(name) {
    try { return Number(session.memory.readRegister(name)) >>> 0; } catch (e) { return -1; }
}
function hex(v) { return "0x" + (v >>> 0).toString(16); }

try {
    server.setConfig(String(arguments[0]));
    session = server.openSession(".*C28xx.*");
    session.target.connect();
    session.target.halt();
    session.memory.loadProgram(String(arguments[1]));
    for (var i = 0; i < 32; i++) {
        session.memory.writeData(Memory.Page.DATA, 0x9E00 + i, 0, 16);
    }
    for (var a = 2; a < arguments.length; a++) {
        session.breakpoint.add(Number(arguments[a]));
    }
    session.memory.writeRegister("PC", session.symbol.getAddress("code_start"));
    session.target.runAsynch();
    Thread.sleep(300);
    session.target.halt();
    var out = "";
    for (var a = 2; a < arguments.length; a++) {
        out += "addr " + hex(Number(arguments[a])) + " PC=" + hex(reg("PC")) +
               " ACC=" + hex(reg("ACC")) + " XT=" + hex(reg("XT")) +
               " XAR0=" + hex(reg("XAR0")) + " XAR2=" + hex(reg("XAR2")) +
               " XAR4=" + hex(reg("XAR4")) + " XAR5=" + hex(reg("XAR5")) +
               " XAR6=" + hex(reg("XAR6")) + " XAR7=" + hex(reg("XAR7")) +
               " AR0=" + hex(reg("AR0")) + " SP=" + hex(reg("SP")) + "\n";
    }
    System.out.println(out);
} catch (err) {
    System.err.println("BP=ERROR: " + err);
    System.exit(1);
} finally {
    if (session !== null) { session.terminate(); }
    server.stop();
}
