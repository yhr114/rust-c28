importPackage(Packages.com.ti.debug.engine.scripting);
importPackage(Packages.com.ti.ccstudio.scripting.environment);
importPackage(Packages.java.lang);
importPackage(Packages.java.io);

var environment = ScriptingEnvironment.instance();
environment.setScriptTimeout(20000);
var server = environment.getServer("DebugServer.1");
var session = null;

try {
    server.setConfig(new File(String(arguments[0])).getCanonicalPath());
    session = server.openSession(".*C28xx.*");
    session.options.setBoolean("AutoRunToLabelOnRestart", false);
    session.options.setBoolean("AutoRunToLabelOnReset", false);
    session.target.connect();
    session.memory.loadProgram(new File(String(arguments[1])).getCanonicalPath());
    session.target.restart();
    session.memory.writeRegister("SP", session.symbol.getAddress("__TI_STACK_END"));
    session.memory.writeRegister("PC", session.symbol.getAddress("main"));
    session.target.runAsynch();
    Thread.sleep(10);
    session.target.halt();

    var add = Number(session.expression.evaluate("mir_add_actual"));
    var sub = Number(session.expression.evaluate("mir_sub_actual"));
    var mul = Number(session.expression.evaluate("mir_mul_actual"));
    var callChain = Number(session.expression.evaluate("mir_call_chain_actual"));
    var callChainLarge = Number(session.expression.evaluate("mir_call_chain_large_actual"));
    var linearMix = Number(session.expression.evaluate("mir_linear_mix_actual"));
    var reuseResult = Number(session.expression.evaluate("mir_reuse_result_actual"));
    var nonLifo = Number(session.expression.evaluate("mir_non_lifo_actual"));
    var xor = Number(session.expression.evaluate("mir_xor_actual"));
    var not = Number(session.expression.evaluate("mir_not_actual"));
    var max = Number(session.expression.evaluate("mir_max_actual"));
    var min = Number(session.expression.evaluate("mir_min_actual"));
    var addThree = Number(session.expression.evaluate("mir_add_three_actual"));
    var addLarge = Number(session.expression.evaluate("mir_add_large_actual"));
    var lowByte = Number(session.expression.evaluate("mir_low_byte_actual"));
    var highByte = Number(session.expression.evaluate("mir_high_byte_actual"));
    var writeLow = Number(session.expression.evaluate("mir_write_low_actual"));
    var writeHigh = Number(session.expression.evaluate("mir_write_high_actual"));
    var passed = Number(session.expression.evaluate("mir_arithmetic_pass"));
    System.out.println("mir_results=" + add + "," + sub + "," + mul + "," + max + "," + min + "," + addThree + "," + addLarge);
    System.out.println("mir_call_chain_results=" + callChain + "," + callChainLarge + "," + linearMix + "," + reuseResult + "," + nonLifo);
    System.out.println("mir_bitwise_results=" + xor + "," + not);
    System.out.println("mir_byte_results=" + lowByte + "," + highByte + "," + writeLow + "," + writeHigh);
    System.out.println("mir_arithmetic_pass=" + passed);
    if (add === 1 && sub === 65533 && mul === 65534 && callChain === 3 && callChainLarge === 18470 && linearMix === 4654 && reuseResult === 4660 && nonLifo === 18653 && xor === 23130 && not === 43605 && max === 65535 && min === 2 && addThree === 2 && addLarge === 4659 && lowByte === 17 && highByte === 34 && writeLow === 8874 && writeHigh === 47889 && passed === 1) {
        System.out.println("MIR_ARITHMETIC_TARGET_TEST=PASS");
    } else {
        System.err.println("MIR_ARITHMETIC_TARGET_TEST=FAIL");
    }
} catch (error) {
    System.err.println("MIR_ARITHMETIC_TARGET_TEST=ERROR");
    System.err.println(String(error));
} finally {
    if (session !== null) {
        try { session.target.disconnect(); } catch (ignoredDisconnect) {}
        try { session.terminate(); } catch (ignoredTerminate) {}
    }
    try { server.stop(); } catch (ignoredStop) {}
}
