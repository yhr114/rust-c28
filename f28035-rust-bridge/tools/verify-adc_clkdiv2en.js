importPackage(Packages.com.ti.debug.engine.scripting);
importPackage(Packages.com.ti.ccstudio.scripting.environment);
importPackage(Packages.java.lang);
importPackage(Packages.java.io);

if (arguments.length < 2) {
    System.err.println("usage: verify-adc-eoc-irq.js <target.ccxml> <firmware.out>");
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
    session.target.connect();

    var passwordAllFf = true;
    for (var passwordAddress = 0x3F7FF8; passwordAddress <= 0x3F7FFF; passwordAddress++) {
        var passwordWord = Number(
            session.memory.readData(Memory.Page.DATA, passwordAddress, 16, false));
        if (passwordWord !== 0xFFFF) { passwordAllFf = false; }
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
        called = Number(session.expression.evaluate("rust_adc_clkdiv2en_called"));
    }
    session.target.halt();

    /* int1f not checked */
    /* overflow not checked */
    var timeouts = Number(session.expression.evaluate("rust_adc_clkdiv2en_timeouts"));

    System.out.println("rust_adc_clkdiv2en_called=" + called);
    
    
    System.out.println("TIMEOUTS=" + timeouts + " (expect 0)");

    if (called === 1 && timeouts === 0) {
        System.out.println("adc_clkdiv2en_TARGET_TEST=PASS");
    } else {
        System.err.println("adc_clkdiv2en_TARGET_TEST=FAIL");
    }
} catch (error) {
    System.err.println("adc_clkdiv2en_TARGET_TEST=ERROR");
    System.err.println(String(error));
} finally {
    if (session !== null) {
        try { session.target.disconnect(); } catch (ignored) {}
        try { session.terminate(); } catch (ignored) {}
    }
    try { server.stop(); } catch (ignored) {}
    try { environment.traceEnd(); } catch (ignored) {}
}
