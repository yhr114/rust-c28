; 契约 fixture：EALLOW 包裹的 MMIO 寄存器写
; 镜像 rust-api 中 f28035_sysctl_* / GPIO 初始化（PATH A 真机验证序列）。
; 当前后端尚无可编码的 EALLOW/EDIS 指令；本文件定义该序列落地后必须满足的
; 汇编形状（golden: golden/eallow-store.ll.s）。属契约型用例（oracle kind=contract）。
define void @eallow_store() {
entry:
  ; 期望形状（与 PATH A control-loop.asm 第 37-46 行一致）：
  ;   EALLOW
  ;   MOVW DP, #reg
  ;   OR  @reg+off, #imm
  ;   EDIS
  store volatile i16 8, i16* @sysctrl_reg, align 2
  ret void
}

@sysctrl_reg = external global i16
