importPackage(Packages.com.ti.debug.engine.scripting);
importPackage(Packages.com.ti.ccstudio.scripting.environment);
importPackage(Packages.java.lang);
importPackage(Packages.java.io);

if (arguments.length < 2) {
    System.err.println("usage: verify-mir-adc-sample-basic.js <target.ccxml> <firmware.out>");
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

try {
    server.setConfig(targetConfig);
    session = server.openSession(".*C28xx.*");
    session.options.setBoolean("AutoRunToLabelOnRestart", false);
    session.options.setBoolean("AutoRunToLabelOnReset", false);
    session.target.connect();
    session.memory.loadProgram(firmware);
    session.target.restart();
    session.expression.evaluate("rust_adc_sample_basic_called = 0");
    session.expression.evaluate("f28035_adc_sample_count = 0xffff");
    session.expression.evaluate("f28035_adc_timeout_count = 0xffff");
    session.expression.evaluate("f28035_peripherals_taken = 0xffff");
    session.memory.writeRegister("PC", session.symbol.getAddress("code_start"));
    session.target.runAsynch();

    var called = 0;
    var deadline = java.lang.System.currentTimeMillis() + 5000;
    while (called === 0 && java.lang.System.currentTimeMillis() < deadline) {
        Thread.sleep(20);
        called = Number(session.expression.evaluate("rust_adc_sample_basic_called"));
    }
    session.target.halt();

    var returnedSample = Number(session.expression.evaluate("rust_adc_sample_basic_value"));
    var harnessAdcResult0 = Number(session.expression.evaluate("rust_adc_sample_basic_adcresult0"));
    var directAdcResult0 = readU16(session, 0x0b00);
    var sampleCount = Number(session.expression.evaluate("f28035_adc_sample_count"));
    var timeoutCount = Number(session.expression.evaluate("f28035_adc_timeout_count"));
    var peripheralsTaken = Number(session.expression.evaluate("f28035_peripherals_taken"));

    System.out.println("rust_adc_sample_basic_called=" + called);
    System.out.println("ADC_SAMPLE_RETURN=" + returnedSample);
    System.out.println("ADCRESULT0_HARNESS=" + harnessAdcResult0);
    System.out.println("ADCRESULT0_DIRECT=" + directAdcResult0);
    System.out.println("ADC_SAMPLE_COUNT=" + sampleCount);
    System.out.println("ADC_TIMEOUT_COUNT=" + timeoutCount);
    System.out.println("PERIPHERALS_TAKEN=" + peripheralsTaken);

    if (called === 1 && sampleCount === 1 && timeoutCount === 0 &&
        peripheralsTaken === 1 && returnedSample === harnessAdcResult0 &&
        returnedSample === directAdcResult0) {
        System.out.println("ADC_SAMPLE_BASIC_TARGET_TEST=PASS");
    } else {
        System.err.println("ADC_SAMPLE_BASIC_TARGET_TEST=FAIL");
    }
} catch (error) {
    System.err.println("ADC_SAMPLE_BASIC_TARGET_TEST=ERROR");
    System.err.println(String(error));
} finally {
    if (session !== null) {
        try { session.target.disconnect(); } catch (ignoredDisconnect) {}
        try { session.terminate(); } catch (ignoredTerminate) {}
    }
    try { server.stop(); } catch (ignoredStop) {}
}
