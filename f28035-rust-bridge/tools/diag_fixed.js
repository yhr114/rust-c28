importPackage(Packages.com.ti.debug.engine.scripting);
importPackage(Packages.com.ti.ccstudio.scripting.environment);
importPackage(Packages.java.lang);

if (arguments.length < 2) { System.exit(2); }

var environment = ScriptingEnvironment.instance();
environment.setScriptTimeout(30000);
var server = environment.getServer("DebugServer.1");
var session = null;

function readWord(address) {
    return Number(session.memory.readData(Memory.Page.DATA, address, 16, false)) & 0xffff;
}
function readProgWord(address) {
    return Number(session.memory.readData(Memory.Page.PROGRAM, address, 16, false)) & 0xffff;
}

try {
    server.setConfig(String(arguments[0]));
    session = server.openSession(".*C28xx.*");
    session.target.connect();
    session.target.halt();
    session.memory.loadProgram(String(arguments[1]));
    System.out.println("RAM_LOAD=PASS");

    // Read TINT0_handler instructions at 0x818c
    System.out.println("TINT0_handler @0x818c:");
    for (var i = 0; i < 12; i++) {
        var w = readProgWord(0x818c + i);
        System.out.println("  [0x" + (0x818c+i).toString(16) + "] = 0x" + w.toString(16));
    }

    // Set PC to code_start entry point and run
    session.memory.writeRegister("PC", 0x8000);
    session.target.runAsynch();
    Thread.sleep(100);
    session.target.halt();

    var pc = Number(session.memory.readRegister("PC"));
    var st1 = Number(session.memory.readRegister("ST1"));
    var intm = (st1 >> 11) & 1;
    var gpbdat = readWord(0x6FC8);
    System.out.println("After 100ms: PC=0x" + pc.toString(16) + " INTM=" + intm + " GPBDAT=0x" + gpbdat.toString(16) + " GPIO34=" + ((gpbdat>>2)&1));

    // Sample GPIO multiple times to detect toggling
    var samples = [];
    for (var s = 0; s < 5; s++) {
        session.target.runAsynch();
        Thread.sleep(200);
        session.target.halt();
        gpbdat = readWord(0x6FC8);
        st1 = Number(session.memory.readRegister("ST1"));
        intm = (st1 >> 11) & 1;
        samples.push(((gpbdat>>2)&1));
        System.out.println("  sample " + s + ": GPIO34=" + ((gpbdat>>2)&1) + " INTM=" + intm);
    }

    var toggled = false;
    for (var i = 1; i < samples.length; i++) {
        if (samples[i] != samples[i-1]) { toggled = true; break; }
    }
    System.out.println("GPIO_TOGGLE=" + (toggled ? "PASS" : "FAIL"));

    // Final register dump
    var pieifr1 = readWord(0x0ce3);
    var pieier1 = readWord(0x0ce2);
    var pieack = readWord(0x0ce1);
    var tcr = readWord(0x0c04);
    System.out.println("PIEIER1=0x" + pieier1.toString(16) + " PIEIFR1=0x" + pieifr1.toString(16) + " PIEACK=0x" + pieack.toString(16) + " TCR=0x" + tcr.toString(16));

    System.out.println("DIAG_DONE");
} catch (error) {
    System.err.println("DIAG_FAIL " + String(error));
} finally {
    if (session !== null) {
        try { session.target.disconnect(); } catch (e1) {}
        try { session.terminate(); } catch (e2) {}
    }
    try { server.stop(); } catch (e3) {}
}
