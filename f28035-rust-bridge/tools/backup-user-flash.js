importPackage(Packages.com.ti.debug.engine.scripting);
importPackage(Packages.com.ti.ccstudio.scripting.environment);
importPackage(Packages.java.lang);

var script = ScriptingEnvironment.instance();
script.traceSetConsoleLevel(TraceLevel.INFO);

if (arguments.length < 2) {
    throw "usage: backup-user-flash.js <target.ccxml> <backup.bin>";
}

var targetConfig = String(arguments[0]);
var backupPath = String(arguments[1]);

var server = script.getServer("DebugServer.1");
server.setConfig(targetConfig);
var session = server.openSession(".*C28xx");

try {
    session.target.connect();
    session.target.halt();

    var passwordAllFF = true;
    for (var i = 0; i < 8; i++) {
        var word = Number(session.memory.readData(
            Memory.Page.PROGRAM, 0x3F7FF8 + i, 16, false)) & 0xFFFF;
        if (word != 0xFFFF) {
            passwordAllFF = false;
        }
    }
    var csmStatus = Number(session.memory.readData(
        Memory.Page.DATA, 0x0AEF, 16, false)) & 0xFFFF;
    if (!passwordAllFF || (csmStatus & 0x0001) != 0) {
        throw "CSM safety guard failed; refusing backup workflow";
    }

    // F28035 user Flash: 0x3E8000..0x3F7FFF, 0x10000 16-bit words.
    session.memory.saveRaw(
        Memory.Page.PROGRAM, 0x3E8000, backupPath, 0x10000, 16, false);
    print("BACKUP_OK=" + backupPath);
    print("PASSWORD_ALL_FF=true");
    print("CSMSCR=0x" + csmStatus.toString(16));
} finally {
    try { session.target.disconnect(); } catch (ignore) {}
    try { server.stop(); } catch (ignore2) {}
}
