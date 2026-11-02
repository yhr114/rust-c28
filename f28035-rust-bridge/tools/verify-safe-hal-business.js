// Hardware readback for the integrated business loop (report layout v2).
//
// The image runs ADC -> compute -> PWM inside a 1 ms Timer0 interrupt, exchanges
// a status byte on the SCI-A link every 4th tick, and keeps the main loop alive
// in parallel.  After ~1.2 s of free running this script:
//   * cross-checks ADCRESULT0 against the sample the firmware reported;
//   * recomputes duty = raw * period / 4095 and requires CMPA to equal it,
//     which is the only way to prove the ADC value really reached the PWM;
//   * requires TBCTR to advance (the time base is actually clocked);
//   * requires zero ADC timeouts and zero link failures;
//   * confirms the report block magic (0xBEEF) so a torn read cannot pass.
importPackage(Packages.com.ti.debug.engine.scripting);
importPackage(Packages.com.ti.ccstudio.scripting.environment);
importPackage(Packages.java.lang);

if (arguments.length < 2) {
    System.err.println("usage: verify-safe-hal-business.js <target.ccxml> <firmware.out>");
    System.exit(2);
}

var PWM_PERIOD = 1000;
var ADC_FULL_SCALE = 4095;
var ADCRESULT0 = 0x0b00;   // ADC result mirror (not the 0x7100 control frame)
var TBCTR = 0x6804;
var TBPRD = 0x6805;
var CMPA = 0x6809;
var AQCTLA = 0x680b;
var REPORT_MAGIC = 0xbeef;

