importPackage(Packages.com.ti.debug.engine.scripting);
importPackage(Packages.com.ti.ccstudio.scripting.environment);
importPackage(Packages.java.lang);
importPackage(Packages.java.io);

if (arguments.length < 2) {
    System.err.println("usage: program-user-main-flash.js <target.ccxml> <flash.out>");
    System.exit(2);
}

var environment = ScriptingEnvironment.instance();
environment.setScriptTimeout(120000);
var server = environment.getServer("DebugServer.1");
var session = null;
var programmed = false;
try {
    server.setConfig(new File(String(arguments[0])).getCanonicalPath());
    session = server.openSession(".*C28xx.*");
    session.target.connect();
    session.target.halt();

    var passwordAllFf = true;
    for (var address = 0x3F7FF8; address <= 0x3F7FFF; address++) {
        var word = Number(session.memory.readData(Memory.Page.PROGRAM, address, 16, false)) & 0xFFFF;
        if (word !== 0xFFFF) { passwordAllFf = false; }
    }
    var csm = Number(session.memory.readData(Memory.Page.DATA, 0x0AEF, 16, false)) & 0xFFFF;
    System.out.println("CSM_PASSWORD_ALL_FF=" + passwordAllFf);
    System.out.println("CSMSCR=0x" + csm.toString(16));
    if (!passwordAllFf || (csm & 1) !== 0) {
        throw "Refusing Flash erase: CSM is protected or password words are not erased";
    }

    session.flash.options.setString("FlashOperations", "Erase, Program, Verify");
    session.memory.loadProgram(new File(String(arguments[1])).getCanonicalPath());
    programmed = true;
    System.out.println("USER_MAIN_FLASH_PROGRAM=PASS");
} catch (error) {
    System.err.println("USER_MAIN_FLASH_PROGRAM=ERROR");
    System.err.println(String(error));
} finally {
    if (session !== null) {
        try { session.target.disconnect(); } catch (ignoredDisconnect) {}
        try { session.terminate(); } catch (ignoredTerminate) {}
    }
    try { server.stop(); } catch (ignoredStop) {}
}
if (!programmed) { System.exit(1); }
