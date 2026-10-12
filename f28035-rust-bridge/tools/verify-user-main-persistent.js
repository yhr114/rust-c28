importPackage(Packages.com.ti.debug.engine.scripting);
importPackage(Packages.com.ti.ccstudio.scripting.environment);
importPackage(Packages.java.lang);
importPackage(Packages.java.io);

if (arguments.length < 2) {
    System.err.println("usage: verify-user-main-persistent.js <target.ccxml> <flash.out>");
    System.exit(2);
}

var environment = ScriptingEnvironment.instance();
environment.setScriptTimeout(60000);
var server = environment.getServer("DebugServer.1");
var session = null;
var passed = false;
try {
    server.setConfig(new File(String(arguments[0])).getCanonicalPath());
    session = server.openSession(".*C28xx.*");
    session.options.setBoolean("AutoRunToLabelOnReset", false);
    session.options.setBoolean("AutoRunToLabelOnRestart", false);
    session.target.connect();
    session.symbol.load(new File(String(arguments[1])).getCanonicalPath());
    System.out.println("SYMBOLS_ONLY_LOAD=PASS");

    session.target.halt();
    session.expression.evaluate("user_main_called = 0");
    session.target.reset();
    session.target.runAsynch();
    var called = 0;
    var deadline = java.lang.System.currentTimeMillis() + 5000;
    while (called !== 1 && java.lang.System.currentTimeMillis() < deadline) {
        Thread.sleep(5);
        called = Number(session.expression.evaluate("user_main_called"));
    }
    session.target.halt();

    var names = [
        "user_gpio30_mux", "user_gpio30_direction", "user_gpio30_data",
        "user_gpio34_mux", "user_gpio34_direction", "user_gpio34_data"
    ];
    var actual = [];
    for (var i = 0; i < names.length; i++) {
        actual.push(Number(session.expression.evaluate(names[i])));
        System.out.println(names[i] + "=" + actual[i]);
    }
    var result = Number(session.expression.evaluate("user_main_result"));
    var claimed = Number(session.expression.evaluate("f28035_peripherals_taken"));
    System.out.println("user_main_called=" + called);
    System.out.println("user_main_result=" + result);
    System.out.println("PERIPHERALS_TAKEN=" + claimed);
    passed = called === 1 && result === 0xfffd && claimed === 1 &&
        actual[0] === 0 && actual[1] === 1 && actual[2] === 1 &&
        actual[3] === 0 && actual[4] === 1 && actual[5] === 1;
    System.out.println("USER_MAIN_FLASH_BOOT=" + (passed ? "PASS" : "FAIL"));
} catch (error) {
    System.err.println("USER_MAIN_FLASH_BOOT=ERROR");
    System.err.println(String(error));
} finally {
    if (session !== null) {
        try { session.target.disconnect(); } catch (ignoredDisconnect) {}
        try { session.terminate(); } catch (ignoredTerminate) {}
    }
    try { server.stop(); } catch (ignoredStop) {}
}
if (!passed) { System.exit(1); }
