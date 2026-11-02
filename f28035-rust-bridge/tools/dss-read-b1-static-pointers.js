importPackage(Packages.com.ti.debug.engine.scripting)
importPackage(Packages.com.ti.ccstudio.scripting.environment)
importPackage(Packages.java.lang)
var script = ScriptingEnvironment.instance(); script.setScriptTimeout(90000);
var server = script.getServer("DebugServer.1"); server.setConfig(arguments[1]);
var s = server.openSession("*", "*");
function rd(e) { return s.expression.evaluate(e); }
function u32(word) {
    return rd("*(unsigned short*)"+word) + 65536*rd("*(unsigned short*)"+(word+1));
}
try {
    s.target.connect(); s.target.reset(); s.target.halt();
    s.memory.loadProgram(arguments[0]);
    s.expression.evaluate("PC = code_start");
    var done = s.symbol.getAddress("hw_done"), bp = s.breakpoint.add(done);
    s.target.run(); s.target.halt(); s.breakpoint.remove(bp);
    if (rd("PC") != done) throw new Error("Static pointer firmware did not reach hw_done");
    var fields=["FUNCTION_POINTER","DATA_REFERENCE","LOCAL_REFERENCE","ODD_REFERENCE"];
    var targets=["external_value","external_data","LOCAL_VALUE","external_data"];
    for(var i=0;i<fields.length;i++) {
        var actual=u32(s.symbol.getAddress(fields[i]));
        var expected=2*s.symbol.getAddress(targets[i])+(i==3 ? 1 : 0);
        System.out.println(fields[i]+"="+actual+" EXPECTED="+expected);
        if(actual != expected) throw new Error("Bad relocated pointer: "+fields[i]);
    }
    var values=[], want=[0x1234,0xabcd,0x12];
    for(var k=0;k<3;k++) {
        values.push(rd("HW_STATIC_RESULT["+k+"]"));
        if(values[k]!=want[k]) throw new Error("Bad Rust static dereference "+k+": "+values[k]);
    }
    System.out.println("STATIC_VALUES="+values);
    System.out.println("PASS: static function/data/local/odd pointers and Rust volatile dereferences");
} finally { try{s.target.halt();}catch(e){} s.terminate(); server.stop(); }
