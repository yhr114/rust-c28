importPackage(Packages.com.ti.debug.engine.scripting);
importPackage(Packages.com.ti.ccstudio.scripting.environment);
importPackage(Packages.java.lang);
importPackage(Packages.java.io);

if (arguments.length < 2) {
    System.err.println("usage: verify-mir-timer0-periodic-basic.js <target.ccxml> <firmware.out>");
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
    session.expression.evaluate("rust_timer0_periodic_basic_called = 0");
    session.expression.evaluate("f28035_timer0_interrupt_count = 0xffff");
    session.expression.evaluate("f28035_peripherals_taken = 0xffff");
    session.memory.writeRegister("PC", session.symbol.getAddress("code_start"));
    session.target.runAsynch();

    var called = 0;
    var deadline = java.lang.System.currentTimeMillis() + 5000;
    while (called === 0 && java.lang.System.currentTimeMillis() < deadline) {
        Thread.sleep(20);
        called = Number(session.expression.evaluate("rust_timer0_periodic_basic_called"));
    }
    Thread.sleep(35);
    session.target.halt();

    var mux = Number(session.expression.evaluate("rust_timer0_periodic_basic_gpio30_mux"));
    var direction = Number(session.expression.evaluate("rust_timer0_periodic_basic_gpio30_dir"));
    var interruptCount = Number(session.expression.evaluate("f28035_timer0_interrupt_count"));
    var timerControl = readU16(session, 0x0c04);
    var timerRunning = (timerControl >>> 4) & 0x1;
    var timerEnabled = (timerControl >>> 14) & 0x1;
    var timerPieEnabled = (readU16(session, 0x0ce2) >>> 6) & 0x1;
    var timerVector = readU32(session, 0x0d4c);
    var expectedTimerVector = Number(session.symbol.getAddress("f28035_timer0_isr"));
    var peripheralsTaken = Number(session.expression.evaluate("f28035_peripherals_taken"));

    System.out.println("rust_timer0_periodic_basic_called=" + called);
    System.out.println("GPIO30_MUX=" + mux);
    System.out.println("GPIO30_DIR=" + direction);
    System.out.println("TIMER0_INTERRUPT_COUNT=" + interruptCount);
    System.out.println("TIMER0_TSS=" + timerRunning);
    System.out.println("TIMER0_TIE=" + timerEnabled);
    System.out.println("TIMER0_PIE_INTX7=" + timerPieEnabled);
    System.out.println("TIMER0_VECTOR=" + timerVector);
    System.out.println("EXPECTED_TIMER0_VECTOR=" + expectedTimerVector);
    System.out.println("PERIPHERALS_TAKEN=" + peripheralsTaken);

    if (called === 1 && peripheralsTaken === 1 &&
        mux === 0 && direction === 1 && interruptCount >= 2 &&
        timerRunning === 0 && timerEnabled === 1 && timerPieEnabled === 1 &&
        timerVector === expectedTimerVector) {
        System.out.println("TIMER0_PERIODIC_BASIC_TARGET_TEST=PASS");
    } else {
        System.err.println("TIMER0_PERIODIC_BASIC_TARGET_TEST=FAIL");
    }
} catch (error) {
    System.err.println("TIMER0_PERIODIC_BASIC_TARGET_TEST=ERROR");
    System.err.println(String(error));
} finally {
    if (session !== null) {
        try { session.target.disconnect(); } catch (ignoredDisconnect) {}
        try { session.terminate(); } catch (ignoredTerminate) {}
    }
    try { server.stop(); } catch (ignoredStop) {}
}
