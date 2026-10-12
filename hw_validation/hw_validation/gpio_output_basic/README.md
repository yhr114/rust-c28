# gpio_output_basic 实板测试

结果：PASS，失败码0。使用原 main.c + TI GPIO适配层，通过XDS100v1在F28035上RAM下载执行。

实测采样为 `[0,0,1]`：初始化低电平、等待100us后仍为低、写高并等待100us后为高。
原main.c中的低电平和高电平检查均通过。最终GPBDAT=0x1CCF（GPIO34对应bit2=1），
GPBDIR=0x4（输出），GPBMUX1=0（GPIO功能）。结束PC=0x81CB，test_status=1。

原main.c SHA256：F11FD300C3389B638B9C9564DECBDBE73A1D92B4B538CE086B729A6D304E2746。
适配层沿用gpio_toggle_basic的TI InitSysCtrl（名义60MHz）和GPIO34初始化，
新增gpio_case_gpio34_write，通过GPBSET/GPBCLEAR控制bit2。
这里只验证软件可见的状态，未测量外部引脚波形时序。

运行 `./validate.ps1` 可重跑编译、连接、复位、RAM下载和结果采集。
日志：run.log；结构化结果：results.json；程序：case.out；内存布局：case.map。
