importPackage(Packages.com.ti.debug.engine.scripting);
importPackage(Packages.com.ti.ccstudio.scripting.environment);
importPackage(Packages.java.lang);

if (arguments.length < 2) {
    System.err.println("usage: verify-bare-gpio34-ram.js <target.ccxml> <firmware.out>");
    System.exit(2);
}

var environment = ScriptingEnvironment.instance();
environment.setScriptTimeout(30000);
var server = environment.getServer("DebugServer.1");
var session = null;
var failed = false;
var multi = arguments.length < 3 || String(arguments[2]) !== "single";
function readWord(address) {
    return Number(session.memory.readData(Memory.Page.DATA, address, 16, false)) & 0xffff;
}

try {
    server.setConfig(String(arguments[0]));
    session = server.openSession(".*C28xx.*");
    session.target.connect();
    session.target.halt();
    session.memory.loadProgram(String(arguments[1]));
    // Establish high, then perturb MUX/DIR so stale register state cannot pass.
    if (multi) {
        session.memory.writeData(Memory.Page.DATA, 0x6f86, readWord(0x6f86) & ~0x30, 16);
        session.memory.writeData(Memory.Page.DATA, 0x6f8a, readWord(0x6f8a) | 4, 16);
        session.memory.writeData(Memory.Page.DATA, 0x6fc2, 4, 16);
        if ((readWord(0x6fc0) & 4) !== 4) {
            throw "GPIO2 high precondition failed";
        }
    }
    session.memory.writeData(Memory.Page.DATA, 0x6f96, readWord(0x6f96) & ~0x30, 16);
    session.memory.writeData(Memory.Page.DATA, 0x6f9a, readWord(0x6f9a) | 4, 16);
    session.memory.writeData(Memory.Page.DATA, 0x6fca, 4, 16);
    if ((readWord(0x6fc8) & 4) !== 4) {
        throw "GPIO34 high precondition failed";
    }
    if (multi) {
        session.memory.writeData(Memory.Page.DATA, 0x6f86, readWord(0x6f86) | 0x10, 16);
        session.memory.writeData(Memory.Page.DATA, 0x6f8a, readWord(0x6f8a) & ~4, 16);
    }
    session.memory.writeData(Memory.Page.DATA, 0x6f96, readWord(0x6f96) | 0x10, 16);
    session.memory.writeData(Memory.Page.DATA, 0x6f9a, readWord(0x6f9a) & ~4, 16);
    session.memory.writeRegister("PC", session.symbol.getAddress("code_start"));
    session.target.runAsynch();
    Thread.sleep(100);
    session.target.halt();

    var mux2 = readWord(0x6f86);
    var dir2 = readWord(0x6f8a);
    var data2 = readWord(0x6fc0);
    var mux = readWord(0x6f96);
    var dir = readWord(0x6f9a);
    var data = readWord(0x6fc8);
    var pc = Number(session.memory.readRegister("PC"));
    var idle = Number(session.symbol.getAddress("bare_idle"));
    if (multi) {
        System.out.println("GPIO2_MUX=" + ((mux2 >> 4) & 3));
        System.out.println("GPIO2_DIR=" + ((dir2 >> 2) & 1));
        System.out.println("GPIO2_DATA=" + ((data2 >> 2) & 1));
    }
    System.out.println("GPIO34_MUX=" + ((mux >> 4) & 3));
    System.out.println("GPIO34_DIR=" + ((dir >> 2) & 1));
    System.out.println("GPIO34_DATA=" + ((data >> 2) & 1));
    System.out.println("PC=0x" + pc.toString(16) + " IDLE=0x" + idle.toString(16));
    if ((multi && (((mux2 >> 4) & 3) !== 0 || ((dir2 >> 2) & 1) !== 1 || ((data2 >> 2) & 1) !== 0)) ||
        ((mux >> 4) & 3) !== 0 || ((dir >> 2) & 1) !== 1 || ((data >> 2) & 1) !== 0 || pc !== idle) {
        throw "GPIO2/GPIO34 register or idle-PC check failed";
    }
    if (multi) { System.out.println("BARE_GPIO_MULTI_RAM=PASS"); }
    else { System.out.println("SAFE_HAL_GPIO34_ZERO_C_RAM=PASS"); }
    if (multi) { System.out.println("BARE_GPIO34_RAM=PASS"); }
} catch (error) {
    System.err.println("BARE_GPIO34_RAM=FAIL " + String(error));
    failed = true;
} finally {
    if (session !== null) {
        try { session.target.disconnect(); } catch (ignoredDisconnect) {}
        try { session.terminate(); } catch (ignoredTerminate) {}
    }
    try { server.stop(); } catch (ignoredStop) {}
}
if (failed) { System.exit(1); }
