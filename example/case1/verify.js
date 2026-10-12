importPackage(Packages.com.ti.debug.engine.scripting);
importPackage(Packages.com.ti.ccstudio.scripting.environment);
importPackage(Packages.java.lang);
importPackage(Packages.java.io);

if (arguments.length < 2) {
    System.err.println("usage: verify.js <target.ccxml> <firmware.out>");
    System.exit(2);
}

var environment = ScriptingEnvironment.instance();
environment.setScriptTimeout(60000);
var server = environment.getServer("DebugServer.1");
var session = null;
var passed = false;

function word(address) {
    return Number(session.memory.readData(Memory.Page.DATA, address, 16, false));
}

try {
    server.setConfig(new File(String(arguments[0])).getCanonicalPath());
    session = server.openSession(".*C28xx.*");
    session.options.setBoolean("AutoRunToLabelOnRestart", false);
    session.options.setBoolean("AutoRunToLabelOnReset", false);
    session.target.connect();
    session.memory.loadProgram(new File(String(arguments[1])).getCanonicalPath());
    session.target.restart();
    session.expression.evaluate("f28035_peripherals_taken = 0");
    session.memory.writeRegister("PC", session.symbol.getAddress("code_start"));
    session.target.runAsynch();

    var claimed = 0;
    var deadline = java.lang.System.currentTimeMillis() + 5000;
    while (claimed !== 1 && java.lang.System.currentTimeMillis() < deadline) {
        Thread.sleep(5);
        claimed = Number(session.expression.evaluate("f28035_peripherals_taken"));
    }
    var samples = 0;
    var samplingDeadline = java.lang.System.currentTimeMillis() + 3000;
    while (samples < 2 && java.lang.System.currentTimeMillis() < samplingDeadline) {
        Thread.sleep(20);
        samples = Number(session.expression.evaluate("f28035_adc_sample_count"));
    }
    session.target.halt();

    // C28x word addresses from GPIOCTRL=0x6F80 and GPIODAT=0x6FC0.
    var actual = [
        (word(0x6F96) >> 4) & 3,  // GPBMUX1.GPIO34
        (word(0x6F9A) >> 2) & 1,  // GPBDIR.GPIO34
        (word(0x6FC8) >> 2) & 1,  // GPBDAT.GPIO34
        (word(0x6F96) >> 14) & 3, // GPBMUX1.GPIO39
        (word(0x6F9A) >> 7) & 1,  // GPBDIR.GPIO39
        (word(0x6FC8) >> 7) & 1   // GPBDAT.GPIO39
    ];
    samples = Number(session.expression.evaluate("f28035_adc_sample_count"));
    var adc0 = word(0x0B00); // TI ADC_RESULT origin: ADCRESULT0.
    System.out.println("GPIO34_MUX=" + actual[0] + " DIR=" + actual[1] + " DATA=" + actual[2]);
    System.out.println("GPIO39_MUX=" + actual[3] + " DIR=" + actual[4] + " DATA=" + actual[5]);
    System.out.println("ADC0_RESULT=" + adc0);
    System.out.println("ADC_SAMPLE_COUNT=" + samples);
    System.out.println("PERIPHERALS_TAKEN=" + claimed);
    passed = claimed === 1 &&
        actual[0] === 0 && actual[1] === 0 &&
        actual[3] === 0 && actual[4] === 1 && actual[5] === 0 &&
        samples >= 2;
    System.out.println("F28035_RUST_CASE=" + (passed ? "PASS" : "FAIL"));
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
if (!passed) { System.exit(1); }
