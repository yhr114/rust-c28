// JTAG-only GPIO34 output/readback test.
// Does NOT call loadProgram, so nothing is written to flash.
// Halts the CPU and directly pokes GPIOB registers over JTAG.
//
// Usage: dss.bat jtag-gpio34-ram.js <target.ccxml>

importPackage(Packages.com.ti.debug.engine.scripting);
importPackage(Packages.com.ti.ccstudio.scripting.environment);
importPackage(Packages.java.lang);

if (arguments.length < 1) {
    System.err.println("usage: jtag-gpio34-ram.js <target.ccxml>");
    System.exit(2);
}

var environment = ScriptingEnvironment.instance();
environment.setScriptTimeout(15000);
var server = environment.getServer("DebugServer.1");
var session = null;

// F28035 GPIOB word addresses (from pac.rs)
var GPBMUX1_LO  = 0x6F96;  // 32-bit: GPIO34 local bit 2 -> bits 4:5
var GPBDIR_LO   = 0x6F9A;  // 32-bit: bit 2 = direction
var GPBDAT_LO   = 0x6FC8; // 32-bit: read data
var GPBCLEAR_LO = 0x6FCC; // 32-bit: write 1 to clear (drive low)
var GPBSET_LO   = 0x6FCA; // 32-bit: write 1 to set  (drive high)
var pinMask = 0x4;        // local bit 2

function rd(addr) {
    return Number(session.memory.readData(Memory.Page.DATA, addr, 16, false)) & 0xFFFF;
}
function wr(addr, val) {
    session.memory.writeData(Memory.Page.DATA, addr, val & 0xFFFF, 16);
}

try {
    server.setConfig(String(arguments[0]));
    session = server.openSession(".*C28xx.*");
    session.target.connect();
    session.target.halt();

    // Step 1: configure GPIO34 as GPIO output.
    // Clear MUX1 bits 4:5 (set to 00 = GPIO). Preserve other bits.
    var mux = rd(GPBMUX1_LO);
    wr(GPBMUX1_LO, mux & ~0x0030);
    // Set DIR bit 2 = 1 (output). Preserve other bits.
    var dir = rd(GPBDIR_LO);
    wr(GPBDIR_LO, dir | pinMask);

    // Step 2: drive low via GPBCLEAR.
    wr(GPBCLEAR_LO, pinMask);
    Thread.sleep(50);
    var low = rd(GPBDAT_LO) & pinMask;

    // Step 3: drive high via GPBSET.
    wr(GPBSET_LO, pinMask);
    Thread.sleep(50);
    var high = rd(GPBDAT_LO) & pinMask;

    System.out.println("GPBMUX1(lo)=0x" + rd(GPBMUX1_LO).toString(16));
    System.out.println("GPBDIR(lo) =0x" + rd(GPBDIR_LO).toString(16));
    System.out.println("After CLEAR, GPBDAT bit2 = " + (low ? "1" : "0"));
    System.out.println("After SET,   GPBDAT bit2 = " + (high ? "1" : "0"));

    if (low === 0 && high === pinMask) {
        System.out.println("JTAG_GPIO34_RAM=PASS");
    } else {
        System.err.println("JTAG_GPIO34_RAM=FAIL low=" + low + " high=" + high);
    }
} catch (error) {
    System.err.println("JTAG_GPIO34_RAM=ERROR: " + String(error));
} finally {
    if (session !== null) {
        try { session.target.disconnect(); } catch (ignored) {}
        try { session.terminate(); } catch (ignored) {}
    }
    try { server.stop(); } catch (ignored) {}
}
