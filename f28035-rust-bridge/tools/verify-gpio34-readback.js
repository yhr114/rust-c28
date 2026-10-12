importPackage(Packages.com.ti.debug.engine.scripting);
importPackage(Packages.com.ti.ccstudio.scripting.environment);
importPackage(Packages.java.lang);
importPackage(Packages.java.io);

if (arguments.length < 2) {
    System.err.println("usage: verify-gpio34-readback.js <target.ccxml> <firmware.out>");
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

    // Fail closed before the Flash loader is allowed to erase/program.  This
    // script intentionally supports only an erased/unprotected CSM password.
    var passwordAllFf = true;
    for (var passwordAddress = 0x3F7FF8; passwordAddress <= 0x3F7FFF; passwordAddress++) {
        var passwordWord = Number(
            session.memory.readData(Memory.Page.DATA, passwordAddress, 16, false));
        if (passwordWord !== 0xFFFF) {
            passwordAllFf = false;
        }
    }
    var csmStatus = Number(session.memory.readData(Memory.Page.DATA, 0x0AEF, 16, false));
    System.out.println("CSMSCR_BEFORE_PROGRAM=0x" + csmStatus.toString(16));
    System.out.println("CSM_PASSWORD_ALL_FF=" + passwordAllFf);
    if (!passwordAllFf || (csmStatus & 1) !== 0) {
        throw "Refusing Flash program: CSM is protected or password words are not all FFFF";
    }

    // Match the CCS GUI's normal Flash load operation explicitly.  The loader
    // erases only the sectors occupied by the audited .out image, programs
    // them, and verifies the result.
    session.flash.options.setString("FlashOperations", "Erase, Program, Verify");
    session.target.halt();
    session.memory.loadProgram(firmware);
    System.out.println("FLASH_LOAD_PROGRAM=PASS");
    session.target.restart();
    session.memory.writeRegister("PC", session.symbol.getAddress("code_start"));
    session.target.runAsynch();

    // Poll until the C harness records that the Rust function ran and the
    // read-back sequence completed.
    var called = 0;
    var deadline = java.lang.System.currentTimeMillis() + 5000;
    while (called === 0 && java.lang.System.currentTimeMillis() < deadline) {
        Thread.sleep(20);
        called = Number(session.expression.evaluate("rust_gpio34_readback_called"));
    }
    session.target.halt();

    var mux = Number(session.expression.evaluate("rust_gpio34_readback_mux"));
    var direction = Number(session.expression.evaluate("rust_gpio34_readback_direction"));
    var afterHigh = Number(session.expression.evaluate("rust_gpio34_readback_after_high"));
    var afterLow = Number(session.expression.evaluate("rust_gpio34_readback_after_low"));
    var readbackFinal = Number(session.expression.evaluate("rust_gpio34_readback_final"));

    System.out.println("rust_gpio34_readback_called=" + called);
    System.out.println("GPIO34_READBACK_MUX=" + mux);
    System.out.println("GPIO34_READBACK_DIR=" + direction);
    System.out.println("GPIO34_READBACK_AFTER_HIGH=" + afterHigh);
    System.out.println("GPIO34_READBACK_AFTER_LOW=" + afterLow);
    System.out.println("GPIO34_READBACK_FINAL=" + readbackFinal);

    // Rust ran, GPIO34 is a GPIO output, and the read-back levels prove the
    // write -> read path: high reads 1, low reads 0, high reads 1.
    if (called === 1 && mux === 0 && direction === 1 &&
        afterHigh === 1 && afterLow === 0 && readbackFinal === 1) {
        System.out.println("GPIO34_READBACK_TARGET_TEST=PASS");
    } else {
        System.err.println("GPIO34_READBACK_TARGET_TEST=FAIL");
    }
} catch (error) {
    System.err.println("GPIO34_READBACK_TARGET_TEST=ERROR");
    System.err.println(String(error));
} finally {
    if (session !== null) {
        try { session.target.disconnect(); } catch (ignoredDisconnect) {}
        try { session.terminate(); } catch (ignoredTerminate) {}
    }
    try { server.stop(); } catch (ignoredStop) {}
    try { environment.traceEnd(); } catch (ignoredTraceEnd) {}
}
