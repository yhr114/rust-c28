importPackage(Packages.com.ti.debug.engine.scripting);
importPackage(Packages.com.ti.ccstudio.scripting.environment);
importPackage(Packages.java.lang);
importPackage(Packages.java.io);

if (arguments.length < 2) {
    System.err.println("usage: verify-gpio2-3-low.js <target.ccxml> <firmware.out>");
    System.exit(2);
}

var targetConfig = new File(String(arguments[0])).getCanonicalPath();
var firmware = new File(String(arguments[1])).getCanonicalPath();
var environment = ScriptingEnvironment.instance();
environment.setScriptTimeout(60000);
var server = environment.getServer("DebugServer.1");
var session = null;

try {
    server.setConfig(targetConfig);
    session = server.openSession(".*C28xx.*");
    session.options.setBoolean("AutoRunToLabelOnRestart", false);
    session.options.setBoolean("AutoRunToLabelOnReset", false);
    session.target.connect();
    session.memory.loadProgram(firmware);
    session.target.restart();
    session.expression.evaluate("rust_gpio2_3_called = 0");
    session.expression.evaluate("rust_gpio2_3_mux2 = 0xffff");
    session.expression.evaluate("rust_gpio2_3_mux3 = 0xffff");
    session.expression.evaluate("rust_gpio2_3_dir2 = 0xffff");
    session.expression.evaluate("rust_gpio2_3_dir3 = 0xffff");
    session.expression.evaluate("rust_gpio2_3_data2 = 0xffff");
    session.expression.evaluate("rust_gpio2_3_data3 = 0xffff");
    session.expression.evaluate("f28035_peripherals_taken = 0");
    session.memory.writeRegister("PC", session.symbol.getAddress("code_start"));
    session.target.runAsynch();
    var called = 0;
    var deadline = java.lang.System.currentTimeMillis() + 5000;
    while (called !== 1 && java.lang.System.currentTimeMillis() < deadline) {
        Thread.sleep(5);
        called = Number(session.expression.evaluate("rust_gpio2_3_called"));
    }
    session.target.halt();

    var mux2 = Number(session.expression.evaluate("rust_gpio2_3_mux2"));
    var mux3 = Number(session.expression.evaluate("rust_gpio2_3_mux3"));
    var dir2 = Number(session.expression.evaluate("rust_gpio2_3_dir2"));
    var dir3 = Number(session.expression.evaluate("rust_gpio2_3_dir3"));
    var data2 = Number(session.expression.evaluate("rust_gpio2_3_data2"));
    var data3 = Number(session.expression.evaluate("rust_gpio2_3_data3"));
    var pc = Number(session.memory.readRegister("PC"));
    var peripheralTaken = Number(session.expression.evaluate("f28035_peripherals_taken"));

    System.out.println("rust_gpio2_3_called=" + called);
    System.out.println("GPIO2_MUX=" + mux2);
    System.out.println("GPIO3_MUX=" + mux3);
    System.out.println("GPIO2_DIR=" + dir2);
    System.out.println("GPIO3_DIR=" + dir3);
    System.out.println("GPIO2_DATA=" + data2);
    System.out.println("GPIO3_DATA=" + data3);
    System.out.println("PC=" + pc);
    System.out.println("PERIPHERALS_TAKEN=" + peripheralTaken);

    if (called === 1 && mux2 === 0 && mux3 === 0 && dir2 === 1 && dir3 === 1 &&
        data2 === 0 && data3 === 0) {
        System.out.println("GPIO2_3_LOW_TARGET_TEST=PASS");
    } else {
        System.err.println("GPIO2_3_LOW_TARGET_TEST=FAIL");
    }
} catch (error) {
    System.err.println("GPIO2_3_LOW_TARGET_TEST=ERROR");
    System.err.println(String(error));
} finally {
    if (session !== null) {
        try { session.target.disconnect(); } catch (ignoredDisconnect) {}
        try { session.terminate(); } catch (ignoredTerminate) {}
    }
    try { server.stop(); } catch (ignoredStop) {}
}
