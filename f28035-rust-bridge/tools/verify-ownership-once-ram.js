importPackage(Packages.com.ti.debug.engine.scripting);
importPackage(Packages.com.ti.ccstudio.scripting.environment);
importPackage(Packages.java.lang);

if (arguments.length < 2) {
    System.err.println("usage: verify-ownership-once-ram.js <target.ccxml> <firmware.out>");
    System.exit(2);
}

var environment = ScriptingEnvironment.instance();
environment.setScriptTimeout(30000);
var server = environment.getServer("DebugServer.1");
var session = null;
var failed = false;

function readSymbol(name) {
    var address = Number(session.symbol.getAddress(name));
    return Number(session.memory.readData(Memory.Page.DATA, address, 16, false)) & 0xffff;
}

function readWord(address) {
    return Number(session.memory.readData(Memory.Page.DATA, address, 16, false)) & 0xffff;
}

try {
    server.setConfig(String(arguments[0]));
    session = server.openSession(".*C28xx.*");
    session.target.connect();
    session.target.halt();
    session.memory.loadProgram(String(arguments[1]));
    session.memory.writeData(Memory.Page.DATA, 0x6f96, readWord(0x6f96) & ~0x30, 16);
    session.memory.writeData(Memory.Page.DATA, 0x6f9a, readWord(0x6f9a) | 4, 16);
    session.memory.writeData(Memory.Page.DATA, 0x6fca, 4, 16);
    if ((readWord(0x6fc8) & 4) !== 4) {
        throw "GPIO34 high precondition failed";
    }
    session.memory.writeData(Memory.Page.DATA, 0x6f96, readWord(0x6f96) | 0x30, 16);
    session.memory.writeData(Memory.Page.DATA, 0x6f9a, readWord(0x6f9a) & ~4, 16);
    session.memory.writeRegister("PC", session.symbol.getAddress("code_start"));
    session.target.runAsynch();
    Thread.sleep(100);
    session.target.halt();

    var applicationResult = readSymbol("application_result");
    var ownerPeripherals = readSymbol("owner_peripherals");
    var ownerGpio34 = readSymbol("owner_gpio34");
    var mux = readWord(0x6f96);
    var direction = readWord(0x6f9a);
    var data = readWord(0x6fc8);
    var pc = Number(session.memory.readRegister("PC"));
    var idle = Number(session.symbol.getAddress("bare_idle"));
    System.out.println("APPLICATION_RESULT=" + applicationResult);
    System.out.println("OWNER_FLAGS=" + ownerPeripherals + "," + ownerGpio34);
    System.out.println("GPIO34_MUX=" + ((mux >> 4) & 3));
    System.out.println("GPIO34_DIR=" + ((direction >> 2) & 1));
    System.out.println("GPIO34_DATA=" + ((data >> 2) & 1));
    System.out.println("PC=0x" + pc.toString(16) + " IDLE=0x" + idle.toString(16));
    if (applicationResult !== 1 || ownerPeripherals !== 1 || ownerGpio34 !== 1 ||
        ((mux >> 4) & 3) !== 0 || ((direction >> 2) & 1) !== 1 ||
        ((data >> 2) & 1) !== 0 || pc !== idle) {
        throw "ownership method result or idle-PC check failed";
    }
    System.out.println("RUST_ONCE_METHOD_RAM=PASS");
} catch (error) {
    System.err.println("RUST_ONCE_METHOD_RAM=FAIL " + String(error));
    failed = true;
} finally {
    if (session !== null) {
        try { session.target.disconnect(); } catch (ignoredDisconnect) {}
        try { session.terminate(); } catch (ignoredTerminate) {}
    }
    try { server.stop(); } catch (ignoredStop) {}
}
if (failed) { System.exit(1); }
