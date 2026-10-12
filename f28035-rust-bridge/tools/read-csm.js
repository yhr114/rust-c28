importPackage(Packages.com.ti.debug.engine.scripting);
importPackage(Packages.com.ti.ccstudio.scripting.environment);
importPackage(Packages.java.lang);
importPackage(Packages.java.io);

var targetConfig = new File(String(arguments[0])).getCanonicalPath();
var environment = ScriptingEnvironment.instance();
environment.setScriptTimeout(30000);
var server = environment.getServer("DebugServer.1");
var session = null;
function rd(addr) {
    return Number(session.memory.readData(Memory.Page.DATA, addr, 16, false));
}
try {
    server.setConfig(targetConfig);
    session = server.openSession(".*C28xx.*");
    session.target.connect();

    System.out.println("--- CSM password region 0x3F7FF8..0x3F7FFF (8 words) ---");
    var pwd = [];
    for (var a = 0x3F7FF8; a <= 0x3F7FFF; a++) { pwd.push(rd(a)); }
    System.out.println("pwd=" + pwd.map(function(x){return x.toString(16);}).join(","));
    var allFF = pwd.every(function(x){return x === 0xFFFF;});
    System.out.println("PWD_ALL_FF=" + allFF + "  (true = factory no-password / unlocked default)");

    System.out.println("--- CSM / Flash option / control registers (read-only) ---");
    System.out.println("CSMSCR  @0x0AEF = 0x" + rd(0x0AEF).toString(16));
    System.out.println("FOPT    @0x0A80 = 0x" + rd(0x0A80).toString(16));
    System.out.println("FPWR    @0x0A82 = 0x" + rd(0x0A82).toString(16));
    System.out.println("FSTATUS @0x0A83 = 0x" + rd(0x0A83).toString(16));
    System.out.println("PLLSTS  @0x7011 = 0x" + rd(0x7011).toString(16));
    System.out.println("CLKCTL  @0x7012 = 0x" + rd(0x7012).toString(16));
    System.out.println("PLLCR   @0x7021 = 0x" + rd(0x7021).toString(16));
    System.out.println("PARTID  @0x3D7E80 = 0x" + rd(0x3D7E80).toString(16));

    // F28034/F28035 user Flash is 0x3E8000..0x3F7FFF. 0x3F8000 is
    // outside the user Flash array and must not be used as a health probe.
    var flashStarts = [0x3E8000, 0x3F0000, 0x3F6000];
    System.out.println("--- valid user-Flash sector samples (read-only) ---");
    for (var i = 0; i < flashStarts.length; i++) {
        var b = flashStarts[i];
        try {
            System.out.println(
                "0x" + b.toString(16) + " = 0x" + rd(b).toString(16) +
                ", 0x" + (b + 1).toString(16) + " = 0x" + rd(b + 1).toString(16));
        } catch (e) {
            System.out.println("0x" + b.toString(16) + " read-failed");
        }
    }
} catch (e) {
    System.out.println("READ_ERROR=" + e);
} finally {
    if (session !== null) {
        try { session.target.disconnect(); } catch (ignored) {}
        try { session.terminate(); } catch (ignored) {}
    }
    try { server.stop(); } catch (ignored) {}
}
