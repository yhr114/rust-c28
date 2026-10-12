importPackage(Packages.com.ti.debug.engine.scripting);
importPackage(Packages.com.ti.ccstudio.scripting.environment);
importPackage(Packages.java.lang);
importPackage(Packages.java.io);

if (arguments.length < 1) {
    System.err.println("usage: erase-and-unlock-f28035.js <TMS320F28035 target.ccxml>");
    System.exit(2);
}

var targetConfig = new File(String(arguments[0])).getCanonicalPath();
if (targetConfig.indexOf("TMS320F28035") < 0) {
    System.err.println("Refusing erase: target configuration is not explicitly named TMS320F28035.");
    System.exit(3);
}

var environment = ScriptingEnvironment.instance();
environment.setScriptTimeout(180000);
var server = environment.getServer("DebugServer.1");
var session = null;

function readCsmStatus() {
    return Number(session.memory.readData(Memory.Page.DATA, 0x0aef, 16, false)) & 0xffff;
}

try {
    server.setConfig(targetConfig);
    session = server.openSession(".*C28xx.*");
    session.options.setBoolean("AutoRunToLabelOnRestart", false);
    session.options.setBoolean("AutoRunToLabelOnReset", false);
    session.target.connect();
    session.target.halt();

    var before = readCsmStatus();
    System.out.println("CSM_STATUS_BEFORE_ERASE=0x" + before.toString(16));

    var sectors = ["A", "B", "C", "D", "E", "F", "G", "H"];
    for (var i = 0; i < sectors.length; i++) {
        session.flash.options.setBoolean("FlashSector" + sectors[i], true);
    }
    System.out.println("FLASH_ERASE_SCOPE=SECTORS_A_THROUGH_H");
    session.flash.performOperation("Erase");
    System.out.println("FLASH_MASS_ERASE=PASS");

    // Reload the erased (FFFF) CSM password after reset, then perform the
    // required dummy read and write the erased-device key to KEY0..KEY7.
    session.target.reset();
    session.target.halt();
    session.memory.readData(Memory.Page.PROGRAM, 0x3f7ff8, 16, false);
    for (var key = 0; key < 8; key++) {
        session.memory.writeData(Memory.Page.DATA, 0x0ae0 + key, 0xffff, 16);
    }

    var after = readCsmStatus();
    System.out.println("CSM_STATUS_AFTER_ERASE=0x" + after.toString(16));
    if ((after & 1) !== 0) {
        System.err.println("F28035_ERASE_AND_UNLOCK=ERASED_BUT_STILL_SECURE");
        System.exit(5);
    }
    System.out.println("F28035_ERASE_AND_UNLOCK=PASS");
} catch (error) {
    System.err.println("F28035_ERASE_AND_UNLOCK=ERROR");
    System.err.println(String(error));
    System.exit(4);
} finally {
    if (session !== null) {
        try { session.target.disconnect(); } catch (ignoredDisconnect) {}
        try { session.terminate(); } catch (ignoredTerminate) {}
    }
    try { server.stop(); } catch (ignoredStop) {}
}
