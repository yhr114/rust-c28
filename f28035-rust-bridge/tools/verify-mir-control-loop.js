importPackage(Packages.com.ti.debug.engine.scripting);
importPackage(Packages.com.ti.ccstudio.scripting.environment);
importPackage(Packages.java.lang);
importPackage(Packages.java.io);

if (arguments.length < 2) {
    System.err.println("usage: verify-mir-control-loop.js <target.ccxml> <firmware.out>");
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
    // Poison initialized state first.  Starting at code_start must traverse
    // _c_int00, establish SP, and restore these C initializers before main.
    session.expression.evaluate("f28035_peripherals_taken = 0xffff");
    session.expression.evaluate("f28035_timer0_interrupt_count = 0xffff");
    session.memory.writeRegister("PC", session.symbol.getAddress("code_start"));
    session.breakpoint.add(session.symbol.getAddress("rust_timer0_interrupt"));
    session.target.run();
    session.breakpoint.removeAll();
    session.target.runAsynch();
    // After the first callback, allow at least two more 10 ms periods.
    Thread.sleep(25);
    session.target.halt();

    // Absolute peripheral linker symbols intentionally have no C debug type;
    // decode the documented word-addressed registers directly.
    var mux2 = readU32(session, 0x6f88);
    var directionA = readU32(session, 0x6f8a);
    var dataA = readU32(session, 0x6fc0);
    var mux = (mux2 >>> 30) & 0x3;
    var direction = (directionA >>> 31) & 0x1;
    var data = (dataA >>> 31) & 0x1;
    var sample = readU16(session, 0x0b00);
    var adcSampleCount = Number(session.expression.evaluate("f28035_adc_sample_count"));
    var adcTimeoutCount = Number(session.expression.evaluate("f28035_adc_timeout_count"));
    var expectedData = sample >= 2048 ? 1 : 0;
    var interruptMux = (mux2 >>> 28) & 0x3;
    var interruptDirection = (directionA >>> 30) & 0x1;
    var interruptCount = Number(session.expression.evaluate("f28035_timer0_interrupt_count"));
    var timerControl = readU16(session, 0x0c04);
    var timerRunning = (timerControl >>> 4) & 0x1;
    var timerEnabled = (timerControl >>> 14) & 0x1;
    var timerPieEnabled = (readU16(session, 0x0ce2) >>> 6) & 0x1;
    var timerVector = readU32(session, 0x0d4c);
    var expectedTimerVector = Number(session.symbol.getAddress("f28035_timer0_isr"));
    var pwmMux = readU32(session, 0x6f86) & 0x3;
    var pwmPeriod = readU16(session, 0x6805);
    var pwmCompare = readU16(session, 0x6809);
    var expectedPwmCompare = sample > 4095 ? 4095 : sample;
    var pwmTrackingError = Math.abs(pwmCompare - expectedPwmCompare);
    var pc = Number(session.memory.readRegister("PC"));
    var sp = Number(session.memory.readRegister("SP"));
    System.out.println("GPIO31_MUX=" + mux);
    System.out.println("GPIO31_DIR=" + direction);
    System.out.println("GPIO31_DATA=" + data);
    System.out.println("ADCRESULT0=" + sample);
    System.out.println("ADC_SAMPLE_COUNT=" + adcSampleCount);
    System.out.println("ADC_TIMEOUT_COUNT=" + adcTimeoutCount);
    System.out.println("EXPECTED_GPIO31_DATA=" + expectedData);
    System.out.println("GPIO30_MUX=" + interruptMux);
    System.out.println("GPIO30_DIR=" + interruptDirection);
    System.out.println("TIMER0_INTERRUPT_COUNT=" + interruptCount);
    System.out.println("TIMER0_TSS=" + timerRunning);
    System.out.println("TIMER0_TIE=" + timerEnabled);
    System.out.println("TIMER0_PIE_INTX7=" + timerPieEnabled);
    System.out.println("TIMER0_VECTOR=" + timerVector);
    System.out.println("EXPECTED_TIMER0_VECTOR=" + expectedTimerVector);
    System.out.println("EPWM1_GPIO0_MUX=" + pwmMux);
    System.out.println("EPWM1_TBPRD=" + pwmPeriod);
    System.out.println("EPWM1_CMPA=" + pwmCompare);
    System.out.println("EXPECTED_EPWM1_CMPA=" + expectedPwmCompare);
    System.out.println("EPWM1_TRACKING_ERROR=" + pwmTrackingError);
    System.out.println("PC=" + pc);
    System.out.println("SP=" + sp);

    if (mux === 0 && direction === 1 && data === expectedData &&
        adcSampleCount > 0 && adcTimeoutCount === 0 &&
        interruptMux === 0 && interruptDirection === 1 && interruptCount >= 2 &&
        timerRunning === 0 && timerEnabled === 1 && timerPieEnabled === 1 &&
        timerVector === expectedTimerVector && pwmMux === 1 && pwmPeriod === 4095 &&
        pwmCompare <= pwmPeriod && pwmTrackingError <= 64) {
        System.out.println("MIR_CONTROL_LOOP_TARGET_TEST=PASS");
    } else {
        System.err.println("MIR_CONTROL_LOOP_TARGET_TEST=FAIL");
    }
} catch (error) {
    System.err.println("MIR_CONTROL_LOOP_TARGET_TEST=ERROR");
    System.err.println(String(error));
} finally {
    if (session !== null) {
        try { session.target.disconnect(); } catch (ignoredDisconnect) {}
        try { session.terminate(); } catch (ignoredTerminate) {}
    }
    try { server.stop(); } catch (ignoredStop) {}
}
