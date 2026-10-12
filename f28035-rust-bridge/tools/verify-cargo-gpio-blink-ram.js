importPackage(Packages.com.ti.debug.engine.scripting);
importPackage(Packages.com.ti.ccstudio.scripting.environment);
importPackage(Packages.java.lang);

// verify-cargo-gpio-blink-ram.js <target.ccxml> <gpio_blink.out>
// Loads the cargo-built GPIO34 blink .out into F28035 RAM via JTAG,
// runs it, halts, and checks the GPIO34 register state.

if (arguments.length < 2) {
    System.err.println("usage: verify-cargo-gpio-blink-ram.js <target.ccxml> <gpio_blink.out>");
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

try {
    server.setConfig(String(arguments[0]));
    session = server.openSession(".*C28xx.*");
    session.target.connect();
    session.target.halt();
    session.memory.loadProgram(String(arguments[1]));
    System.out.println("RAM_LOAD=PASS " + String(arguments[1]));

    // Start execution at code_start.
    session.memory.writeRegister("PC", session.symbol.getAddress("code_start"));
    session.target.runAsynch();
    Thread.sleep(300);
    session.target.halt();

    var mux  = readWord(0x6f96);  // GPBMUX1
    var dir  = readWord(0x6f9a);  // GPBDIR
    var data = readWord(0x6fc8);  // GPBDAT
    var pc   = Number(session.memory.readRegister("PC"));
    var mainAddr = Number(session.symbol.getAddress("main"));
    var idleAddr = Number(session.symbol.getAddress("blink_idle"));

    System.out.println("GPBMUX1(0x6f96)=0x" + mux.toString(16));
    System.out.println("GPBDIR(0x6f9a)=0x" + dir.toString(16));
    System.out.println("GPBDAT(0x6fc8)=0x" + data.toString(16));
    System.out.println("PC=0x" + pc.toString(16) + " main=0x" + mainAddr.toString(16) + " blink_idle=0x" + idleAddr.toString(16));

    // GPIO34 = GPIOB bit2: mux bits 5:4 must be 00 (GPIO function),
    // direction bit2 must be 1 (output).
    var muxOk  = ((mux >> 4) & 3) === 0;
    var dirOk  = ((dir >> 2) & 1) === 1;
    // PC should be near main (the toggle loop), not stuck in blink_idle.
    var pcOk   = (Math.abs(pc - mainAddr) < 0x100);
    System.out.println("MUX34_GPIO=" + muxOk + " DIR34_OUT=" + dirOk + " PC_IN_MAIN_LOOP=" + pcOk);

    if (!muxOk || !dirOk || !pcOk) {
        throw "register check failed";
    }
    System.out.println("CARGO_GPIO_BLINK_RAM=PASS");
} catch (error) {
    System.err.println("CARGO_GPIO_BLINK_RAM=FAIL " + String(error));
    failed = true;
} finally {
    if (session !== null) {
        try { session.target.disconnect(); } catch (e1) {}
        try { session.terminate(); } catch (e2) {}
    }
    try { server.stop(); } catch (e3) {}
}
if (failed) { System.exit(1); }
