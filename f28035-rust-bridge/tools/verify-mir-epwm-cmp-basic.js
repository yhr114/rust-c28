importPackage(Packages.com.ti.debug.engine.scripting);
importPackage(Packages.com.ti.ccstudio.scripting.environment);
importPackage(Packages.java.lang);
importPackage(Packages.java.io);

if (arguments.length < 2) {
    System.err.println("usage: verify-mir-epwm-cmp-basic.js <target.ccxml> <firmware.out>");
    System.exit(2);
}

var targetConfig = new File(String(arguments[0])).getCanonicalPath();
var firmware = new File(String(arguments[1])).getCanonicalPath();
var environment = ScriptingEnvironment.instance();
environment.setScriptTimeout(30000);
var server = environment.getServer("DebugServer.1");
var session = null;

function readU16(session, address) {
    return Number(session.memory.readData(Memory.Page.DATA, address, 16, false));
}

function readU32(session, address) {
    return Number(session.memory.readData(Memory.Page.DATA, address, 32, false));
}

try {
    server.setConfig(targetConfig);
    session = server.openSession(".*C28xx.*");
    session.options.setBoolean("AutoRunToLabelOnRestart", false);
    session.options.setBoolean("AutoRunToLabelOnReset", false);
    session.target.connect();
    session.memory.loadProgram(firmware);
    session.target.restart();
    session.expression.evaluate("rust_epwm_cmp_basic_called = 0");
    session.expression.evaluate("f28035_peripherals_taken = 0xffff");
    session.memory.writeRegister("PC", session.symbol.getAddress("code_start"));
    session.target.runAsynch();

    var called = 0;
    var deadline = java.lang.System.currentTimeMillis() + 5000;
    while (called === 0 && java.lang.System.currentTimeMillis() < deadline) {
        Thread.sleep(20);
        called = Number(session.expression.evaluate("rust_epwm_cmp_basic_called"));
    }
    session.target.halt();

    var mux = Number(session.expression.evaluate("rust_epwm_cmp_basic_gpio0_mux"));
    var tbprd = Number(session.expression.evaluate("rust_epwm_cmp_basic_tbprd"));
    var cmpa = Number(session.expression.evaluate("rust_epwm_cmp_basic_cmpa"));
    var directMux = readU32(session, 0x6f86) & 0x3;
    var directTbprd = readU16(session, 0x6805);
    var directCmpa = readU16(session, 0x6809);
    var peripheralsTaken = Number(session.expression.evaluate("f28035_peripherals_taken"));

    System.out.println("rust_epwm_cmp_basic_called=" + called);
    System.out.println("EPWM1_GPIO0_MUX=" + mux);
    System.out.println("EPWM1_TBPRD=" + tbprd);
    System.out.println("EPWM1_CMPA=" + cmpa);
    System.out.println("EPWM1_GPIO0_MUX_DIRECT=" + directMux);
    System.out.println("EPWM1_TBPRD_DIRECT=" + directTbprd);
    System.out.println("EPWM1_CMPA_DIRECT=" + directCmpa);
    System.out.println("PERIPHERALS_TAKEN=" + peripheralsTaken);

    if (called === 1 && peripheralsTaken === 1 &&
        mux === 1 && directMux === 1 &&
        tbprd === 4095 && directTbprd === 4095 &&
        cmpa === 2048 && directCmpa === 2048) {
        System.out.println("EPWM_CMP_BASIC_TARGET_TEST=PASS");
    } else {
        System.err.println("EPWM_CMP_BASIC_TARGET_TEST=FAIL");
    }
} catch (error) {
    System.err.println("EPWM_CMP_BASIC_TARGET_TEST=ERROR");
    System.err.println(String(error));
} finally {
    if (session !== null) {
        try { session.target.disconnect(); } catch (ignoredDisconnect) {}
        try { session.terminate(); } catch (ignoredTerminate) {}
    }
    try { server.stop(); } catch (ignoredStop) {}
}
