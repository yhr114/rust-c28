importPackage(Packages.com.ti.debug.engine.scripting);
importPackage(Packages.com.ti.ccstudio.scripting.environment);
importPackage(Packages.java.lang);
importPackage(Packages.java.io);

if (arguments.length < 2) {
    System.err.println("usage: verify-rust-add.js <target.ccxml> <firmware.out>");
    System.exit(2);
}

var targetConfig = new File(String(arguments[0])).getCanonicalPath();
var firmware = new File(String(arguments[1])).getCanonicalPath();
var environment = ScriptingEnvironment.instance();
environment.setScriptTimeout(20000);
var server = environment.getServer("DebugServer.1");
var session = null;
var exitCode = 1;

try {
    server.setConfig(targetConfig);
    session = server.openSession(".*C28xx.*");
    session.options.setBoolean("AutoRunToLabelOnRestart", false);
    session.options.setBoolean("AutoRunToLabelOnReset", false);
    session.target.connect();
    session.memory.loadProgram(firmware);
    session.target.restart();
    var entryPoint = session.symbol.getAddress("main");
    var stackEnd = session.symbol.getAddress("__TI_STACK_END");
    session.memory.writeRegister("SP", stackEnd);
    session.memory.writeRegister("PC", entryPoint);
    System.out.println("ENTRY_PC=" + session.memory.readRegister("PC"));
    session.target.runAsynch();
    Thread.sleep(1);
    session.target.halt();

    var actual = Number(session.expression.evaluate("rust_add_actual"));
    var expected = Number(session.expression.evaluate("rust_add_expected"));
    var passed = Number(session.expression.evaluate("rust_add_pass"));
    var programCounter = session.expression.evaluate("PC");

    System.out.println("PC=" + programCounter);
    System.out.println("rust_add_actual=" + actual);
    System.out.println("rust_add_expected=" + expected);
    System.out.println("rust_add_pass=" + passed);

    if (actual === 1 && expected === 1 && passed === 1) {
        System.out.println("RUST_ADD_TARGET_TEST=PASS");
        exitCode = 0;
    } else {
        System.err.println("RUST_ADD_TARGET_TEST=FAIL");
    }
} catch (error) {
    System.err.println("RUST_ADD_TARGET_TEST=ERROR");
    System.err.println(String(error));
} finally {
    if (session !== null) {
        try { session.target.disconnect(); } catch (ignoredDisconnect) {}
        try { session.terminate(); } catch (ignoredTerminate) {}
    }
    try { server.stop(); } catch (ignoredStop) {}
}

System.exit(exitCode);