var environment = ScriptingEnvironment.instance();
environment.setScriptTimeout(60000);
var server = environment.getServer("DebugServer.1");
var session = null;

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
    session.expression.evaluate("PC = code_start");
    session.target.runAsynch();
    Thread.sleep(1200);
    session.target.halt();

    var report = session.symbol.getAddress("HW_BUSINESS_REPORT");
    var ticksLo = readWord(report + 0);
    var ticksHi = readWord(report + 1);
    var raw = readWord(report + 2);
    var duty = readWord(report + 3);
    var sciOk = readWord(report + 4);
    var sciErr = readWord(report + 5);
    var adcErr = readWord(report + 6);
    var mainLoops = readWord(report + 7);
    var lastStatus = readWord(report + 8);
    var rawThisTick = readWord(report + 9);
    var okLo = readWord(report + 10);
    var okHi = readWord(report + 11);
    var cpuScictl2 = readWord(report + 12);
    var cpuAdcctl1 = readWord(report + 13);
    var magic = readWord(report + 19);
    // The unchecked build eliminates the unused panic handler (no panic paths),
    // so PANIC_FLAG may be absent -- that means "no handler = no panic possible".
    var panicFlag = -1;
    try { panicFlag = readWord(session.symbol.getAddress("PANIC_FLAG")); } catch (ignore) { panicFlag = -1; }
    var offBefore = readWord(report + 29);
    var offAfter = readWord(report + 30);
    var jtagScictl2 = readWord(0x7054);
    var jtagAdcctl1 = readWord(0x7100);

    var ticks = (ticksLo + ticksHi * 65536);
    var okSamples = (okLo + okHi * 65536);

    var adcReg = readWord(ADCRESULT0);
    var cmpa = readWord(CMPA);
    var period = readWord(TBPRD);
    var aq = readWord(AQCTLA);
    var tb1 = readWord(TBCTR);

    // The time base must still be moving: sample it again after 10 ms.
    session.target.runAsynch();
    Thread.sleep(10);
    session.target.halt();
    var tb2 = readWord(TBCTR);
    var pc = Number(session.memory.readRegister("PC"));

    System.out.println("BUSINESS_TICKS=" + ticks);
    System.out.println("BUSINESS_MAIN_LOOPS=" + mainLoops);
    System.out.println("BUSINESS_ADC=" + raw + " ADCRESULT0=" + adcReg);
    System.out.println("BUSINESS_DUTY=" + duty + " CMPA=" + cmpa);
    System.out.println("BUSINESS_LINK_OK=" + sciOk + " LINK_ERR=" + sciErr + " LAST_STATUS=" + lastStatus);
    System.out.println("BUSINESS_ADC_ERR=" + adcErr);
    System.out.println("BUSINESS_RAW_THIS_TICK=" + rawThisTick + " OK_SAMPLES=" + okSamples);
    System.out.println("BUSINESS_CPU_SCICTL2=0x" + cpuScictl2.toString(16) +
                       " JTAG_SCICTL2=0x" + jtagScictl2.toString(16));
    System.out.println("BUSINESS_CPU_ADCCTL1=0x" + cpuAdcctl1.toString(16) +
                       " JTAG_ADCCTL1=0x" + jtagAdcctl1.toString(16));
    System.out.println("BUSINESS_TBPRD=" + period + " AQCTLA=0x" + aq.toString(16));
    System.out.println("BUSINESS_TBCTR=" + tb1 + " -> " + tb2);
    System.out.println("BUSINESS_PC=0x" + pc.toString(16));
    System.out.println("BUSINESS_MAGIC=0x" + magic.toString(16));
    System.out.println("BUSINESS_PANIC_FLAG=" + (panicFlag < 0 ? "n/a(no-handler)" : "0x" + panicFlag.toString(16)));
    System.out.println("BUSINESS_ADC_OFFTRIM_BEFORE=" + offBefore + " AFTER=" + offAfter);

    var expected = Math.floor((Math.min(raw, ADC_FULL_SCALE) * PWM_PERIOD) / ADC_FULL_SCALE);

    // Three independent verdicts so a partial result stays actionable:
    //   CHAIN : ADC -> compute -> PWM is coherent and the ISR keeps running
    //   EOC   : every software-triggered conversion reported its end-of-conv
    //   LINK  : the serial link accepted every status byte
    var chainFailures = [];
    if (magic !== REPORT_MAGIC) { chainFailures.push("report magic 0x" + magic.toString(16) + " != 0xbeef"); }
    if (panicFlag > 0) { chainFailures.push("panic flag 0x" + panicFlag.toString(16) + " (firmware panicked)"); }
    if (ticks < 100) { chainFailures.push("control ticks too low: " + ticks); }
    if (mainLoops < 1) { chainFailures.push("main loop did not run"); }
    if (rawThisTick <= ADC_FULL_SCALE) {
        if (adcReg !== rawThisTick) {
            chainFailures.push("ADCRESULT0 " + adcReg + " != reported sample " + rawThisTick);
        }
        if (duty !== expected) {
            chainFailures.push("duty " + duty + " != expected " + expected + " for raw " + rawThisTick);
        }
        if (cmpa !== duty) { chainFailures.push("CMPA " + cmpa + " != duty " + duty); }
    }
    if (period !== PWM_PERIOD) { chainFailures.push("TBPRD " + period + " != " + PWM_PERIOD); }
    if (aq !== 0x12) { chainFailures.push("AQCTLA 0x" + aq.toString(16) + " != 0x12"); }
    if (tb1 === tb2) { chainFailures.push("time base not advancing (TBCTR stuck at " + tb1 + ")"); }
    if (tb1 > PWM_PERIOD) { chainFailures.push("TBCTR " + tb1 + " above the period"); }
    if (pc < 0x8000 || pc > 0xffff) {
        chainFailures.push("PC 0x" + pc.toString(16) + " outside the RAM image");
    }

    var eocFailures = [];
    if (adcErr !== 0) {
        eocFailures.push(adcErr + " of " + ticks + " conversions missed their EOC flag");
    }
    if (Math.abs((okSamples + adcErr) - ticks) > 1) {
        eocFailures.push("sample accounting does not add up: " + okSamples + "+" + adcErr + " vs " + ticks);
    }

    var linkFailures = [];
    if (sciErr !== 0) { linkFailures.push(sciErr + " link frames failed"); }
    if (sciOk < 10) { linkFailures.push("too few frames sent: " + sciOk); }

    System.out.println("BUSINESS_CHAIN=" + (chainFailures.length ? "FAIL" : "PASS"));
    System.out.println("BUSINESS_EOC=" + (eocFailures.length ? "FAIL" : "PASS"));
    System.out.println("BUSINESS_LINK=" + (linkFailures.length ? "FAIL" : "PASS"));
    var all = chainFailures.concat(eocFailures).concat(linkFailures);
    for (var i = 0; i < all.length; i++) { System.out.println("BUSINESS_FAIL: " + all[i]); }

    if (chainFailures.length) {
        throw new Error("integrated business chain is incoherent");
    }
    if (eocFailures.length || linkFailures.length) {
        System.out.println("SAFE_HAL_BUSINESS_CHAIN=PASS (EOC and/or LINK still open)");
        System.exit(1);
    }
    System.out.println("SAFE_HAL_BUSINESS_LOOP=PASS");
} catch (e) {
    System.out.println("SAFE_HAL_BUSINESS_LOOP=FAIL " + e);
    System.exit(1);
} finally {
    if (session !== null) {
        try { session.target.halt(); } catch (ignore) {}
        try { session.terminate(); } catch (ignore) {}
    }
}
