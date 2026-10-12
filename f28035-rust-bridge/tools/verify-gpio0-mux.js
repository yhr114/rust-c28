importPackage(Packages.com.ti.debug.engine.scripting);
importPackage(Packages.com.ti.ccstudio.scripting.environment);
importPackage(Packages.java.lang);
importPackage(Packages.java.io);

if (arguments.length < 2) {
    System.err.println("usage: verify-gpio0-mux.js <target.ccxml> <firmware.out>");
    System.exit(2);
}

var targetConfig = new File(String(arguments[0])).getCanonicalPath();
var firmware = new File(String(arguments[1])).getCanonicalPath();
var traceFile = firmware + ".dss-trace.xml";
var environment = ScriptingEnvironment.instance();
environment.setScriptTimeout(30000);
environment.traceBegin(traceFile, "DefaultStylesheet.xsl");
environment.traceSetFileLevel(TraceLevel.ALL);
var server = environment.getServer("DebugServer.1");
var session = null;

try {
    server.setConfig(targetConfig);
    session = server.openSession(".*C28xx.*");
    session.options.setBoolean("AutoRunToLabelOnRestart", false);
    session.options.setBoolean("AutoRunToLabelOnReset", false);
    try { session.options.setBoolean("FlashVerboseMode", true); } catch (ignoredVerboseOption) {}
    session.target.connect();

    // RAM verification only; this RAM image never touches flash.  The CSM
    // password guard below is the same fail-closed protection used by the
    // other Safe HAL RAM verifiers: refuse to run if the device is protected.
    var passwordAllFf = true;
    for (var passwordAddress = 0x3F7FF8; passwordAddress <= 0x3F7FFF; passwordAddress++) {
        var passwordWord = Number(
            session.memory.readData(Memory.Page.DATA, passwordAddress, 16, false));
        if (passwordWord !== 0xFFFF) {
            passwordAllFf = false;
        }
    }
    var csmStatus = Number(session.memory.readData(Memory.Page.DATA, 0x0AEF, 16, false));
    System.out.println("CSMSCR_BEFORE=0x" + csmStatus.toString(16));
    System.out.println("CSM_PASSWORD_ALL_FF=" + passwordAllFf);
    if (!passwordAllFf || (csmStatus & 1) !== 0) {
        throw "Refusing verification: CSM is protected or password words are not all FFFF";
    }

    session.target.halt();
    session.memory.loadProgram(firmware);
    System.out.println("RAM_LOAD_PROGRAM=PASS");
    session.target.restart();
    session.memory.writeRegister("PC", session.symbol.getAddress("code_start"));
    session.target.runAsynch();

    // Poll until the C harness records that both Rust-authored mirror
    // functions ran and the full 0->1->0 MUX round trip completed.
    var called = 0;
    var deadline = java.lang.System.currentTimeMillis() + 5000;
    while (called === 0 && java.lang.System.currentTimeMillis() < deadline) {
        Thread.sleep(20);
        called = Number(session.expression.evaluate("rust_gpio0_mux_called"));
    }
    session.target.halt();

    var phase1 = Number(session.expression.evaluate("rust_gpio0_mux_phase1_mux"));
    var phase2 = Number(session.expression.evaluate("rust_gpio0_mux_phase2_mux"));

    System.out.println("rust_gpio0_mux_called=" + called);
    System.out.println("GPIO0_MUX_PHASE1=" + phase1 + " (expect 1 = EPWM1A, after set_mux(0,1))");
    System.out.println("GPIO0_MUX_PHASE2=" + phase2 + " (expect 0 = GPIO, after set_mux(0,0))");

    // The intermediate snapshot (phase1 == 1) is what a single final-state
    // check could never prove; phase2 == 0 closes the round trip.
    if (called === 1 && phase1 === 1 && phase2 === 0) {
        System.out.println("GPIO0_MUX_TARGET_TEST=PASS");
    } else {
        System.err.println("GPIO0_MUX_TARGET_TEST=FAIL");
    }
} catch (error) {
    System.err.println("GPIO0_MUX_TARGET_TEST=ERROR");
    System.err.println(String(error));
} finally {
    if (session !== null) {
        try { session.target.disconnect(); } catch (ignoredDisconnect) {}
        try { session.terminate(); } catch (ignoredTerminate) {}
    }
    try { server.stop(); } catch (ignoredStop) {}
    try { environment.traceEnd(); } catch (ignoredTraceEnd) {}
}
