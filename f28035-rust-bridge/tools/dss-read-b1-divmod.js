importPackage(Packages.com.ti.debug.engine.scripting)
importPackage(Packages.com.ti.ccstudio.scripting.environment)
importPackage(Packages.java.lang)
var script=ScriptingEnvironment.instance(); script.setScriptTimeout(60000);
var server=script.getServer("DebugServer.1"); server.setConfig(arguments[1]);
var s=server.openSession("*","*");
var dividends=[0,3,23,0xffffffff,0xffffffff,0x80000000,0xffffffff,0x12345678,0x80000001,0xfedcba98];
var divisors=[3,9,3,0x10001,1,7,0x80000000,0x1234,0xffff,0x123456];
try {
    s.target.connect(); s.target.reset(); s.target.halt(); s.memory.loadProgram(arguments[0]);
    s.expression.evaluate("PC = code_start");
    var done=s.symbol.getAddress("divmod_done"), bp=s.breakpoint.add(done);
    script.setScriptTimeout(15000); s.target.run(); s.target.halt(); s.breakpoint.remove(bp);
    if(s.expression.evaluate("PC")!=done) throw new Error("divmod test did not finish");
    var address=s.symbol.getAddress("HW_DIVMOD_RESULT"), values=[];
    for(var i=0;i<24;i++) {
        var v=s.expression.evaluate("*((unsigned long *)"+address+" + "+i+")");
        values.push(v<0 ? v+4294967296 : v);
    }
    System.out.println("DIVMOD_RESULTS="+values);
    for(var j=0;j<dividends.length;j++) {
        var q=Math.floor(dividends[j]/divisors[j]);
        var r=dividends[j]-q*divisors[j];
        if(values[2*j]!=q || values[2*j+1]!=r) throw new Error("divmod mismatch case "+j);
    }
    if(values[20]!=7 || values[21]!=0xb1d4) throw new Error("null remainder or completion mismatch");
    if(values[22]!=14 || values[23]!=2) throw new Error("global remainder mismatch");
    System.out.println("PASS: C28x divmod quotient, logical-pointer remainder and null output on F28035");
} finally {try{s.target.halt();}catch(e){} s.terminate(); server.stop();}
