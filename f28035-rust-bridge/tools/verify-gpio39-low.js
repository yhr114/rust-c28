importPackage(Packages.com.ti.debug.engine.scripting);
importPackage(Packages.com.ti.ccstudio.scripting.environment);
importPackage(Packages.java.lang);
importPackage(Packages.java.io);

if (arguments.length < 2) {
    System.err.println("usage: verify-gpio39-low.js <target.ccxml> <firmware.out>");
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
    session.expression.evaluate("rust_gpio39_called = 0");
    session.expression.evaluate("rust_gpio39_mux = 0xffff");
    session.expression.evaluate("rust_gpio39_direction = 0xffff");
    session.expression.evaluate("rust_gpio39_data = 0xffff");
    session.expression.evaluate("f28035_peripherals_taken = 0");
    session.memory.writeRegister("PC", session.symbol.getAddress("code_start"));
    session.target.runAsynch();
    var called = 0;
    var deadline = java.lang.System.currentTimeMillis() + 5000;
    while (called !== 1 && java.lang.System.currentTimeMillis() < deadline) {
        Thread.sleep(5);
        called = Number(session.expression.evaluate("rust_gpio39_called"));
    }
    session.target.halt();

    // The C harness snapshots the typed TI register fields after the Rust
    // function returns. This works with both generated-C and MIR firmware.
    var mux = Number(session.expression.evaluate("rust_gpio39_mux"));
    var direction = Number(session.expression.evaluate("rust_gpio39_direction"));
    var data = Number(session.expression.evaluate("rust_gpio39_data"));
    var pc = Number(session.memory.readRegister("PC"));
    var peripheralTaken = Number(session.expression.evaluate("f28035_peripherals_taken"));

    System.out.println("rust_gpio39_called=" + called);
    System.out.println("GPIO39_MUX=" + mux);
    System.out.println("GPIO39_DIR=" + direction);
    System.out.println("GPIO39_DATA=" + data);
    System.out.println("PC=" + pc);
    System.out.println("PERIPHERALS_TAKEN=" + peripheralTaken);

    if (called === 1 && mux === 0 && direction === 1 && data === 0) {
        System.out.println("GPIO39_LOW_TARGET_TEST=PASS");
    } else {
        System.err.println("GPIO39_LOW_TARGET_TEST=FAIL");
    }
} catch (error) {
    System.err.println("GPIO39_LOW_TARGET_TEST=ERROR");
    System.err.println(String(error));
} finally {
    if (session !== null) {
        try { session.target.disconnect(); } catch (ignoredDisconnect) {}
        try { session.terminate(); } catch (ignoredTerminate) {}
    }
    try { server.stop(); } catch (ignoredStop) {}
}
