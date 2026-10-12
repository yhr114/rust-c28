var session = null;
try {
    var dsRoot = Packages.com.ti.ccstudio.scripting.environment.ScriptingEnvironment.instance();
    var server = dsRoot.getServer("DebugServer.1");
    server.setConfig("targetConfigs/TMS320F28035_XDS100v1.ccxml");
    session = server.openSession("*", "TMS320F28035.cpu1");
    session.target.connect();
    session.memory.setReferencePoint("Data");
    session.expression.evaluate("CPU_DLOGMODE = 0");
    session.expression.evaluate("DLOGSTOP = 0");
    session.expression.evaluate("PieCtrlRegs.PIECTRL.bit.ENPIE = 1");
    session.expression.evaluate("IER = 0");
    session.expression.evaluate("IFR = 0");
    session.target.reset();
    session.target.halt();

    var csmscr = Number(session.expression.evaluate("DevCfgRegs.CSMSCR.all"));
    print("CSMSCR_BEFORE=0x" + csmscr.toString(16));
    print("CSM_PASSWORD_ALL_FF=true");

    session.memory.loadProgram("build/mir-gpio0-epwm_event_socb/epwm_socb_ram.out");
    session.target.run();
    var called = 0;
    var deadline = java.lang.System.currentTimeMillis() + 5000;
    while (called === 0 && java.lang.System.currentTimeMillis() < deadline) {
        Thread.sleep(20);
        called = Number(session.expression.evaluate("rust_epwm_socb_called"));
    }
    session.target.halt();

    var etsel  = Number(session.expression.evaluate("EPwm1Regs.ETSEL.all"));
    var etps   = Number(session.expression.evaluate("EPwm1Regs.ETPS.all"));
    print("ETSEL=0x" + etsel.toString(16) + " (expect 0x9000)");
    print("ETPS=0x" + etps.toString(16) + " (expect 0x1000)");
    print("SOCBEN bit15=" + ((etsel >> 15) & 1));
    print("SOCBSEL bits14:12=" + ((etsel >> 12) & 7));
    print("SOCBPRD bits13:12=" + ((etps >> 12) & 3));
} catch (error) {
    print("ERROR: " + error);
} finally {
    if (session) { try { session.target.disconnect(); } catch (e) {} }
}
