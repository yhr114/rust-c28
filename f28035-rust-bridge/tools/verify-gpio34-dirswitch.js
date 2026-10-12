importPackage(Packages.com.ti.debug.engine.scripting);
importPackage(Packages.com.ti.ccstudio.scripting.environment);
importPackage(Packages.java.lang);
importPackage(Packages.java.io);

if (arguments.length < 2) {
    System.err.println("usage: verify-gpio34-dirswitch.js <target.ccxml> <firmware.out>");
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

    session.flash.options.setString("FlashOperations", "Erase, Program, Verify");
    session.target.halt();
    session.memory.loadProgram(firmware);
    System.out.println("FLASH_LOAD_PROGRAM=PASS");
    session.target.restart();
    session.memory.writeRegister("PC", session.symbol.getAddress("code_start"));
    session.target.runAsynch();

    // Poll until the C harness records that the Rust function ran and the
    // full direction-switch sequence completed.
    var called = 0;
    var deadline = java.lang.System.currentTimeMillis() + 5000;
    while (called === 0 && java.lang.System.currentTimeMillis() < deadline) {
        Thread.sleep(20);
        called = Number(session.expression.evaluate("rust_gpio34_direction_called"));
    }
    session.target.halt();

    var mux = Number(session.expression.evaluate("rust_gpio34_direction_mux"));
    var direction = Number(session.expression.evaluate("rust_gpio34_direction_direction"));
    var data = Number(session.expression.evaluate("rust_gpio34_direction_data"));
    var qsel = Number(session.expression.evaluate("rust_gpio34_direction_qsel"));
    var pud = Number(session.expression.evaluate("rust_gpio34_direction_pud"));

    // GPIO34 -> GPIOB pin 2: QSEL1 bits 4-5 (Sync = 0), PUD bit 2 (0 = pull-up
    // enabled).  These are programmed by make_input and NOT cleared by the
    // later make_output, so they are hard evidence the input stage ran.
    var qsel34 = (qsel >> 4) & 0x3;
    var pud34 = (pud >> 2) & 0x1;

    System.out.println("rust_gpio34_direction_called=" + called);
    System.out.println("GPIO34_DIRS_MUX=" + mux);
    System.out.println("GPIO34_DIRS_DIR=" + direction);
    System.out.println("GPIO34_DIRS_DATA=" + data);
    System.out.println("GPIO34_DIRS_QSEL=" + qsel34 + " (expect 0 = Sync, from make_input)");
    System.out.println("GPIO34_DIRS_PUD=" + pud34 + " (expect 0 = pull-up enabled, from make_input)");

    // Final state: GPIO output (DIR=1) driving low (DATA=0), plus the input
    // residue proving the direction really switched through the input stage.
    if (called === 1 && mux === 0 && direction === 1 && data === 0 &&
        qsel34 === 0 && pud34 === 0) {
        System.out.println("GPIO34_DIRECTION_SWITCH_TARGET_TEST=PASS");
    } else {
        System.err.println("GPIO34_DIRECTION_SWITCH_TARGET_TEST=FAIL");
    }
} catch (error) {
    System.err.println("GPIO34_DIRECTION_SWITCH_TARGET_TEST=ERROR");
    System.err.println(String(error));
} finally {
    if (session !== null) {
        try { session.target.disconnect(); } catch (ignoredDisconnect) {}
        try { session.terminate(); } catch (ignoredTerminate) {}
    }
    try { server.stop(); } catch (ignoredStop) {}
    try { environment.traceEnd(); } catch (ignoredTraceEnd) {}
}
