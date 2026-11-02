importPackage(Packages.com.ti.debug.engine.scripting);
importPackage(Packages.com.ti.ccstudio.scripting.environment);
importPackage(Packages.java.lang);

// bare-pac-hwtest RAM verification (also used by pac-hwtest-b1):
// load -> run -> halt -> read mailbox 0x9E00.., exact-compare.
// Cells: [0]0xC001 [1]0x0004 [2]0x0000 [3]0x8000 [4]0x0000
//        [5]0x005A [6]0x003C [7]0xC003; [8..11] diagnostics.
// Any failing step stops the sequence (remaining cells stay 0).
if (arguments.length < 2) {
    System.err.println("usage: verify-bare-pac-hwtest-ram.js <target.ccxml> <firmware.out>");
    System.exit(2);
}

var environment = ScriptingEnvironment.instance();
environment.setScriptTimeout(60000);
var server = environment.getServer("DebugServer.1");
var session = null;

var expected = [0xC001, 0x0004, 0x0000, 0x8000, 0x0000, 0x005A, 0x003C, 0xC003];
var mailbox = 0x9E00;

function readWord(address) {
    return Number(session.memory.readData(Memory.Page.DATA, address, 16, false)) & 0xffff;
}

try {
    server.setConfig(String(arguments[0]));
    session = server.openSession(".*C28xx.*");
    session.target.connect();
    session.target.halt();
    session.memory.loadProgram(String(arguments[1]));

// (comment)
    for (var i = 0; i < 16; i++) {
        session.memory.writeData(Memory.Page.DATA, mailbox + i, 0, 16);
    }

    session.memory.writeRegister("PC", session.symbol.getAddress("code_start"));
    session.target.runAsynch();
    Thread.sleep(500);
    session.target.halt();

    var allPass = true;
    var report = "";
    for (var i = 0; i < expected.length; i++) {
        var got = readWord(mailbox + i);
        var ok = (got === expected[i]);
        if (!ok) { allPass = false; }
        report += "  [" + i + "] got=0x" + (got >>> 0).toString(16) +
                  " want=0x" + (expected[i] >>> 0).toString(16) + (ok ? " OK" : " ** FAIL") + "\n";
    }
    System.out.println(report);

    // diagnostics cells [8..12] are report-only (SPISTS/FFRX/FFTX/CCR)
    var diag = "";
    for (var i = 8; i < 12; i++) {
        diag += "  diag[" + i + "] = 0x" + (readWord(mailbox + i) >>> 0).toString(16) + "\n";
    }
    System.out.println(diag);

    if (!allPass) {
        throw "Mailbox sequence mismatch (see report above)";
    }
    System.out.println("PAC_HWTEST=PASS");
} catch (err) {
    System.err.println("PAC_HWTEST=FAIL: " + err);
    System.exit(1);
} finally {
    if (session !== null) {
        session.terminate();
    }
    server.stop();
}
