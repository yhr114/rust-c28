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

    // Read handler flag at 0x280 (word addr = Rust byte addr 0x500)
    var flag = readWord(0x280);
    System.out.println("HANDLER_FLAG@0x280=0x" + flag.toString(16));

    // Read ALL Group 1 vectors
    for (var v = 0; v < 8; v++) {
        var vlo = readWord(0x0d00 + v*2);
        System.out.println("VEC INT1." + (v+1) + " @0x" + (0x0d00+v*2).toString(16) + " = 0x" + vlo.toString(16));
    }
    // Read TINT0_handler instructions at 0x813e
    System.out.println("TINT0_handler @0x813e:");
    for (var i = 0; i < 10; i++) {
        var w = readProgWord(0x813e + i);
        System.out.println("  [0x" + (0x813e+i).toString(16) + "] = 0x" + w.toString(16));
    }

    // Set PC and run (code_start entry point)
    session.memory.writeRegister("PC", 0x80ba);
    session.target.runAsynch();
    Thread.sleep(10);
    session.target.halt();

    var pc = Number(session.memory.readRegister("PC"));
    var st1 = Number(session.memory.readRegister("ST1"));
    var intm = (st1 >> 11) & 1;
    System.out.println("After 10ms: PC=0x" + pc.toString(16) + " INTM=" + intm);

    session.target.runAsynch();
    Thread.sleep(90);
    session.target.halt();

    pc = Number(session.memory.readRegister("PC"));
    st1 = Number(session.memory.readRegister("ST1"));
    intm = (st1 >> 11) & 1;
    System.out.println("After 100ms: PC=0x" + pc.toString(16) + " ST1=0x" + st1.toString(16) + " INTM=" + intm);

    var gpbdir = readWord(0x6F9A);
    var gpbdat = readWord(0x6FC8);
    System.out.println("GPBDIR=0x" + gpbdir.toString(16) + " GPBDAT=0x" + gpbdat.toString(16) + " GPIO34=" + ((gpbdat>>2)&1));

    // Dump full stack frame: SP-16 to SP+1
    var sp = Number(session.memory.readRegister("SP"));
    System.out.println("SP=0x" + sp.toString(16));
    for (var si = -16; si <= 1; si++) {
        var sw = readWord(sp + si);
        System.out.println("  [SP" + (si>=0?"+":"") + si + "]@0x" + (sp+si).toString(16) + "=0x" + sw.toString(16));
    }

    // Run more
    session.target.runAsynch();
    Thread.sleep(2000);
    session.target.halt();

    pc = Number(session.memory.readRegister("PC"));
    st1 = Number(session.memory.readRegister("ST1"));
    intm = (st1 >> 11) & 1;
    gpbdat = readWord(0x6FC8);
    var pieifr1 = readWord(0x0ce3);
    var pieier1 = readWord(0x0ce2);
    var pieack = readWord(0x0ce1);
    var piectrl = readWord(0x0ce0);
    var tcr = readWord(0x0c04);
    var tim_lo = readWord(0x0c00);
    var tim_hi = readWord(0x0c01);
    System.out.println("After 2.1s: PC=0x" + pc.toString(16) + " INTM=" + intm + " GPBDAT=0x" + gpbdat.toString(16) + " GPIO34=" + ((gpbdat>>2)&1));
    System.out.println("PIECTRL=0x" + piectrl.toString(16) + " PIEIER1=0x" + pieier1.toString(16) + " PIEIFR1=0x" + pieifr1.toString(16) + " PIEACK=0x" + pieack.toString(16) + " TCR=0x" + tcr.toString(16));
    System.out.println("TIM=0x" + ((tim_hi<<16)|tim_lo).toString(16));

    // Read all 8 handler flags
    for (var fi = 0; fi < 8; fi++) {
        var fv = readWord(0x280 + fi);
        System.out.println("FLAG[" + fi + "]@0x" + (0x280+fi).toString(16) + "=0x" + fv.toString(16));
    }

    // Read handler flag
    var hflag = readWord(0x280);
    System.out.println("HANDLER_FLAG=0x" + hflag.toString(16));

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
