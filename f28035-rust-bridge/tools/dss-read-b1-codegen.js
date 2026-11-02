importPackage(Packages.com.ti.debug.engine.scripting);
importPackage(Packages.com.ti.ccstudio.scripting.environment);
importPackage(Packages.java.lang);
var script=ScriptingEnvironment.instance(); script.setScriptTimeout(60000);
var server=script.getServer("DebugServer.1"); server.setConfig(arguments[1]);
var session=server.openSession("*","*");
try {
  session.target.connect(); session.target.reset(); session.target.halt();
  session.memory.loadProgram(arguments[0]);
  session.expression.evaluate("PC = "+session.symbol.getAddress("code_start"));
  var done=session.symbol.getAddress("codegen_done"), stop=session.breakpoint.add(done);
  script.setScriptTimeout(15000); session.target.run(); session.target.halt();
  session.breakpoint.remove(stop);
  if(session.expression.evaluate("PC")!=done) throw new Error("Codegen tests did not finish");
  var base=session.symbol.getAddress("HW_CODEGEN_RESULT"), actual=[], expected=[];
  var byteAddress=session.symbol.getAddress("CODEGEN_BYTE");
  System.out.println("CODEGEN_BYTE_ADDRESS="+byteAddress+" RESULT_ADDRESS="+base);
  if(byteAddress>=base && byteAddress<base+216) throw new Error("Byte global aliases result storage");
  for(var i=0;i<108;i++) {
    var low=session.expression.evaluate("*((unsigned int *)"+(base+i*2)+")")&65535;
    var high=session.expression.evaluate("*((unsigned int *)"+(base+i*2+1)+")")&65535;
    actual.push(low+high*65536);
  }
  var inputs=[0,1,127,128,255,256,32768,65535];
  for(var i=0;i<inputs.length;i++) {
    var v=inputs[i], old=v&255, next=old^165;
    var keep=(0x12345678^(v<<8))>>>0;
    expected.push(old,next,old,next,90,keep,(v+0x203+17)&65535,v^0x69a5,
      (keep^((v<<16)|0xa55a)^17)>>>0,(v+0x203+17+3)&65535,
      (v&1)?0:1,(v&1)?(v^0x9a5a):((v+17)&65535),((v^0x203)&0x8000)?0:1);
  }
  expected.push(1,0,1,0xb1c6);
  var failures=0;
  for(var i=0;i<expected.length;i++) if(actual[i]!=expected[i]) {
    System.out.println("CODEGEN_FAIL index="+i+" actual="+actual[i]+" expected="+expected[i]); failures++;
  }
  System.out.println("CODEGEN_CHECKS="+expected.length+" FAILURES="+failures);
  if(failures) throw new Error("Codegen regressions: "+failures);
  System.out.println("PASS: C28x byte exchange, live ACC, bool flag and const-generic ZST methods");
} finally { try {session.target.halt();} catch(e) {} session.terminate(); server.stop(); }
