importPackage(Packages.com.ti.debug.engine.scripting);
importPackage(Packages.com.ti.ccstudio.scripting.environment);
importPackage(java.lang);

var env = ScriptingEnvironment.instance();
env.setScriptTimeout(60000);
var ccxml = arguments[0];
var outFile = arguments[1];

var dbg = env.getServer("DebugServer.1");
dbg.setConfig(ccxml);
var session = dbg.openSession(".*C28xx.*");

session.target.connect();
session.memory.loadProgram(outFile);

function readWord(addr) {
    return Number(session.memory.readData(0, addr, 16, false));
}

// Run 200ms then halt
session.memory.writeRegister("PC", 0x8000);
session.target.runAsynch();
Thread.sleep(200);
session.target.halt();

var pc = Number(session.memory.readRegister("PC"));
var flag = readWord(0x280);
var pieack = readWord(0x0ce1);
var pieifr1 = readWord(0x0ce3);
var tcr = readWord(0x0c04);

System.out.println("PC=0x" + pc.toString(16));
System.out.println("FLAG@0x280=0x" + flag.toString(16));
System.out.println("PIEACK=0x" + pieack.toString(16));
System.out.println("PIEIFR1=0x" + pieifr1.toString(16));
System.out.println("TCR=0x" + tcr.toString(16));

session.terminate();
System.out.println("DONE");
