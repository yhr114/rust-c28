importPackage(Packages.com.ti.debug.engine.scripting);
importPackage(Packages.com.ti.ccstudio.scripting.environment);
importPackage(Packages.java.lang);
importPackage(Packages.java.io);

if (arguments.length < 2) {
    System.err.println("usage: verify-native-arithmetic.js <target.ccxml> <firmware.out>");
    System.exit(2);
}

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
    // The exhaustive packed-byte target test performs 1,536 runtime calls.
    Thread.sleep(100);
    session.target.halt();

    var addResult = Number(session.expression.evaluate("native_add_actual"));
    var subResult = Number(session.expression.evaluate("native_sub_actual"));
    var mulResult = Number(session.expression.evaluate("native_mul_actual"));
    var xorResult = Number(session.expression.evaluate("native_xor_actual"));
    var notResult = Number(session.expression.evaluate("native_not_actual"));
    var maxResult = Number(session.expression.evaluate("native_max_actual"));
    var maxReverseResult = Number(session.expression.evaluate("native_max_reverse_actual"));
    var addThreeResult = Number(session.expression.evaluate("native_add_three_actual"));
    var addLargeResult = Number(session.expression.evaluate("native_add_large_actual"));
    var minResult = Number(session.expression.evaluate("native_min_actual"));
    var minReverseResult = Number(session.expression.evaluate("native_min_reverse_actual"));
    var packedLow = Number(session.expression.evaluate("packed_low_actual"));
    var packedHigh = Number(session.expression.evaluate("packed_high_actual"));
    var packedWriteLow = Number(session.expression.evaluate("packed_write_low_actual"));
    var packedWriteHigh = Number(session.expression.evaluate("packed_write_high_actual"));
    var pointerRead0 = Number(session.expression.evaluate("pointer_read_0_actual"));
    var pointerRead1 = Number(session.expression.evaluate("pointer_read_1_actual"));
    var pointerRead2 = Number(session.expression.evaluate("pointer_read_2_actual"));
    var pointerRead3 = Number(session.expression.evaluate("pointer_read_3_actual"));
    var pointerWord0 = Number(session.expression.evaluate("packed_words[0]"));
    var pointerWord1 = Number(session.expression.evaluate("packed_words[1]"));
    var pointerExhaustivePass = Number(session.expression.evaluate("pointer_exhaustive_pass"));
    var passed = Number(session.expression.evaluate("native_arithmetic_pass"));
    System.out.println("native_add_actual=" + addResult);
    System.out.println("native_sub_actual=" + subResult);
    System.out.println("native_mul_actual=" + mulResult);
    System.out.println("native_xor_actual=" + xorResult);
    System.out.println("native_not_actual=" + notResult);
    System.out.println("native_max_actual=" + maxResult);
    System.out.println("native_max_reverse_actual=" + maxReverseResult);
    System.out.println("native_add_three_actual=" + addThreeResult);
    System.out.println("native_add_large_actual=" + addLargeResult);
    System.out.println("native_min_actual=" + minResult);
    System.out.println("native_min_reverse_actual=" + minReverseResult);
    System.out.println("packed_low_actual=" + packedLow);
    System.out.println("packed_high_actual=" + packedHigh);
    System.out.println("packed_write_low_actual=" + packedWriteLow);
    System.out.println("packed_write_high_actual=" + packedWriteHigh);
    System.out.println("pointer_reads=" + pointerRead0 + "," + pointerRead1 + "," + pointerRead2 + "," + pointerRead3);
    System.out.println("pointer_words_after_write=" + pointerWord0 + "," + pointerWord1);
    System.out.println("pointer_exhaustive_pass=" + pointerExhaustivePass);
    System.out.println("native_arithmetic_pass=" + passed);

    if (addResult === 1 && subResult === 65533 && mulResult === 65534 && xorResult === 23130 && notResult === 43605 && maxResult === 65535 && maxReverseResult === 65535 && addThreeResult === 2 && addLargeResult === 4659 && minResult === 0 && minReverseResult === 2 && packedLow === 17 && packedHigh === 34 && packedWriteLow === 8874 && packedWriteHigh === 47889 && pointerRead0 === 17 && pointerRead1 === 34 && pointerRead2 === 51 && pointerRead3 === 68 && pointerWord0 === 8874 && pointerWord1 === 47923 && pointerExhaustivePass === 1 && passed === 1) {
        System.out.println("NATIVE_ARITHMETIC_TARGET_TEST=PASS");
    } else {
        System.err.println("NATIVE_ARITHMETIC_TARGET_TEST=FAIL");
    }
} catch (error) {
    System.err.println("NATIVE_ARITHMETIC_TARGET_TEST=ERROR");
    System.err.println(String(error));
} finally {
    if (session !== null) {
        try { session.target.disconnect(); } catch (ignoredDisconnect) {}
        try { session.terminate(); } catch (ignoredTerminate) {}
    }
    try { server.stop(); } catch (ignoredStop) {}
}
