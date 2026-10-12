importPackage(Packages.com.ti.debug.engine.scripting);
importPackage(Packages.com.ti.ccstudio.scripting.environment);
importPackage(Packages.java.lang);
importPackage(Packages.java.io);

if (arguments.length < 2) {
    System.err.println("usage: verify-case.js <target.ccxml> <firmware.out>");
    System.exit(2);
}

var targetConfig = new File(String(arguments[0])).getCanonicalPath();
var firmware = new File(String(arguments[1])).getCanonicalPath();
var environment = ScriptingEnvironment.instance();
environment.setScriptTimeout(30000);
var server = environment.getServer("DebugServer.1");
var session = null;

function readU16(address) {
    return Number(session.memory.readData(Memory.Page.DATA, address, 16, false));
}

try {
    server.setConfig(targetConfig);
    session = server.openSession(".*C28xx.*");
    session.options.setBoolean("AutoRunToLabelOnRestart", false);
    session.options.setBoolean("AutoRunToLabelOnReset", false);
    session.target.connect();
    session.memory.loadProgram(firmware);
    session.target.restart();
    session.memory.writeRegister("PC", session.symbol.getAddress("code_start"));
    session.target.runAsynch();

    var status = 0;
    var deadline = java.lang.System.currentTimeMillis() + 5000;
    while (status === 0 && java.lang.System.currentTimeMillis() < deadline) {
        Thread.sleep(20);
        status = Number(session.expression.evaluate("f28035_test_status"));
    }
    session.target.halt();
    var failCode = Number(session.expression.evaluate("f28035_test_fail_code"));
    System.out.println("TEST_STATUS=" + status);
    System.out.println("TEST_FAIL_CODE=" + failCode);
    if (status === 2) {
        System.out.println("EPWM1_TBCTL=" + readU16(0x6800));
        System.out.println("EPWM1_TBPRD=" + readU16(0x6805));
        System.out.println("EPWM1_CMPA=" + readU16(0x6809));
        System.out.println("EPWM1_AQCTLA=" + readU16(0x680b));
        System.out.println("EPWM1_TZSEL=" + readU16(0x6812));
        System.out.println("EPWM1_TZCTL=" + readU16(0x6814));
        System.out.println("EPWM1_TZEINT=" + readU16(0x6815));
        System.out.println("EPWM1_TZFLG=" + readU16(0x6816));
    }

    if (status === 1 && failCode === 0) {
        System.out.println("F28035_RUST_CASE=PASS");
    } else if (status === 2) {
        System.err.println("F28035_RUST_CASE=FAIL");
    } else {
        System.err.println("F28035_RUST_CASE=TIMEOUT");
    }
} catch (error) {
    System.err.println("F28035_RUST_CASE=ERROR");
    System.err.println(String(error));
} finally {
    if (session !== null) {
        try { session.target.disconnect(); } catch (ignoredDisconnect) {}
        try { session.terminate(); } catch (ignoredTerminate) {}
    }
    try { server.stop(); } catch (ignoredStop) {}
}
