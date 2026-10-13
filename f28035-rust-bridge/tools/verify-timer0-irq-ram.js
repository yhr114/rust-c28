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

    // Check vector table
    var tint0_vec = readLong(0x0D0C);
    System.out.println("PIEVECT[TINT0]=0x" + tint0_vec.toString(16));

    // Start at code_start
    session.memory.writeRegister("PC", session.symbol.getAddress("code_start"));
    session.target.runAsynch();

    // Wait for interrupts to fire
    Thread.sleep(500);
    session.target.halt();

    var pc = Number(session.memory.readRegister("PC"));
    var gpbmux1 = readWord(0x6F96);
    var gpbdir = readWord(0x6F9A);
    var gpbdat = readWord(0x6FC8);
    var gpbtoggle = readWord(0x6FCE);
    var pieier1 = readWord(0x0ce2);
    var pieifr1 = readWord(0x0ce3);
    var pieack = readWord(0x0ce1);
    var tcr = readWord(0x0c04);
    var tim = readWord(0x0c01);
    var prd = readLong(0x0c02);

    System.out.println("PC=0x" + pc.toString(16));
    System.out.println("GPBMUX1=0x" + gpbmux1.toString(16) + " GPBDIR=0x" + gpbdir.toString(16) + " GPBDAT=0x" + gpbdat.toString(16) + " GPIO34=" + ((gpbdat>>2)&1));
    System.out.println("PIEIER1=0x" + pieier1.toString(16) + " PIEIFR1=0x" + pieifr1.toString(16) + " PIEACK=0x" + pieack.toString(16));
    System.out.println("TCR=0x" + tcr.toString(16) + " TIM=0x" + tim.toString(16) + " PRD=0x" + prd.toString(16));

    // Sample GPBDAT a few times with delay
    var samples = [];
    for (var i = 0; i < 5; i++) {
        session.target.runAsynch();
        Thread.sleep(300);
        session.target.halt();
        var dat = readWord(0x6fc8);
        samples.push((dat >> 2) & 1);
        System.out.println("sample[" + i + "] GPBDAT=0x" + dat.toString(16) + " GPIO34=" + ((dat>>2)&1) + " PC=0x" + Number(session.memory.readRegister("PC")).toString(16));
    }

    var toggled = false;
    for (var i = 1; i < samples.length; i++) {
        if (samples[i] !== samples[i-1]) { toggled = true; break; }
    }

    System.out.println("GPIO34_TOGGLED=" + toggled);
    if (!toggled) { throw "GPIO34 not toggling"; }
    System.out.println("TIMER0_IRQ_RAM=PASS");
} catch (error) {
    System.err.println("TIMER0_IRQ_RAM=FAIL " + String(error));
    failed = true;
} finally {
    if (session !== null) {
        try { session.target.disconnect(); } catch (e1) {}
        try { session.terminate(); } catch (e2) {}
    }
    try { server.stop(); } catch (e3) {}
}
if (failed) { System.exit(1); }
