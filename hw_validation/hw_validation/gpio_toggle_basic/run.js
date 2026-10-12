const fs=require('fs');
const stage='C:/Users/61987/AppData/Local/Temp/gpio_toggle_28035_20260904';
const ds=initScripting(); ds.setScriptingTimeout(20000);
const r={scope:'Original main.c with replacement TI GPIO helpers; RAM execution'};
const hex=x=>'0x'+x.toString(16);
let s;
try {
    ds.configure(stage+'/target.ccxml');
    s=ds.openSession(/C28/i);s.target.connect();s.target.halt();
    console.log('CONNECTED');
    s.target.reset();s.memory.loadProgram(stage+'/case.out');
    if(s.registers.read('PC')!==s.expressions.evaluate('main')) {
        const bp=s.breakpoints.add('main');s.target.run();s.breakpoints.remove(bp);
    }
    if(s.registers.read('PC')!==s.expressions.evaluate('main')) throw Error('Not at main');
    console.log('RAM LOADED; AT MAIN');
    try{s.target.run();}catch(e){
        if(!(e instanceof ScriptingTimeoutError))throw e;
        s.target.halt();r.timeout=true;
    }
    for(const n of ['test_status','test_fail_code','toggle_count','sample_count','final_dat','final_dir','final_mux'])
        r[n]=hex(s.expressions.evaluate(n));
    r.pc=hex(s.registers.read('PC'));
    const count=Number(s.expressions.evaluate('sample_count'));
    if(count>9)throw Error('Invalid sample_count');
    r.samples=count?s.memory.read(s.expressions.evaluate('&samples[0]'),count,16).map(Number):[];
    const status=Number(s.expressions.evaluate('test_status'));
    if(status!==1&&status!==2)throw Error('No test completion');
    r.outcome=status===1?'PASS':'FAIL';
    r.sequence_ok=JSON.stringify(r.samples)===JSON.stringify([0,1,0,1,0,1,0,1,0]);
    console.log(JSON.stringify(r,null,2));
}catch(e){r.error=String(e);console.error(e);}
finally{fs.writeFileSync(stage+'/results.json',JSON.stringify(r,null,2));ds.shutdown();}
if(r.error||r.outcome!=='PASS'||!r.sequence_ok)throw Error(r.error||'Validation failed');
