importPackage(Packages.com.ti.debug.engine.scripting);
importPackage(Packages.com.ti.ccstudio.scripting.environment);
importPackage(Packages.java.lang);

// 通用邮箱转储：加载 -> 运行 -> 停机 -> 打印 0x9E00 起 N 个字。
if (arguments.length < 2) {
    System.err.println("usage: dump-mailbox.js <target.ccxml> <firmware.out> [words]");
    System.exit(2);
}
var count = (arguments.length > 2) ? Number(arguments[2]) : 8;
var environment = ScriptingEnvironment.instance();
environment.setScriptTimeout(60000);
var server = environment.getServer("DebugServer.1");
var session = null;

function readWord(address) {
    return Number(session.memory.readData(Memory.Page.DATA, address, 16, false)) & 0xffff;
}

try {
    server.setConfig(String(arguments[0]));
    session = server.openSession(".*C28xx.*");
    session.target.connect();
    session.target.halt();
    session.memory.loadProgram(String(arguments[1]));
    for (var i = 0; i < 32; i++) {
        session.memory.writeData(Memory.Page.DATA, 0x9E00 + i, 0, 16);
    }
    session.memory.writeRegister("PC", session.symbol.getAddress("code_start"));
    session.target.runAsynch();
    Thread.sleep(300);
    session.target.halt();
    var out = "";
    for (var i = 0; i < count; i++) {
        out += "  [" + i + "] 0x" + (readWord(0x9E00 + i) >>> 0).toString(16) + "\n";
    }
    System.out.println(out);
    System.out.println("PC=0x" + (Number(session.memory.readRegister("PC")) >>> 0).toString(16));
} catch (err) {
    System.err.println("DUMP=ERROR: " + err);
    System.exit(1);
} finally {
    if (session !== null) { session.terminate(); }
    server.stop();
}
