importPackage(Packages.com.ti.debug.engine.scripting);
importPackage(Packages.com.ti.ccstudio.scripting.environment);
importPackage(Packages.java.lang);

var targetConfig = new java.io.File(String(arguments[0])).getCanonicalPath();
var environment = ScriptingEnvironment.instance();
environment.setScriptTimeout(30000);
var server = environment.getServer("DebugServer.1");
var session = null;
try {
    server.setConfig(targetConfig);
    session = server.openSession(".*C28xx.*");
    session.target.connect();
    System.out.println("Connected.");
    try {
        var ops = session.flash.listSupportedOperations();
        System.out.println("SUPPORTED_OPERATIONS=" + ops);
    } catch (e1) {
        System.out.println("listSupportedOperations failed: " + e1);
        try {
            var oc = session.flash.getSupportedOpCodes();
            System.out.println("SUPPORTED_OPCODES=" + oc);
        } catch (e2) {
            System.out.println("getSupportedOpCodes failed: " + e2);
        }
    }
    try {
        session.flash.options.printOptions();
    } catch (e3) {
        System.out.println("printOptions failed: " + e3);
    }
    ["FlashOperations", "FlashOSCCLK", "FlashCLKINDV", "FlashPLLCR"].forEach(function (id) {
        try {
            System.out.println(id + "=" + session.flash.options.getString(id));
        } catch (optionError) {
            System.out.println(id + " unavailable: " + optionError);
        }
    });
} catch (error) {
    System.err.println("ERROR: " + error);
} finally {
    if (session !== null) {
        try { session.target.disconnect(); } catch (e) {}
        try { session.terminate(); } catch (e) {}
    }
    try { server.stop(); } catch (e) {}
}
