// Hardware readback for the Safe HAL Timer0 interrupt self-check.
// The c28x-rt startup installs TINT0_ISR; the Rust main enables the interrupt
// and drives GPIO34 low once the ISR has fired.  GPIO34 low therefore proves
// the fully automatic interrupt path (IER/EINT/PIE ack) ran.
importPackage(Packages.com.ti.debug.engine.scripting);
importPackage(Packages.com.ti.ccstudio.scripting.environment);
importPackage(Packages.java.lang);

if (arguments.length < 2) {
    System.err.println("usage: verify-safe-hal-timer0.js <target.ccxml> <firmware.out>");
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
    session.target.reset();
    // Establish GPIO34 high first so a stale latch cannot pass the test.
    session.memory.writeData(Memory.Page.DATA, 0x6f96, readWord(0x6f96) & ~0x30, 16);
    session.memory.writeData(Memory.Page.DATA, 0x6f9a, readWord(0x6f9a) & ~4, 16);
    session.memory.writeData(Memory.Page.DATA, 0x6fca, 4, 16);
    if ((readWord(0x6fc8) & 4) !== 4) {
        throw "failed to preset GPIO34 high";
    }
    session.expression.evaluate("PC = code_start");
    session.target.runAsynch();
    Thread.sleep(1000);
    session.target.halt();

    var mux = readWord(0x6f96);
    var dir = readWord(0x6f9a);
    var data = readWord(0x6fc8);
    var pc = Number(session.memory.readRegister("PC"));
    System.out.println("PC=0x" + pc.toString(16));
    System.out.println("GPIO34_MUX=" + ((mux >> 4) & 3));
    System.out.println("GPIO34_DIR=" + ((dir >> 2) & 1));
    System.out.println("GPIO34_DATA=" + ((data >> 2) & 1));
    if (((mux >> 4) & 3) !== 0 || ((dir >> 2) & 1) !== 1 || ((data >> 2) & 1) !== 0) {
        throw "Timer0 ISR did not drive GPIO34 low";
    }
    System.out.println("SAFE_HAL_TIMER0_ISR=PASS");
} catch (error) {
    System.err.println("SAFE_HAL_TIMER0_ISR=FAIL " + String(error));
    failed = true;
} finally {
    if (session !== null) {
        try { session.target.disconnect(); } catch (ignoredDisconnect) {}
        try { session.terminate(); } catch (ignoredTerminate) {}
    }
    try { server.stop(); } catch (ignoredStop) {}
}
if (failed) { System.exit(1); }
