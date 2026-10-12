// Mass-erase a secured TMS320F28035 over XDS100v2 via DSS.
//
// Erases the entire flash array (including the 128-bit CSM password at
// 0x3F7FF8-0x3F7FFF), which restores the chip to the erased/unsecured state
// (all PWL words = 0xFFFF, SECURE bit cleared). This wipes all firmware;
// reflash with tools/build-mir-control-loop.ps1 afterwards.
//
// usage: dss.bat unlock-csm-mass-erase.js <target.ccxml>

importPackage(Packages.com.ti.debug.engine.scripting);
importPackage(Packages.com.ti.ccstudio.scripting.environment);
importPackage(Packages.java.lang);

if (arguments.length < 1) {
    System.err.println("usage: unlock-csm-mass-erase.js <target.ccxml>");
    java.lang.System.exit(2);
}

var targetConfig = new java.io.File(String(arguments[0])).getCanonicalPath();
var environment = ScriptingEnvironment.instance();
environment.setScriptTimeout(60000);
var server = environment.getServer("DebugServer.1");
var session = null;

function readU16(addr) {
    return Number(session.memory.readData(Memory.Page.DATA, addr, 16, false));
}

try {
    server.setConfig(targetConfig);
    session = server.openSession(".*C28xx.*");
    session.options.setBoolean("AutoRunToLabelOnRestart", false);
    session.options.setBoolean("AutoRunToLabelOnReset", false);

    System.out.println("Connecting to target...");
    session.target.connect();
    System.out.println("Connected.");

    // Pre-erase CSM state. When secured, flash reads return 0x0000; the CSM
    // status register (base 0x0AE0, CSMSCR at +0x000F) bit0 = SECURE.
    try {
        var secureBefore = (readU16(0x0AEF) & 0x1);
        System.out.println("SECURE_BEFORE=" + secureBefore);
    } catch (e) {
        System.out.println("SECURE_BEFORE=unreadable (likely secured)");
    }

    // Try to unlock with the erased-state password (all 0xFFFF). This matches
    // this project's own CSMPasswords.asm. If the part was locked with a real
    // non-FFFF key, unlock() will throw and we report it below.
    System.out.println("Setting FlashKey0..7 = FFFF and unlocking...");
    for (var k = 0; k < 8; k++) {
        session.flash.options.setString("FlashKey" + k, "FFFF");
    }
    try {
        session.flash.unlock();
        System.out.println("Unlock returned.");
    } catch (uErr) {
        System.out.println("Unlock(FFFF) failed: " + uErr);
    }

    // Mass erase. The C2000 flash plug-in erases the whole array, resetting
    // PWL to 0xFFFF.
    System.out.println("Erasing entire flash (mass erase)...");
    session.flash.erase();
    System.out.println("Erase call returned.");

    // Give the probe/device a moment, then re-verify.
    Thread.sleep(500);

    var allFfff = true;
    var pwl = [];
    for (var i = 0; i < 8; i++) {
        var w = readU16(0x3F7FF8 + i);
        pwl.push(w);
        if (w !== 0xFFFF) { allFfff = false; }
    }
    System.out.println("PWL0..PWL7=" + pwl.map(function (x) {
        return ("0000" + x.toString(16).toUpperCase()).slice(-4);
    }).join(","));

    var secureAfter = (readU16(0x0AEF) & 0x1);
    System.out.println("SECURE_AFTER=" + secureAfter);

    if (allFfff && secureAfter === 0) {
        System.out.println("CSM_MASS_ERASE_UNLOCK=PASS");
    } else {
        System.err.println("CSM_MASS_ERASE_UNLOCK=FAIL");
    }
} catch (error) {
    System.err.println("CSM_MASS_ERASE_UNLOCK=ERROR");
    System.err.println(String(error));
} finally {
    if (session !== null) {
        try { session.target.disconnect(); } catch (ignored) {}
        try { session.terminate(); } catch (ignored) {}
    }
    try { server.stop(); } catch (ignored) {}
}
