const fs=require('fs');
const path=require('path');
const stage='C:/Users/61987/AppData/Local/Temp/can_mask_28035_20260904';
const ds=initScripting(); ds.setScriptingTimeout(20000);
const result={scope:'Original main.c with replacement TI self-test helper layer', events:[]};
const baseline=process.env.CAN_TRACE==='0';
result.baseline=baseline;
let s;
function hex(x){return '0x'+x.toString(16).padStart(8,'0');}
function live(label){
    const r={label,pc:hex(s.registers.read('PC'))};
    for(const n of ['CANME','CANMD','CANMIM','CANMIL','CANTA','CANRMP','CANTRS','CANMC','CANES','CANGAM']) {
        const addr=s.expressions.evaluate('&ECanaRegs.'+n+'.all');
        r[n]={address:hex(addr),value:hex(s.memory.readOne(addr,32))};
    }
    result.events.push(r); console.log(JSON.stringify(r));
}
try {
    ds.configure(path.join(stage,'target.ccxml'));
    s=ds.openSession(/C28/i); s.target.connect(); s.target.halt();
    console.log('CONNECTED');
    s.target.reset(); s.memory.loadProgram(path.join(stage,'case.out'));
    if(s.registers.read('PC')!==s.expressions.evaluate('main')) {
        const bp=s.breakpoints.add('main'); s.target.run(); s.breakpoints.remove(bp);
    }
    if(s.registers.read('PC')!==s.expressions.evaluate('main')) throw Error('Not stopped at main');
    console.log('RAM LOADED; AT MAIN');
    s.memory.write(s.expressions.evaluate('&trace_enabled'),[baseline?0:1],16);
    if(Number(s.expressions.evaluate('trace_enabled'))!==(baseline?0:1)) throw Error('Trace setting failed');
    live('before_main');
    if(!baseline) {
        const phase1=s.breakpoints.add(path.join(stage,'main.c'),17);
        s.target.run(); s.breakpoints.remove(phase1);
        if(Number(s.expressions.evaluate('test_status'))!==0) throw Error('Case ended before phase-1 breakpoint');
        live('after_first_write_group_before_line17');
    }
    try {s.target.run();} catch(e) {
        if(!(e instanceof ScriptingTimeoutError)) throw e;
        s.target.halt(); result.timeout=true;
    }
    result.status=Number(s.expressions.evaluate('test_status'));
    result.fail_code=hex(s.expressions.evaluate('test_fail_code'));
    live('after_case');
    const fields=['stage','CANME','CANMD','CANMIM','CANMIL','CANTA','CANRMP','CANTRS','CANMC','CANES','CANGAM','LAM0','MSGID0','MSGCTRL0','MDL0','MDH0'];
    const count=Number(s.expressions.evaluate('trace_count'));
    if(count>10) throw Error('Invalid trace length');
    const raw=count ? s.memory.read(s.expressions.evaluate('&trace[0]'),count*16,32) : [];
    result.trace=[];
    for(let i=0;i<count;i++) {
        const row={}; fields.forEach((n,j)=>row[n]=hex(raw[i*16+j]));
        result.trace.push(row); console.log(JSON.stringify(row));
    }
    if(result.status!==1 && result.status!==2) throw Error('No PASS/FAIL reached');
    result.outcome=result.status===1?'PASS':'FAIL';
    console.log('RESULT '+result.outcome+' '+result.fail_code);
} catch(e) {result.error=String(e); console.error(e); process.exitCode=1;}
finally {fs.writeFileSync(path.join(stage,'results.json'),JSON.stringify(result,null,2)); ds.shutdown();}
if(result.error || result.outcome!=='PASS') throw Error(result.error || 'Case returned FAIL '+result.fail_code);
