// Clock / period diagnostic: settle whether the ~0.989 ms control period is a
// real SYSCLK offset or a measurement artifact.
//
//   * reads PLLSTS (0x7011) and PLLCR (0x7021) to confirm the configured PLL;
//   * measures Timer0 ticks over a wall-clock interval to derive SYSCLK from
//     the period register:  SYSCLK = (PRD+1) / period.
//
// usage: diag-clock.js <target.ccxml> <firmware.out>
importPackage(Packages.com.ti.debug.engine.scripting);
importPackage(Packages.com.ti.ccstudio.scripting.environment);
importPackage(Packages.java.lang);

if (arguments.length < 2) {
    System.err.println("usage: diag-clock.js <target.ccxml> <firmware.out>");
    System.exit(2);
}

var environment = ScriptingEnvironment.instance();
environment.setScriptTimeout(60000);
var server = environment.getServer("DebugServer.1");
var session = null;

function readWord(a) { return Number(session.memory.readData(Memory.Page.DATA, a, 16, false)) & 0xffff; }
function read32(a) { return readWord(a) + readWord(a + 1) * 65536; }

try {
    server.setConfig(String(arguments[0]));
    session = server.openSession(".*C28xx.*");
    session.target.connect();
    session.target.halt();
    session.memory.loadProgram(String(arguments[1]));
    session.target.reset();
    session.expression.evaluate("PC = code_start");

    var report = session.symbol.getAddress("HW_BUSINESS_REPORT");

    // let the PLL lock and the loop settle
    session.target.runAsynch();
    Thread.sleep(500);
    session.target.halt();

    var pllsts = readWord(0x7011);   // DIVSEL=bits8:7, PLLLOCKS=bit0, MCLKSTS=bit3
    var pllcr  = readWord(0x7021);   // DIV=bits3:0
    var prd    = read32(0x0c02);     // Timer0 PRD (low word first)
    var ticksA = read32(report + 0);

    // measure over a clean window using nanoTime (currentTimeMillis has ~15 ms
    // granularity, which is ~0.75 % over 2 s -- too coarse to resolve a 1 %
    // clock offset).  nanoTime is sub-microsecond.
    var w0 = System.nanoTime();
    session.target.runAsynch();
    Thread.sleep(5000);
    session.target.halt();
    var w1 = System.nanoTime();

    var ticksB = read32(report + 0);
    var delta = ticksB - ticksA;
    var wallNs = w1 - w0;
    var wall = wallNs / 1e6;
    var periodMs = wall / delta;
    var sysclkMHz = (prd + 1) / periodMs / 1000.0;   // cycles / (ms) / 1000 = MHz

    System.out.println("CLK_PLLSTS=0x" + pllsts.toString(16) +
                       " DIVSEL=" + ((pllsts >> 7) & 3) +
                       " PLLLOCKS=" + (pllsts & 1) + " MCLKSTS=" + ((pllsts >> 3) & 1));
    System.out.println("CLK_PLLCR=0x" + pllcr.toString(16) + " DIV=" + (pllcr & 0xf));
    System.out.println("CLK_TIMER0_PRD=" + prd);
    System.out.println("CLK_TICKS_DELTA=" + delta + " WALL_MS=" + wall + " PERIOD_MS=" + periodMs.toFixed(4));
    System.out.println("CLK_SYSCLK_MHZ=" + sysclkMHz.toFixed(3));
    // Interpret the crystal under both DIVSEL conventions (the encoding differs
    // between doc revisions): DIVSEL=2 as /2 vs /1.
    var divsel = ((pllsts >> 7) & 3);
    var mult = (pllcr & 0xf);
    if (mult > 0) {
        System.out.println("CLK_IF_DIVSEL2_IS_DIV2: crystal=" + (sysclkMHz * 2 / mult).toFixed(3) + " MHz");
        System.out.println("CLK_IF_DIVSEL2_IS_DIV1: crystal=" + (sysclkMHz / mult).toFixed(3) + " MHz");
    }
} catch (e) {
    System.out.println("DIAG_CLOCK=FAIL " + e);
    System.exit(1);
} finally {
    if (session !== null) {
        try { session.target.halt(); } catch (ignore) {}
        try { session.terminate(); } catch (ignore) {}
    }
}
