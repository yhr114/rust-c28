importPackage(Packages.com.ti.debug.engine.scripting);
importPackage(Packages.com.ti.ccstudio.scripting.environment);
importPackage(Packages.java.lang);
importPackage(Packages.java.io);

if (arguments.length < 2) {
    System.err.println("usage: verify-gpio-sweep.js <target.ccxml> <firmware.out>");
    System.exit(2);
}

var targetConfig = new File(String(arguments[0])).getCanonicalPath();
var firmware = new File(String(arguments[1])).getCanonicalPath();
var environment = ScriptingEnvironment.instance();
environment.setScriptTimeout(90000);
var server = environment.getServer("DebugServer.1");
var session = null;
var PIN_COUNT = 45;

try {
    server.setConfig(targetConfig);
    session = server.openSession(".*C28xx.*");
    session.options.setBoolean("AutoRunToLabelOnRestart", false);
    session.options.setBoolean("AutoRunToLabelOnReset", false);
    session.target.connect();
    session.memory.loadProgram(firmware);
    session.target.restart();
    session.expression.evaluate("rust_gpio_sweep_called = 0");
    session.expression.evaluate("rust_gpio_sweep_pass_count = 0");
    session.expression.evaluate("rust_gpio_sweep_fail_count = 0xffff");
    session.expression.evaluate("f28035_peripherals_taken = 0");
    session.memory.writeRegister("PC", session.symbol.getAddress("code_start"));
    session.target.runAsynch();

    var called = 0;
    var deadline = java.lang.System.currentTimeMillis() + 10000;
    while (called !== 1 && java.lang.System.currentTimeMillis() < deadline) {
        Thread.sleep(5);
        called = Number(session.expression.evaluate("rust_gpio_sweep_called"));
    }
    session.target.halt();

    var passCount = Number(session.expression.evaluate("rust_gpio_sweep_pass_count"));
    var failCount = Number(session.expression.evaluate("rust_gpio_sweep_fail_count"));
    var peripheralTaken = Number(session.expression.evaluate("f28035_peripherals_taken"));
    var pc = Number(session.memory.readRegister("PC"));

    System.out.println("rust_gpio_sweep_called=" + called);
    System.out.println("GPIO_SWEEP_PASS_COUNT=" + passCount);
    System.out.println("GPIO_SWEEP_FAIL_COUNT=" + failCount);
    System.out.println("PC=" + pc);
    System.out.println("PERIPHERALS_TAKEN=" + peripheralTaken);
    System.out.println("GPIO_SWEEP_TABLE_BEGIN");

    var tablePass = true;
    var nonJtagTablePass = true;
    for (var pin = 0; pin < PIN_COUNT; pin++) {
        var mux = Number(session.expression.evaluate("rust_gpio_sweep_mux[" + pin + "]"));
        var dir = Number(session.expression.evaluate("rust_gpio_sweep_dir[" + pin + "]"));
        var data = Number(session.expression.evaluate("rust_gpio_sweep_data[" + pin + "]"));
        var cLowData = Number(session.expression.evaluate("rust_gpio_sweep_c_low_data[" + pin + "]"));
        var cHighData = Number(session.expression.evaluate("rust_gpio_sweep_c_high_data[" + pin + "]"));
        var pass = Number(session.expression.evaluate("rust_gpio_sweep_pass[" + pin + "]"));
        var rowPass = pass === 1 && mux === 0 && dir === 1 && data === 1 && cLowData === 0 && cHighData === 1;
        if (!rowPass) {
            tablePass = false;
            if (pin < 35 || pin > 38) {
                nonJtagTablePass = false;
            }
        }
        var pinName = pin < 10 ? "GPIO0" + pin : "GPIO" + pin;
        System.out.println(pinName + " MUX=" + mux + " DIR=" + dir + " RUST_FINAL=" + data + " C_LOW=" + cLowData + " C_HIGH=" + cHighData + " " + (rowPass ? "PASS" : "FAIL"));
    }

    System.out.println("GPIO_SWEEP_TABLE_END");

    if (called === 1 && passCount === PIN_COUNT && failCount === 0 && peripheralTaken === 1 && tablePass) {
        System.out.println("GPIO_SWEEP_TARGET_TEST=PASS");
    } else {
        System.err.println("GPIO_SWEEP_TARGET_TEST=FAIL");
    }
    if (called === 1 && peripheralTaken === 1 && nonJtagTablePass) {
        System.out.println("GPIO_SWEEP_NON_JTAG_TARGET_TEST=PASS");
    } else {
        System.err.println("GPIO_SWEEP_NON_JTAG_TARGET_TEST=FAIL");
    }
} catch (error) {
    System.err.println("GPIO_SWEEP_TARGET_TEST=ERROR");
    System.err.println(String(error));
} finally {
    if (session !== null) {
        try { session.target.disconnect(); } catch (ignoredDisconnect) {}
        try { session.terminate(); } catch (ignoredTerminate) {}
    }
    try { server.stop(); } catch (ignoredStop) {}
}
