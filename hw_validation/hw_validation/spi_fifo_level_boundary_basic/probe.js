const ds = initScripting();
ds.setScriptingTimeout(20000);
try {
    console.log(ds.configure('C:/Users/61987/AppData/Local/Temp/spi_fifo_28035_20260904/target.ccxml'));
    const s = ds.openSession(/C28/i);
    s.target.connect();
    s.target.halt();
    console.log('CONNECTED PC=0x' + s.registers.read('PC').toString(16));
    for (const a of [0x7040,0x7041,0x7042,0x7044,0x7048,0x7049,0x704a,0x704b]) {
        console.log('0x'+a.toString(16)+'=0x'+s.memory.readOne(BigInt(a),16).toString(16));
    }
} finally { ds.shutdown(); }
