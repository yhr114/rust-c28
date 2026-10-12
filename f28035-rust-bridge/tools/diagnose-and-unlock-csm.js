importPackage(Packages.com.ti.debug.engine.scripting);
importPackage(Packages.com.ti.ccstudio.scripting.environment);
importPackage(Packages.java.lang);
importPackage(Packages.java.io);

if (arguments.length < 1) {
    System.err.println("usage: diagnose-and-unlock-csm.js <target.ccxml>");
    System.exit(2);
}

var targetConfig = new File(String(arguments[0])).getCanonicalPath();
var environment = ScriptingEnvironment.instance();
environment.setScriptTimeout(60000);
var server = environment.getServer("DebugServer.1");
var session = null;

function readU16(page, address) {
    return Number(session.memory.readData(page, address, 16, false)) & 0xffff;
}

try {
    server.setConfig(targetConfig);
    session = server.openSession(".*C28xx.*");
    session.options.setBoolean("AutoRunToLabelOnRestart", false);
    session.options.setBoolean("AutoRunToLabelOnReset", false);
    session.target.connect();
    session.target.halt();

    var before = readU16(Memory.Page.DATA, 0x0aef);
    var passwords = [];
    for (var i = 0; i < 8; i++) {
        passwords.push(readU16(Memory.Page.DATA, 0x3f7ff8 + i));
    }
    System.out.println("CSM_STATUS_BEFORE=0x" + before.toString(16));
    System.out.println("CSM_PASSWORD_WORDS=" + passwords.map(function (v) {
        return "0x" + v.toString(16);
    }).join(","));

    // A locked CSM masks password reads as zero. First try TI's erased-device
    // key, then the all-zero key used by legacy uninitialized CsmPwl sections.
    for (var key = 0; key < 8; key++) {
        session.memory.writeData(Memory.Page.DATA, 0x0ae0 + key, 0xffff, 16);
    }
    var after = readU16(Memory.Page.DATA, 0x0aef);
    System.out.println("CSM_STATUS_AFTER_FFFF=0x" + after.toString(16));
    if ((after & 1) !== 0) {
        for (var zeroKey = 0; zeroKey < 8; zeroKey++) {
            session.memory.writeData(Memory.Page.DATA, 0x0ae0 + zeroKey, 0x0000, 16);
        }
        after = readU16(Memory.Page.DATA, 0x0aef);
        System.out.println("CSM_STATUS_AFTER_ZERO=0x" + after.toString(16));
    }
    if ((after & 1) !== 0) {
        // The CSM requires CPU reads of every password location. Debug-port
        // memory reads are not guaranteed to count as the required dummy reads,
        // so reproduce TI's f28035.gel sequence through the expression engine.
        for (var passwordAddress = 0x3f7ff8; passwordAddress <= 0x3f7fff; passwordAddress++) {
            session.expression.evaluate("XAR0 = *0x" + passwordAddress.toString(16));
        }
        for (var gelKey = 0; gelKey < 8; gelKey++) {
            session.expression.evaluate("*0x" + (0x0ae0 + gelKey).toString(16) + " = 0xFFFF");
        }
        after = readU16(Memory.Page.DATA, 0x0aef);
        System.out.println("CSM_STATUS_AFTER_GEL_SEQUENCE=0x" + after.toString(16));
    }
    if ((after & 1) !== 0) {
        var keyRegisters = [];
        for (var keyAddress = 0; keyAddress < 8; keyAddress++) {
            keyRegisters.push(readU16(Memory.Page.DATA, 0x0ae0 + keyAddress));
            session.flash.options.setString("FlashKey" + keyAddress, "FFFF");
        }
        System.out.println("CSM_KEY_REGISTERS=" + keyRegisters.map(function (v) {
            return "0x" + v.toString(16);
        }).join(","));
        try {
            session.flash.performOperation("Unlock");
            after = readU16(Memory.Page.DATA, 0x0aef);
            System.out.println("CSM_STATUS_AFTER_FLASH_UNLOCK=0x" + after.toString(16));
        } catch (unlockError) {
            System.out.println("FLASH_PLUGIN_UNLOCK_ERROR=" + String(unlockError));
        }
    }
    if ((after & 1) !== 0) {
        System.err.println("CSM_KNOWN_KEYS_UNLOCK=FAIL");
        System.exit(4);
    }
    System.out.println("CSM_KNOWN_KEYS_UNLOCK=PASS");
} catch (error) {
    System.err.println("CSM_DIAGNOSTIC=ERROR");
    System.err.println(String(error));
    System.exit(5);
} finally {
    if (session !== null) {
        try { session.target.disconnect(); } catch (ignoredDisconnect) {}
        try { session.terminate(); } catch (ignoredTerminate) {}
    }
    try { server.stop(); } catch (ignoredStop) {}
}
