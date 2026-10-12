// JTAG-only GPIO2/GPIO3 output-low setup.
// Usage: jtag-gpio2-3-low.js <target.ccxml>

importPackage(Packages.com.ti.debug.engine.scripting);
importPackage(Packages.com.ti.ccstudio.scripting.environment);
importPackage(Packages.java.lang);
importPackage(Packages.java.io);

var targetConfig = new File(String(arguments[0])).getCanonicalPath();
var environment = ScriptingEnvironment.instance();
environment.setScriptTimeout(15000);
var server = environment.getServer("DebugServer.1");
var session = null;

var GPAMUX1_LO = 0x6F86;
var GPADIR_LO = 0x6F8A;
var GPADAT_LO = 0x6FC0;
var GPACLEAR_LO = 0x6FC4;
var GPIO2_3_MASK = 0x000C;
var GPIO2_3_MUX_MASK = 0x00F0;

function rd(addr) {
    return Number(session.memory.readData(Memory.Page.DATA, addr, 16, false)) & 0xFFFF;
}

function wr(addr, value) {
    session.memory.writeData(Memory.Page.DATA, addr, value & 0xFFFF, 16);
}

try {
    server.setConfig(targetConfig);
    session = server.openSession(".*C28xx.*");
    session.target.connect();
    session.target.halt();

    var mux = rd(GPAMUX1_LO);
    var dir = rd(GPADIR_LO);

    wr(GPAMUX1_LO, mux & ~GPIO2_3_MUX_MASK);
    wr(GPADIR_LO, dir | GPIO2_3_MASK);
    wr(GPACLEAR_LO, GPIO2_3_MASK);
    Thread.sleep(10);

    var muxAfter = rd(GPAMUX1_LO);
    var dirAfter = rd(GPADIR_LO);
    var datAfter = rd(GPADAT_LO);

    System.out.println("GPAMUX1_LO=0x" + muxAfter.toString(16));
    System.out.println("GPADIR_LO=0x" + dirAfter.toString(16));
    System.out.println("GPADAT_LO=0x" + datAfter.toString(16));

    if (((muxAfter & GPIO2_3_MUX_MASK) === 0) &&
        ((dirAfter & GPIO2_3_MASK) === GPIO2_3_MASK) &&
        ((datAfter & GPIO2_3_MASK) === 0)) {
        System.out.println("JTAG_GPIO2_3_LOW=PASS");
    } else {
        System.err.println("JTAG_GPIO2_3_LOW=FAIL");
    }
} catch (error) {
    System.err.println("JTAG_GPIO2_3_LOW=ERROR: " + String(error));
} finally {
    if (session !== null) {
        try { session.target.disconnect(); } catch (ignored) {}
        try { session.terminate(); } catch (ignored) {}
    }
    try { server.stop(); } catch (ignored) {}
}
