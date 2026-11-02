importPackage(Packages.com.ti.debug.engine.scripting)
importPackage(Packages.com.ti.ccstudio.scripting.environment)
importPackage(Packages.java.lang)
var script=ScriptingEnvironment.instance(); script.setScriptTimeout(60000);
var server=script.getServer("DebugServer.1"); server.setConfig(arguments[1]);
var s=server.openSession("*","*");
function word(address) {return s.expression.evaluate("*((unsigned int *)"+address+")");}
try {
  s.target.connect(); s.target.reset(); s.target.halt(); s.memory.loadProgram(arguments[0]);
  var start=s.symbol.getAddress("code_start"), irq=s.symbol.getAddress("TINT0");
  var odd=s.symbol.getAddress("rt_probe_odd"), done=s.symbol.getAddress("rt_done");
  var fallback=s.symbol.getAddress("c28x_rt_default_handler");
  var even=s.symbol.getAddress("rt_probe_even");
  var stopEven=s.breakpoint.add(even), stopDone=s.breakpoint.add(done);
  s.expression.evaluate("PC = "+start); script.setScriptTimeout(15000);
  s.target.run();
  if(s.expression.evaluate("PC")!=even) throw new Error("Rust application loop did not finish");
  var loopCount=word(s.symbol.getAddress("HW_RT_RUST_LOOP"));
  System.out.println("RUNTIME_RUST_LOOP="+loopCount);
  if(loopCount==0) throw new Error("Rust application loop did not execute");
  s.breakpoint.remove(stopEven);
  var stopIRQ=s.breakpoint.add(irq), stopOdd=s.breakpoint.add(odd);
  s.target.run();
  if(s.expression.evaluate("PC")!=irq) throw new Error("Timer0 did not enter the Rust interrupt handler");
  var evenSP=s.expression.evaluate("SP");
  var evenBase=word(s.symbol.getAddress("HW_RT_SP_BEFORE"));
  System.out.println("RUNTIME_FIRST_IRQ PC="+irq+" SP="+evenSP+" BACKGROUND_SP="+evenBase);
  s.breakpoint.remove(stopIRQ);
  s.target.run();
  if(s.expression.evaluate("PC")!=odd) throw new Error("Even-stack probe did not return to Rust main");
  s.breakpoint.remove(stopOdd); stopIRQ=s.breakpoint.add(irq);
  s.target.run();
  if(s.expression.evaluate("PC")!=irq) throw new Error("Second timer sequence did not interrupt");
  var oddSP=s.expression.evaluate("SP");
  var oddBase=word(s.symbol.getAddress("HW_RT_SP_BEFORE"));
  System.out.println("RUNTIME_ODD_IRQ SP="+oddSP+" BACKGROUND_SP="+oddBase);
  // Hardware entry changes SP before the handler breakpoint. Verify both
  // interrupted parities and differing handler-entry parities without
  // assuming a hardware frame word count.
  if((evenBase&1)!=0 || (oddBase&1)!=1 || (evenSP&1)==(oddSP&1)) throw new Error("Did not exercise both entry stack parities");
  s.breakpoint.remove(stopIRQ);
  s.target.run(); s.target.halt(); s.breakpoint.remove(stopDone);
  if(s.expression.evaluate("PC")!=done) throw new Error("Runtime test did not reach completion");
  var address=s.symbol.getAddress("HW_RT_RESULT"), values=[];
  for(var i=0;i<12;i++) values.push(word(address+i));
  System.out.println("RUNTIME_RESULTS="+values);
  var regsAddress=s.symbol.getAddress("HW_RT_REGS"), regs=[];
  for(var r=0;r<22;r++) regs.push(word(regsAddress+r));
  System.out.println("RUNTIME_REGISTER_WORDS="+regs);
  var expected=[0x5678,0x1234,0x6789,0x2345,0x789a,0x3456,0x89ab,0x4567,0x9abc,0x5678,0xabcd,0x6789,0xbcde,0x789a,0xcdef,0x89ab,0xcdef,0x89ab,0x3210,0x7654];
  if(regs[0]<16 || regs[1]!=0x5678) throw new Error("ACC context changed");
  for(var j=0;j<expected.length;j++) if(regs[j+2]!=expected[j]) throw new Error("Register context changed at word "+(j+2));
  if(values[0]!=0xa55a || values[1]!=1 || values[2]!=1 || values[3]<16 || values[4]!=0 || values[5]<16 || values[6]!=0 || values[7]<48 || values[8]!=1 || values[9]!=1 || values[10]!=1 || values[11]!=0xb1e7)
    throw new Error("Rust runtime initialization/context preservation failed");
  var sharedAddress=s.symbol.getAddress("HW_RT_SHARED"), shared=[];
  for(var c=0;c<13;c++) shared.push(word(sharedAddress+c));
  System.out.println("RUNTIME_SHARED_RESULTS="+shared);
  for(var c=0;c<12;c++) if(shared[c]!=1) throw new Error("SharedCell/INTM check failed at "+c);
  if(shared[12]!=0xb1c5) throw new Error("SharedCell checks did not complete");
  System.out.println("PASS: SharedCell reentry, nested INTM restore, stack balance and main/ISR updates on F28035");
  if((word(0xd4c)+word(0xd4d)*65536)!=irq || (word(0xd50)+word(0xd51)*65536)!=fallback)
    throw new Error("PIE vectors do not contain native TI word-address handlers");
  // Raise an otherwise unbound PIE group 2 interrupt after the normal test.
  var stopDefault=s.breakpoint.add(fallback);
  s.expression.evaluate("*((unsigned int *)0xCE1) = 2");
  s.expression.evaluate("*((unsigned int *)0xCE4) = 1");
  s.expression.evaluate("*((unsigned int *)0xCE5) = 1");
  s.expression.evaluate("IER = IER | 2");
  s.expression.evaluate("ST1 = ST1 & 0xFFFE");
  s.target.run(); s.target.halt(); s.breakpoint.remove(stopDefault);
  if(s.expression.evaluate("PC")!=fallback) throw new Error("Unhandled interrupt did not reach DefaultHandler");
  System.out.println("PASS: Rust entry, pre-init, RAM init, Timer0 repeated IRQ, even/odd context and default vector on F28035");
} finally {try{s.target.halt();}catch(e){} s.terminate(); server.stop();}
