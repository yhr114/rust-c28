const fs=require('fs');
const stage='C:/Users/61987/AppData/Local/Temp/i2c_nack_28035_20260904';
const ds=initScripting();ds.setScriptingTimeout(20000);
const results=[];
let s;
const hex=x=>'0x'+x.toString(16);
function finishRun(){
    try{s.target.run();}catch(e){if(!(e instanceof ScriptingTimeoutError))throw e;s.target.halt();throw Error('Run timed out, PC='+hex(s.registers.read('PC')));}
}
try {
    ds.configure(stage+'/target.ccxml');s=ds.openSession(/C28/i);
    s.target.connect();s.target.halt();console.log('CONNECTED');
    for(const trace of [false,true]) {
        s.target.reset();s.memory.loadProgram(stage+'/case.out');
        if(s.registers.read('PC')!==s.expressions.evaluate('main')) {
            const b=s.breakpoints.add('main');finishRun();s.breakpoints.remove(b);
        }
        if(s.registers.read('PC')!==s.expressions.evaluate('main'))throw Error('Not at main');
        const r={run:trace?'nack_breakpoint':'continuous',events:[]};results.push(r);
        console.log('AT MAIN '+r.run);
        if(trace){
            const b=s.breakpoints.add(stage+'/main.c',56);
            finishRun();s.breakpoints.remove(b);
            if(Number(s.expressions.evaluate('test_status'))===0) {
                const e={label:'NACK branch before clearing flag',pc:hex(s.registers.read('PC'))};
                for(const n of ['I2CSTR.all','I2CMDR.all','I2CCNT','I2CSAR'])e[n]=hex(s.expressions.evaluate('I2caRegs.'+n));
                r.events.push(e);console.log(JSON.stringify(e));
                if((Number(s.expressions.evaluate('I2caRegs.I2CSTR.all'))&2)===0)throw Error('NACK flag missing at breakpoint');
                r.nack_observed=true;
                const stopBp=s.breakpoints.add(stage+'/main.c',11);
                finishRun();s.breakpoints.remove(stopBp);
                if(Number(s.expressions.evaluate('test_status'))===0) {
                    const e2={label:'SCD success branch before clearing STOP event',pc:hex(s.registers.read('PC'))};
                    for(const n of ['I2CSTR.all','I2CMDR.all','I2CCNT'])e2[n]=hex(s.expressions.evaluate('I2caRegs.'+n));
                    r.events.push(e2);console.log(JSON.stringify(e2));
                }else throw Error('Did not reach SCD branch');
                finishRun();
            }else {r.nack_observed=false;}
        }else finishRun();
        for(const n of ['test_status','test_fail_code','init_str','init_mdr','init_gpio','final_str','final_mdr','final_cnt','final_sar','final_gpio'])r[n]=hex(s.expressions.evaluate(n));
        const status=Number(s.expressions.evaluate('test_status'));
        r.outcome=status===1?'PASS':status===2?'FAIL':'INCOMPLETE';
        r.stop_cleared=(Number(s.expressions.evaluate('final_mdr'))&0x800)===0;
        r.bus_idle=(Number(s.expressions.evaluate('final_str'))&0x1000)===0;
        r.live_mdr=hex(s.expressions.evaluate('I2caRegs.I2CMDR.all'));
        r.live_str=hex(s.expressions.evaluate('I2caRegs.I2CSTR.all'));
        /* STP clearing can lag SCD. Preserve immediate firmware samples,
           but distinguish this transient from a persistently busy controller. */
        for(let k=0;k<20 && ((Number(r.live_mdr)&0x800)||(Number(r.live_str)&0x1000));k++) {
            r.live_mdr=hex(s.expressions.evaluate('I2caRegs.I2CMDR.all'));
            r.live_str=hex(s.expressions.evaluate('I2caRegs.I2CSTR.all'));
        }
        r.settled_idle=(Number(r.live_mdr)&0x800)===0&&(Number(r.live_str)&0x1000)===0;
        console.log(JSON.stringify(r,null,2));
    }
}catch(e){results.push({error:String(e)});console.error(e);}
finally{fs.writeFileSync(stage+'/results.json',JSON.stringify(results,null,2));ds.shutdown();}
if(results.some(r=>r.error||r.outcome!=='PASS'||!r.settled_idle||(r.run==='nack_breakpoint'&&!r.nack_observed)))throw Error('I2C validation did not pass; inspect results.json');
