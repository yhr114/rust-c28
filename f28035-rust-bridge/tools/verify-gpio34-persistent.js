importPackage(Packages.com.ti.debug.engine.scripting);
importPackage(Packages.com.ti.ccstudio.scripting.environment);
importPackage(Packages.java.lang);
importPackage(Packages.java.io);

if (arguments.length < 2) {
    System.err.println("usage: verify-gpio34-persistent.js <target.ccxml> <firmware.out>");
    System.exit(2);
}

var targetConfig = new File(String(arguments[0])).getCanonicalPath();
var firmware = new File(String(arguments[1])).getCanonicalPath();
var environment = ScriptingEnvironment.instance();
environment.setScriptTimeout(30000);
var server = environment.getServer("DebugServer.1");
var session = null;

try {
    server.setConfig(targetConfig);
    session = server.openSession(".*C28xx.*");
    session.options.setBoolean("AutoRunToLabelOnReset", false);
    session.options.setBoolean("AutoRunToLabelOnRestart", false);
    session.target.connect();

    // Symbols only: this call does not erase, program, or otherwise write
    // Flash.  It lets the verifier locate the status variables in the image
    // that must already be resident in Flash.
    session.symbol.load(firmware);
    System.out.println("SYMBOLS_ONLY_LOAD=PASS");

    // A target reset deliberately starts through the Boot ROM.  No PC write is
    // used here: success therefore proves that the boot-mode pins selected
    // boot-to-Flash and that the branch at 0x3F7FF6 reached the application.
    session.target.reset();
    session.target.runAsynch();

    var called = 0;
    var deadline = java.lang.System.currentTimeMillis() + 5000;
    while (called === 0 && java.lang.System.currentTimeMillis() < deadline) {
        Thread.sleep(20);
        called = Number(session.expression.evaluate("rust_gpio34_called"));
    }
    session.target.halt();

    var mux = Number(session.expression.evaluate("rust_gpio34_mux"));
    var direction = Number(session.expression.evaluate("rust_gpio34_direction"));
    var data = Number(session.expression.evaluate("rust_gpio34_data"));

    System.out.println("rust_gpio34_called=" + called);
    System.out.println("GPIO34_MUX=" + mux);
    System.out.println("GPIO34_DIR=" + direction);
    System.out.println("GPIO34_DATA=" + data);

    if (called === 1 && mux === 0 && direction === 1 && data === 0) {
        System.out.println("GPIO34_PERSISTENT_BOOT_TEST=PASS");
    } else {
        System.err.println("GPIO34_PERSISTENT_BOOT_TEST=FAIL");
        System.err.println("Check GPIO34/GPIO37 boot-mode straps: they must select boot-to-Flash at reset.");
    }
} catch (error) {
    System.err.println("GPIO34_PERSISTENT_BOOT_TEST=ERROR");
    System.err.println(String(error));
} finally {
    if (session !== null) {
        try { session.target.disconnect(); } catch (ignoredDisconnect) {}
        try { session.terminate(); } catch (ignoredTerminate) {}
    }
    try { server.stop(); } catch (ignoredStop) {}
}
