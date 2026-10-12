importPackage(Packages.com.ti.debug.engine.scripting);
importPackage(Packages.com.ti.ccstudio.scripting.environment);
importPackage(Packages.java.lang);
importPackage(Packages.java.io);

var targetConfig = new File(String(arguments[0])).getCanonicalPath();
var firmware = new File(String(arguments[1])).getCanonicalPath();
System.out.println("TC=" + targetConfig);
System.out.println("FW=" + firmware);

var environment = ScriptingEnvironment.instance();
environment.setScriptTimeout(60000);
var server = environment.getServer("DebugServer.1");
var session = null;
try {
    server.setConfig(targetConfig);
    session = server.openSession(".*C28xx.*");
    session.options.setBoolean("AutoRunToLabelOnRestart", false);
    session.options.setBoolean("AutoRunToLabelOnReset", false);
    try { session.options.setBoolean("FlashVerboseMode", true); } catch (ignoredVerboseOption) {}
    session.target.connect();

    var passwordAllFf = true;
    for (var passwordAddress = 0x3F7FF8; passwordAddress <= 0x3F7FFF; passwordAddress++) {
        var passwordWord = Number(
            session.memory.readData(Memory.Page.DATA, passwordAddress, 16, false));
        if (passwordWord !== 0xFFFF) { passwordAllFf = false; }
    }
    var csmStatus = Number(session.memory.readData(Memory.Page.DATA, 0x0AEF, 16, false));
    System.out.println("CSMSCR_BEFORE_PROGRAM=0x" + csmStatus.toString(16));
    System.out.println("CSM_PASSWORD_ALL_FF=" + passwordAllFf);
    if (!passwordAllFf || (csmStatus & 1) !== 0) {
        throw "Refusing Flash program: CSM is protected or password words are not all FFFF";
    }

    session.flash.options.setString("FlashOperations", "Erase, Program, Verify");
    session.target.halt();
    System.out.println("connected. attempting loadProgram (this touches flash)...");
    try {
        session.memory.loadProgram(firmware);
        System.out.println("LOADPROGRAM=OK (flash programmed successfully)");
    } catch (e) {
        System.out.println("LOADPROGRAM=FAILED");
        System.out.println("ERR_CLASS=" + e.getClass().getName());
        System.out.println("ERR_MSG=" + e);
    }
} catch (outer) {
    System.out.println("OUTER_ERROR=" + outer);
} finally {
    if (session !== null) {
        try { session.target.disconnect(); } catch (ignored) {}
        try { session.terminate(); } catch (ignored) {}
    }
    try { server.stop(); } catch (ignored) {}
}
