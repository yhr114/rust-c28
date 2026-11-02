importPackage(Packages.com.ti.debug.engine.scripting)
importPackage(Packages.com.ti.ccstudio.scripting.environment)
importPackage(Packages.java.lang)
var script=ScriptingEnvironment.instance(); script.setScriptTimeout(60000);
var server=script.getServer("DebugServer.1"); server.setConfig(arguments[1]);
var s=server.openSession("*","*");
try {
    s.target.connect(); s.target.reset(); s.target.halt(); s.memory.loadProgram(arguments[0]);
    s.expression.evaluate("PC = code_start");
    var done=s.symbol.getAddress("hw_done"), bp=s.breakpoint.add(done);
    script.setScriptTimeout(15000);
    var runError=null;
    try { s.target.run(); } catch(e) { runError=e; }
    s.target.halt(); s.breakpoint.remove(bp);
    var pc=s.expression.evaluate("PC");
    System.out.println("ARITH_PC="+pc+" DONE="+done);
    var want=[7,2,65535,0,306783378,2,0,3,0,0,
        4294967289,4294967294,4294967289,2,7,4294967294,2147483648,4294967294,
        0x40700000,0xbfa00000,0xc0c00000,0x40600000,0x3f800000,0x80000000,
        0x7f800000,0xff800000,2,0x00400000,-1,615,1114659,0xb1a0];
    // Cargo --strip-debug removes DWARF array types but retains ELF symbols.
    // Read the driver's unsigned long[64] with explicit TI 32-bit elements;
    // untyped SYMBOL[i] otherwise defaults to 16-bit words in CCS.
    var resultAddress=s.symbol.getAddress("HW_ARITH_RESULT");
    var values=[];
    for(var i=0;i<want.length;i++) {
        var value=s.expression.evaluate("*((unsigned long *)"+resultAddress+" + "+i+")");
        if(value<0) value+=4294967296;
        values.push(value);
        var ok=want[i]==-1 ? ((value & 0x7f800000)==0x7f800000 && (value & 0x007fffff)!=0) : value==want[i];
        if(!ok) System.out.println("MISMATCH["+i+"] got="+value+" want="+want[i]);
    }
    System.out.println("ARITH_RESULTS="+values);
    if(runError || pc!=done) throw new Error("arithmetic did not reach hw_done: PC="+pc);
    for(var j=0;j<want.length;j++) {
        var v=values[j];
        if(want[j]==-1 ? !((v&0x7f800000)==0x7f800000 && (v&0x007fffff)!=0) : v!=want[j])
            throw new Error("arithmetic/4-arg result mismatch at "+j);
    }
    System.out.println("PASS: 32 arithmetic/4-argument checks on F28035");
} finally { try{s.target.halt();}catch(e){} s.terminate(); server.stop(); }
