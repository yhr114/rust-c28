importPackage(Packages.com.ti.debug.engine.scripting);
importPackage(Packages.com.ti.ccstudio.scripting.environment);
importPackage(Packages.java.lang);

// b1-u32-compose probe: load, run, halt, dump mailbox 0x9E00.
// Expected cells (see crates/b1-u32-compose/src/lib.rs):
//   [0]=0x5678 [1]=0x1234 [2]=0x5678 [3]=0x1234 [4]=1 [5]=0
//   [6]=0x1234 [7]=0x1234 [8]=1 [9]=0 [10]=0xC0DE
var expected = [0x5678,0x1234,0x5678,0x1234,1,0,0x1234,0x1234,1,0,0xC0DE,1,0,0,0,1,0,0,1,0,0,0x5679,0x1234,0xA989,0xEDCB];

if (arguments.length < 2) {
    System.err.println("usage: verify-b1-u32-compose-ram.js <target.ccxml> <firmware.out>");
    System.exit(2);
}
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

    var allPass = true;
    var report = "";
    for (var i = 0; i < expected.length; i++) {
        var got = readWord(0x9E00 + i);
        var ok = (got === expected[i]);
        if (!ok) { allPass = false; }
        report += "  [" + i + "] got=0x" + (got >>> 0).toString(16) +
                  " want=0x" + (expected[i] >>> 0).toString(16) + (ok ? " OK" : " ** MISMATCH") + "\n";
    }
    System.out.println(report);
    System.out.println(allPass ? "U32_COMPOSE=PASS" : "U32_COMPOSE=FAIL");
    if (!allPass) { System.exit(1); }
} catch (err) {
    System.err.println("U32_COMPOSE=ERROR: " + err);
    System.exit(1);
} finally {
    if (session !== null) { session.terminate(); }
    server.stop();
}
