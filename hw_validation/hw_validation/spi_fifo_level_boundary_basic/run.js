const fs = require('fs');
const path = require('path');
const stage = 'C:/Users/61987/AppData/Local/Temp/spi_fifo_28035_20260904';
const ds = initScripting({logFile:path.join(stage,'debugger.log')});
ds.setScriptingTimeout(20000);
const results = [];
let session;
try {
    ds.configure(path.join(stage,'target.ccxml'));
    session = ds.openSession(/C28/i);
    session.target.connect();
    session.target.halt();
    console.log('CONNECTED');
    for (const mode of [0,1]) {
        session.target.reset();
        session.memory.loadProgram(path.join(stage,'case.out'));
        console.log('LOADED mode='+mode);
        console.log('AFTER LOAD PC=0x'+session.registers.read('PC').toString(16));
        if (session.registers.read('PC') !== session.expressions.evaluate('main')) {
            const bp = session.breakpoints.add('main');
            session.target.run();
            session.breakpoints.remove(bp);
        }
        const mainPC = session.registers.read('PC');
        console.log('BEFORE CASE PC=0x'+mainPC.toString(16));
        if (mainPC !== session.expressions.evaluate('main')) throw new Error('Did not stop at main');
        session.memory.write(session.expressions.evaluate('&validation_mode'), [mode],16);
        console.log('AT MAIN mode='+session.expressions.evaluate('validation_mode'));
        try { session.target.run(); }
        catch(e) {
            if (!(e instanceof ScriptingTimeoutError)) throw e;
            console.log('RUN TIMEOUT; halting for diagnosis');
            session.target.halt();
        }
        const result = {mode,pc:'0x'+session.registers.read('PC').toString(16)};
        for (const name of ['test_status','test_fail_code','saved_spiccr','saved_spictl','saved_spists','saved_spifftx','saved_spiffrx','saved_spidat']) {
            result[name] = '0x'+session.expressions.evaluate(name).toString(16);
        }
        if (Number(session.expressions.evaluate('test_status')) === 0) {
            throw new Error('Unexpected halt before case completion');
        }
        results.push(result);
        console.log(JSON.stringify(result,null,2));
    }
} catch (e) {
    results.push({error:String(e)});
    throw e;
} finally {
    fs.writeFileSync(path.join(stage,'results.json'),JSON.stringify(results,null,2));
    ds.shutdown();
}
