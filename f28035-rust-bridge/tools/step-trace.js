importPackage(Packages.com.ti.debug.engine.scripting);
importPackage(Packages.com.ti.ccstudio.scripting.environment);
importPackage(Packages.java.lang);

// 从断点处逐条单步，每步打印 PC 与关键寄存器，用于定位"值在哪一条指令被改坏"。
// usage: step-trace.js <ccxml> <firmware.out> <startAddr> <steps>
if (arguments.length < 4) {
    System.err.println("usage: step-trace.js <ccxml> <firmware.out> <startAddr> <steps>");
    System.exit(2);
}
var startAddr = Number(arguments[2]);
var steps = Number(arguments[3]);
var environment = ScriptingEnvironment.instance();
environment.setScriptTimeout(120000);
var server = environment.getServer("DebugServer.1");
var session = null;

function reg(name) {
    try { return Number(session.memory.readRegister(name)) >>> 0; } catch (e) { return -1; }
}
function hex(v) { return "0x" + (v >>> 0).toString(16); }
function pc() { return reg("PC"); }

try {
    server.setConfig(String(arguments[0]));
    session = server.openSession(".*C28xx.*");
    session.target.connect();
    session.target.halt();
    session.memory.loadProgram(String(arguments[1]));
    for (var i = 0; i < 32; i++) {
        session.memory.writeData(Memory.Page.DATA, 0x9E00 + i, 0, 16);
    }
    session.breakpoint.add(startAddr);
    session.memory.writeRegister("PC", session.symbol.getAddress("code_start"));
    session.target.runAsynch();
    Thread.sleep(300);
    session.target.halt();

    var out = "";
    for (var i = 0; i <= steps; i++) {
        out += "  PC=" + hex(pc()) +
               " ACC=" + hex(reg("ACC")) + " XT=" + hex(reg("XT")) +
               " XAR0=" + hex(reg("XAR0")) + " XAR2=" + hex(reg("XAR2")) +
               " XAR4=" + hex(reg("XAR4")) + " XAR5=" + hex(reg("XAR5")) +
               " XAR6=" + hex(reg("XAR6")) + " XAR7=" + hex(reg("XAR7")) +
               " SP=" + hex(reg("SP")) + "\n";
        if (i < steps) { session.target.stepInto(); }
    }
    System.out.println(out);
} catch (err) {
    System.err.println("STEP=ERROR: " + err);
    System.exit(1);
} finally {
    if (session !== null) { session.terminate(); }
    server.stop();
}
