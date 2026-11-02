importPackage(Packages.com.ti.debug.engine.scripting)
importPackage(Packages.com.ti.ccstudio.scripting.environment)
var script = ScriptingEnvironment.instance(); script.setScriptTimeout(60000);
var server = script.getServer("DebugServer.1"); server.setConfig(arguments[1]);
var session = server.openSession("*", "*");
var group = Number(arguments[2]), counts = [0, 48, 192, 72, 144, 6];
try {
    session.target.connect(); session.target.reset(); session.target.halt();
    session.memory.loadProgram(arguments[0]); session.expression.evaluate("PC = code_start");
    var done = session.symbol.getAddress("hw_done"), bp = session.breakpoint.add(done), error = null;
    script.setScriptTimeout(15000);
    try { session.target.run(); } catch (e) { error = e; }
    session.target.halt(); session.breakpoint.remove(bp);
    var pc = session.expression.evaluate("PC"), values = [];
    var resultsAddress = session.symbol.getAddress("HW_MEMORY_RESULT");
    for (var i = 0; i < 8; ++i) values.push(session.expression.evaluate("*((unsigned int *)" + (resultsAddress + i) + ")"));
    java.lang.System.out.println("MEMORY_GROUP=" + group + " PC=" + pc + " DONE=" + done + " RESULTS=" + values);
    if (error || pc != done) throw new Error("Memory test did not reach its completion breakpoint");
    if (values[0] != counts[group] || values[1] != 0 || values[2] != 0 || values[6] != group || values[7] != 0xB1E0 + group)
        throw new Error("Memory case count, mismatch count, or completion marker failed");
    java.lang.System.out.println("PASS: Cargo memory group " + group + " cases=" + counts[group] + " on F28035");
} finally { try { session.target.halt(); } catch (e) {} session.terminate(); server.stop(); }
