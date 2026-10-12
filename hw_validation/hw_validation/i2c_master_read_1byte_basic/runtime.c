#include "board_i2c_case.h"
#include "test_runtime.h"
volatile Uint16 test_status=0;
volatile unsigned long test_fail_code=0;
volatile Uint16 init_str=0, init_mdr=0, final_str=0, final_mdr=0, final_cnt=0, final_sar=0;
volatile unsigned long init_gpio=0, final_gpio=0;
volatile Uint16 read_status=0, observed_str=0, observed_mdr=0, received_count=0, last_byte=0;
volatile Uint16 cleanup_idle=0;
static unsigned int wait_idle(unsigned long loops)
{
    while(loops--) {
        if(!(I2caRegs.I2CMDR.all & 0x0800U) && !(I2caRegs.I2CSTR.all & 0x1000U)) {
            I2caRegs.I2CSTR.all=0x0020U;
            cleanup_idle=1;
            return I2C_CASE_STATUS_OK;
        }
    }
    return I2C_CASE_STATUS_TIMEOUT;
}
unsigned int i2c_case_master_read(Uint16 address, Uint16 *data, Uint16 length, unsigned long wait_loops)
{
    unsigned long remaining=wait_loops;
    Uint16 str;
    if(I2caRegs.I2CMDR.bit.STP) return read_status=I2C_CASE_STATUS_STP_BUSY;
    if(I2caRegs.I2CSTR.bit.BB) return read_status=I2C_CASE_STATUS_BUS_BUSY;
    I2caRegs.I2CSAR=address;
    I2caRegs.I2CCNT=length;
    I2caRegs.I2CSTR.all=0x0027U;
    I2caRegs.I2CMDR.all=I2C_CASE_MDR_FREE | I2C_CASE_MDR_STT | I2C_CASE_MDR_STP | I2C_CASE_MDR_MST | I2C_CASE_MDR_IRS;
    while(remaining--) {
        str=I2caRegs.I2CSTR.all;
        if(str & 0x0003U) {
            observed_str=str;
            observed_mdr=I2caRegs.I2CMDR.all;
            if(str & 1U) {
                I2caRegs.I2CSTR.all=1U;
                return read_status=I2C_CASE_STATUS_ARB_LOST;
            }
            /* No slave ACK: preserve the actual flag, then finish STOP.
               Do not report this expected lab outcome as a case PASS. */
            if(!(str & 0x0020U) && (str & 0x1000U)) I2caRegs.I2CMDR.bit.STP=1;
            I2caRegs.I2CSTR.all=2U;
            wait_idle(wait_loops);
            return read_status=I2C_CASE_STATUS_NACK;
        }
        if((str & 0x0008U) && received_count<length) {
            last_byte=I2caRegs.I2CDRR & 0x00FFU;
            data[received_count++]=last_byte;
        }
        if(received_count==length) return read_status=wait_idle(wait_loops);
        if(str & 0x0020U) break;
    }
    observed_str=I2caRegs.I2CSTR.all;
    observed_mdr=I2caRegs.I2CMDR.all;
    I2caRegs.I2CMDR.bit.STP=1;
    wait_idle(wait_loops);
    return read_status=I2C_CASE_STATUS_TIMEOUT;
}
void board_demo_init(void)
{
    DINT; IER=0; IFR=0;
    InitSysCtrl();
}
void board_delay_us(unsigned long us)
{
    if(us) DSP28x_usDelay(us*12UL-2UL);
}
void i2c_case_i2ca_init(Uint16 own, Uint16 prescaler, Uint16 low, Uint16 high)
{
    EALLOW;
    SysCtrlRegs.PCLKCR0.bit.I2CAENCLK=1;
    GpioCtrlRegs.GPAPUD.bit.GPIO28=0;
    GpioCtrlRegs.GPAPUD.bit.GPIO29=0;
    GpioCtrlRegs.GPAQSEL2.bit.GPIO28=3;
    GpioCtrlRegs.GPAQSEL2.bit.GPIO29=3;
    GpioCtrlRegs.GPAMUX2.bit.GPIO28=2;
    GpioCtrlRegs.GPAMUX2.bit.GPIO29=2;
    EDIS;
    I2caRegs.I2CMDR.all=0;
    I2caRegs.I2CIER.all=0;
    I2caRegs.I2CPSC.all=prescaler;
    I2caRegs.I2CCLKL=low;
    I2caRegs.I2CCLKH=high;
    I2caRegs.I2COAR=own;
    I2caRegs.I2CEMDR.all=0;
    I2caRegs.I2CFFTX.all=0;
    I2caRegs.I2CFFRX.all=0;
    I2caRegs.I2CCNT=0;
    I2caRegs.I2CSTR.all=0x0027U;
    I2caRegs.I2CMDR.all=I2C_CASE_MDR_IRS | I2C_CASE_MDR_FREE;
    init_str=I2caRegs.I2CSTR.all;
    init_mdr=I2caRegs.I2CMDR.all;
    init_gpio=GpioDataRegs.GPADAT.all;
}
void test_done(void)
{
    final_str=I2caRegs.I2CSTR.all;
    final_mdr=I2caRegs.I2CMDR.all;
    final_cnt=I2caRegs.I2CCNT;
    final_sar=I2caRegs.I2CSAR;
    final_gpio=GpioDataRegs.GPADAT.all;
    asm(" ESTOP0"); for(;;) {}
}
void test_runtime_pass(void){test_status=1;test_done();}
void test_runtime_fail(unsigned long code){test_fail_code=code;test_status=2;test_done();}

