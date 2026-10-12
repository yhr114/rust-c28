importPackage(Packages.com.ti.debug.engine.scripting);
importPackage(Packages.com.ti.ccstudio.scripting.environment);
importPackage(Packages.java.lang);
importPackage(Packages.java.io);

if (arguments.length < 2) {
    System.err.println("usage: verify-epwm-up-aq.js <target.ccxml> <firmware.out>");
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

    var called = 0;
    var deadline = java.lang.System.currentTimeMillis() + 5000;
    while (called === 0 && java.lang.System.currentTimeMillis() < deadline) {
        Thread.sleep(20);
        called = Number(session.expression.evaluate("rust_epwm_socb_called"));
    }
    session.target.halt();

    var tbprd   = Number(session.expression.evaluate("rust_epwm_socb_tbprd"));
    var cmpa    = Number(session.expression.evaluate("rust_epwm_socb_cmpa"));
    var aqctla  = Number(session.expression.evaluate("rust_epwm_socb_aqctla"));
    var ctrMode = Number(session.expression.evaluate("rust_epwm_socb_ctr_mode"));
    var socbEn  = Number(session.expression.evaluate("rust_epwm_socb_socb_en"));
    var socbPrd = Number(session.expression.evaluate("rust_epwm_socb_socb_prd"));

    System.out.println("rust_epwm_socb_called=" + called);
    System.out.println("TBPRD=" + tbprd + " (expect 99)");
    System.out.println("CMPA=" + cmpa + " (expect 40)");
    System.out.println("AQCTLA=0x" + aqctla.toString(16) + " (expect 0x12)");
    System.out.println("CTRMODE=" + ctrMode + " (expect 0 = up-count)");
    System.out.println("SOCB_EN=" + socbEn + " (expect 1)");
    System.out.println("SOCB_PRD=" + socbPrd + " (expect 1)");

    if (called === 1 && tbprd === 99 && cmpa === 40 &&
        aqctla === 0x0012 && ctrMode === 0 && socbEn === 1 && socbPrd === 1) {
        System.out.println("epwm_socb_TARGET_TEST=PASS");
    } else {
        System.err.println("epwm_socb_TARGET_TEST=FAIL");
    }
} catch (error) {
    System.err.println("epwm_socb_TARGET_TEST=ERROR");
    System.err.println(String(error));
} finally {
    if (session !== null) {
        try { session.target.disconnect(); } catch (ignoredDisconnect) {}
        try { session.terminate(); } catch (ignoredTerminate) {}
    }
    try { server.stop(); } catch (ignoredStop) {}
    try { environment.traceEnd(); } catch (ignoredTraceEnd) {}
}
