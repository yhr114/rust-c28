# i2c_master_read_1byte_basic 实板测试

结果：**FAIL**，test_status=2，test_fail_code=0x6E15。
使用原main.c + TI适配层，F28035/XDS100v1，CCS scripting，RAM下载运行。
原main.c SHA256：9F44AE2043B5F6DE61338CDBA7E8A06F26099D54D99CD582978CE336F0946C71。

## 用例要求

主机向7位地址0x36直接读取1字节，数据必须等于0xDE。
需要实际从设备应答地址并提供0xDE，或等效的受控I2C从机。
单纯接一个任意I2C设备不能保证通过：地址与直接读取的数据都必须匹配。
本次GPIO28=SDA、GPIO29=SCL，启用内部上拉，未添加虚拟从机或模拟返回数据。

## 实测证据

- I2CSAR=0x36；I2CCNT仍为1；received_count=0。
- observed_str=0x1416，NACK(bit1)=1，ARBL(bit0)=0。
- 适配层返回NACK状态5，main按0x6E10+5报0x6E15，未执行后续0xDE数据比较。
- last_byte=0是未接收时的初始值，不能解释为收到一个0字节。
- 清理后I2CMDR=0x4020（STP=0），I2CSTR=0x0410（BB=0），cleanup_idle=1。
- PC=0x8272，为适配层结束停机标记位置。

当前连线下没有收到0x36的地址应答，与缺少应答从机的条件相符；不据此判断I2C硬件故障。
之前addr_nack_stop用例把NACK当作成功条件；本例要求成功读取，所以NACK导致FAIL。

## 自动化

运行 ./validate.ps1 可重跑。case.out/map为程序，run.log/results.json为证据。
脚本退出1是正确传播用例FAIL，并非未完成编译或未连接仿真器。
补充适配层状态编码：OK=0，TIMEOUT=1，STP_BUSY=2，BUS_BUSY=3，ARB_LOST=4，NACK=5。
这些辅助状态值属于本次适配层，不用于反推其他SDK版本的历史失败码。
正向从机应答/返回0xDE路径尚未验证。
