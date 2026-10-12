const fs=require('fs');
const stage='C:/Users/61987/AppData/Local/Temp/i2c_read1_28035_20260904';
const ds=initScripting();ds.setScriptingTimeout(20000);
const r={case:'i2c_master_read_1byte_basic',scope:'Original main.c + TI adapter; physical GPIO28/29 I2C; no simulated slave data'};
const hex=x=>'0x'+x.toString(16);
let s;
try {
    ds.configure(stage+'/target.ccxml');s=ds.openSession(/C28/i);
    s.target.connect();s.target.halt();console.log('CONNECTED');
    s.target.reset();s.memory.loadProgram(stage+'/case.out');
    if(s.registers.read('PC')!==s.expressions.evaluate('main')) {
        const b=s.breakpoints.add('main');s.target.run();s.breakpoints.remove(b);
    }
    if(s.registers.read('PC')!==s.expressions.evaluate('main'))throw Error('Not at main');
    console.log('AT MAIN; RUN');
    try{s.target.run();}catch(e){if(!(e instanceof ScriptingTimeoutError))throw e;s.target.halt();throw Error('Run timeout');}
    r.pc=hex(s.registers.read('PC'));
    for(const n of ['test_status','test_fail_code','read_status','received_count','last_byte','observed_str','observed_mdr','cleanup_idle','init_str','init_mdr','final_str','final_mdr','final_cnt','final_sar','final_gpio'])r[n]=hex(s.expressions.evaluate(n));
    const status=Number(s.expressions.evaluate('test_status'));
    r.outcome=status===1?'PASS':status===2?'FAIL':'INCOMPLETE';
    r.nack_observed=(Number(s.expressions.evaluate('observed_str'))&2)!==0;
    r.live_mdr=hex(s.expressions.evaluate('I2caRegs.I2CMDR.all'));
    r.live_str=hex(s.expressions.evaluate('I2caRegs.I2CSTR.all'));
    console.log(JSON.stringify(r,null,2));
}catch(e){r.error=String(e);console.error(e);}
finally{fs.writeFileSync(stage+'/results.json',JSON.stringify(r,null,2));ds.shutdown();}
if(r.error||r.outcome!=='PASS')throw Error(r.error||'Case FAIL '+r.test_fail_code+' (adapter status '+r.read_status+')');
