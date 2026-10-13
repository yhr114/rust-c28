importPackage(Packages.com.ti.debug.engine.scripting);
importPackage(Packages.com.ti.ccstudio.scripting.environment);
importPackage(Packages.java.lang);

if (arguments.length < 2) {
    System.err.println("usage: verify-timer0-irq-ram.js <target.ccxml> <gpio_blink.out>");
    System.exit(2);
}

var environment = ScriptingEnvironment.instance();
environment.setScriptTimeout(30000);
var server = environment.getServer("DebugServer.1");
var session = null;
var failed = false;

function readWord(address) {
    return Number(session.memory.readData(Memory.Page.DATA, address, 16, false)) & 0xffff;
}

function readLong(address) {
    var lo = readWord(address);
    var hi = readWord(address + 1);
    return (hi << 16) | lo;
}

try {
    server.setConfig(String(arguments[0]));
    session = server.openSession(".*C28xx.*");
    session.target.connect();
    session.target.halt();
    session.memory.loadProgram(String(arguments[1]));
    System.out.println("RAM_LOAD=PASS");

    // Start at code_start
    session.memory.writeRegister("PC", session.symbol.getAddress("code_start"));
    session.target.runAsynch();
    Thread.sleep(300);
    session.target.halt();

    var pc = Number(session.memory.readRegister("PC"));
    var ier = Number(session.memory.readRegister("IER")) & 0xffff;
    var intm = (Number(session.memory.readRegister("ST1")) >> 11) & 1;

    System.out.println("PC=0x" + pc.toString(16) + " IER=0x" + ier.toString(16) + " INTM=" + intm);

    // PIE registers
    var piectrl = readWord(0x0ce0);
    var pieack = readWord(0x0ce1);
    System.out.println("PIECTRL=0x" + piectrl.toString(16) + " PIEACK=0x" + pieack.toString(16));

    // All PIE IFR and IER
    for (var g = 1; g <= 12; g++) {
        var ierAddr = 0x0ce0 + g*2;
        var ifrAddr = 0x0ce0 + g*2 + 1;
        var ierVal = readWord(ierAddr);
        var ifrVal = readWord(ifrAddr);
        if (ierVal != 0 || ifrVal != 0) {
            System.out.println("PIE group " + g + ": IER=0x" + ierVal.toString(16) + " IFR=0x" + ifrVal.toString(16));
        }
    }

    // GPIO
    var gpbmux1 = readWord(0x6F96);
    var gpbdir = readWord(0x6F9A);
    var gpbdat = readWord(0x6FC8);
    System.out.println("GPBMUX1=0x" + gpbmux1.toString(16) + " GPBDIR=0x" + gpbdir.toString(16) + " GPBDAT=0x" + gpbdat.toString(16) + " GPIO34=" + ((gpbdat>>2)&1));

    // Timer0
    var tcr = readWord(0x0c04);
    var tim = readLong(0x0c00);
    var prd = readLong(0x0c02);
    System.out.println("TCR=0x" + tcr.toString(16) + " TIM=0x" + tim.toString(16) + " PRD=0x" + prd.toString(16));

    // Vector table entries for group 1
    System.out.println("PIE vectors group 1:");
    for (var i = 0; i < 8; i++) {
        var vec = readLong(0x0d00 + i*2);
        System.out.println("  INT1." + (i+1) + " @0x" + (0x0d00+i*2).toString(16) + " = 0x" + vec.toString(16));
    }

    System.out.println("DIAG_DONE");
} catch (error) {
    System.err.println("DIAG_FAIL " + String(error));
    failed = true;
} finally {
    if (session !== null) {
        try { session.target.disconnect(); } catch (e1) {}
        try { session.terminate(); } catch (e2) {}
    }
    try { server.stop(); } catch (e3) {}
}
if (failed) { System.exit(1); }
